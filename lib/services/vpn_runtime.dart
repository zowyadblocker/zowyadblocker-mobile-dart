import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'package:flutter/services.dart';
import 'package:flutter/widgets.dart';

import '../core/config.dart';
import '../data/filter_lists.dart';
import '../protection/dns_resolver.dart';
import '../protection/dns_wire.dart';
import '../protection/rules.dart';
import '../protection/tcp_dns.dart';

const runtimeChannel = MethodChannel('dev.zowy/runtime');
const packetChannel = BasicMessageChannel<ByteData?>(
  'dev.zowy/packets',
  BinaryCodec(),
);

@pragma('vm:entry-point')
Future<void> vpnMain() async {
  WidgetsFlutterBinding.ensureInitialized();
  final runtime = VpnRuntime();
  try {
    await runtime.initialize();
  } catch (e) {
    await runtimeChannel.invokeMethod<void>('fatal', e.toString());
  }
}

@pragma('vm:entry-point')
Future<void> filterUpdateMain() async {
  WidgetsFlutterBinding.ensureInitialized();
  final errors = <String>[];
  try {
    final config = AppConfig.decode(
      (await runtimeChannel.invokeMethod<String>('loadConfig'))!,
    );
    final path = (await runtimeChannel.invokeMethod<String>('dataPath'))!;
    final manager = FilterListManager(Directory('$path/filters'));
    for (final source in config.sources.where((s) => s.enabled)) {
      try {
        await manager.update(source);
      } catch (e) {
        errors.add('${source.name}: $e');
      }
    }
  } catch (e) {
    errors.add(e.toString());
  }
  await runtimeChannel.invokeMethod<void>('jobDone', errors.join('\n'));
}

class VpnRuntime {
  late AppConfig config;
  late FilterListManager lists;
  late FilterEngine engine;
  late DnsResolver resolver;
  late DnsCache cache;
  int blocked = 0,
      allowed = 0,
      errors = 0,
      cacheHits = 0,
      pending = 0,
      totalMicros = 0;
  final logs = <Map<String, dynamic>>[];
  final days = <String, int>{};
  String? lastError, _lastResolverFailure;
  DateTime? _lastTunnelQuery, _lastResolverReply;
  int _reloadGeneration = 0;
  Timer? _publishTimer;
  bool closing = false;
  late TcpDnsServer tcp;

  Future<void> initialize() async {
    final path = (await runtimeChannel.invokeMethod<String>('dataPath'))!;
    lists = FilterListManager(Directory('$path/filters'));
    await reload();
    tcp = TcpDnsServer(
      resolve: (query) => process(query, tcpRequest: true),
      emit: (packet) {
        if (!closing) {
          unawaited(packetChannel.send(ByteData.sublistView(packet)));
        }
      },
    );
    runtimeChannel.setMethodCallHandler((call) async {
      switch (call.method) {
        case 'reload':
          await reload();
          publish();
        case 'clearLogs':
          logs.clear();
          publish();
        case 'clearCache':
          cache.clear();
          publish();
        case 'networkChanged':
          _resetResolver(config);
          publish();
        case 'resetStats':
          blocked = allowed = errors = cacheHits = totalMicros = 0;
          days.clear();
          logs.clear();
          publish();
        case 'shutdown':
          closing = true;
          tcp.close();
          _publishTimer?.cancel();
          resolver.close();
      }
    });
    packetChannel.setMessageHandler((data) async {
      if (data == null || closing) return null;
      IpDnsPacket packet;
      try {
        packet = IpDnsPacket.parse(
          data.buffer.asUint8List(data.offsetInBytes, data.lengthInBytes),
        );
      } on FormatException {
        try {
          final reply = tcp.accept(
            data.buffer.asUint8List(data.offsetInBytes, data.lengthInBytes),
          );
          return reply == null ? null : ByteData.sublistView(reply);
        } on FormatException {
          return null;
        }
      }
      if (pending >= 64) {
        try {
          return ByteData.sublistView(packet.reply(dnsError(packet.dns, 2)));
        } on FormatException {
          return null;
        }
      }
      pending++;
      try {
        return ByteData.sublistView(packet.reply(await process(packet.dns)));
      } on FormatException {
        return null;
      } finally {
        pending--;
      }
    });
    publish();
    await runtimeChannel.invokeMethod<void>('ready');
  }

  Future<void> reload() async {
    final generation = ++_reloadGeneration;
    final next = AppConfig.decode(
      (await runtimeChannel.invokeMethod<String>('loadConfig'))!,
    );
    final compiled = await lists.compile(next);
    if (closing || generation != _reloadGeneration) return;
    // Swap only after compilation succeeds, keeping the last working rules on error.
    if (!_initialized ||
        jsonEncode(config.upstream) != jsonEncode(next.upstream)) {
      _resetResolver(next);
    } else if (config.cacheSize != next.cacheSize) {
      cache = DnsCache(next.cacheSize);
    }
    config = next;
    engine = compiled;
    if (!config.logging) logs.clear();
    _initialized = true;
  }

  bool _initialized = false;
  void _resetResolver(AppConfig next) {
    if (_initialized) resolver.close();
    resolver = DnsResolver(next.upstream);
    cache = DnsCache(next.cacheSize);
    _lastResolverReply = null;
    _lastResolverFailure = null;
  }

  Future<Uint8List> process(Uint8List query, {bool tcpRequest = false}) async {
    final question = DnsQuestion.parse(query);
    _lastTunnelQuery = DateTime.now();
    final activeResolver = resolver;
    final activeCache = cache;
    final watch = Stopwatch()..start();
    final match = engine.match(
      question.name,
      temporary: config.temporaryAllows,
    );
    final isBlocked = match != null && !match.allow;
    Uint8List response;
    String? error;
    var hit = false;
    try {
      if (isBlocked) {
        response = dnsError(query, 3);
        blocked++;
        final day = DateTime.now().toIso8601String().substring(0, 10);
        days[day] = (days[day] ?? 0) + 1;
        while (days.length > 7) {
          days.remove(days.keys.first);
        }
      } else {
        final cached = activeCache.get(query);
        hit = cached != null;
        if (hit) cacheHits++;
        response = cached ?? await activeResolver.resolve(query);
        if (!hit && identical(activeResolver, resolver)) {
          final rcode = response[3] & 15;
          if (rcode == 0 || rcode == 3) {
            _lastResolverReply = DateTime.now();
            _lastResolverFailure = null;
          } else {
            _lastResolverFailure = 'DNS response code $rcode';
          }
          if (identical(activeCache, cache)) activeCache.put(query, response);
        }
        allowed++;
      }
      // Fit under the IPv6 minimum MTU and let resolvers retry large answers via TCP.
      if (!tcpRequest && response.length > 1232) {
        response = dnsError(query, 0, truncated: true);
      }
    } catch (e) {
      response = dnsError(query, 2);
      errors++;
      error = e.toString();
      lastError = error;
      if (identical(activeResolver, resolver)) {
        _lastResolverFailure = e is TimeoutException
            ? 'The resolver timed out'
            : 'The resolver could not be reached or returned an invalid reply';
      }
    }
    watch.stop();
    totalMicros += watch.elapsedMicroseconds;
    if (config.logging) {
      logs.insert(0, {
        'domain': question.name,
        'time': DateTime.now().toIso8601String(),
        'blocked': isBlocked,
        'rule': match?.rule,
        'source': match?.source,
        'type': question.type,
        'rcode': response[3] & 15,
        'resolver': config.upstream.name,
        'mode': 'VPN DNS',
        'application': 'Unknown application',
        'ms': watch.elapsedMicroseconds / 1000,
        'cache': hit,
        'error': error,
      });
      if (logs.length > 500) logs.removeLast();
    }
    _publishTimer ??= Timer(const Duration(seconds: 1), () {
      _publishTimer = null;
      publish();
    });
    return response;
  }

  void publish() {
    unawaited(
      runtimeChannel.invokeMethod<void>(
        'snapshot',
        jsonEncode({
          'blocked': blocked,
          'allowed': allowed,
          'errors': errors,
          'cacheHits': cacheHits,
          'averageMs': blocked + allowed + errors == 0
              ? 0
              : totalMicros / (blocked + allowed + errors) / 1000,
          'rules': engine.size,
          'reports': engine.reports.map((k, v) => MapEntry(k, v.toJson())),
          'logs': logs,
          'days': days,
          'lastError': lastError,
          'lastTunnelQuery': _lastTunnelQuery?.toUtc().toIso8601String(),
          'lastResolverReply': _lastResolverReply?.toUtc().toIso8601String(),
          'lastResolverFailure': _lastResolverFailure,
        }),
      ),
    );
  }
}

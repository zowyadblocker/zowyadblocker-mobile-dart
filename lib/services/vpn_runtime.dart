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
  String? lastError;
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
          resolver.close();
          resolver = DnsResolver(config.upstream);
          cache.clear();
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
    final next = AppConfig.decode(
      (await runtimeChannel.invokeMethod<String>('loadConfig'))!,
    );
    final compiled = await lists.compile(next);
    final nextResolver = DnsResolver(next.upstream);
    // Build replacement state before swapping; failed compilation keeps the old engine.
    if (_initialized) resolver.close();
    config = next;
    engine = compiled;
    resolver = nextResolver;
    cache = DnsCache(config.cacheSize);
    if (!config.logging) logs.clear();
    _initialized = true;
  }

  bool _initialized = false;

  Future<Uint8List> process(Uint8List query, {bool tcpRequest = false}) async {
    final question = DnsQuestion.parse(query);
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
        final cached = cache.get(query);
        hit = cached != null;
        if (hit) cacheHits++;
        response = cached ?? await resolver.resolve(query);
        if (!hit) cache.put(query, response);
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
        }),
      ),
    );
  }
}

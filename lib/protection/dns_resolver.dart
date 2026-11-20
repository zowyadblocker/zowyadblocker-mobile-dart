import 'dart:async';
import 'dart:convert';
import 'dart:io';
import 'dart:math';
import 'dart:typed_data';

import '../core/config.dart';
import 'dns_wire.dart';

class _CacheEntry {
  _CacheEntry(this.bytes, this.ttls, this.inserted, this.ttl);
  final Uint8List bytes;
  final Map<int, int> ttls;
  final DateTime inserted;
  final int ttl;
}

class DnsCache {
  DnsCache(this.capacity);
  final int capacity;
  final _entries = <String, _CacheEntry>{};
  int _bytes = 0;
  String _key(Uint8List q) => base64Encode(q.sublist(2));
  int _cost(String key, _CacheEntry entry) =>
      entry.bytes.length + key.length * 2 + entry.ttls.length * 32 + 128;
  void clear() {
    _entries.clear();
    _bytes = 0;
  }

  Uint8List? get(Uint8List q, {DateTime? now}) {
    final key = _key(q), entry = _entries.remove(_key(q));
    if (entry == null) return null;
    _bytes -= _cost(key, entry);
    final seconds = (now ?? DateTime.now())
        .difference(entry.inserted)
        .inSeconds;
    if (seconds < 0 || seconds >= entry.ttl) return null;
    _entries[key] = entry;
    _bytes += _cost(key, entry);
    final b = Uint8List.fromList(entry.bytes);
    put16(b, 0, u16(q, 0));
    entry.ttls.forEach(
      (offset, ttl) => put32(b, offset, max(0, ttl - seconds)),
    );
    return b;
  }

  void put(Uint8List q, Uint8List r, {DateTime? now}) {
    if (capacity == 0 ||
        (r[3] & 15) != 0 ||
        (r[2] & 2) != 0 ||
        u16(r, 6) == 0) {
      return;
    }
    final fields = ttlFields(r);
    if (fields.isEmpty) return;
    final ttl = min(3600, fields.values.reduce(min));
    if (ttl == 0) return;
    final key = _key(q);
    final old = _entries.remove(key);
    if (old != null) _bytes -= _cost(key, old);
    final entry = _CacheEntry(
      Uint8List.fromList(r),
      fields,
      now ?? DateTime.now(),
      ttl,
    );
    _entries[key] = entry;
    _bytes += _cost(key, entry);
    while (_entries.length > capacity || _bytes > 4 * 1024 * 1024) {
      final oldest = _entries.keys.first;
      _bytes -= _cost(oldest, _entries.remove(oldest)!);
    }
  }
}

class DnsResolver {
  DnsResolver(this.upstream, {this.securityContext}) {
    _http.connectionTimeout = timeout;
    _http.idleTimeout = const Duration(seconds: 15);
    _http.maxConnectionsPerHost = 8;
    _http.findProxy = (_) => 'DIRECT';
    // A custom HttpClient factory must provide TLS itself; a raw socket here
    // would send plaintext HTTP despite the HTTPS URI.
    _http.connectionFactory = (uri, proxyHost, proxyPort) async {
      final task = await Socket.startConnect(
        InternetAddress(upstream.address),
        uri.port,
      );
      Socket? connected;
      var cancelled = false;
      final secured = task.socket.then<Socket>((raw) async {
        connected = raw;
        if (cancelled) {
          raw.destroy();
          throw const SocketException('Connection cancelled');
        }
        try {
          final tls = await SecureSocket.secure(
            raw,
            host: uri.host,
            context: securityContext,
          ).timeout(timeout);
          connected = tls;
          if (cancelled) {
            tls.destroy();
            throw const SocketException('Connection cancelled');
          }
          return tls;
        } catch (_) {
          raw.destroy();
          rethrow;
        }
      });
      return ConnectionTask.fromSocket<Socket>(secured, () {
        cancelled = true;
        task.cancel();
        connected?.destroy();
      });
    };
  }
  static const timeout = Duration(seconds: 5);
  final Upstream upstream;
  final SecurityContext? securityContext;
  final _http = HttpClient();
  void close() => _http.close(force: true);

  Future<Uint8List> resolve(Uint8List original) async {
    DnsQuestion.parse(original);
    final q = Uint8List.fromList(original);
    put16(q, 0, Random.secure().nextInt(65536));
    var r = await _exchange(q).timeout(timeout);
    validateResponse(q, r);
    if (upstream.transport == DnsTransport.udp && (r[2] & 2) != 0) {
      r = await _stream(q, tls: false).timeout(timeout);
      validateResponse(q, r);
    }
    put16(r, 0, u16(original, 0));
    return r;
  }

  Future<Uint8List> _exchange(Uint8List q) async {
    switch (upstream.transport) {
      case DnsTransport.doh:
        final request = await _http.postUrl(
          Uri(
            scheme: 'https',
            host: upstream.host,
            path: upstream.path,
            port: upstream.port,
          ),
        );
        request.followRedirects = false;
        request.headers.set('content-type', 'application/dns-message');
        request.headers.set('accept', 'application/dns-message');
        request.contentLength = q.length;
        request.add(q);
        final response = await request.close();
        if (response.statusCode != 200 ||
            response.headers.contentType?.mimeType !=
                'application/dns-message') {
          await response.take(0).drain<void>();
          throw HttpException(
            'DoH returned HTTP ${response.statusCode} or invalid content type.',
          );
        }
        return _bounded(response);
      case DnsTransport.dot:
        return _stream(q, tls: true);
      case DnsTransport.tcp:
        return _stream(q, tls: false);
      case DnsTransport.udp:
        final address = InternetAddress(upstream.address);
        final socket = await RawDatagramSocket.bind(
          address.type == InternetAddressType.IPv6
              ? InternetAddress.anyIPv6
              : InternetAddress.anyIPv4,
          0,
        );
        try {
          final result = Completer<Uint8List>();
          socket.listen(
            (event) {
              if (event != RawSocketEvent.read) return;
              final d = socket.receive();
              if (d == null ||
                  d.address.address != address.address ||
                  d.port != upstream.port) {
                return;
              }
              try {
                validateResponse(q, d.data);
                if (!result.isCompleted) result.complete(d.data);
              } on FormatException {
                /* Ignore unrelated/malformed datagrams until timeout. */
              }
            },
            onError: (Object e) {
              if (!result.isCompleted) result.completeError(e);
            },
          );
          socket.send(q, address, upstream.port);
          return await result.future.timeout(timeout);
        } finally {
          socket.close();
        }
    }
  }

  Future<Uint8List> _stream(Uint8List q, {required bool tls}) async {
    final raw = await Socket.connect(
      InternetAddress(upstream.address),
      upstream.customPort ?? (tls ? 853 : 53),
      timeout: timeout,
    );
    Socket socket = raw;
    try {
      if (tls) {
        socket = await SecureSocket.secure(
          raw,
          host: upstream.host,
          context: securityContext,
        ).timeout(timeout);
      }
      final data = Uint8List(q.length + 2);
      put16(data, 0, q.length);
      data.setRange(2, data.length, q);
      socket.add(data);
      await socket.flush();
      final bytes = BytesBuilder(copy: false);
      await for (final chunk in socket.timeout(timeout)) {
        bytes.add(chunk);
        if (bytes.length > 65537) {
          throw const FormatException('Oversized DNS stream.');
        }
        final b = bytes.toBytes();
        if (b.length >= 2 && b.length >= u16(b, 0) + 2) {
          return Uint8List.fromList(b.sublist(2, u16(b, 0) + 2));
        }
      }
      throw const SocketException('DNS stream closed before response.');
    } finally {
      socket.destroy();
      raw.destroy();
    }
  }

  Future<Uint8List> _bounded(Stream<List<int>> stream) async {
    final bytes = BytesBuilder(copy: false);
    await for (final chunk in stream.timeout(timeout)) {
      bytes.add(chunk);
      if (bytes.length > 65535) {
        throw const FormatException('Oversized DNS response.');
      }
    }
    return bytes.takeBytes();
  }
}

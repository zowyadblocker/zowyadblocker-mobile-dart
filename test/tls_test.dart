import 'dart:io';
import 'dart:typed_data';

import 'package:flutter_test/flutter_test.dart';
import 'package:zowy_adblocker/core/config.dart';
import 'package:zowy_adblocker/protection/dns_resolver.dart';
import 'package:zowy_adblocker/protection/dns_wire.dart';

import 'fixtures.dart';

void main() {
  late SecurityContext serverContext, clientContext;
  late Directory generated;
  late String certificate, privateKey;
  setUpAll(() async {
    generated = await Directory.systemTemp.createTemp('zowy-tls-');
    addTearDown(() async {
      if (await generated.exists()) await generated.delete(recursive: true);
    });
    certificate = '${generated.path}/certificate.pem';
    privateKey = '${generated.path}/key.pem';
    var openssl = 'openssl';
    if (Platform.isWindows) {
      final git = await Process.run('where.exe', ['git']);
      if (git.exitCode == 0) {
        final path = git.stdout
            .toString()
            .split(RegExp(r'[\r\n]+'))
            .first
            .trim();
        final candidate =
            '${File(path).parent.parent.path}/usr/bin/openssl.exe';
        if (await File(candidate).exists()) openssl = candidate;
      }
    }
    final result = await Process.run(openssl, [
      'req',
      '-x509',
      '-newkey',
      'rsa:2048',
      '-nodes',
      '-keyout',
      privateKey,
      '-out',
      certificate,
      '-days',
      '2',
      '-subj',
      '/CN=localhost',
      '-addext',
      'subjectAltName=DNS:localhost',
    ]);
    if (result.exitCode != 0) {
      throw StateError(
        'Could not generate localhost TLS fixtures: ${result.stderr}',
      );
    }
  });
  setUp(() {
    serverContext = SecurityContext()
      ..useCertificateChain(certificate)
      ..usePrivateKey(privateKey);
    clientContext = SecurityContext(withTrustedRoots: false)
      ..setTrustedCertificates(certificate);
  });
  test(
    'DoH bootstrap socket is TLS and verifies the requested hostname',
    () async {
      final server = await HttpServer.bindSecure(
        InternetAddress.loopbackIPv4,
        0,
        serverContext,
      );
      server.listen((request) async {
        expect(request.uri.path, '/dns-query');
        expect(
          request.headers.contentType?.mimeType,
          'application/dns-message',
        );
        final bytes = <int>[];
        await for (final chunk in request) {
          bytes.addAll(chunk);
        }
        request.response.headers.contentType = ContentType(
          'application',
          'dns-message',
        );
        request.response.add(answer(Uint8List.fromList(bytes)));
        await request.response.close();
      }, onError: (Object _) {});
      final good = DnsResolver(
        Upstream(
          'fixture',
          '127.0.0.1',
          'localhost',
          DnsTransport.doh,
          customPort: server.port,
        ),
        securityContext: clientContext,
      );
      final bad = DnsResolver(
        Upstream(
          'fixture',
          '127.0.0.1',
          'wrong.example',
          DnsTransport.doh,
          customPort: server.port,
        ),
        securityContext: clientContext,
      );
      try {
        final q = makeQuery('example.com');
        validateResponse(q, await good.resolve(q));
        await expectLater(bad.resolve(q), throwsA(isA<HandshakeException>()));
      } finally {
        good.close();
        bad.close();
        await server.close(force: true);
      }
    },
  );
  test(
    'DoT requires TLS and validates hostname without plaintext fallback',
    () async {
      final server = await SecureServerSocket.bind(
        InternetAddress.loopbackIPv4,
        0,
        serverContext,
      );
      server.listen((socket) {
        final received = <int>[];
        socket.listen((chunk) async {
          received.addAll(chunk);
          if (received.length < 2 || received.length < u16(received, 0) + 2) {
            return;
          }
          final r = answer(Uint8List.fromList(received.sublist(2)));
          final framed = Uint8List(r.length + 2);
          put16(framed, 0, r.length);
          framed.setRange(2, framed.length, r);
          socket.add(framed);
          await socket.flush();
          await socket.close();
        });
      }, onError: (Object _) {});
      final good = DnsResolver(
        Upstream(
          'fixture',
          '127.0.0.1',
          'localhost',
          DnsTransport.dot,
          customPort: server.port,
        ),
        securityContext: clientContext,
      );
      final bad = DnsResolver(
        Upstream(
          'fixture',
          '127.0.0.1',
          'wrong.example',
          DnsTransport.dot,
          customPort: server.port,
        ),
        securityContext: clientContext,
      );
      try {
        final q = makeQuery('example.com');
        validateResponse(q, await good.resolve(q));
        await expectLater(bad.resolve(q), throwsA(isA<HandshakeException>()));
      } finally {
        good.close();
        bad.close();
        await server.close();
      }
    },
  );
}

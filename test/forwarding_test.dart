import 'dart:io';
import 'dart:typed_data';

import 'package:flutter_test/flutter_test.dart';
import 'package:zowy_adblocker/core/config.dart';
import 'package:zowy_adblocker/protection/dns_wire.dart';
import 'package:zowy_adblocker/protection/dns_resolver.dart';

import 'fixtures.dart';

void main() {
  test(
    'UDP forwarding uses selected endpoint and validates real socket response',
    () async {
      final server = await RawDatagramSocket.bind(
        InternetAddress.loopbackIPv4,
        0,
      );
      final resolver = DnsResolver(
        Upstream(
          'fixture',
          '127.0.0.1',
          'localhost',
          DnsTransport.udp,
          customPort: server.port,
        ),
      );
      server.listen((event) {
        if (event == RawSocketEvent.read) {
          final d = server.receive()!;
          server.send(answer(d.data), d.address, d.port);
        }
      });
      try {
        final q = makeQuery('example.com');
        final r = await resolver.resolve(q);
        validateResponse(q, r);
        expect(u16(r, 6), 1);
      } finally {
        resolver.close();
        server.close();
      }
    },
  );
  test('TCP forwarding reassembles split framed responses', () async {
    final server = await ServerSocket.bind(InternetAddress.loopbackIPv4, 0);
    final resolver = DnsResolver(
      Upstream(
        'fixture',
        '127.0.0.1',
        'localhost',
        DnsTransport.tcp,
        customPort: server.port,
      ),
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
        socket.add(framed.sublist(0, 1));
        await socket.flush();
        socket.add(framed.sublist(1));
        await socket.flush();
        await socket.close();
      });
    });
    try {
      final q = makeQuery('example.com');
      validateResponse(q, await resolver.resolve(q));
    } finally {
      resolver.close();
      await server.close();
    }
  });
}

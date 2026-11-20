import 'dart:typed_data';

import 'package:flutter_test/flutter_test.dart';
import 'package:zowy_adblocker/protection/tcp_dns.dart';
import 'package:zowy_adblocker/protection/dns_wire.dart';

import 'fixtures.dart';

void main() {
  for (final ipv6 in [false, true]) {
    test(
      'TCP DNS handshake, split input, response framing and FIN (${ipv6 ? 'v6' : 'v4'})',
      () async {
        final emitted = <Uint8List>[];
        final server = TcpDnsServer(
          resolve: (q) async => answer(q),
          emit: emitted.add,
        );
        try {
          final h = ipv6 ? 40 : 20;
          final syn = server.accept(tcpPacket(ipv6: ipv6))!;
          final serverSequence = u32(syn, h + 4) + 1;
          expect(syn[h + 13], 0x12);
          expect(u32(syn, h + 8), 101);
          server.accept(
            tcpPacket(seq: 101, ack: serverSequence, flags: 16, ipv6: ipv6),
          );
          final q = makeQuery('example.com');
          final framed = Uint8List(q.length + 2);
          put16(framed, 0, q.length);
          framed.setRange(2, framed.length, q);
          final ack = server.accept(
            tcpPacket(
              seq: 101,
              ack: serverSequence,
              flags: 0x18,
              data: framed.sublist(0, 5),
              ipv6: ipv6,
            ),
          )!;
          expect(u32(ack, h + 8), 106);
          server.accept(
            tcpPacket(
              seq: 106,
              ack: serverSequence,
              flags: 0x18,
              data: framed.sublist(5),
              ipv6: ipv6,
            ),
          );
          await Future<void>.delayed(Duration.zero);
          expect(emitted, hasLength(1));
          final data = emitted.single.sublist(h + 20);
          expect(u16(data, 0), data.length - 2);
          validateResponse(q, Uint8List.fromList(data.sublist(2)));
          server.accept(
            tcpPacket(
              seq: 101 + framed.length,
              ack: serverSequence + data.length,
              flags: 16,
              ipv6: ipv6,
            ),
          );
          expect(emitted.last[h + 13], 0x11);
          server.accept(
            tcpPacket(
              seq: 101 + framed.length,
              ack: serverSequence + data.length + 1,
              flags: 16,
              ipv6: ipv6,
            ),
          );
        } finally {
          server.close();
        }
      },
    );
  }
  test('TCP checksum corruption is rejected', () {
    final p = tcpPacket()..[39] ^= 1;
    expect(() => TcpPacket.parse(p), throwsFormatException);
  });
}

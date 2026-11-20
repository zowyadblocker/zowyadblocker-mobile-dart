import 'dart:typed_data';

import 'package:zowy_adblocker/protection/dns_wire.dart';

Uint8List answer(Uint8List query, {int ttl = 60}) {
  final r = Uint8List.fromList([
    ...dnsError(query, 0),
    0xc0,
    0x0c,
    0,
    1,
    0,
    1,
    0,
    0,
    0,
    0,
    0,
    4,
    93,
    184,
    215,
    14,
  ]);
  put16(r, 6, 1);
  put32(r, r.length - 10, ttl);
  return r;
}

Uint8List udpPacket(Uint8List query, {bool ipv6 = false}) {
  final h = ipv6 ? 40 : 20;
  final b = Uint8List(h + 8 + query.length);
  if (ipv6) {
    b[0] = 0x60;
    put16(b, 4, b.length - 40);
    b[6] = 17;
    b[7] = 64;
    b.setRange(8, 24, [0xfd, 0, 1, 0x11, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 2]);
    b.setRange(24, 40, [0xfd, 0, 1, 0x11, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 1]);
  } else {
    b[0] = 0x45;
    put16(b, 2, b.length);
    b[8] = 64;
    b[9] = 17;
    b.setRange(12, 16, [10, 111, 0, 2]);
    b.setRange(16, 20, [10, 111, 0, 1]);
    put16(b, 10, checksum(b.sublist(0, 20)));
  }
  put16(b, h, 34000);
  put16(b, h + 2, 53);
  put16(b, h + 4, query.length + 8);
  b.setRange(h + 8, b.length, query);
  final pseudo = ipv6
      ? [
          ...b.sublist(8, 40),
          0,
          0,
          (b.length - h) >> 8,
          (b.length - h) & 255,
          0,
          0,
          0,
          17,
        ]
      : [
          ...b.sublist(12, 20),
          0,
          17,
          (b.length - h) >> 8,
          (b.length - h) & 255,
        ];
  final sum = checksum([...pseudo, ...b.sublist(h)]);
  put16(b, h + 6, sum == 0 ? 65535 : sum);
  return b;
}

Uint8List tcpPacket({
  int seq = 100,
  int ack = 0,
  int flags = 2,
  List<int> data = const [],
  bool ipv6 = false,
}) {
  final original = udpPacket(Uint8List(0), ipv6: ipv6);
  final h = ipv6 ? 40 : 20;
  final b = Uint8List(h + 20 + data.length)..setRange(0, h, original);
  if (ipv6) {
    put16(b, 4, b.length - h);
    b[6] = 6;
  } else {
    put16(b, 2, b.length);
    b[9] = 6;
    put16(b, 10, 0);
    put16(b, 10, checksum(b.sublist(0, 20)));
  }
  put16(b, h, 34000);
  put16(b, h + 2, 53);
  put32(b, h + 4, seq);
  put32(b, h + 8, ack);
  b[h + 12] = 0x50;
  b[h + 13] = flags;
  put16(b, h + 14, 65535);
  b.setRange(h + 20, b.length, data);
  final n = b.length - h;
  final pseudo = ipv6
      ? [...b.sublist(8, 40), 0, 0, n >> 8, n & 255, 0, 0, 0, 6]
      : [...b.sublist(12, 20), 0, 6, n >> 8, n & 255];
  put16(b, h + 16, checksum([...pseudo, ...b.sublist(h)]));
  return b;
}

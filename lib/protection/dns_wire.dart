import 'dart:math';
import 'dart:typed_data';

int u16(List<int> b, int i) => (b[i] << 8) | b[i + 1];
void put16(List<int> b, int i, int v) {
  b[i] = v >> 8;
  b[i + 1] = v & 255;
}

int u32(List<int> b, int i) => (u16(b, i) << 16) | u16(b, i + 2);
void put32(List<int> b, int i, int v) {
  put16(b, i, v >> 16);
  put16(b, i + 2, v);
}

class DnsQuestion {
  const DnsQuestion(this.name, this.type, this.qclass, this.end);
  final String name;
  final int type, qclass, end;
  static DnsQuestion parse(Uint8List b, {bool response = false}) {
    if (b.length < 12 ||
        b.length > 65535 ||
        u16(b, 4) != 1 ||
        ((b[2] & 0x80) != 0) != response ||
        (b[2] & 0x78) != 0) {
      throw const FormatException('Expected one standard DNS question.');
    }
    var offset = 12, total = 0;
    final labels = <String>[];
    // Queries with compressed questions are rejected; normal Android DNS uses
    // uncompressed questions. This also makes response construction unambiguous.
    while (true) {
      if (offset >= b.length) {
        throw const FormatException('Truncated DNS name.');
      }
      final n = b[offset++];
      if (n == 0) break;
      if (n > 63 || offset + n > b.length || (total += n + 1) > 254) {
        throw const FormatException('Invalid DNS label.');
      }
      final label = b.sublist(offset, offset + n);
      if (label.any((c) => c < 33 || c > 126 || c == 46)) {
        throw const FormatException('Non-ASCII DNS name.');
      }
      labels.add(String.fromCharCodes(label).toLowerCase());
      offset += n;
    }
    if (offset + 4 > b.length) {
      throw const FormatException('Truncated DNS question.');
    }
    return DnsQuestion(
      labels.join('.'),
      u16(b, offset),
      u16(b, offset + 2),
      offset + 4,
    );
  }
}

Uint8List dnsError(Uint8List query, int rcode, {bool truncated = false}) {
  final q = DnsQuestion.parse(query);
  final b = Uint8List.fromList(query.sublist(0, q.end));
  b[2] = 0x80 | (query[2] & 1) | (truncated ? 2 : 0);
  b[3] = 0x80 | (query[3] & 0x10) | rcode;
  for (var i = 6; i < 12; i++) {
    b[i] = 0;
  }
  return b;
}

void validateResponse(Uint8List query, Uint8List response) {
  final q = DnsQuestion.parse(query),
      r = DnsQuestion.parse(response, response: true);
  if (u16(query, 0) != u16(response, 0) ||
      q.name != r.name ||
      q.type != r.type ||
      q.qclass != r.qclass) {
    throw const FormatException('Upstream DNS response does not match query.');
  }
  ttlFields(
    response,
  ); // Validate every record boundary, including non-cached replies.
}

int _skipName(List<int> b, int start) {
  var i = start;
  int? end;
  var traversed = 0;
  while (i < b.length) {
    if (++traversed > 128) {
      throw const FormatException('DNS name pointer loop.');
    }
    final n = b[i++];
    if (n == 0) return end ?? i;
    if ((n & 0xc0) == 0xc0) {
      if (i >= b.length ||
          (((n & 63) << 8) | b[i]) >= i - 1 ||
          (((n & 63) << 8) | b[i]) < 12) {
        throw const FormatException('Invalid DNS pointer.');
      }
      end ??= i + 1;
      i = ((n & 63) << 8) | b[i];
      continue;
    }
    if (n > 63 || i + n > b.length) {
      throw const FormatException('Invalid record name.');
    }
    i += n;
  }
  throw const FormatException('Truncated record name.');
}

Map<int, int> ttlFields(Uint8List b) {
  final q = DnsQuestion.parse(b, response: true);
  var offset = q.end;
  final fields = <int, int>{};
  final count = u16(b, 6) + u16(b, 8) + u16(b, 10);
  if (count > 4096) throw const FormatException('Too many DNS records.');
  for (var n = 0; n < count; n++) {
    offset = _skipName(b, offset);
    if (offset + 10 > b.length) {
      throw const FormatException('Truncated DNS record.');
    }
    if (u16(b, offset) != 41) fields[offset + 4] = u32(b, offset + 4);
    offset += 10 + u16(b, offset + 8);
    if (offset > b.length) {
      throw const FormatException('Truncated record data.');
    }
  }
  if (offset != b.length) throw const FormatException('Trailing DNS data.');
  return fields;
}

Uint8List makeQuery(String name, {int type = 1}) {
  final bytes = <int>[0, 0, 1, 0, 0, 1, 0, 0, 0, 0, 0, 0];
  for (final label in name.split('.')) {
    bytes.add(label.length);
    bytes.addAll(label.codeUnits);
  }
  bytes.addAll([0, type >> 8, type & 255, 0, 1]);
  final b = Uint8List.fromList(bytes);
  put16(b, 0, Random.secure().nextInt(65536));
  DnsQuestion.parse(b);
  return b;
}

int checksum(List<int> bytes) {
  var sum = 0;
  for (var i = 0; i < bytes.length; i += 2) {
    sum += (bytes[i] << 8) | (i + 1 < bytes.length ? bytes[i + 1] : 0);
  }
  while (sum > 65535) {
    sum = (sum & 65535) + (sum >> 16);
  }
  return (~sum) & 65535;
}

class IpDnsPacket {
  IpDnsPacket(this.bytes, this.ipLength, this.ipv6, this.protocol);
  final Uint8List bytes;
  final int ipLength, protocol;
  final bool ipv6;
  int get sourcePort => u16(bytes, ipLength);
  Uint8List get dns => Uint8List.sublistView(bytes, ipLength + 8);
  static IpDnsPacket parse(Uint8List b) {
    if (b.isEmpty) throw const FormatException('Empty packet.');
    final v6 = b[0] >> 4 == 6;
    int length, protocol;
    if (v6) {
      if (b.length < 48 || u16(b, 4) + 40 != b.length) {
        throw const FormatException('Invalid IPv6 packet.');
      }
      length = 40;
      protocol = b[6];
    } else {
      if (b[0] >> 4 != 4 || b.length < 28) {
        throw const FormatException('Invalid IPv4 packet.');
      }
      length = (b[0] & 15) * 4;
      protocol = b[9];
      if (length < 20 ||
          length + 8 > b.length ||
          u16(b, 2) != b.length ||
          (u16(b, 6) & 0x3fff) != 0 ||
          checksum(b.sublist(0, length)) != 0) {
        throw const FormatException('Invalid or fragmented IPv4 packet.');
      }
    }
    if (protocol != 17 ||
        u16(b, length + 2) != 53 ||
        u16(b, length + 4) != b.length - length) {
      throw const FormatException('Only unfragmented UDP DNS is supported.');
    }
    if (v6 && u16(b, length + 6) == 0) {
      throw const FormatException('IPv6 UDP checksum is required.');
    }
    if (u16(b, length + 6) != 0) {
      final n = b.length - length;
      final pseudo = v6
          ? [...b.sublist(8, 40), 0, 0, n >> 8, n & 255, 0, 0, 0, 17]
          : [...b.sublist(12, 20), 0, 17, n >> 8, n & 255];
      if (checksum([...pseudo, ...b.sublist(length)]) != 0) {
        throw const FormatException('Invalid UDP checksum.');
      }
    }
    return IpDnsPacket(b, length, v6, protocol);
  }

  Uint8List reply(Uint8List payload) {
    final h = ipv6 ? 40 : 20;
    final b = Uint8List(h + 8 + payload.length);
    if (ipv6) {
      b[0] = 0x60;
      put16(b, 4, b.length - 40);
      b[6] = 17;
      b[7] = 64;
      b.setRange(8, 24, bytes.sublist(24, 40));
      b.setRange(24, 40, bytes.sublist(8, 24));
    } else {
      b[0] = 0x45;
      put16(b, 2, b.length);
      b[8] = 64;
      b[9] = 17;
      b.setRange(12, 16, bytes.sublist(16, 20));
      b.setRange(16, 20, bytes.sublist(12, 16));
      put16(b, 10, checksum(b.sublist(0, 20)));
    }
    put16(b, h, 53);
    put16(b, h + 2, sourcePort);
    put16(b, h + 4, payload.length + 8);
    b.setRange(h + 8, b.length, payload);
    final pseudo = ipv6
        ? <int>[
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
        : <int>[
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
}

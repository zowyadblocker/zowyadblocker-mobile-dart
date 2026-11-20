import 'dart:async';
import 'dart:math';
import 'dart:typed_data';

import 'dns_wire.dart';

bool _atOrAfter(int a, int b) => ((a - b) & 0xffffffff) < 0x80000000;

class TcpPacket {
  TcpPacket(this.ip, this.header, this.offset);
  final Uint8List ip, header;
  final int offset;
  int get sequence => u32(header, 4);
  int get acknowledgement => u32(header, 8);
  int get flags => header[13];
  Uint8List get payload => Uint8List.sublistView(header, offset);
  String get key =>
      '${ip[0] >> 4}:${ip.sublist(ip[0] >> 4 == 6 ? 8 : 12, ip[0] >> 4 == 6 ? 24 : 16).join('.')}:${u16(header, 0)}';
  static TcpPacket parse(Uint8List ip) {
    if (ip.length < 40) throw const FormatException('Short TCP packet.');
    final v6 = ip[0] >> 4 == 6;
    final h = v6 ? 40 : (ip[0] & 15) * 4;
    if ((v6 ? ip[6] : ip[9]) != 6 ||
        h < 20 ||
        h + 20 > ip.length ||
        (!v6 &&
            (ip[0] >> 4 != 4 ||
                (u16(ip, 6) & 0x3fff) != 0 ||
                u16(ip, 2) != ip.length ||
                checksum(ip.sublist(0, h)) != 0)) ||
        (v6 && u16(ip, 4) + 40 != ip.length)) {
      throw const FormatException('Invalid TCP IP envelope.');
    }
    final tcp = Uint8List.sublistView(ip, h);
    final offset = (tcp[12] >> 4) * 4;
    if (u16(tcp, 2) != 53 ||
        offset < 20 ||
        offset > tcp.length ||
        checksum([..._pseudo(ip, tcp.length, 6), ...tcp]) != 0) {
      throw const FormatException('Invalid TCP DNS segment.');
    }
    return TcpPacket(ip, tcp, offset);
  }

  Uint8List reply(int seq, int ack, int flags, [List<int> data = const []]) {
    final tcp = Uint8List(20 + data.length);
    put16(tcp, 0, 53);
    put16(tcp, 2, u16(header, 0));
    put32(tcp, 4, seq);
    put32(tcp, 8, ack);
    tcp[12] = 0x50;
    tcp[13] = flags;
    put16(tcp, 14, 65535);
    tcp.setRange(20, tcp.length, data);
    final v6 = ip[0] >> 4 == 6;
    final b = Uint8List((v6 ? 40 : 20) + tcp.length);
    if (v6) {
      b[0] = 0x60;
      put16(b, 4, tcp.length);
      b[6] = 6;
      b[7] = 64;
      b.setRange(8, 24, ip.sublist(24, 40));
      b.setRange(24, 40, ip.sublist(8, 24));
    } else {
      b[0] = 0x45;
      put16(b, 2, b.length);
      b[8] = 64;
      b[9] = 6;
      b.setRange(12, 16, ip.sublist(16, 20));
      b.setRange(16, 20, ip.sublist(12, 16));
      put16(b, 10, checksum(b.sublist(0, 20)));
    }
    final sum = checksum([..._pseudo(b, tcp.length, 6), ...tcp]);
    put16(tcp, 16, sum);
    b.setRange(v6 ? 40 : 20, b.length, tcp);
    return b;
  }
}

List<int> _pseudo(Uint8List ip, int length, int protocol) => ip[0] >> 4 == 6
    ? [...ip.sublist(8, 40), 0, 0, length >> 8, length & 255, 0, 0, 0, protocol]
    : [...ip.sublist(12, 20), 0, protocol, length >> 8, length & 255];

class _Session {
  _Session(this.packet, this.nextClient, this.nextServer);
  TcpPacket packet;
  int nextClient, nextServer;
  final input = <int>[];
  final output = <Uint8List>[];
  Uint8List? unacked;
  int unackedEnd = 0, retries = 0;
  DateTime touched = DateTime.now(), sent = DateTime.now();
  bool resolving = false,
      established = false,
      finSent = false,
      closedInput = false;
}

/// A bounded DNS TCP endpoint, not a general TCP proxy. It closes after one DNS
/// response. Stop-and-wait segments simplify flow control and retransmission.
class TcpDnsServer {
  TcpDnsServer({required this.resolve, required this.emit});
  final Future<Uint8List> Function(Uint8List) resolve;
  final void Function(Uint8List) emit;
  final _sessions = <String, _Session>{};
  Timer? _timer;
  void close() {
    _timer?.cancel();
    _timer = null;
    _sessions.clear();
  }

  Uint8List? accept(Uint8List bytes) {
    final p = TcpPacket.parse(bytes);
    final key = p.key;
    var s = _sessions[key];
    if ((p.flags & 4) != 0) {
      _sessions.remove(key);
      return null;
    }
    if ((p.flags & 2) != 0) {
      if (s != null && !s.established) return s.unacked;
      if (_sessions.length >= 64) {
        return p.reply(0, (p.sequence + 1) & 0xffffffff, 0x14);
      }
      s = _Session(
        p,
        (p.sequence + 1) & 0xffffffff,
        Random.secure().nextInt(0x7fffffff),
      );
      _sessions[key] = s;
      final syn = p.reply(s.nextServer, s.nextClient, 0x12);
      s.nextServer = (s.nextServer + 1) & 0xffffffff;
      s.unackedEnd = s.nextServer;
      s.unacked = syn;
      _timer ??= Timer.periodic(const Duration(seconds: 1), (_) => _tick());
      return syn;
    }
    if (s == null) {
      return (p.flags & 16) != 0 ? p.reply(p.acknowledgement, 0, 4) : null;
    }
    s.touched = DateTime.now();
    s.packet = p;
    if ((p.flags & 16) == 0 || !_atOrAfter(s.nextServer, p.acknowledgement)) {
      return null;
    }
    if (s.unacked != null && _atOrAfter(p.acknowledgement, s.unackedEnd)) {
      s.unacked = null;
      s.retries = 0;
      s.established = true;
      if (s.finSent) {
        _sessions.remove(key);
        return null;
      }
    }
    if (p.sequence != s.nextClient) {
      return p.reply(s.nextServer, s.nextClient, 16);
    }
    if (p.payload.isNotEmpty && !s.closedInput) {
      if (s.input.length + p.payload.length > 65537) {
        _sessions.remove(key);
        return p.reply(s.nextServer, s.nextClient, 0x14);
      }
      s.input.addAll(p.payload);
      s.nextClient = (s.nextClient + p.payload.length) & 0xffffffff;
      if (!s.resolving &&
          s.input.length >= 2 &&
          s.input.length >= u16(s.input, 0) + 2) {
        s.resolving = true;
        s.closedInput = true;
        final q = Uint8List.fromList(s.input.sublist(2, u16(s.input, 0) + 2));
        _respond(key, s, q);
      }
    }
    if ((p.flags & 1) != 0) {
      s.nextClient = (s.nextClient + 1) & 0xffffffff;
    }
    _pump(s);
    return p.payload.isNotEmpty || (p.flags & 1) != 0
        ? p.reply(s.nextServer, s.nextClient, 16)
        : null;
  }

  Future<void> _respond(String key, _Session s, Uint8List q) async {
    try {
      final response = await resolve(q);
      if (_sessions[key] != s) return;
      final framed = Uint8List(response.length + 2);
      s.input.clear();
      put16(framed, 0, response.length);
      framed.setRange(2, framed.length, response);
      for (var offset = 0; offset < framed.length; offset += 512) {
        s.output.add(
          Uint8List.sublistView(
            framed,
            offset,
            min(offset + 512, framed.length),
          ),
        );
      }
      _pump(s);
    } catch (_) {
      if (_sessions.remove(key) == s) {
        emit(s.packet.reply(s.nextServer, s.nextClient, 0x14));
      }
    }
  }

  void _pump(_Session s) {
    if (!s.established || s.unacked != null || u16(s.packet.header, 14) == 0) {
      return;
    }
    Uint8List? packet;
    if (s.output.isNotEmpty) {
      var data = s.output.removeAt(0);
      final window = u16(s.packet.header, 14);
      if (data.length > window) {
        s.output.insert(0, Uint8List.sublistView(data, window));
        data = Uint8List.sublistView(data, 0, window);
      }
      packet = s.packet.reply(s.nextServer, s.nextClient, 0x18, data);
      s.nextServer = (s.nextServer + data.length) & 0xffffffff;
    } else if (s.resolving && s.closedInput && !s.finSent && s.input.isEmpty) {
      packet = s.packet.reply(s.nextServer, s.nextClient, 0x11);
      s.nextServer = (s.nextServer + 1) & 0xffffffff;
      s.finSent = true;
    }
    if (packet != null) {
      s.unacked = packet;
      s.unackedEnd = s.nextServer;
      s.sent = DateTime.now();
      emit(packet);
    }
  }

  void _tick() {
    final now = DateTime.now();
    for (final key in _sessions.keys.toList()) {
      final s = _sessions[key]!;
      if (now.difference(s.touched).inSeconds > 20 || s.retries >= 4) {
        _sessions.remove(key);
        continue;
      }
      if (s.unacked != null && now.difference(s.sent).inSeconds >= 2) {
        s.retries++;
        s.sent = now;
        emit(s.unacked!);
      }
    }
    if (_sessions.isEmpty) {
      _timer?.cancel();
      _timer = null;
    }
  }
}

import 'dart:typed_data';

import 'package:flutter_test/flutter_test.dart';
import 'package:zowy_adblocker/protection/dns_wire.dart';
import 'package:zowy_adblocker/protection/dns_resolver.dart';

import 'fixtures.dart';

void main() {
  test(
    'cache byte budget includes large query keys, not only small answers',
    () {
      final cache = DnsCache(8192);
      final q = makeQuery('example.com');
      final first = Uint8List(64000)..setRange(0, q.length, q);
      for (var i = 0; i < 100; i++) {
        final padded = Uint8List.fromList(first)..[63999] = i;
        cache.put(padded, answer(q));
      }
      expect(cache.get(first), isNull);
      final last = Uint8List.fromList(first)..[63999] = 99;
      expect(cache.get(last), isNotNull);
    },
  );
  test('DNS questions and negative responses preserve ID and question', () {
    final q = makeQuery('ads.example', type: 28);
    final r = dnsError(q, 3);
    validateResponse(q, r);
    expect(DnsQuestion.parse(q).type, 28);
    expect(r[3] & 15, 3);
    expect(u16(r, 0), u16(q, 0));
    expect(u16(r, 6), 0);
  });
  test('reject truncation, compressed questions, mismatched IDs and record lengths', () {
    final q = makeQuery('example.com');
    for (var i = 0; i < q.length; i++) {
      expect(
        () => DnsQuestion.parse(Uint8List.sublistView(q, 0, i)),
        throwsFormatException,
      );
    }
    final bad = Uint8List.fromList(q)..[12] = 0xc0;
    expect(() => DnsQuestion.parse(bad), throwsFormatException);
    final r = answer(q);
    r[0] ^= 1;
    expect(() => validateResponse(q, r), throwsFormatException);
    final short = answer(q).sublist(0, q.length + 4);
    expect(
      () => validateResponse(q, Uint8List.fromList(short)),
      throwsFormatException,
    );
  });
  for (final ipv6 in [false, true]) {
    test(
      '${ipv6 ? 'IPv6' : 'IPv4'} packet reply swaps addresses, ports and validates checksums',
      () {
        final q = makeQuery('example.com');
        final input = udpPacket(q, ipv6: ipv6);
        final packet = IpDnsPacket.parse(input);
        expect(packet.sourcePort, 34000);
        expect(packet.dns, q);
        final r = packet.reply(answer(q));
        final h = ipv6 ? 40 : 20, n = r.length - h;
        expect(u16(r, h), 53);
        expect(u16(r, h + 2), 34000);
        if (!ipv6) expect(checksum(r.sublist(0, 20)), 0);
        final pseudo = ipv6
            ? [...r.sublist(8, 40), 0, 0, n >> 8, n & 255, 0, 0, 0, 17]
            : [...r.sublist(12, 20), 0, 17, n >> 8, n & 255];
        expect(checksum([...pseudo, ...r.sublist(h)]), 0);
      },
    );
  }
  test('fragmented IP packets are rejected', () {
    final b = udpPacket(makeQuery('example.com'));
    put16(b, 6, 0x2000);
    expect(() => IpDnsPacket.parse(b), throwsFormatException);
  });
  test('UDP checksum corruption and zero IPv6 checksum are rejected', () {
    final bad = udpPacket(makeQuery('example.com'));
    bad[bad.length - 1] ^= 1;
    expect(() => IpDnsPacket.parse(bad), throwsFormatException);
    final ipv6 = udpPacket(makeQuery('example.com'), ipv6: true);
    put16(ipv6, 46, 0);
    expect(() => IpDnsPacket.parse(ipv6), throwsFormatException);
  });
  test(
    'cache obeys TTL, rewrites ID, evicts LRU, and excludes negative answers',
    () {
      final cache = DnsCache(1), now = DateTime(2026);
      final a = makeQuery('example.com'), b = makeQuery('other.example');
      cache.put(a, answer(a, ttl: 60), now: now);
      final same = Uint8List.fromList(a);
      put16(same, 0, 42);
      final hit = cache.get(same, now: now.add(const Duration(seconds: 20)))!;
      expect(u16(hit, 0), 42);
      expect(ttlFields(hit).values.single, 40);
      expect(cache.get(a, now: now.add(const Duration(seconds: 60))), isNull);
      cache.put(a, answer(a), now: now);
      cache.put(b, answer(b), now: now);
      expect(cache.get(a, now: now), isNull);
      cache.clear();
      cache.put(a, dnsError(a, 3), now: now);
      expect(cache.get(a, now: now), isNull);
      final disabled = DnsCache(0)..put(a, answer(a));
      expect(disabled.get(a), isNull);
    },
  );
}

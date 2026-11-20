import 'dart:convert';
import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:zowy_adblocker/core/config.dart';
import 'package:zowy_adblocker/data/filter_lists.dart';

void main() {
  test(
    'temporary exceptions reject invalid names, timestamps and oversized maps',
    () {
      for (final values in [
        <String, int>{'bad/name': 0},
        <String, int>{'ok.example': -1},
        {for (var i = 0; i < 257; i++) 'allow$i.example': 0},
      ]) {
        final config = AppConfig(temporaryAllows: values);
        expect(() => AppConfig.decode(config.encode()), throwsFormatException);
      }
    },
  );
  test('configuration roundtrip preserves user rules and settings', () {
    final original = AppConfig(
      userRules: '@@||safe.example^',
      logging: true,
      excludedApps: ['com.example.app'],
      temporaryAllows: {'test.example': 123},
    );
    expect(AppConfig.decode(original.encode()).toJson(), original.toJson());
  });
  test('imports reject traversal, unsafe URLs, incompatible versions and VPN loops', () {
    final json = AppConfig().toJson();
    final bad = jsonDecode(jsonEncode(json)) as Map<String, dynamic>;
    (bad['sources'] as List).first['id'] = '../escape';
    expect(() => AppConfig.decode(jsonEncode(bad)), throwsFormatException);
    bad['sources'] = [
      {'id': 'test', 'name': 'test', 'url': 'http://example.com'},
    ];
    expect(() => AppConfig.decode(jsonEncode(bad)), throwsFormatException);
    json['version'] = 999;
    expect(() => AppConfig.decode(jsonEncode(json)), throwsFormatException);
    final upstream = presets.first.toJson()..['address'] = '10.111.0.1';
    expect(() => Upstream.fromJson(upstream), throwsFormatException);
  });
  test('failed imports preserve previous working list and user rules compile separately', () async {
    final dir = await Directory.systemTemp.createTemp('zowy-test-');
    try {
      final manager = FilterListManager(dir);
      final config = AppConfig(userRules: '@@||safe.ads.example^');
      final source = config.sources.first;
      await manager.importText(source, '||ads.example^');
      await expectLater(
        manager.importText(source, '<html>error</html>'),
        throwsFormatException,
      );
      expect(await manager.file(source).readAsString(), '||ads.example^');
      final engine = await manager.compile(config);
      expect(engine.match('safe.ads.example')?.allow, true);
      expect(engine.match('ads.example')?.allow, false);
      source.enabled = false;
      expect((await manager.compile(config)).match('ads.example'), isNull);
    } finally {
      await dir.delete(recursive: true);
    }
  });
}

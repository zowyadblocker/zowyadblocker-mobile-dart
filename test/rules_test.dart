import 'package:flutter_test/flutter_test.dart';
import 'package:zowy_adblocker/protection/rules.dart';

void main() {
  test('domain boundaries, case and subdomains are enforced', () {
    final engine = FilterEngine()
      ..add(
        '||ads.example^\n0.0.0.0 tracker.example alias.example # comment',
        'fixture',
      );
    expect(engine.match('A.ADS.EXAMPLE.')?.allow, false);
    expect(engine.match('notads.example'), isNull);
    expect(engine.match('alias.example')?.rule, contains('0.0.0.0'));
  });
  test('exceptions override blocks; important block overrides exception', () {
    final engine = FilterEngine()
      ..add(
        '||ads.example^\n@@||safe.ads.example^\n'
            r'||force.ads.example^$important'
            '\n@@||force.ads.example^',
        'fixture',
      );
    expect(engine.match('safe.ads.example')?.allow, true);
    expect(engine.match('force.ads.example')?.allow, false);
    expect(
      engine.match('ads.example', temporary: {'ads.example': 0})?.allow,
      true,
    );
    expect(
      engine.match('ads.example', temporary: {'ads.example': 1})?.allow,
      false,
    );
  });
  test('contextual and cosmetic rules are never broadened into DNS blocks', () {
    final engine = FilterEngine();
    final report = engine.add(
      '||ads.example^\n||ads.example^\n'
          r'||video.example^$third-party'
          '\n||cdn.example/ad.js\n'
          'news.example##.ad\n/ads[0-9]+/\n*.wild.example\ninvalid_domain\n'
          '127.0.0.1 localhost\n! comment',
      'fixture',
    );
    expect(report.loaded, 1);
    expect(report.duplicates, 1);
    expect(report.unsupported, 5);
    expect(report.invalid, 2);
    for (final domain in [
      'video.example',
      'cdn.example',
      'news.example',
      'wild.example',
    ]) {
      expect(engine.match(domain), isNull);
    }
  });
  test('hostile long rules are bounded', () {
    final report = FilterEngine().add('a' * 5000, 'fixture');
    expect(report.invalid, 1);
    expect(validDomain('-ads.example'), false);
    expect(validDomain('ads..example'), false);
    expect(validDomain('127.0.0.1'), false);
  });
}

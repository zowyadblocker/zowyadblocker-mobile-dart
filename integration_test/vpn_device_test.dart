import 'dart:convert';

import 'package:flutter_test/flutter_test.dart';
import 'package:integration_test/integration_test.dart';
import 'package:zowy_adblocker/core/config.dart';
import 'package:zowy_adblocker/main.dart' as app;
import 'package:zowy_adblocker/services/platform.dart';

void main() {
  IntegrationTestWidgetsFlutterBinding.ensureInitialized();
  testWidgets('real foreground VPN handles external UDP/TCP IPv4/IPv6 probes', (
    tester,
  ) async {
    final platform = AndroidPlatform();
    await platform.save(
      AppConfig(sources: [], userRules: '||previous.zowy.test^'),
    );
    await platform.save(
      AppConfig(sources: [], userRules: '||blocked.zowy.test^', logging: true),
    );
    await platform.save(await platform.load());
    final backup = AppConfig.decode(
      (await platform.call<String>('restoreConfig'))!,
    );
    expect(backup.userRules, '||previous.zowy.test^');
    app.main();
    await tester.pumpAndSettle();
    // flutter test may reinstall the package and reset the emulator's app-op.
    // Only the host test script authorizes the disposable emulator at this point.
    // ignore: avoid_print
    print('ZOWY_VPN_AUTH_READY');
    var prepared = false;
    await tester.runAsync(() async {
      for (var i = 0; i < 90; i++) {
        final caps = await platform.call<Map>('capabilities');
        prepared = caps?['vpnPrepared'] == true;
        if (prepared) break;
        await Future<void>.delayed(const Duration(seconds: 1));
      }
    });
    expect(
      prepared,
      true,
      reason: 'Run tools/test-emulator.ps1 to authorize only the disposable emulator.',
    );
    await platform.call<void>('start');
    Map<String, dynamic> state = {};
    await tester.runAsync(() async {
      for (var i = 0; i < 30; i++) {
        state = jsonDecode(
          (await platform.call<String>('snapshot'))!,
        ) as Map<String, dynamic>;
        if (state['status'] == 'running' || state['status'] == 'error') break;
        await Future<void>.delayed(const Duration(seconds: 1));
      }
    });
    expect(state['status'], 'running', reason: state.toString());
    // Host script now runs the independent shell-UID probe, which is inside VPN.
    // The app itself is excluded to keep all upstream/bootstrap traffic outside TUN.
    // ignore: avoid_print
    print('ZOWY_TUN_TEST_READY');
    await tester.runAsync(() async {
      for (var i = 0; i < 90; i++) {
        state = jsonDecode(
          (await platform.call<String>('snapshot'))!,
        ) as Map<String, dynamic>;
        final recorded = (state['logs'] as List? ?? []).cast<Map>();
        if (recorded.where((e) => e['domain'] == 'blocked.zowy.test').length >=
                4 &&
            recorded.where((e) => e['domain'] == 'example.com').length >= 4) {
          break;
        }
        await Future<void>.delayed(const Duration(seconds: 1));
      }
    });
    expect(state['blocked'], greaterThanOrEqualTo(4), reason: state.toString());
    expect(state['allowed'], greaterThanOrEqualTo(4), reason: state.toString());
    final fixtures = (state['logs'] as List).cast<Map>().where(
      (e) => e['domain'] == 'blocked.zowy.test' || e['domain'] == 'example.com',
    );
    expect(fixtures.length, greaterThanOrEqualTo(8));
    expect(fixtures.where((e) => e['error'] != null), isEmpty);
    await platform.call<void>('clearLogs');
    await tester.runAsync(
      () => Future<void>.delayed(const Duration(seconds: 1)),
    );
    final cleared =
        jsonDecode((await platform.call<String>('snapshot'))!) as Map;
    expect(cleared['logs'], isEmpty);
    await platform.call<void>('stop');
    await tester.pumpAndSettle();
    expect(find.text('Protection is off'), findsOneWidget);
  });
}

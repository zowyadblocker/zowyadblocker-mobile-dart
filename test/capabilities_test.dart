import 'dart:async';
import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:zowy_adblocker/app/controller.dart';
import 'package:zowy_adblocker/core/config.dart';
import 'package:zowy_adblocker/services/platform.dart';

class _Platform extends AndroidPlatform {
  _Platform(this.path);
  final Directory path;
  final events = StreamController<Map<String, dynamic>>();
  bool shizukuRunning = true;
  @override
  Future<AppConfig> load() async => AppConfig(sources: []);
  @override
  Future<Directory> directory() async => path;
  @override
  Stream<Map<String, dynamic>> get updates => events.stream;
  @override
  Future<T?> call<T>(String method, [Object? args]) async {
    final Object? value = switch (method) {
      'snapshot' => '{"status":"stopped"}',
      'capabilities' => {
        'shizukuRunning': shizukuRunning,
        'shizukuGranted': shizukuRunning,
      },
      _ => null,
    };
    return value as T?;
  }
}

void main() {
  test('binder disconnect refreshes capabilities instead of retaining a running badge', () async {
    final path = await Directory.systemTemp.createTemp('zowy-caps-');
    final platform = _Platform(path);
    final controller = AppController(platform: platform);
    try {
      await controller.initialize();
      expect(controller.capabilities['shizukuRunning'], true);
      final refreshed = Completer<void>();
      controller.addListener(() {
        if (controller.capabilities['shizukuRunning'] == false &&
            !refreshed.isCompleted) {
          refreshed.complete();
        }
      });
      platform.shizukuRunning = false;
      platform.events.add({'status': 'stopped', 'capabilitiesChanged': true});
      await refreshed.future.timeout(const Duration(seconds: 2));
      expect(controller.capabilities['shizukuGranted'], false);
    } finally {
      controller.dispose();
      await platform.events.close();
      await path.delete(recursive: true);
    }
  });
}

import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:zowy_adblocker/app/controller.dart';
import 'package:zowy_adblocker/core/config.dart';
import 'package:zowy_adblocker/data/filter_lists.dart';
import 'package:zowy_adblocker/services/platform.dart';

class _Platform extends AndroidPlatform {
  _Platform(this.path);
  final Directory path;
  final calls = <String>[];
  @override
  Future<Directory> directory() async => path;
  @override
  Stream<Map<String, dynamic>> get updates => const Stream.empty();
  @override
  Future<T?> call<T>(String method, [Object? args]) async {
    calls.add(method);
    return (method == 'capabilities' ? <String, dynamic>{} : null) as T?;
  }
}

class _Lists extends FilterListManager {
  _Lists(super.directory);
  int downloads = 0;
  bool fail = false;
  @override
  Future<void> update(FilterSource source, {bool force = false}) async {
    downloads++;
    if (fail) throw const SocketException('Offline');
    await importText(source, '||ads.example.com^');
  }
}

void main() {
  late Directory path;
  late _Platform platform;
  late AppController controller;
  late _Lists lists;
  setUp(() async {
    path = await Directory.systemTemp.createTemp('zowy-first-start-');
    platform = _Platform(path);
    controller = AppController(platform: platform);
    await controller.initialize();
    lists = _Lists(path);
    controller.lists = lists;
  });
  tearDown(() async {
    controller.dispose();
    await path.delete(recursive: true);
  });

  test(
    'fresh install downloads rules and starts with one power-button tap',
    () async {
      expect(controller.engine.size, 0);
      await controller.toggleProtection();
      expect(controller.error, isNull);
      expect(lists.downloads, 1);
      expect(controller.engine.match('ads.example.com')?.allow, false);
      expect(platform.calls.last, 'start');
      expect(
        platform.calls.indexOf('saveConfig'),
        lessThan(platform.calls.indexOf('start')),
      );
      await controller.toggleProtection();
      expect(lists.downloads, 1);
    },
  );

  test(
    'failed first download does not start VPN and the same button retries',
    () async {
      lists.fail = true;
      await controller.toggleProtection();
      expect(platform.calls, isNot(contains('start')));
      expect(controller.error, contains('try again'));
      expect(controller.notice, isNull);
      expect(controller.busy, false);
      lists.fail = false;
      await controller.toggleProtection();
      expect(controller.error, isNull);
      expect(platform.calls.last, 'start');
    },
  );

  test('custom rules start offline without downloading lists', () async {
    controller.config.userRules = '||custom.example.com^';
    await controller.reloadLists();
    lists.fail = true;
    await controller.toggleProtection();
    expect(controller.error, isNull);
    expect(lists.downloads, 0);
    expect(platform.calls.last, 'start');
  });

  test(
    'disabled lists stay disabled and empty protection is not started',
    () async {
      controller.config.sources.single.enabled = false;
      await controller.toggleProtection();
      expect(lists.downloads, 0);
      expect(platform.calls, isNot(contains('start')));
      expect(controller.error, contains('add custom rules'));
    },
  );

  test('stopping protection does not download rules', () async {
    controller.snapshot = {'status': 'running'};
    await controller.toggleProtection();
    expect(platform.calls.last, 'stop');
    expect(lists.downloads, 0);
  });
}

import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'package:flutter/services.dart';

import '../core/config.dart';

class AndroidPlatform {
  static const channel = MethodChannel('dev.zowy/control');
  static const events = EventChannel('dev.zowy/events');
  Future<T?> call<T>(String method, [Object? args]) =>
      channel.invokeMethod<T>(method, args);
  Future<AppConfig> load() async {
    final text = await call<String>('loadConfig');
    return text == null ? AppConfig() : AppConfig.decode(text);
  }

  Future<void> save(AppConfig config) async {
    AppConfig.decode(config.encode());
    await call<void>('saveConfig', config.encode());
  }

  Future<Directory> directory() async =>
      Directory('${await call<String>('dataPath')}/filters');
  Stream<Map<String, dynamic>> get updates =>
      events.receiveBroadcastStream().map(
        (event) =>
            Map<String, dynamic>.from(jsonDecode(event as String) as Map),
      );
}

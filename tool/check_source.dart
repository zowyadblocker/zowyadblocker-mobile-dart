import 'dart:io';
import 'dart:convert';

import 'package:zowy_adblocker/core/config.dart';
import 'package:zowy_adblocker/data/filter_lists.dart';

Future<void> main() async {
  final config = AppConfig();
  final manager = FilterListManager(Directory('.tools/list-check'));
  final source = config.sources.single;
  await manager.update(source);
  final engine = await manager.compile(config);
  if (engine.size == 0) {
    throw StateError('Downloaded source has no enforceable rules.');
  }
  stdout.writeln(
    jsonEncode({
      'source': source.url,
      'engineRules': engine.size,
      'metadata': await manager.info(source),
    }),
  );
}

import 'dart:convert';
import 'dart:io';
import 'dart:isolate';
import 'dart:typed_data';

import '../core/config.dart';
import '../protection/rules.dart';

class FilterListManager {
  FilterListManager(this.directory);
  final Directory directory;
  File file(FilterSource source) => File('${directory.path}/${source.id}.txt');
  File metadata(FilterSource source) =>
      File('${directory.path}/${source.id}.json');
  Future<Map<String, dynamic>> info(FilterSource source) async {
    try {
      return jsonDecode(await metadata(source).readAsString())
          as Map<String, dynamic>;
    } on FileSystemException {
      return {};
    } on FormatException {
      return {};
    }
  }

  Future<FilterEngine> compile(AppConfig config) async {
    final texts = <String, String>{};
    var total = 0;
    for (final source in config.sources.where((s) => s.enabled)) {
      final f = file(source);
      if (await f.exists()) {
        final size = await f.length();
        total += size;
        if (size > 32 * 1024 * 1024 || total > 64 * 1024 * 1024) {
          throw const FormatException('Active lists exceed the 64 MiB budget.');
        }
        texts['${source.name} [${source.id}]'] = await f.readAsString();
      }
    }
    texts['My rules'] = config.userRules;
    return Isolate.run(() {
      final engine = FilterEngine();
      for (final entry in texts.entries) {
        engine.add(entry.value, entry.key);
      }
      return engine;
    });
  }

  Future<RuleReport> importText(FilterSource source, String text) async {
    final report = await Isolate.run(
      () => FilterEngine().add(text, source.name),
    );
    if (report.loaded == 0) {
      throw const FormatException('No enforceable DNS rules found.');
    }
    await directory.create(recursive: true);
    await atomicWrite(file(source), text);
    await atomicWrite(
      metadata(source),
      jsonEncode({
        ...report.toJson(),
        'updated': DateTime.now().toIso8601String(),
      }),
    );
    return report;
  }

  Future<void> update(FilterSource source, {bool force = false}) async {
    final old = await info(source);
    final client = HttpClient()
      ..connectionTimeout = const Duration(seconds: 15);
    client.autoUncompress = false;
    try {
      final uri = Uri.parse(source.url);
      if (uri.scheme != 'https' || uri.userInfo.isNotEmpty) {
        throw const FormatException(
          'Only credential-free HTTPS sources are supported.',
        );
      }
      final request = await client
          .getUrl(uri)
          .timeout(const Duration(seconds: 15));
      request.followRedirects = false;
      request.headers.set('accept-encoding', 'identity');
      request.headers.set('user-agent', 'Zowy/0.1 filter-updater');
      if (!force && await file(source).exists()) {
        if (old['etag'] != null) {
          request.headers.set('if-none-match', old['etag']);
        }
        if (old['modified'] != null) {
          request.headers.set('if-modified-since', old['modified']);
        }
      }
      final response = await request.close().timeout(
        const Duration(seconds: 15),
      );
      if (response.statusCode == 304 && await file(source).exists()) {
        await response.drain<void>();
        await atomicWrite(
          metadata(source),
          jsonEncode({...old, 'updated': DateTime.now().toIso8601String()}),
        );
        return;
      }
      if (response.statusCode != 200 ||
          response.headers.value('content-encoding') != null ||
          (response.contentLength > 32 * 1024 * 1024)) {
        throw HttpException(
          'List rejected: HTTP ${response.statusCode}, encoding or size.',
        );
      }
      final bytes = BytesBuilder(copy: false);
      final deadline = DateTime.now().add(const Duration(seconds: 90));
      await for (final chunk in response.timeout(const Duration(seconds: 15))) {
        if (bytes.length + chunk.length > 32 * 1024 * 1024 ||
            DateTime.now().isAfter(deadline)) {
          throw const FormatException(
            'Download exceeded its size or time budget.',
          );
        }
        bytes.add(chunk);
      }
      final text = utf8.decode(bytes.takeBytes());
      if (text.contains('\u0000') ||
          text.trimLeft().startsWith('<') ||
          response.headers.contentType?.mimeType == 'text/html') {
        throw const FormatException(
          'Expected a text filter list, received unexpected content.',
        );
      }
      final report = await importText(source, text);
      await atomicWrite(
        metadata(source),
        jsonEncode({
          ...report.toJson(),
          'updated': DateTime.now().toIso8601String(),
          'etag': response.headers.value('etag'),
          'modified': response.headers.value('last-modified'),
        }),
      );
    } finally {
      client.close(force: true);
    }
  }
}

Future<void> atomicWrite(File file, String text) async {
  final temp = File(
    '${file.path}.${DateTime.now().microsecondsSinceEpoch}.tmp',
  );
  try {
    await temp.writeAsString(text, flush: true);
    await temp.rename(file.path);
  } finally {
    if (await temp.exists()) await temp.delete();
  }
}

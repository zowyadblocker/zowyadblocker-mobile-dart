import 'dart:convert';
import 'dart:io';

import 'package:zowy_adblocker/protection/rules.dart';

void main(List<String> args) {
  final counts = args.isEmpty ? [100000, 500000, 1000000] : args.map(int.parse);
  for (final count in counts) {
    final before = ProcessInfo.currentRss;
    final text = List.generate(
      count,
      (i) => '||ads$i.fixture.example^',
    ).join('\n');
    final compile = Stopwatch()..start();
    final engine = FilterEngine()..add(text, 'synthetic');
    compile.stop();
    final watch = Stopwatch()..start();
    var hits = 0;
    for (var i = 0; i < 100000; i++) {
      if (engine.match('ads${i % count}.fixture.example') != null) hits++;
    }
    watch.stop();
    if (hits != 100000 || engine.size != count) {
      throw StateError('Benchmark correctness failed');
    }
    stdout.writeln(
      jsonEncode({
        'rules': count,
        'compileMs': compile.elapsedMilliseconds,
        'lookup100kMs': watch.elapsedMilliseconds,
        'rssBefore': before,
        'rssAfter': ProcessInfo.currentRss,
        'maxRss': ProcessInfo.maxRss,
        'runtime': Platform.version,
        'fixture': 'synthetic domain-only, desktop; not Android battery data',
      }),
    );
  }
}

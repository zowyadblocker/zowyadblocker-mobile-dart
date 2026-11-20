import 'dart:convert';

import '../core/domain.dart';
export '../core/domain.dart';

class RuleMatch {
  const RuleMatch(this.domain, this.rule, this.source, this.allow);
  final String domain, rule, source;
  final bool allow;
}

class RuleReport {
  int loaded = 0, unsupported = 0, invalid = 0, duplicates = 0;
  Map<String, int> toJson() => {
    'loaded': loaded,
    'unsupported': unsupported,
    'invalid': invalid,
    'duplicates': duplicates,
  };
}

/// Only compiles syntax whose complete meaning exists at DNS time.
/// This is not uBlock Origin's engine.
class FilterEngine {
  final Map<String, RuleMatch> _block = {}, _allow = {}, _important = {};
  final Map<String, RuleReport> reports = {};
  int get size => _block.length + _allow.length + _important.length;
  Iterable<String> get blockedDomains => _block.keys
      .followedBy(_important.keys)
      .where((d) => match(d)?.allow == false)
      .toSet();

  RuleReport add(String raw, String source) {
    if (raw.length > 32 * 1024 * 1024) {
      throw const FormatException('List exceeds 32 MiB.');
    }
    final report = RuleReport();
    reports[source] = report;
    for (var line in LineSplitter.split(raw)) {
      line = line.trim();
      if (line.isEmpty ||
          line.startsWith('!') ||
          line.startsWith('#') ||
          line.startsWith('[')) {
        continue;
      }
      if (line.length > 4096) {
        report.invalid++;
        continue;
      }
      final original = line;
      var allow = false, important = false;
      if (line.startsWith('@@')) {
        allow = true;
        line = line.substring(2);
      }
      if (line.endsWith(r'$important') && !allow) {
        important = true;
        line = line.substring(0, line.length - 10);
      }
      if (line.startsWith('||') && line.endsWith('^')) {
        line = line.substring(2, line.length - 1);
      } else if (line.contains(RegExp(r'\s'))) {
        final fields = line.split(RegExp(r'\s+'));
        if (!['0.0.0.0', '127.0.0.1', '::', '::1'].contains(fields.first)) {
          report.unsupported++;
          continue;
        }
        final hosts = fields.skip(1).takeWhile((p) => !p.startsWith('#'));
        for (final host in hosts) {
          final d = host.toLowerCase();
          if (validDomain(d)) {
            _put(d, original, source, false, false, report);
          } else {
            report.invalid++;
          }
        }
        continue;
      }
      line = line.toLowerCase();
      if (!validDomain(line)) {
        if (RegExp(r'[|^$/*#@:=<>]').hasMatch(line)) {
          report.unsupported++;
        } else {
          report.invalid++;
        }
        continue;
      }
      _put(line, original, source, allow, important, report);
      if (size > 1500000) throw const FormatException('Rule limit exceeded.');
    }
    return report;
  }

  void _put(
    String d,
    String rule,
    String source,
    bool allow,
    bool important,
    RuleReport report,
  ) {
    final target = important ? _important : (allow ? _allow : _block);
    if (target.containsKey(d)) {
      report.duplicates++;
      return;
    }
    if (size >= 1500000) throw const FormatException('Rule limit exceeded.');
    target[d] = RuleMatch(d, rule, source, allow);
    report.loaded++;
  }

  RuleMatch? _lookup(Map<String, RuleMatch> rules, String host) {
    var suffix = host;
    while (true) {
      if (rules.containsKey(suffix)) return rules[suffix];
      final dot = suffix.indexOf('.');
      if (dot < 0) return null;
      suffix = suffix.substring(dot + 1);
    }
  }

  RuleMatch? match(String domain, {Map<String, int> temporary = const {}}) {
    final host = domain.toLowerCase().replaceFirst(RegExp(r'\.$'), '');
    final now = DateTime.now().millisecondsSinceEpoch;
    for (final entry in temporary.entries) {
      if ((entry.value == 0 || entry.value > now) &&
          (host == entry.key || host.endsWith('.${entry.key}'))) {
        return RuleMatch(
          entry.key,
          '@@||${entry.key}^',
          'Temporary allowlist',
          true,
        );
      }
    }
    return _lookup(_important, host) ??
        _lookup(_allow, host) ??
        _lookup(_block, host);
  }
}

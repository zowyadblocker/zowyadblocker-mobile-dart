import 'dart:async';
import 'dart:convert';

import 'package:flutter/foundation.dart';

import '../core/config.dart';
import '../data/filter_lists.dart';
import '../protection/dns_resolver.dart';
import '../protection/dns_wire.dart';
import '../protection/rules.dart';
import '../services/platform.dart';

class AppController extends ChangeNotifier {
  AppController({AndroidPlatform? platform})
    : platform = platform ?? AndroidPlatform();
  final AndroidPlatform platform;
  AppConfig config = AppConfig();
  FilterListManager? lists;
  FilterEngine engine = FilterEngine();
  Map<String, dynamic> snapshot = {}, capabilities = {};
  Map<String, Map<String, dynamic>> listInfo = {};
  List<Map<String, dynamic>> applications = [];
  final _icons = <String, Future<Uint8List?>>{};
  Future<Uint8List?> icon(String package) => _icons.putIfAbsent(
    package,
    () => platform.call<Uint8List>('appIcon', package),
  );
  bool busy = false, initialized = false;
  String? error, notice;
  StreamSubscription<Map<String, dynamic>>? _events;
  bool get running => snapshot['status'] == 'running';
  bool _stopping = false;
  bool get canStopProtection => running || snapshot['status'] == 'starting';
  bool get canToggleProtection => !_stopping && (!busy || canStopProtection);
  int count(String key) => (snapshot[key] as num?)?.toInt() ?? 0;
  Future<void> initialize() async {
    await run(() async {
      config = await platform.load();
      lists = FilterListManager(await platform.directory());
      await reloadLists();
      final raw = await platform.call<String>('snapshot');
      if (raw != null) snapshot = jsonDecode(raw) as Map<String, dynamic>;
      await refreshCapabilities();
      _events = platform.updates.listen(
        (s) {
          snapshot = s;
          if (s['capabilitiesChanged'] == true) {
            unawaited(_capabilitiesChanged());
          }
          notifyListeners();
        },
        onError: (Object e) {
          error = e.toString();
          notifyListeners();
        },
      );
      initialized = true;
    });
  }

  Future<void> run(Future<void> Function() action) async {
    if (busy) return;
    busy = true;
    error = notice = null;
    notifyListeners();
    try {
      await action();
    } catch (e) {
      error = e.toString();
    } finally {
      busy = false;
      notifyListeners();
    }
  }

  Future<void> save() async {
    await platform.save(config);
    await reloadLists();
  }

  Future<void> reloadLists() async {
    if (lists == null) return;
    engine = await lists!.compile(config);
    listInfo = {for (final s in config.sources) s.id: await lists!.info(s)};
  }

  Future<void> refreshCapabilities() async {
    capabilities = Map<String, dynamic>.from(
      (await platform.call<Map>('capabilities'))!,
    );
  }

  Future<void> _capabilitiesChanged() async {
    try {
      await refreshCapabilities();
    } catch (e) {
      capabilities = {
        ...capabilities,
        'shizukuRunning': false,
        'shizukuGranted': false,
        'shizukuUid': null,
      };
      error = 'Capability refresh failed: $e';
    }
    notifyListeners();
  }

  Future<void> toggleProtection() async {
    if (!canToggleProtection) return;
    if (canStopProtection) {
      _stopping = true;
      error = notice = null;
      notifyListeners();
      try {
        await platform.call<void>('stop');
      } catch (e) {
        error = e.toString();
      } finally {
        _stopping = false;
        notifyListeners();
      }
      return;
    }
    await run(() async {
      if (engine.size == 0 && config.sources.any((s) => s.enabled)) {
        notice = 'Downloading filter lists before starting protection…';
        notifyListeners();
        await _updateLists(force: false);
        notice = null;
      }
      if (engine.size == 0) {
        throw StateError(
          'Download a filter list or add custom rules before enabling protection.',
        );
      }
      await platform.save(config);
      await platform.call<void>('start');
    });
  }

  Future<void> updateLists({bool force = true}) => run(() async {
    await _updateLists(force: force);
    notice =
        'Filter lists updated. Previous versions were retained on failure.';
  });

  Future<void> _updateLists({required bool force}) async {
    final failures = <String>[];
    for (final source in config.sources.where((s) => s.enabled)) {
      try {
        await lists!.update(source, force: force);
      } catch (e) {
        failures.add('${source.name}: $e');
      }
    }
    await save();
    if (failures.isNotEmpty) {
      notice = null;
      throw StateError(
        'Could not download filter lists. Check your connection and try again.\n'
        '${failures.join('\n')}',
      );
    }
  }

  Future<void> testResolver() => run(() async {
    final resolver = DnsResolver(config.upstream);
    final watch = Stopwatch()..start();
    try {
      final r = await resolver.resolve(makeQuery('example.com'));
      notice =
          '${config.upstream.name}: DNS RCODE ${r[3] & 15}, ${watch.elapsedMilliseconds} ms. '
          'This tests the upstream connection; use the device checklist to test VPN routing.';
    } finally {
      resolver.close();
    }
  });
  Future<void> loadApplications() => run(() async {
    applications = ((await platform.call<List>('applications'))!)
        .map((a) => Map<String, dynamic>.from(a as Map))
        .toList();
  });
  String normalizeDomain(String domain) {
    final value = domain.trim().toLowerCase().replaceFirst(RegExp(r'\.$'), '');
    if (!validDomain(value)) {
      throw const FormatException('Enter a domain, such as example.com.');
    }
    return value;
  }

  RuleMatch? inspectDomain(String domain) =>
      engine.match(normalizeDomain(domain), temporary: config.temporaryAllows);

  Future<void> temporaryAllow(String domain, int minutes) => run(() async {
    final value = normalizeDomain(domain);
    final next = AppConfig.decode(config.encode());
    next.temporaryAllows[value] = minutes == 0
        ? 0
        : DateTime.now().add(Duration(minutes: minutes)).millisecondsSinceEpoch;
    await platform.save(next);
    config = next;
    notice =
        '$value is allowed ${minutes == 0 ? 'until removed' : 'for $minutes minutes'}.';
  });

  Future<void> removeTemporaryAllow(String domain) => run(() async {
    final next = AppConfig.decode(config.encode());
    next.temporaryAllows.remove(normalizeDomain(domain));
    await platform.save(next);
    config = next;
    notice = 'Temporary exception removed.';
  });

  Future<void> export(String name, String text) => run(() async {
    final saved = await platform.call<bool>('export', {
      'name': name,
      'text': text,
    });
    if (saved == true) notice = 'Saved $name to your selected location.';
  });
  Future<void> importConfig() => run(() async {
    final raw = await platform.call<String>('import');
    if (raw == null) return;
    final imported = AppConfig.decode(raw);
    await lists!.compile(imported);
    await platform.save(imported);
    config = imported;
    await reloadLists();
    notice = 'Settings imported. Download uncached lists. Restart VPN to apply app exclusions.';
  });
  @override
  void dispose() {
    _events?.cancel();
    super.dispose();
  }
}

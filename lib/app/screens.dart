import 'dart:convert';

import 'package:material_ui/material_ui.dart';

import '../core/config.dart';
import '../protection/rules.dart';
import 'controller.dart';

const purple = Color(0xff8b5cf6);

class ZowyApp extends StatefulWidget {
  const ZowyApp({super.key});
  @override
  State<ZowyApp> createState() => _ZowyAppState();
}

class _ZowyAppState extends State<ZowyApp> with WidgetsBindingObserver {
  final controller = AppController();
  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);
    controller.initialize();
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    if (state == AppLifecycleState.resumed && controller.initialized) {
      controller.run(controller.refreshCapabilities);
    }
  }

  @override
  void dispose() {
    WidgetsBinding.instance.removeObserver(this);
    controller.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) => MaterialApp(
    title: 'Zowy',
    debugShowCheckedModeBanner: false,
    theme: ThemeData(
      useMaterial3: true,
      brightness: Brightness.dark,
      scaffoldBackgroundColor: Colors.black,
      colorScheme: const ColorScheme.dark(
        primary: purple,
        secondary: Color(0xffc4b5fd),
        surface: Color(0xff111015),
      ),
      cardTheme: const CardThemeData(
        margin: EdgeInsets.zero,
        color: Color(0xff111015),
        elevation: 0,
      ),
      appBarTheme: const AppBarTheme(
        backgroundColor: Colors.black,
        centerTitle: false,
      ),
      inputDecorationTheme: InputDecorationTheme(
        filled: true,
        border: OutlineInputBorder(borderRadius: BorderRadius.circular(16)),
      ),
      navigationBarTheme: const NavigationBarThemeData(
        backgroundColor: Color(0xff0b090f),
        indicatorColor: Color(0xff352052),
      ),
    ),
    home: ListenableBuilder(
      listenable: controller,
      builder: (_, _) => ZowyShell(c: controller),
    ),
  );
}

class ZowyShell extends StatefulWidget {
  const ZowyShell({required this.c, super.key});
  final AppController c;
  @override
  State<ZowyShell> createState() => _ZowyShellState();
}

class _ZowyShellState extends State<ZowyShell> {
  int selected = 0;
  @override
  Widget build(BuildContext context) {
    final c = widget.c;
    const titles = [
      'Your quiet internet.',
      'Activity',
      'Filter lists',
      'Applications',
      'Settings',
    ];
    final pages = [
      HomePage(c: c),
      ActivityPage(c: c),
      FiltersPage(c: c),
      ApplicationsPage(c: c),
      SettingsPage(c: c),
    ];
    return Scaffold(
      appBar: AppBar(
        title: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            const Text(
              'ZOWY',
              style: TextStyle(
                color: purple,
                fontSize: 12,
                letterSpacing: 4,
                fontWeight: FontWeight.w800,
              ),
            ),
            Text(
              titles[selected],
              style: const TextStyle(fontSize: 25, fontWeight: FontWeight.w700),
            ),
          ],
        ),
        toolbarHeight: 88,
        actions: [
          IconButton(
            tooltip: 'Refresh capabilities',
            onPressed: c.busy ? null : () => c.run(c.refreshCapabilities),
            icon: const Icon(Icons.health_and_safety_outlined),
          ),
        ],
      ),
      body: SafeArea(
        child: Column(
          children: [
            if (c.busy) const LinearProgressIndicator(minHeight: 2),
            if (c.error != null || c.snapshot['serviceError'] != null)
              Message(
                text: c.error ?? c.snapshot['serviceError'].toString(),
                error: true,
              ),
            if (c.notice != null) Message(text: c.notice!),
            Expanded(
              child: !c.initialized
                  ? Center(
                      child: c.busy
                          ? const CircularProgressIndicator()
                          : FilledButton(
                              onPressed: c.initialize,
                              child: const Text('Retry initialization'),
                            ),
                    )
                  : Center(
                      child: ConstrainedBox(
                        constraints: const BoxConstraints(maxWidth: 800),
                        child: pages[selected],
                      ),
                    ),
            ),
          ],
        ),
      ),
      bottomNavigationBar: NavigationBar(
        selectedIndex: selected,
        onDestinationSelected: (index) {
          setState(() => selected = index);
          if (index == 3 && c.applications.isEmpty) c.loadApplications();
        },
        destinations: const [
          NavigationDestination(
            icon: Icon(Icons.shield_outlined),
            selectedIcon: Icon(Icons.shield),
            label: 'Protect',
          ),
          NavigationDestination(icon: Icon(Icons.radar), label: 'Activity'),
          NavigationDestination(icon: Icon(Icons.tune), label: 'Filters'),
          NavigationDestination(icon: Icon(Icons.apps), label: 'Apps'),
          NavigationDestination(
            icon: Icon(Icons.settings_outlined),
            label: 'Settings',
          ),
        ],
      ),
    );
  }
}

class Message extends StatelessWidget {
  const Message({required this.text, this.error = false, super.key});
  final String text;
  final bool error;
  @override
  Widget build(BuildContext context) => Container(
    width: double.infinity,
    color: error ? const Color(0xff38131d) : const Color(0xff211535),
    padding: const EdgeInsets.all(12),
    child: Text(
      text,
      style: TextStyle(
        color: error ? const Color(0xffffb4ab) : const Color(0xffddd0ff),
      ),
    ),
  );
}

class Panel extends StatelessWidget {
  const Panel({required this.children, super.key});
  final List<Widget> children;
  @override
  Widget build(BuildContext context) => Card(
    child: Padding(
      padding: const EdgeInsets.all(20),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: children,
      ),
    ),
  );
}

Widget heading(String text) => Padding(
  padding: const EdgeInsets.symmetric(vertical: 12),
  child: Text(
    text,
    style: const TextStyle(fontSize: 19, fontWeight: FontWeight.w700),
  ),
);
Widget muted(String text) =>
    Text(text, style: const TextStyle(color: Color(0xffb9b3c4), height: 1.5));
Widget gap() => const SizedBox(height: 16);

class HomePage extends StatelessWidget {
  const HomePage({required this.c, super.key});
  final AppController c;
  @override
  Widget build(BuildContext context) {
    final blocked = c.count('blocked'), allowed = c.count('allowed');
    final percent = blocked + allowed == 0
        ? '0'
        : (100 * blocked / (blocked + allowed)).toStringAsFixed(1);
    return ListView(
      padding: const EdgeInsets.fromLTRB(20, 12, 20, 24),
      children: [
        Center(
          child: Semantics(
            label: c.canStopProtection
                ? 'Stop DNS protection'
                : 'Start DNS protection',
            button: true,
            child: AnimatedContainer(
              duration: const Duration(milliseconds: 300),
              margin: const EdgeInsets.all(20),
              padding: const EdgeInsets.all(14),
              decoration: BoxDecoration(
                shape: BoxShape.circle,
                border: Border.all(
                  color: purple.withValues(alpha: c.running ? .7 : .2),
                ),
                boxShadow: [
                  BoxShadow(
                    color: purple.withValues(alpha: c.running ? .18 : .04),
                    blurRadius: 50,
                    spreadRadius: 8,
                  ),
                ],
              ),
              child: SizedBox(
                width: 156,
                height: 156,
                child: FilledButton(
                  style: FilledButton.styleFrom(
                    shape: const CircleBorder(),
                    backgroundColor: c.running
                        ? purple
                        : const Color(0xff21182f),
                  ),
                  onPressed: !c.canToggleProtection
                      ? null
                      : () async {
                          if (!c.canStopProtection &&
                              c.capabilities['otherVpn'] == true) {
                            if (!await confirm(
                              context,
                              'Replace the active VPN?',
                              'Android allows one VPN per user. Starting Zowy will replace your current VPN.',
                            )) {
                              return;
                            }
                          }
                          await c.toggleProtection();
                        },
                  child: Icon(
                    c.running ? Icons.shield : Icons.power_settings_new,
                    size: 64,
                    color: Colors.white,
                  ),
                ),
              ),
            ),
          ),
        ),
        Center(
          child: Text(
            c.running
                ? 'VPN tunnel is up'
                : c.snapshot['status'] == 'starting'
                ? 'Starting protection…'
                : 'Protection is off',
            style: const TextStyle(fontSize: 23, fontWeight: FontWeight.w700),
          ),
        ),
        const SizedBox(height: 8),
        Center(child: muted('Local VPN · ${c.engine.size} compiled DNS rules')),
        gap(),
        if (c.capabilities['privateDns'] == true)
          const Message(
            text: 'Android Private DNS is active. It may bypass local DNS filtering. Check Network settings before relying on protection.',
            error: true,
          ),
        if (c.running) ...[ProtectionHealth(c: c), gap()],
        if (c.engine.size == 0)
          Panel(
            children: [
              heading('Start with a filter list'),
              muted(
                'Tap the power button to download the enabled HaGeZi list and start protection, or choose your own lists and rules in Filters. Internet access is needed for the first download.',
              ),
              gap(),
              FilledButton.icon(
                onPressed: c.busy ? null : c.updateLists,
                icon: const Icon(Icons.download),
                label: const Text('Download enabled lists'),
              ),
            ],
          ),
        gap(),
        Row(
          children: [
            Expanded(child: _metric('Blocked', '$blocked', Icons.block)),
            const SizedBox(width: 12),
            Expanded(
              child: _metric('Allowed', '$allowed', Icons.check_circle_outline),
            ),
          ],
        ),
        gap(),
        Panel(
          children: [
            Row(
              mainAxisAlignment: MainAxisAlignment.spaceBetween,
              children: [
                heading('This protection session'),
                Text(
                  '$percent%',
                  style: const TextStyle(
                    color: purple,
                    fontSize: 25,
                    fontWeight: FontWeight.bold,
                  ),
                ),
              ],
            ),
            LinearProgressIndicator(
              value: blocked + allowed == 0 ? 0 : blocked / (blocked + allowed),
              minHeight: 7,
              borderRadius: BorderRadius.circular(8),
            ),
            gap(),
            muted(
              'Errors: ${c.count('errors')}  ·  Cache hits: ${c.count('cacheHits')}',
            ),
            muted(
              'Average processing: ${((c.snapshot['averageMs'] as num?) ?? 0).toStringAsFixed(1)} ms',
            ),
            if (c.snapshot['lastError'] != null)
              Text(
                'Last DNS error: ${c.snapshot['lastError']}',
                style: const TextStyle(color: Color(0xffffb4ab)),
              ),
            TextButton(
              onPressed: () => Navigator.of(context).push(
                MaterialPageRoute<void>(
                  builder: (_) => ListenableBuilder(
                    listenable: c,
                    builder: (_, _) => StatisticsPage(c: c),
                  ),
                ),
              ),
              child: const Text('View statistics'),
            ),
          ],
        ),
        gap(),
        Panel(
          children: [
            heading('Resolver'),
            Text(
              c.config.upstream.name,
              style: const TextStyle(fontSize: 22, fontWeight: FontWeight.w600),
            ),
            muted(
              '${c.config.upstream.transport.name.toUpperCase()} · ${c.config.upstream.host}',
            ),
            muted(
              'Only DNS queries go to this provider. Your ordinary internet traffic stays on its existing route.',
            ),
            TextButton.icon(
              onPressed: c.busy ? null : c.testResolver,
              icon: const Icon(Icons.speed),
              label: const Text('Test resolver'),
            ),
          ],
        ),
        gap(),
        Panel(
          children: [
            heading('Transparent by design'),
            muted(
              'DNS filtering cannot remove same-domain video ads, inspect HTTPS paths, or apply cosmetic filters. Apps with their own encrypted DNS can bypass it. '
              'The Android runtime currently uses a conservative Dart DNS rule engine; official uBlock core is a separate tested desktop proof of concept.',
            ),
          ],
        ),
      ],
    );
  }

  Widget _metric(String label, String value, IconData icon) => Panel(
    children: [
      Icon(icon, color: purple, size: 20),
      const SizedBox(height: 12),
      Text(
        value,
        style: const TextStyle(fontSize: 32, fontWeight: FontWeight.bold),
      ),
      muted(label),
    ],
  );
}

class ProtectionHealth extends StatelessWidget {
  const ProtectionHealth({required this.c, super.key});
  final AppController c;

  @override
  Widget build(BuildContext context) {
    final format = MaterialLocalizations.of(context);
    String? timestamp(String key) {
      final raw = c.snapshot[key] as String?;
      final time = raw == null ? null : DateTime.tryParse(raw)?.toLocal();
      if (time == null) return null;
      return '${format.formatShortDate(time)} at ${format.formatTimeOfDay(TimeOfDay.fromDateTime(time))}';
    }

    final query = timestamp('lastTunnelQuery');
    final reply = timestamp('lastResolverReply');
    final failure = c.snapshot['lastResolverFailure'] as String?;
    return Panel(
      children: [
        heading('Protection health'),
        const Text('DNS through Zowy'),
        muted(
          query == null
              ? 'Waiting for a DNS request. Open a site in another app to check.'
              : 'Last request: $query',
        ),
        const SizedBox(height: 12),
        const Text('Upstream resolver'),
        if (failure != null) ...[
          Text(failure, style: const TextStyle(color: Color(0xffffb4ab))),
          if (reply != null) muted('Last successful reply: $reply'),
          TextButton(
            onPressed: c.busy ? null : c.testResolver,
            child: const Text('Test resolver'),
          ),
        ] else
          muted(
            reply == null
                ? 'Waiting for an uncached request on this connection.'
                : 'Last successful reply: $reply',
          ),
        if (c.snapshot['alwaysOn'] == true)
          TextButton(
            onPressed: c.busy
                ? null
                : () => c.run(() async {
                    await c.platform.call<void>('vpnSettings');
                  }),
            child: const Text('Android always-on VPN is enabled'),
          ),
      ],
    );
  }
}

Future<void> _checkDomain(BuildContext context, AppController c) async {
  final entered = await editText(
    context,
    'Check a domain',
    '',
    submit: 'Check',
  );
  if (entered == null || !context.mounted) return;
  try {
    final domain = c.normalizeDomain(entered);
    await _showDomainDetails(context, c, domain);
  } on FormatException catch (e) {
    await c.run(() async => throw e);
  }
}

Future<void> _showDomainDetails(
  BuildContext context,
  AppController c,
  String domain, {
  Map? event,
}) => showModalBottomSheet<void>(
  context: context,
  isScrollControlled: true,
  builder: (_) => SafeArea(
    child: SingleChildScrollView(
      padding: const EdgeInsets.all(24),
      child: ListenableBuilder(
        listenable: c,
        builder: (_, _) {
          final supported = validDomain(domain);
          final match = supported ? c.inspectDomain(domain) : null;
          final expiry = c.config.temporaryAllows[domain];
          final hasException =
              expiry != null &&
              (expiry == 0 || expiry > DateTime.now().millisecondsSinceEpoch);
          return Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            mainAxisSize: MainAxisSize.min,
            children: [
              heading(domain),
              if (event != null) ...[
                Text(
                  event['blocked'] == true
                      ? 'Blocked at the time of this request'
                      : event['error'] != null
                      ? 'DNS request failed'
                      : 'Passed through Zowy',
                ),
                if (event['source'] is String)
                  muted('Source: ${event['source']}'),
                if (event['rule'] is String)
                  SelectableText(event['rule'] as String),
                if (event['error'] is String) muted(event['error'] as String),
                gap(),
              ],
              if (supported) ...[
                const Text('Current configured rules'),
                muted(
                  match == null
                      ? 'No matching block rule.'
                      : match.allow
                      ? 'Allowed by ${match.source}'
                      : 'Blocked by ${match.source}',
                ),
                if (match != null) SelectableText(match.rule),
                if (c.error != null) Message(text: c.error!, error: true),
                if (hasException)
                  TextButton(
                    onPressed: c.busy
                        ? null
                        : () => c.removeTemporaryAllow(domain),
                    child: const Text('Undo temporary allow'),
                  )
                else if (match?.allow == false) ...[
                  muted('This exception also allows subdomains.'),
                  FilledButton(
                    onPressed: c.busy
                        ? null
                        : () => c.temporaryAllow(domain, 30),
                    child: const Text('Allow for 30 minutes'),
                  ),
                ],
              ],
            ],
          );
        },
      ),
    ),
  ),
);

class ActivityPage extends StatefulWidget {
  const ActivityPage({required this.c, super.key});
  final AppController c;
  @override
  State<ActivityPage> createState() => _ActivityPageState();
}

class _ActivityPageState extends State<ActivityPage> {
  String query = '', decision = 'All';
  @override
  Widget build(BuildContext context) {
    final c = widget.c;
    final all = ((c.snapshot['logs'] as List?) ?? []).cast<Map>();
    final entries = all
        .where(
          (e) =>
              '${e['domain']} ${e['rule']} ${e['source']}'
                  .toLowerCase()
                  .contains(query.toLowerCase()) &&
              (decision == 'All' ||
                  (e['blocked'] == true) == (decision == 'Blocked')),
        )
        .toList();
    return ListView(
      padding: const EdgeInsets.all(20),
      children: [
        SwitchListTile(
          contentPadding: EdgeInsets.zero,
          title: const Text('Record DNS activity'),
          subtitle: const Text(
            'Off by default. Up to 500 events in service memory; never uploaded.',
          ),
          value: c.config.logging,
          onChanged: c.busy
              ? null
              : (v) => c.run(() async {
                  c.config.logging = v;
                  await c.save();
                }),
        ),
        TextButton.icon(
          onPressed: c.busy ? null : () => _checkDomain(context, c),
          icon: const Icon(Icons.rule),
          label: const Text('Check a domain'),
        ),
        TextField(
          decoration: const InputDecoration(
            prefixIcon: Icon(Icons.search),
            hintText: 'Search domain, rule or source',
          ),
          onChanged: (v) => setState(() => query = v),
        ),
        gap(),
        Wrap(
          spacing: 8,
          children: ['All', 'Blocked', 'Allowed']
              .map(
                (v) => ChoiceChip(
                  label: Text(v),
                  selected: decision == v,
                  onSelected: (_) => setState(() => decision = v),
                ),
              )
              .toList(),
        ),
        Row(
          children: [
            TextButton.icon(
              onPressed: c.busy
                  ? null
                  : () => c.run(() async {
                      await c.platform.call<void>('clearLogs');
                    }),
              icon: const Icon(Icons.delete_outline),
              label: const Text('Delete all'),
            ),
            TextButton.icon(
              onPressed: c.busy
                  ? null
                  : () => c.export(
                      'zowy-activity.json',
                      const JsonEncoder.withIndent('  ').convert(entries),
                    ),
              icon: const Icon(Icons.ios_share),
              label: const Text('Export shown'),
            ),
          ],
        ),
        if (entries.isEmpty)
          Padding(
            padding: const EdgeInsets.symmetric(vertical: 40),
            child: muted(
              c.config.logging
                  ? 'No matching recorded DNS requests. Start protection and use another app.'
                  : 'Activity logging is off. Aggregate counters remain available.',
            ),
          ),
        ...entries.map(
          (e) => Card(
            margin: const EdgeInsets.only(bottom: 8),
            child: ListTile(
              leading: Icon(
                e['blocked'] == true ? Icons.block : Icons.check_circle_outline,
                color: e['blocked'] == true ? purple : Colors.grey,
              ),
              title: Text(e['domain'].toString()),
              subtitle: Text(
                '${e['time']}\n${e['application']} · ${e['ms']} ms',
              ),
              isThreeLine: true,
              onTap: () => _showDomainDetails(
                context,
                c,
                e['domain'].toString(),
                event: e,
              ),
            ),
          ),
        ),
      ],
    );
  }
}

class FiltersPage extends StatelessWidget {
  const FiltersPage({required this.c, super.key});
  final AppController c;
  @override
  Widget build(BuildContext context) => ListView(
    padding: const EdgeInsets.all(20),
    children: [
      Panel(
        children: [
          heading('DNS rules, honestly counted'),
          muted(
            'Hosts entries, plain domains, ||domain^, @@ exceptions and blocking \$important rules. URL paths, wildcards, regex, cosmetic filters and contextual options are skipped.',
          ),
          Text(
            '${c.engine.size} active compiled rules',
            style: const TextStyle(color: purple, fontSize: 22),
          ),
          gap(),
          Wrap(
            spacing: 8,
            runSpacing: 8,
            children: [
              FilledButton.icon(
                onPressed: c.busy ? null : c.updateLists,
                icon: const Icon(Icons.sync),
                label: const Text('Update lists'),
              ),
              OutlinedButton.icon(
                onPressed: c.busy ? null : () => _add(context),
                icon: const Icon(Icons.add),
                label: const Text('Add source'),
              ),
            ],
          ),
        ],
      ),
      gap(),
      ...c.config.sources.map((s) {
        final info = c.listInfo[s.id] ?? {};
        return Padding(
          padding: const EdgeInsets.only(bottom: 12),
          child: Panel(
            children: [
              SwitchListTile(
                contentPadding: EdgeInsets.zero,
                title: Text(s.name),
                value: s.enabled,
                onChanged: c.busy
                    ? null
                    : (v) => c.run(() async {
                        s.enabled = v;
                        await c.save();
                      }),
              ),
              SelectableText(
                s.url,
                style: const TextStyle(fontSize: 12, color: Color(0xffc4b5fd)),
              ),
              gap(),
              muted(
                'Enforceable: ${info['loaded'] ?? 0} · Unsupported: ${info['unsupported'] ?? 0}\n'
                'Invalid: ${info['invalid'] ?? 0} · Duplicates: ${info['duplicates'] ?? 0}\n'
                'Last checked: ${info['updated'] ?? 'Not downloaded'}',
              ),
              Wrap(
                children: [
                  TextButton(
                    onPressed: c.busy
                        ? null
                        : () => c.run(() async {
                            final raw = await c.platform.call<String>('import');
                            if (raw == null) return;
                            await c.lists!.importText(s, raw);
                            await c.save();
                          }),
                    child: const Text('Import list file'),
                  ),
                  TextButton(
                    onPressed: c.busy
                        ? null
                        : () => c.run(() async {
                            c.config.sources.remove(s);
                            await c.save();
                            for (final f in [
                              c.lists!.file(s),
                              c.lists!.metadata(s),
                            ]) {
                              if (await f.exists()) await f.delete();
                            }
                          }),
                    child: const Text('Remove'),
                  ),
                ],
              ),
            ],
          ),
        );
      }),
      Panel(
        children: [
          heading('My rules'),
          muted('Your rules are kept separately from downloaded lists.'),
          TextButton.icon(
            onPressed: c.busy
                ? null
                : () async {
                    final raw = await editText(
                      context,
                      'My rules',
                      c.config.userRules,
                      multiline: true,
                    );
                    if (raw == null) return;
                    await c.run(() async {
                      final candidate = FilterEngine()..add(raw, 'My rules');
                      if (candidate.reports['My rules']!.invalid > 0) {
                        throw const FormatException(
                          'Fix invalid custom rules before saving.',
                        );
                      }
                      c.config.userRules = raw;
                      await c.save();
                    });
                  },
            icon: const Icon(Icons.edit_outlined),
            label: const Text('Edit custom rules'),
          ),
          ...c.engine.reports.entries
              .where((e) => e.key == 'My rules')
              .map(
                (e) => muted(
                  '${e.value.loaded} loaded · ${e.value.unsupported} unsupported · ${e.value.duplicates} duplicates',
                ),
              ),
        ],
      ),
      gap(),
      Panel(
        children: [
          heading('Temporary allowlist'),
          TextButton.icon(
            onPressed: c.busy ? null : () => _checkDomain(context, c),
            icon: const Icon(Icons.rule),
            label: const Text('Check a domain'),
          ),
          TextButton.icon(
            onPressed: c.busy
                ? null
                : () async {
                    final domain = await editText(
                      context,
                      'Allow a domain for 30 minutes',
                      '',
                    );
                    if (domain != null) await c.temporaryAllow(domain, 30);
                  },
            icon: const Icon(Icons.add),
            label: const Text('Allow domain'),
          ),
          ...c.config.temporaryAllows.entries.map(
            (e) => ListTile(
              contentPadding: EdgeInsets.zero,
              title: Text(e.key),
              subtitle: Text(
                e.value == 0
                    ? 'Until removed'
                    : 'Expires ${DateTime.fromMillisecondsSinceEpoch(e.value).toLocal()}',
              ),
              trailing: IconButton(
                tooltip: 'Remove exception',
                icon: const Icon(Icons.close),
                onPressed: c.busy ? null : () => c.removeTemporaryAllow(e.key),
              ),
            ),
          ),
        ],
      ),
    ],
  );
  Future<void> _add(BuildContext context) async {
    final raw = await editText(context, 'HTTPS filter list URL', 'https://');
    if (raw == null) return;
    await c.run(() async {
      final source = FilterSource.fromJson({
        'id': 'custom_${DateTime.now().millisecondsSinceEpoch}',
        'name': Uri.parse(raw.trim()).host,
        'url': raw.trim(),
        'enabled': true,
      });
      if (c.config.sources.any((s) => s.url == source.url)) {
        throw const FormatException('This source is already added.');
      }
      c.config.sources.add(source);
      await c.save();
    });
  }
}

class ApplicationsPage extends StatefulWidget {
  const ApplicationsPage({required this.c, super.key});
  final AppController c;
  @override
  State<ApplicationsPage> createState() => _ApplicationsPageState();
}

class _ApplicationsPageState extends State<ApplicationsPage> {
  String query = '';
  @override
  Widget build(BuildContext context) {
    final c = widget.c;
    return ListView(
      padding: const EdgeInsets.all(20),
      children: [
        muted(
          'Launchable apps visible to Android. Excluded apps bypass this DNS VPN; they retain internet access. '
          'Restart protection after changing exclusions. Request attribution is unavailable, so per-app counts are not shown.',
        ),
        gap(),
        TextField(
          decoration: const InputDecoration(
            prefixIcon: Icon(Icons.search),
            hintText: 'Search applications',
          ),
          onChanged: (v) => setState(() => query = v),
        ),
        TextButton.icon(
          onPressed: c.busy ? null : c.loadApplications,
          icon: const Icon(Icons.refresh),
          label: const Text('Refresh apps'),
        ),
        ...c.applications
            .where(
              (a) => '${a['name']} ${a['package']}'.toLowerCase().contains(
                query.toLowerCase(),
              ),
            )
            .map((a) {
              final id = a['package'] as String;
              final own = id == 'dev.zowy.zowy_adblocker';
              final excluded = own || c.config.excludedApps.contains(id);
              return SwitchListTile(
                title: Text(a['name'].toString()),
                subtitle: Text(
                  '$id\n${excluded ? 'Excluded from VPN' : 'Included in VPN'}',
                ),
                secondary: FutureBuilder(
                  future: c.icon(id),
                  builder: (context, icon) => icon.data == null
                      ? const Icon(Icons.android, color: purple)
                      : Image.memory(icon.data!, width: 40, height: 40),
                ),
                value: !excluded,
                onChanged: c.busy || own
                    ? null
                    : (included) async {
                        if (a['system'] == true &&
                            !included &&
                            !await confirm(
                              context,
                              'Exclude a system app?',
                              'Changing DNS coverage for system apps can affect account and connectivity services.',
                            )) {
                          return;
                        }
                        await c.run(() async {
                          if (included) {
                            c.config.excludedApps.remove(id);
                          } else {
                            c.config.excludedApps.add(id);
                          }
                          await c.save();
                          c.notice = 'Saved. Stop and start protection to apply exclusions.';
                        });
                      },
              );
            }),
      ],
    );
  }
}

class SettingsPage extends StatelessWidget {
  const SettingsPage({required this.c, super.key});
  final AppController c;
  @override
  Widget build(BuildContext context) => ListView(
    padding: const EdgeInsets.all(20),
    children: [
      heading('Network'),
      ListTile(
        leading: const Icon(Icons.dns_outlined),
        title: const Text('Upstream DNS'),
        subtitle: Text(
          '${c.config.upstream.name} · ${c.config.upstream.transport.name.toUpperCase()}',
        ),
        trailing: const Icon(Icons.chevron_right),
        onTap: c.busy
            ? null
            : () => Navigator.push(
                context,
                MaterialPageRoute<void>(builder: (_) => DnsPage(c: c)),
              ),
      ),
      ListTile(
        title: const Text('Cache capacity'),
        subtitle: Text(
          '${c.config.cacheSize} entries · TTL respected, maximum one hour',
        ),
        onTap: c.busy
            ? null
            : () async {
                final text = await editText(
                  context,
                  'Cache entries (0–8192)',
                  '${c.config.cacheSize}',
                );
                if (text == null) return;
                await c.run(() async {
                  final value = int.tryParse(text);
                  if (value == null || value < 0 || value > 8192) {
                    throw const FormatException('Choose 0–8192 entries.');
                  }
                  c.config.cacheSize = value;
                  await c.save();
                });
              },
      ),
      ListTile(
        title: const Text('Clear DNS cache'),
        leading: const Icon(Icons.cleaning_services_outlined),
        onTap: c.busy
            ? null
            : () => c.run(() async {
                await c.platform.call<void>('clearCache');
                c.notice = 'DNS cache cleared.';
              }),
      ),
      ListTile(
        title: const Text('Android always-on VPN'),
        subtitle: const Text(
          'Enable in Android VPN settings. Leave “Block connections without VPN” off: Zowy routes DNS only.',
        ),
        onTap: () => c.run(() async {
          await c.platform.call<void>('vpnSettings');
        }),
      ),
      ListTile(
        leading: const Icon(Icons.battery_std_outlined),
        title: const Text('Android battery settings'),
        subtitle: const Text(
          'Check Zowy’s battery restrictions if protection drops while the screen is off.',
        ),
        onTap: () => c.run(() async {
          await c.platform.call<void>('batterySettings');
        }),
      ),
      heading('Filter updates'),
      DropdownButtonFormField<int>(
        initialValue: c.config.updateHours,
        decoration: const InputDecoration(labelText: 'Background schedule'),
        items: const [
          DropdownMenuItem(value: 0, child: Text('Manual')),
          DropdownMenuItem(value: 12, child: Text('Every 12 hours')),
          DropdownMenuItem(value: 24, child: Text('Daily')),
          DropdownMenuItem(value: 168, child: Text('Weekly')),
        ],
        onChanged: c.busy
            ? null
            : (v) => c.run(() async {
                c.config.updateHours = v!;
                await c.save();
              }),
      ),
      gap(),
      muted(
        'Android schedules updates with network and battery constraints. Times are approximate. Failed list updates retain the previous working content.',
      ),
      heading('Privacy & backups'),
      ListTile(
        leading: const Icon(Icons.file_upload_outlined),
        title: const Text('Export settings'),
        subtitle: const Text(
          'Contains custom rules and source URLs; no DNS activity. Filter content is downloaded separately.',
        ),
        onTap: c.busy
            ? null
            : () => c.export('zowy-settings.json', c.config.encode()),
      ),
      ListTile(
        leading: const Icon(Icons.file_download_outlined),
        title: const Text('Import settings'),
        onTap: c.busy ? null : c.importConfig,
      ),
      ListTile(
        leading: const Icon(Icons.restore),
        title: const Text('Restore previous settings'),
        onTap: c.busy
            ? null
            : () => c.run(() async {
                final text = await c.platform.call<String>('restoreConfig');
                if (text != null) {
                  final restored = AppConfig.decode(text);
                  await c.platform.save(restored);
                  c.config = restored;
                  await c.reloadLists();
                }
              }),
      ),
      ListTile(
        leading: const Icon(Icons.restart_alt),
        title: const Text('Reset session statistics'),
        onTap: c.busy
            ? null
            : () async {
                if (await confirm(
                  context,
                  'Reset statistics?',
                  'This deletes the current counters and recorded activity.',
                )) {
                  await c.run(() async {
                    await c.platform.call<void>('resetStats');
                  });
                }
              },
      ),
      heading('Capabilities & diagnostics'),
      Panel(
        children: [
          _cap(
            'Local DNS VPN',
            'Available on Android 10+; UDP/TCP DNS over IPv4/IPv6',
          ),
          _cap(
            'Root filtering',
            'Not activated: requires validated systemless integration',
          ),
          _cap(
            'Shizuku',
            c.capabilities['shizukuRunning'] == true
                ? 'Running · ${c.capabilities['shizukuGranted'] == true ? 'authorized, UID ${c.capabilities['shizukuUid']}' : 'permission required'}'
                : 'Server unavailable',
          ),
          _cap(
            'Per-app internet firewall',
            'Unavailable in this DNS-only backend',
          ),
          _cap(
            'Private DNS',
            c.capabilities['privateDns'] == true
                ? 'Active; may bypass DNS VPN'
                : 'Not reported active',
          ),
          TextButton(
            onPressed: c.busy
                ? null
                : () => c.run(() async {
                    await c.platform.call<void>('shizukuPermission');
                    await c.refreshCapabilities();
                  }),
            child: const Text('Request Shizuku permission'),
          ),
          muted(
            'Shizuku is optional diagnostics, not a third local filtering backend. A shell session cannot run these local blocklists system-wide without the VPN.',
          ),
          TextButton(
            onPressed: c.busy
                ? null
                : () async {
                    if (!await confirm(
                      context,
                      'Request root for diagnostics?',
                      'Zowy will run exactly: su -c id\n\nThis requests root-manager authorization and reports the UID. No system files or firewall rules will be changed.',
                    )) {
                      return;
                    }
                    await c.run(() async {
                      c.notice = await c.platform.call<String>('rootCheck');
                    });
                  },
            child: const Text('Request root diagnostics'),
          ),
          TextButton(
            onPressed: c.busy
                ? null
                : () => c.run(() async {
                    await c.refreshCapabilities();
                    c.notice = const JsonEncoder.withIndent('  ')
                        .convert(c.capabilities);
                  }),
            child: const Text('Refresh capability report'),
          ),
          TextButton(
            onPressed: c.busy
                ? null
                : () => c.platform.call<void>('privateDnsSettings'),
            child: const Text('Open Android network settings'),
          ),
          if (c.capabilities['updateError'] != null)
            Text(
              'Last scheduled update error: ${c.capabilities['updateError']}',
            ),
        ],
      ),
      gap(),
      Panel(
        children: [
          heading('Troubleshooting'),
          muted(
            'VPN denied: enable protection again and approve Android’s prompt.\n\n'
            'No blocking: check loaded rules, Private DNS, browser Secure DNS and app exclusions.\n\n'
            'Broken app: enable temporary activity logging, reproduce the issue, inspect a recorded rule and temporarily allow only the affected domain.\n\n'
            'DNS failures: test your selected resolver and check connectivity. Encrypted DNS failures never trigger plaintext fallback.\n\n'
            'Service stops: inspect Android battery restrictions; optionally enable always-on VPN.\n\n'
            'Recovery: stop Zowy, disable always-on for Zowy, or revoke its VPN in Android settings. No certificates or system DNS settings are installed.',
          ),
        ],
      ),
      gap(),
      ListTile(
        title: const Text('Open-source licenses'),
        onTap: () => showLicensePage(
          context: context,
          applicationName: 'Zowy',
          applicationVersion: '0.1.0',
        ),
      ),
      muted(
        'Zowy 0.1.0 · GPL-3.0-or-later\nNo accounts, ads, analytics or telemetry. Logs stay in service memory unless you explicitly export them.',
      ),
    ],
  );
  Widget _cap(String name, String value) => ListTile(
    contentPadding: EdgeInsets.zero,
    title: Text(name),
    subtitle: Text(value),
  );
}

class DnsPage extends StatefulWidget {
  const DnsPage({required this.c, super.key});
  final AppController c;
  @override
  State<DnsPage> createState() => _DnsPageState();
}

class _DnsPageState extends State<DnsPage> {
  late final TextEditingController name, address, host, path;
  late DnsTransport transport;
  @override
  void initState() {
    super.initState();
    final s = widget.c.config.upstream;
    name = TextEditingController(text: s.name);
    address = TextEditingController(text: s.address);
    host = TextEditingController(text: s.host);
    path = TextEditingController(text: s.path);
    transport = s.transport;
  }

  @override
  void dispose() {
    for (final c in [name, address, host, path]) {
      c.dispose();
    }
    super.dispose();
  }

  @override
  Widget build(BuildContext context) => Scaffold(
    appBar: AppBar(title: const Text('DNS resolver')),
    body: ListView(
      padding: const EdgeInsets.all(24),
      children: [
        muted(
          'DNS queries go to your chosen provider. TLS certificates are verified. There is no automatic fallback to a different provider or plaintext transport.',
        ),
        gap(),
        Wrap(
          spacing: 8,
          children: presets
              .map(
                (p) => ActionChip(
                  label: Text(p.name),
                  onPressed: () => setState(() {
                    name.text = p.name;
                    address.text = p.address;
                    host.text = p.host;
                    path.text = p.path;
                    transport = p.transport;
                  }),
                ),
              )
              .toList(),
        ),
        gap(),
        TextField(
          controller: name,
          decoration: const InputDecoration(labelText: 'Display name'),
        ),
        gap(),
        TextField(
          controller: address,
          decoration: const InputDecoration(
            labelText: 'Bootstrap IPv4 or IPv6 address',
          ),
        ),
        gap(),
        TextField(
          controller: host,
          decoration: const InputDecoration(labelText: 'TLS / HTTPS hostname'),
        ),
        gap(),
        DropdownButtonFormField<DnsTransport>(
          initialValue: transport,
          key: ValueKey(transport),
          decoration: const InputDecoration(labelText: 'Transport'),
          items: DnsTransport.values
              .map(
                (t) => DropdownMenuItem(
                  value: t,
                  child: Text(t.name.toUpperCase()),
                ),
              )
              .toList(),
          onChanged: (t) => setState(() => transport = t!),
        ),
        gap(),
        if (transport == DnsTransport.doh)
          TextField(
            controller: path,
            decoration: const InputDecoration(
              labelText: 'DoH path (no credentials)',
            ),
          ),
        if (transport == DnsTransport.udp || transport == DnsTransport.tcp)
          const Message(
            text: 'This transport sends DNS queries in plaintext to the selected server.',
          ),
        gap(),
        FilledButton(
          onPressed: () async {
            await widget.c.run(() async {
              final next = Upstream.fromJson({
                'name': name.text,
                'address': address.text.trim(),
                'host': host.text.trim(),
                'transport': transport.name,
                'path': path.text.trim(),
              });
              widget.c.config.upstream = next;
              await widget.c.save();
            });
            if (context.mounted && widget.c.error == null) {
              Navigator.pop(context);
            } else if (context.mounted) {
              ScaffoldMessenger.of(context).showSnackBar(
                SnackBar(content: Text(widget.c.error ?? 'Save failed')),
              );
            }
          },
          child: const Text('Save resolver'),
        ),
      ],
    ),
  );
}

class StatisticsPage extends StatelessWidget {
  const StatisticsPage({required this.c, super.key});
  final AppController c;
  @override
  Widget build(BuildContext context) {
    final daily = Map<String, dynamic>.from((c.snapshot['days'] as Map?) ?? {});
    final logs = ((c.snapshot['logs'] as List?) ?? []).cast<Map>();
    final top = <String, int>{};
    for (final e in logs.where((e) => e['blocked'] == true)) {
      top[e['domain'].toString()] = (top[e['domain'].toString()] ?? 0) + 1;
    }
    final sorted = top.entries.toList()
      ..sort((a, b) => b.value.compareTo(a.value));
    return Scaffold(
      appBar: AppBar(title: const Text('Protection statistics')),
      body: ListView(
        padding: const EdgeInsets.all(24),
        children: [
          heading('Blocked requests by day'),
          muted(
            'Current service session. Counters reset when the service restarts.',
          ),
          gap(),
          if (daily.isEmpty) muted('No blocked requests in this session.'),
          ...daily.entries.map(
            (e) => Padding(
              padding: const EdgeInsets.only(bottom: 12),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text('${e.key} · ${e.value} blocked'),
                  const SizedBox(height: 6),
                  LinearProgressIndicator(
                    minHeight: 14,
                    borderRadius: BorderRadius.circular(5),
                    value:
                        (e.value as num).toDouble() /
                        daily.values.cast<num>().reduce(
                          (a, b) => a > b ? a : b,
                        ),
                  ),
                ],
              ),
            ),
          ),
          heading('Top domains in recorded activity'),
          muted(
            'Requires activity logging. Counts cover only the last 500 recorded events.',
          ),
          ...sorted
              .take(20)
              .map(
                (e) => ListTile(
                  contentPadding: EdgeInsets.zero,
                  title: Text(e.key),
                  trailing: Text('${e.value}'),
                ),
              ),
          gap(),
          muted(
            'Cache hit rate: ${c.count('allowed') == 0 ? '0' : (100 * c.count('cacheHits') / c.count('allowed')).toStringAsFixed(1)}% of allowed requests.\nNo bandwidth savings are estimated.',
          ),
        ],
      ),
    );
  }
}

Future<bool> confirm(BuildContext context, String title, String text) async =>
    await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        title: Text(title),
        content: SingleChildScrollView(child: Text(text)),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context, false),
            child: const Text('Cancel'),
          ),
          FilledButton(
            onPressed: () => Navigator.pop(context, true),
            child: const Text('Continue'),
          ),
        ],
      ),
    ) ??
    false;

Future<String?> editText(
  BuildContext context,
  String title,
  String initial, {
  bool multiline = false,
  String submit = 'Save',
}) async {
  final controller = TextEditingController(text: initial);
  final value = await showDialog<String>(
    context: context,
    builder: (context) => AlertDialog(
      title: Text(title),
      content: SizedBox(
        width: 600,
        child: TextField(
          controller: controller,
          autofocus: true,
          minLines: multiline ? 10 : 1,
          maxLines: multiline ? 16 : 3,
          maxLength: multiline ? 500000 : 2048,
          autocorrect: false,
          style: multiline
              ? const TextStyle(fontFamily: 'monospace', fontSize: 13)
              : null,
        ),
      ),
      actions: [
        TextButton(
          onPressed: () => Navigator.pop(context),
          child: const Text('Cancel'),
        ),
        FilledButton(
          onPressed: () => Navigator.pop(context, controller.text),
          child: Text(submit),
        ),
      ],
    ),
  );
  // Let the closing route release its TextField before disposing its controller.
  Future<void>.delayed(const Duration(seconds: 1), controller.dispose);
  return value;
}

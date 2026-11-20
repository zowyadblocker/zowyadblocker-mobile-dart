import 'dart:convert';
import 'dart:io';

import 'domain.dart';

enum DnsTransport { doh, dot, udp, tcp }

class Upstream {
  const Upstream(
    this.name,
    this.address,
    this.host,
    this.transport, {
    this.path = '/dns-query',
    this.customPort,
  });
  final String name, address, host, path;
  final DnsTransport transport;
  final int? customPort;
  int get port =>
      customPort ??
      (transport == DnsTransport.doh
          ? 443
          : transport == DnsTransport.dot
          ? 853
          : 53);
  Map<String, dynamic> toJson() => {
    'name': name,
    'address': address,
    'host': host,
    'transport': transport.name,
    'path': path,
    'port': customPort,
  };
  factory Upstream.fromJson(Map<String, dynamic> j) {
    final address = j['address'] as String;
    final parsedAddress = InternetAddress.tryParse(address);
    if (parsedAddress == null ||
        parsedAddress.address == '10.111.0.1' ||
        parsedAddress.address == 'fd00:111::1') {
      throw const FormatException(
        'A numeric upstream IP outside the VPN is required.',
      );
    }
    final host = j['host'] as String;
    if (!RegExp(r'^[a-zA-Z0-9.-]{1,253}$').hasMatch(host)) {
      throw const FormatException('Invalid TLS hostname.');
    }
    final path = j['path'] as String? ?? '/dns-query';
    final port = j['port'] as int?;
    if (port != null && (port < 1 || port > 65535)) {
      throw const FormatException('Invalid upstream port.');
    }
    if (!path.startsWith('/') || path.contains('#') || path.length > 1024) {
      throw const FormatException('Invalid DoH path.');
    }
    return Upstream(
      (j['name'] as String).substring(
        0,
        (j['name'] as String).length.clamp(0, 80),
      ),
      address,
      host,
      DnsTransport.values.byName(j['transport'] as String),
      path: path,
      customPort: port,
    );
  }
}

const presets = [
  Upstream('Cloudflare', '1.1.1.1', 'cloudflare-dns.com', DnsTransport.doh),
  Upstream('Google', '8.8.8.8', 'dns.google', DnsTransport.doh),
  Upstream('Quad9', '9.9.9.9', 'dns.quad9.net', DnsTransport.doh),
  Upstream('AdGuard', '94.140.14.14', 'dns.adguard-dns.com', DnsTransport.doh),
];

class FilterSource {
  FilterSource({
    required this.id,
    required this.name,
    required this.url,
    this.enabled = true,
    this.updated,
    this.etag,
    this.modified,
    this.rules = 0,
    this.unsupported = 0,
    this.duplicates = 0,
  });
  final String id, name, url;
  bool enabled;
  DateTime? updated;
  String? etag, modified;
  int rules, unsupported, duplicates;
  Map<String, dynamic> toJson() => {
    'id': id,
    'name': name,
    'url': url,
    'enabled': enabled,
    'updated': updated?.toIso8601String(),
    'etag': etag,
    'modified': modified,
    'rules': rules,
    'unsupported': unsupported,
    'duplicates': duplicates,
  };
  factory FilterSource.fromJson(Map<String, dynamic> j) {
    final id = j['id'] as String;
    if (!RegExp(r'^[a-zA-Z0-9_-]{1,80}$').hasMatch(id)) {
      throw const FormatException('Invalid list identifier.');
    }
    final uri = Uri.parse(j['url'] as String);
    if (uri.scheme != 'https' || uri.host.isEmpty || uri.userInfo.isNotEmpty) {
      throw const FormatException(
        'Filter lists must use HTTPS without credentials.',
      );
    }
    return FilterSource(
      id: id,
      name: j['name'] as String,
      url: uri.toString(),
      enabled: j['enabled'] as bool? ?? true,
      updated: DateTime.tryParse(j['updated'] as String? ?? ''),
      etag: j['etag'] as String?,
      modified: j['modified'] as String?,
      rules: j['rules'] as int? ?? 0,
      unsupported: j['unsupported'] as int? ?? 0,
      duplicates: j['duplicates'] as int? ?? 0,
    );
  }
}

class AppConfig {
  AppConfig({
    Upstream? upstream,
    List<FilterSource>? sources,
    this.userRules = '',
    this.logging = false,
    this.cacheSize = 1024,
    this.updateHours = 24,
    List<String>? excludedApps,
    Map<String, int>? temporaryAllows,
  }) : upstream = upstream ?? presets.first,
       sources =
           sources ??
           [
             FilterSource(
               id: 'hagezi',
               name: 'HaGeZi Multi NORMAL',
               url: 'https://raw.githubusercontent.com/hagezi/dns-blocklists/main/adblock/multi.txt',
             ),
           ],
       excludedApps = excludedApps ?? [],
       temporaryAllows = temporaryAllows ?? {};
  Upstream upstream;
  List<FilterSource> sources;
  String userRules;
  bool logging;
  int cacheSize, updateHours;
  List<String> excludedApps;
  Map<String, int> temporaryAllows;
  Map<String, dynamic> toJson() => {
    'version': 1,
    'upstream': upstream.toJson(),
    'sources': sources.map((s) => s.toJson()).toList(),
    'userRules': userRules,
    'logging': logging,
    'cacheSize': cacheSize,
    'updateHours': updateHours,
    'excludedApps': excludedApps,
    'temporaryAllows': temporaryAllows,
  };
  String encode() => const JsonEncoder.withIndent('  ').convert(toJson());
  factory AppConfig.decode(String text) {
    if (utf8.encode(text).length > 2 * 1024 * 1024) {
      throw const FormatException('Configuration exceeds 2 MiB.');
    }
    final j = jsonDecode(text) as Map<String, dynamic>;
    if (j['version'] != 1) {
      throw const FormatException('Unsupported configuration version.');
    }
    final sources = (j['sources'] as List)
        .map((s) => FilterSource.fromJson(Map<String, dynamic>.from(s as Map)))
        .toList();
    if (sources.length > 32 ||
        sources.map((s) => s.id).toSet().length != sources.length) {
      throw const FormatException(
        'At most 32 lists with unique IDs are supported.',
      );
    }
    final rules = j['userRules'] as String? ?? '';
    if (rules.length > 500000) {
      throw const FormatException('Custom rules exceed 500 KB.');
    }
    final excluded = (j['excludedApps'] as List? ?? []).cast<String>();
    if (excluded.length > 500 ||
        excluded.any((s) => !RegExp(r'^[a-zA-Z0-9_.]+$').hasMatch(s))) {
      throw const FormatException('Invalid application exclusions.');
    }
    final hours = j['updateHours'] as int? ?? 24;
    final temporary = (j['temporaryAllows'] as Map? ?? {}).map(
      (k, v) => MapEntry(k as String, v as int),
    );
    if (temporary.length > 256 ||
        temporary.entries.any(
          (e) =>
              !validDomain(e.key) || e.value < 0 || e.value > 8640000000000000,
        )) {
      throw const FormatException(
        'Invalid temporary allowlist (maximum 256 domains).',
      );
    }
    if (![0, 12, 24, 168].contains(hours)) {
      throw const FormatException('Invalid update schedule.');
    }
    return AppConfig(
      upstream: Upstream.fromJson(j['upstream'] as Map<String, dynamic>),
      sources: sources,
      userRules: rules,
      logging: j['logging'] as bool? ?? false,
      cacheSize: (j['cacheSize'] as int? ?? 1024).clamp(0, 8192),
      updateHours: hours,
      excludedApps: excluded,
      temporaryAllows: temporary,
    );
  }
}

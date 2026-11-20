# Implementation plan

1. Create an Android-only Flutter application, persistent versioned configuration,
   AMOLED interface, real service status, tests and CI.
2. Run DNS processing in a dedicated headless Dart engine owned by an Android
   foreground VpnService. Route only synthetic DNS IPv4/IPv6 addresses. Implement
   packet validation, UDP DNS transport, encrypted upstreams, exceptions, bounded
   cache and optional activity logging. Keep ordinary internet traffic outside TUN.
3. Implement atomic, bounded HTTPS filter downloads and conservative DNS rule
   compilation. Run the official uBO core proof of concept before selecting an
   Android runtime; report unsupported rules rather than approximate URL semantics.
4. Add explicit root authorization and a reversible systemless hosts workflow only
   if it can be validated. Integrate official Shizuku capability diagnostics.
5. Connect applications, settings, statistics, import/export, diagnostics and privacy
   controls end to end. Build APK and document exact verification limits.

## Initial capability matrix

| Capability | DNS VPN | Systemless root | Shizuku shell |
|---|---|---|---|
| Local domain rules | Implement | Requires validated root integration | Unavailable alone |
| IPv4 / IPv6 DNS | Implement | Hosts resolver dependent | No interception |
| URL paths / resource types / third party | No metadata | No metadata | No metadata |
| Cosmetic / scriptlets | No DOM | No DOM | No DOM |
| App exclusions | Android VPN builder | Global hosts rules | No local filtering |
| App internet firewall | Not a DNS exclusion | Deferred until validated | Device dependent, not assumed |
| Uses VPN slot | Yes | No | No |
| Privileged operations | VPN consent | Explicit root consent | Shizuku consent |

This is an implementation plan, not a claim that device tests have passed.

## Delivered phase status

- Foundation: Android-only app, persistence, real state, UI, tests and CI completed.
- VPN: real local IPv4/IPv6 UDP/TCP DNS implemented and emulator-tested.
- Advanced filtering: list management and conservative DNS engine implemented;
  official uBO proof passed on desktop, Android adapter remains unfinished.
- Root: read-only authorized diagnostic implemented; systemless protection unfinished.
- Shizuku: official capability/permission/binder integration implemented;
  privileged network changes and standalone filtering unavailable.
- Advanced features: per-app exclusions/icons, DNS controls, activity, session
  statistics and backup/restore implemented. Firewall, profiles, persistent
  historical statistics and compiled Android engine snapshots remain unfinished.
- Polish: AMOLED UI, documentation, debug APK and unsigned AAB built. Production
  signing, physical/root/Shizuku device verification and distribution remain open.

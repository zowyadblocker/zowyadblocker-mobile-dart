# Capability matrix (0.1.0)

| Feature | State | Details |
|---|---|---|
| Local DNS VPN | Implemented | Android 10+, foreground service, synthetic DNS routes |
| IPv4 / IPv6 UDP and TCP client DNS | Implemented | Bounded TCP endpoint; one answer per connection |
| Upstream DoH / DoT / UDP / TCP | Implemented | Bootstrap numeric IP; verified TLS; UDP truncation retries TCP |
| Resolver presets | Implemented | Cloudflare, Google, Quad9, AdGuard; custom endpoint editor |
| NextDNS | Custom endpoint only | No account/token storage workflow or preset |
| Failover | Explicit fail closed | No automatic provider/transport fallback; UDP→TCP stays same provider |
| DNS cache | Implemented | LRU, TTL aging, max 8192 entries, no negative caching |
| Domain rules / exceptions / important | Implemented | Conservative Dart engine; not uBO |
| Actual uBO core | Desktop proof only | Official core compilation, matching, serialization tested |
| Regex / wildcards / contextual rules | Unsupported in Android engine | Counted as unsupported, never broadened |
| Cosmetic / scriptlets / HTTPS path inspection | Unavailable | No browser DOM, TLS interception or certificates |
| Filter downloads and local imports | Implemented | Atomic validation, prior content on failure, HTTPS cache validators |
| Background list updates | Implemented | Android JobScheduler; scheduling is approximate |
| Custom rules and temporary exceptions | Implemented | Separate from downloaded content; temporary UI default 30 minutes |
| Installed apps / VPN exclusions | Implemented | Launchable visible apps only; restart applies exclusions |
| Per-app activity attribution / counts | Unavailable | Recorded as Unknown application |
| Internet firewall / Wi-Fi/mobile restrictions | Unavailable | A VPN exclusion is not an internet block |
| Activity / explanations / export / deletion | Implemented | Opt-in, memory only, max 500 events; no invented rule matches |
| Statistics | Session counters | No fabricated history or bandwidth savings |
| Always-on | Android settings | Lockdown unsupported for this DNS-only design |
| Root systemless filtering | Not implemented | Explicit root UID check only; no hosts writes or module installation |
| Shizuku | Official API diagnostics | Binder/permission/UID checks; no standalone local filtering |
| Privacy / backup | Implemented | Keystore-encrypted local config; explicit SAF export/import |
| Profiles / automatic broken-app detection | Not implemented | Manual recorded-rule diagnostics and temporary exceptions work |
| Pause/resume timer / language selection | Not implemented | Stop/start protection is available |
| F-Droid | Unverified | No compatibility claim |

Device report in Settings reads the current VPN conflict, Private DNS, Android API,
Shizuku binder availability, granted permission and server UID. A root binary is
only a hint. Root availability is established only after the user's explicit `su
-c id` authorization. Shizuku UID 0 is not treated as proof that a hosts mount or
firewall API works.

This version is a functional development build, not completion of the full
production specification. It needs rooted-device/Shizuku testing, larger Android
list benchmarks, long-running lifecycle tests and further TCP interoperability
testing before a production release.

# Architecture

Zowy is Android-only. Dart owns configuration models, filter compilation, DNS wire
format, IP response construction, the bounded DNS TCP endpoint, encrypted upstream
resolution, cache, statistics and Flutter UI. Kotlin owns Android APIs only.

```
Flutter UI → AppController → AndroidPlatform (MethodChannel)
                                  ↓
                          Android VpnService
                                  ↓
                  TUN reader → BinaryCodec channel
                                  ↓
                    dedicated headless Dart engine
                IPv4 / IPv6 UDP and TCP DNS endpoint
                                  ↓
                 rule decision → TTL cache → upstream
                                  ↓
                       response → TUN writer
```

Only 10.111.0.1/32 and fd00:111::1/128 are routed. Android advertises those as the
VPN DNS servers. There is no default route and no remote VPN server. The app's UID
is excluded so bootstrap, updater and upstream sockets cannot loop through TUN.
IPv6 routes allow ordinary IPv6 traffic outside the VPN. Do not enable Android's
lockdown / “Block connections without VPN”: this deliberately narrow tunnel does
not carry ordinary traffic and lockdown may prevent internet access.

The native foreground service owns the headless engine independently of the
activity. It reads blocking TUN packets on a worker thread; no idle polling loop
is used. At most 64 native packet operations and 64 TCP sessions are active. TCP
answers use stop-and-wait segments, bounded reassembly, retransmission and a
20-second idle timeout. Each TCP connection handles one DNS response then closes.
IPv4 fragments, IPv6 extensions/fragments and compressed DNS questions are not
supported. Oversized UDP replies request retry via TCP. TCP is a DNS endpoint,
not a TCP/IP proxy.

The rule engine only accepts a documented DNS subset. It never strips contextual
options to manufacture broad blocking. Exceptions beat ordinary blocks; important
blocks beat normal exceptions; explicit temporary user exceptions take precedence
over both. Suffix lookup respects label boundaries. Rule provenance is retained.
Compilation runs in a Dart isolate; compiled objects swap only after success.

Filter sources are fetched over HTTPS with bounded identity encoding, timeouts,
ETag and Last-Modified validation. Redirects, HTML and compressed responses are
rejected. Each downloaded file is validated before an atomic rename. No lists are
bundled. User rules are stored independently. Source IDs are validated before they
become filenames. Active list text is capped at 64 MiB, one file at 32 MiB, rules
at 1.5 million and custom rules at 500 KB. Large list memory remains a release risk.

The Android JobScheduler runs a separate headless update entrypoint with network
and battery constraints. It retains the last working content on failed downloads
and asks an active VPN engine to reload after updates. Job scheduling survives
reboot; starting protection at boot is delegated to user-enabled Android always-on
VPN rather than an unsolicited boot receiver.

Configuration and its previous version are AES-GCM encrypted with an Android
Keystore key. Automatic Android application backups are disabled. Imports validate
schema and bounds before writing. The Storage Access Framework handles explicit
exports/imports; no broad storage permission is requested. Activity logging is
optional, bounded and kept in memory. Statistics currently cover the service
session; historical persistent analytics are not implemented.

Root authorization and Shizuku are diagnostics, not additional filtering backends.
No unvalidated privileged networking APIs or system modifications are shipped.
See the capability matrix and research record for unfinished work.

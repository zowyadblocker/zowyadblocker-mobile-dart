# Sources and third-party licenses

No third-party blocklist is bundled with the APK or repository. Downloading is an
explicit UI action; subsequent selected periodic updates use the same source.

The only default list is [HaGeZi Multi NORMAL](https://github.com/hagezi/dns-blocklists),
downloaded from `https://raw.githubusercontent.com/hagezi/dns-blocklists/main/adblock/multi.txt`.
The [repository license](https://github.com/hagezi/dns-blocklists/blob/main/LICENSE)
verified on 2026-11-20 is GPLv3. Preserve its license and upstream provenance if you
redistribute downloaded or derived lists. This project uses GPL-3.0-or-later.
The app checks daily by default, supports 12 hours/weekly/manual, and uses server
cache validators. This schedule is Zowy's policy, not an assertion of an upstream
guaranteed update cadence. Lists may change without app releases.

EasyList, EasyPrivacy, uBO lists, StevenBlack, OISD and Peter Lowe are not preset or
bundled until their specific file licenses/update requirements are audited. Users
can supply HTTPS URLs or import text they are entitled to use. Accepting a list
does not mean all its syntax can be enforced. Inspect its unsupported count.

Resolver endpoints verified against provider documentation:

| Provider | Bootstrap | DoH endpoint | Source |
|---|---|---|---|
| Cloudflare | 1.1.1.1 | https://cloudflare-dns.com/dns-query | [Official](https://developers.cloudflare.com/1.1.1.1/encryption/dns-over-https/make-api-requests/) |
| Google | 8.8.8.8 | https://dns.google/dns-query | [Official](https://developers.google.com/speed/public-dns/docs/doh) |
| Quad9 | 9.9.9.9 | https://dns.quad9.net/dns-query | [Official](https://quad9.net/service/service-addresses-and-features/) |
| AdGuard | 94.140.14.14 | https://dns.adguard-dns.com/dns-query | [Official](https://adguard-dns.io/en/public-dns.html) |

Presets are convenience choices, not endorsements or guarantees about provider
retention policies. The selected DNS provider receives permitted queries. TLS is
validated for its hostname while connecting to the chosen bootstrap address.
No different-provider fallback occurs. Custom transports use port 443/853/53 by
default; imported configuration can set an explicit port.

Shizuku API/provider 13.1.5 is MIT licensed; see its
[official developer guide](https://github.com/RikkaApps/Shizuku-API). Flutter/Dart
use their upstream licenses; Material UI is the extracted Flutter Material library.
The npm uBO tool is a GPL-3.0-or-later development dependency, absent from the APK.
Use `flutter pub deps` and Gradle dependencies to inspect the full graph.

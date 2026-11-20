# Security and privacy

No ads, analytics SDK, accounts, telemetry, remote commands, certificate
installation or TLS interception. DNS queries are necessarily sent to the resolver
you select. Filter downloads go to your selected list hosts. DNS logs are never
uploaded. The UI never claims universal YouTube/Twitch ad removal.

Configuration and its previous version are encrypted with Android Keystore-backed
AES-GCM. Android app backups are disabled. Detailed activity is off by default,
bounded to 500 events in memory and limited to domain/DNS metadata, never URLs or
credentials. Aggregate counters are local to the service session. Exported logs
and settings go only to a location you explicitly select; exports are plaintext,
so inspect source URLs/custom endpoints and do not use secret-bearing endpoints.
Authenticated DNS/filter subscriptions and secret token management are not supported.

Permissions:

| Permission | Purpose |
|---|---|
| INTERNET | DNS upstreams and selected filter downloads |
| ACCESS_NETWORK_STATE | VPN/Private DNS conflict diagnostics |
| FOREGROUND_SERVICE / SPECIAL_USE | User-enabled persistent VPN service |
| POST_NOTIFICATIONS | Optional user consent to display protection status in Android 13+ notification drawer |
| BIND_VPN_SERVICE (service protection) | Only Android may bind as VPN controller |
| RECEIVE_BOOT_COMPLETED | Persisted JobScheduler updates; not automatic UI launch |
| Shizuku API_V23 | Optional, explicit Shizuku authorization |

ShizukuProvider is guarded by INTERACT_ACROSS_USERS_FULL. JobService is guarded by
BIND_JOB_SERVICE. No broad package or storage permission is requested. Launcher
app queries use scoped package visibility. The app always excludes its own UID
from TUN to prevent resolver/bootstrap loops.

Untrusted inputs have download/text/rule/cache/session bounds, strict DNS framing,
question matching, randomized upstream IDs and TLS verification. No downloaded
rules execute JS or shell. Production readiness still requires fuzzing, Android
memory/battery testing and a full lifecycle/security review. The DNS TCP endpoint
is intentionally small and needs broader interoperability testing.

Report suspected vulnerabilities privately through your repository's security
advisory channel when configured. Do not include private DNS activity or tokens
in public issues. No security contact or hosted service is fabricated here.

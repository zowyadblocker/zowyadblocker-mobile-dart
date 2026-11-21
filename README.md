# Zowy Adblocker

[Download the latest version](https://github.com/zowyadblocker/zowyadblocker-mobile-dart/releases/latest) · [Obtainium setup](.github/OBTAINIUM.md)


An Android-only Flutter application for local DNS ad/tracker filtering. AMOLED
black, purple accents, no account, no analytics and no remote VPN server.

**Status: functional development build (0.3.0), not the completed production
specification.** The DNS VPN is implemented; official uBlock core is currently a
tested desktop proof, root is an authorized diagnostic, and Shizuku supplies
capability diagnostics. Unsupported modes are never presented as active protection.
See [the full capability matrix](docs/CAPABILITIES.md).

## Build and install

Requirements: Flutter **3.50.0** stable / Dart **3.14**, Java **21**, Android SDK
**36**, accepted SDK licenses. Minimum Android **10 / API 29**. The repository
pins Pub/npm locks, AGP and Gradle versions. Local SDK paths and signing keys are
not committed. Builds are version-pinned, but byte-for-byte reproducibility has
not been established.

```sh
flutter doctor -v
flutter pub get
flutter analyze
flutter test
flutter build apk --debug
```

The installable test APK is `build/app/outputs/flutter-apk/app-debug.apk`. Transfer
it to Android, allow installation from that source, and open it. Alternatively:

```sh
adb -s YOUR_DEVICE_SERIAL install -r build/app/outputs/flutter-apk/app-debug.apk
```

Always choose the device explicitly. No changes are made to a connected device
merely by building. Debug builds use a debug certificate and are for development.

Local packaged APKs for ARM64, ARMv7, x86_64 and universal Android, an unsigned AAB,
and SHA-256 checksums are in `artifacts/` in this workspace. Keep using the same
ABI for debug updates because split-ABI version codes differ. The AAB needs your
production signature and cannot be installed directly as an APK.

Release APK/AAB requires your own signing configuration. Set `ZOWY_KEYSTORE`,
`ZOWY_STORE_PASSWORD`, `ZOWY_KEY_ALIAS`, and `ZOWY_KEY_PASSWORD` in your environment:

```sh
flutter build apk --release --split-per-abi
flutter build appbundle --release
```

Without signing credentials the release build is unsigned; it does not silently
use the debug certificate. Keep your signing key for future updates. Never commit
it. ARM64, ARMv7 and x86_64 use Flutter's supported Android targets; actual artifact
and device checks are recorded in [verification](docs/VERIFICATION.md).

## First use

1. Tap the **power button**. On first use, Zowy downloads the enabled HaGeZi
   NORMAL list, then continues to VPN setup. Internet access is needed for this
   download; a failed download can be retried with the same button. To choose
   other lists or custom rules first, open **Filters**. Nothing downloads merely
   from opening the app.
2. Approve Android's VPN permission prompt. The UI shows active only after the
   headless engine and real TUN interface start.
3. Inspect rule counts and unsupported syntax in **Filters**. The Android engine
   only enforces its [documented DNS subset](docs/ENGINE_RESEARCH.md).
4. Optional: open **Settings → Upstream DNS** to change the default Cloudflare
   DoH resolver. Allowed DNS queries go to Cloudflare unless you choose another
   preset or configure a bootstrap IP, TLS hostname, transport and path.
   **Test resolver** checks the actual upstream. TLS verification is never bypassed.
5. If Android Private DNS or a browser's encrypted DNS is active, it may bypass
   local filtering. Zowy reports detected conflicts and leaves system settings
   under your control. Starting Zowy replaces another active VPN.
6. Zowy runs as a foreground VPN service while protection is on, including when
   you leave the app. Use the power button or the VPN notification to stop it.
   Android **always-on VPN** can restart protection automatically, including after
   a reboot. Leave **Block connections without VPN** off because Zowy routes DNS
   only. If your phone drops the VPN while idle, use **Settings → Android battery
   settings** to check Zowy’s battery restrictions.

Only synthetic DNS destinations are routed through TUN. Ordinary internet traffic
does not go through a third-party tunnel. There is no HTTPS interception. DNS
cannot reliably remove same-domain video ads, cosmetic elements or scriptlets.
YouTube/Twitch universal ad removal is not claimed.

## Filters and applications

**Add source** accepts an HTTPS URL; review the list's license yourself before
using or redistributing it. Use **Import list file** to replace a source with local
text. Rejects redirects, HTML, malformed/unexpected content and oversized downloads.
Failed updates retain the working list. Enable/disable/remove sources separately.
Periodic updates use Android JobScheduler at 12 hours, daily, weekly or manual.

**My rules** is a separate editor, preserved through source updates. Examples:

```text
||ads.example.com^
@@||safe.ads.example.com^
0.0.0.0 tracker.example.com
```

The engine records a matching rule and source. URL paths, regex/wildcards,
third-party conditions and cosmetic/scriptlet rules are counted as unsupported.
Temporary allowlisting is available from a recorded request or Filters.

**Apps** shows launchable apps visible through Android's scoped package APIs.
Turn off inclusion to exclude an app, then stop/start protection. An exclusion
does not block internet access. Per-app blocked counts are absent because this
backend cannot reliably attribute DNS traffic to apps.

## Activity, diagnostics and recovery

Detailed activity is **off by default**. Enable it temporarily, reproduce a broken
app and inspect a recorded domain/rule. You can allow that domain for 30 minutes,
delete activity or export the shown events. Up to 500 events are retained in
memory; no DNS activity is uploaded. Counts and timing are actual service events,
not demo data or bandwidth estimates. Current statistics reset with the service.

Settings includes resolver testing, Private DNS/VPN conflict detection, cache
clearing, settings export/import, and restoration of the previous saved settings.
Settings exports contain rules/source URLs and are plaintext; authenticated or
secret-bearing endpoints are not supported. Filter data is downloaded separately.

If connectivity breaks, stop protection. If always-on restarts it, disable Zowy's
always-on setting in Android's VPN settings; revoke its VPN profile if needed.
Then inspect activity and the resolver configuration. There are no certificates,
system DNS changes, root mounts or firewall rules to undo.

## Root and Shizuku

Root filtering is **not implemented**. Settings offers an explicit, read-only
`su -c id` authorization check. It never modifies `/system`, installs modules or
touches iptables/nftables. There is no fake root-protection toggle. See the
[root safety/recovery guide](docs/ROOT_RECOVERY.md).

Install and start official Shizuku, then request permission in Settings. The
capability report shows binder availability, permission and shell/root UID. A
Shizuku shell session is not root and does not make local rules available through
Private DNS. If standalone filtering is unavailable, use the local VPN.

## Development and verification

- [Architecture](ARCHITECTURE.md)
- [Capability matrix and remaining work](docs/CAPABILITIES.md)
- [uBO runtime investigation and proof](docs/ENGINE_RESEARCH.md)
- [Source/provider/license audit](docs/SOURCES.md)
- [Privacy and security](SECURITY.md)
- [Actual tests and device limits](docs/VERIFICATION.md)
- [Desktop benchmarks](docs/BENCHMARKS.md)
- [Contributing](CONTRIBUTING.md)

The GitHub Actions workflow formats, analyzes, tests, runs the official-core proof,
audits npm dependencies, builds a debug APK and uploads checksums. Release signing
is optional and secrets stay in repository settings. Matching version tags publish
signed releases once the four signing secrets are configured; see the
[release workflow guide](.github/RELEASING.md). Current APK downloads are locally built development builds. F-Droid acceptance and
production distribution have not been verified.

Licensed **GPL-3.0-or-later**; see [LICENSE](LICENSE). Preserve third-party notices
and make corresponding source available when distributing binaries.

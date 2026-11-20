# Verification record

Date: 2026-11-20. Local environment: Windows x64, Flutter 3.50.0, Dart 3.14,
Java 21, Android SDK 36 / NDK 28.2.13676358.

## Automated checks

- Dart formatting, static analysis and unit tests are run locally.
- 24 regression tests cover capability refresh on binder death,
  rules/precedence/unsupported syntax, configuration
  import bounds, persistence roundtrip, last-working list retention, DNS framing,
  corrupt packets, IPv4/IPv6 checksums, TTL/LRU cache, real local UDP/TCP forwarding,
  downstream TCP handshake/reassembly/FIN, DoH/DoT TLS and hostname rejection.
- The official uBO core proof passes actual compilation, matching, precedence,
  third-party context and serialization assertions. See its raw JSON results.
- Synthetic 100k/500k/1m Dart benchmarks were run; results are desktop-only.
- A real default-source HTTPS download compiled **194,288** HaGeZi rules with
  zero unsupported, invalid or duplicate lines at the time checked. This number
  changes as the upstream list changes. No list content is bundled in the APK.

## Android emulator

A new disposable Pixel 6 emulator, Android 15 / API 35, x86_64, was created in the
ignored workspace `.tools` directory. Tests explicitly target emulator-5580.
The connected physical phone was not installed on or reconfigured.

`tools/test-emulator.ps1` compiles a small NDK test probe, runs the Flutter device
integration test, authorizes VPN only inside that emulator, then runs the probe
as the independent Android shell UID. This is necessary because Zowy's own UID is
excluded from the VPN to prevent upstream/bootstrap loops. The probe exercises
real kernel TCP/UDP traffic through TUN, not mocked platform channels.

All eight probes passed: blocked.zowy.test → NXDOMAIN and example.com → successful
resolution, each over IPv4/IPv6 and UDP/TCP. See `emulator-dns-probe-results.txt`.
Allowed queries used the selected Cloudflare DoH resolver with TLS verification.
The Flutter integration test also checks actual recorded fixture events, activity
deletion, distinct-settings backup preservation and stopping the foreground VPN.
The complete test passed after fixing
headless entrypoint resolution, TLS socket construction and an initial network
callback that unnecessarily cancelled in-flight requests.

The Flutter/DDS test launcher intermittently failed to attach before tests ran.
A clean emulator restart recovered the harness; this failure is separate from
the recorded successful DNS probes and is not counted as a passing test.

For reproduction, start a disposable Android x86_64 emulator and run:

```powershell
./tools/test-emulator.ps1 -Serial emulator-5580
```

The helper assumes the SDK is at ANDROID_HOME, NDK 28.2.13676358 and Flutter at
C:\dev\flutter; adapt those development-tool paths on another machine. It refuses
physical-device serials. It does not request root or install Shizuku.

## Not verified

No physical-device, rooted-device, active Shizuku-server, OEM battery, long-running
sleep/network-switch, boot/always-on, Android 16/17, ARM memory/battery or F-Droid
tests have passed in this workspace. No production signing key is configured.
GitHub Actions is configured but has not been executed remotely. Privileged hosts
and firewall operations are not implemented or claimed. Treat the current APK as
a development build; broad production readiness remains unfinished.

## Artifacts

Normal (non-test) debug APKs were built for ARM64, ARMv7, x86_64 and universal
Android. A release AAB was built and checked with jarsigner: it is unsigned.
The final x86_64 APK installed and launched with fresh application data on the
disposable emulator. APK metadata confirms minSdk 29 and targetSdk 36. The screenshot
in `screenshots/home.png` is that real first-use screen, with no simulated counts.
Locally packaged files and SHA-256 checksums are in the ignored `artifacts` directory.

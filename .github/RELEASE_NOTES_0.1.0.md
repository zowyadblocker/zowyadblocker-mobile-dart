# Zowy 0.1.0

The first functional Android development build. Android 10 or later is required.

## Included

- Local DNS VPN filtering over IPv4/IPv6 and UDP/TCP.
- DNS-over-HTTPS, DNS-over-TLS, UDP/TCP upstreams and bounded TTL cache.
- Filter downloads/imports, custom rules, exceptions and rule explanations.
- App exclusions, optional local activity, session statistics and settings backups.
- AMOLED black/purple Flutter interface and official Shizuku capability diagnostics.

## Install

Choose **arm64** for most modern phones, **armv7** for 32-bit phones, **x86_64**
for compatible emulators, or **universal** if unsure. APKs are installable;
the unsigned AAB is provided for build/distribution work and cannot be installed
directly. SHA256SUMS covers all uploaded binaries.

These APKs use a **development debug signing certificate**, not a production key.
Future in-place updates must retain the same certificate and increase the version
code. Changing to a different production certificate will require uninstalling this
build first; export your settings before doing that. Keep the same APK ABI for
updates, or use the universal APK consistently.

## Obtainium

See [the Obtainium setup link and configuration](https://github.com/zowyadblocker/zowyadblocker-mobile-dart/blob/main/.github/OBTAINIUM.md).
The provided configuration selects the universal APK to keep update version codes
consistent. Obtainium cannot bypass Android's signing-certificate checks.

## Verified and unfinished

24 unit tests, static analysis, and real emulator tests of all eight allowed/blocked
IPv4/IPv6 UDP/TCP DNS paths passed locally. See the
[verification record](https://github.com/zowyadblocker/zowyadblocker-mobile-dart/blob/main/docs/VERIFICATION.md).

This is **not production-complete**. Official uBlock core currently runs only in a
desktop proof of concept; the Android app uses its documented Dart DNS rule subset.
Root hosts filtering, firewall controls and physical/root/Shizuku device validation
remain unfinished. DNS filtering cannot remove every ad or apply cosmetic filters.

Source code is provided under GPL-3.0-or-later. See the repository LICENSE and
third-party notices before redistributing builds or filter data.

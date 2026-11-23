# Zowy 0.4.0

- Protection health separates tunnel status, the last DNS request through Zowy, and the latest upstream result. When Android always-on VPN is enabled, the home screen links to VPN settings.
- **Check a domain** in Activity or Filters to see which configured rule applies, even with activity logging off.
- From the domain checker or a recorded block, allow a blocked domain and its subdomains for 30 minutes. Undo the exception from the same screen.

## Install or update

Requires Android 10 or later. For an in-place update, install the same APK variant you used for 0.3.0. For a new installation, choose the universal APK if unsure. [Obtainium setup](https://github.com/zowyadblocker/zowyadblocker-mobile-dart/blob/main/.github/OBTAINIUM.md) selects the universal build.

These APKs retain the development signing certificate used in 0.3.0. The Android App Bundle is unsigned. SHA256SUMS covers the four APKs and the bundle.

On the Android emulator, eight IPv4/IPv6 UDP/TCP DNS probes passed, and independent DNS queries confirmed that Allow changed the result and Undo restored blocking. Physical-device testing remains pending.

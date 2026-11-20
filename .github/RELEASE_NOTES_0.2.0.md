# Zowy 0.2.0

The power button now downloads the enabled filter list on first use and continues to Android's VPN permission prompt. If the download fails, check your internet connection and tap the same button to retry. Existing filter lists and custom rules can still start protection without a download.

## Install or update

Android 10 or later is required. Use the same APK variant you installed for 0.1.0. For a fresh install, choose `Zowy-0.2.0-universal-debug.apk` if unsure. Obtainium selects the universal APK automatically using the [Zowy setup link](https://github.com/zowyadblocker/zowyadblocker-mobile-dart/blob/main/.github/OBTAINIUM.md).

These development APKs retain the 0.1.0 signing certificate. `SHA256SUMS` covers the APKs and the unsigned Android App Bundle. Install an APK on your device.

The first-start regression tests cover list download, retry after a network failure, custom rules, disabled lists, and stopping protection. The app still uses local DNS filtering, which cannot block ads served from the same domains as content.

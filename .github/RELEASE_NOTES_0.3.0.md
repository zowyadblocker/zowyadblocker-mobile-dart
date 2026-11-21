# Zowy 0.3.0

- Fixed a VPN shutdown hang that could leave protection on until you force-stopped Zowy. The tunnel closes as soon as Stop is handled.
- The power button can stop protection while another app operation is running.
- Zowy runs as an Android foreground VPN service. Settings now links to Android battery settings if your device drops protection while idle.

## Install or update

Requires Android 10 or later. To update from 0.2.0, use the same APK variant. For a fresh install, choose the universal APK if unsure. [Obtainium setup](https://github.com/zowyadblocker/zowyadblocker-mobile-dart/blob/main/.github/OBTAINIUM.md) selects the universal build.

The debug APKs retain the 0.2.0 signing certificate. Install an APK on your phone. The unsigned Android App Bundle is for distribution work. SHA256SUMS covers all five binaries.

The Android emulator stayed connected with the screen off in deep idle, then stopped from inside the app. Start and restart tests and all eight IPv4/IPv6 UDP/TCP DNS probes passed. Manufacturer-specific battery behavior still needs physical-device verification.

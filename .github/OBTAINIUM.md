# Install and update with Obtainium

[Add Zowy to Obtainium](https://apps.obtainium.imranr.dev/redirect?r=obtainium%3A%2F%2Fapp%2F%257B%2522id%2522%253A%2522dev.zowy.zowy_adblocker%2522%252C%2522url%2522%253A%2522https%253A%252F%252Fgithub.com%252Fzowyadblocker%252Fzowyadblocker-mobile-dart%2522%252C%2522author%2522%253A%2522zowyadblocker%2522%252C%2522name%2522%253A%2522Zowy%2522%252C%2522additionalSettings%2522%253A%257B%2522apkFilterRegEx%2522%253A%2522universal.%252A%255C%255C.apk%2524%2522%257D%257D)

Install [Obtainium](https://github.com/ImranR98/Obtainium/releases/latest) first,
then open the link above on Android and confirm the configuration. It tracks
[Zowy's GitHub releases](https://github.com/zowyadblocker/zowyadblocker-mobile-dart/releases)
and selects the universal APK so the same ABI/version-code scheme is used for updates.

Manual source URL: https://github.com/zowyadblocker/zowyadblocker-mobile-dart

The import configuration is [obtainium.json](obtainium.json). If adding manually,
set the APK filename filter to `universal.*\.apk$` or consistently choose your
phone's ABI. No account or secret is included in the configuration.

Version 0.1.0 is a development build signed with a debug certificate. Android
requires the same signing certificate for future in-place updates. A later switch
to another production key requires uninstalling first; export settings beforehand.

The link uses Obtainium's [documented deep-link format](https://wiki.obtainium.imranr.dev/deep_links/).
# Install and update with Obtainium

On Android, install [Obtainium](https://github.com/ImranR98/Obtainium/releases/latest) first. Open the link below in your Android browser and confirm the import. It tracks GitHub releases and selects the universal APK.

[Add Zowy to Obtainium on Android](https://apps.obtainium.imranr.dev/redirect?r=obtainium%3A%2F%2Fapp%2F%257B%2522id%2522%253A%2522dev.zowy.zowy_adblocker%2522%252C%2522url%2522%253A%2522https%253A%252F%252Fgithub.com%252Fzowyadblocker%252Fzowyadblocker-mobile-dart%2522%252C%2522author%2522%253A%2522zowyadblocker%2522%252C%2522name%2522%253A%2522Zowy%2522%252C%2522additionalSettings%2522%253A%2522%257B%255C%2522apkFilterRegEx%255C%2522%253A%255C%2522universal.%252A%255B.%255Dapk%2524%255C%2522%257D%2522%257D)

If the link does not open Obtainium, add Zowy from inside the app:

1. Tap **Add App** and paste `https://github.com/zowyadblocker/zowyadblocker-mobile-dart` as the source URL.
2. Set the APK link filter (regular expression) to `universal.*[.]apk$`.
3. Tap **Add**, then install Zowy. If you already track Zowy, edit its APK filter instead.

You can also download the [JSON import file](https://raw.githubusercontent.com/zowyadblocker/zowyadblocker-mobile-dart/main/.github/obtainium.json) and import it from Obtainium's **Import/Export** screen.

If you installed an ABI-specific APK, keep using that variant to update in place. Set the filter to match its filename instead, such as `arm64.*[.]apk$` for arm64. The 0.1.0 through 0.4.0 development APKs share a signing certificate.

[Download from GitHub](https://github.com/zowyadblocker/zowyadblocker-mobile-dart/releases/latest) · [Obtainium deep-link documentation](https://wiki.obtainium.imranr.dev/deep_links/)

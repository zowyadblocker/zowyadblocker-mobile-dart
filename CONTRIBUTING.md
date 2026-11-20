# Contributing

Use Flutter 3.50.0 / Dart 3.14, Android SDK 36 and Java 21. Keep packet processing
and business logic in Dart; Kotlin is for Android API integration.

TLS tests generate temporary localhost credentials with OpenSSL. Linux CI uses
the system executable; Windows tests can use the executable bundled with Git.

Run:

```sh
flutter pub get
dart format --output=none --set-exit-if-changed lib test integration_test tool
flutter analyze
flutter test
flutter build apk --debug
```

Add meaningful regression coverage for packet/rule/storage changes. Never test
root changes on a person's device without explicit authorization. Emulator tests
must target disposable emulators, not whichever USB device happens to be connected.
The independent probe in `tools/dns-probe.c` is test-only, not an app dependency.

Do not claim a parsed rule is enforceable without the necessary metadata. Keep
unsupported UI capabilities disabled and update the matrix when behavior changes.
Preserve user configuration, filter license notices and GPL source obligations.
Never commit signing keys, local SDK paths, node_modules, emulator data or DNS logs.

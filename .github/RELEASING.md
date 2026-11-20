# Releasing Zowy

The Android workflow runs formatting, analysis, tests, the official-core proof,
dependency auditing and a debug APK build on pushes and pull requests. Tags must
match the version in pubspec.yaml, for example v0.1.0 for 0.1.0+1.

Version 0.1.0 is bootstrapped from the locally tested development APKs. Those APKs
use the existing local debug certificate; their limitations are recorded in the
release notes. The unsigned AAB is not an installable APK.

## Future automated signed releases

Configure these repository Actions secrets before publishing subsequent signed
versions:

- ZOWY_KEYSTORE_BASE64: base64-encoded signing keystore.
- ZOWY_STORE_PASSWORD: keystore password.
- ZOWY_KEY_ALIAS: signing-key alias.
- ZOWY_KEY_PASSWORD: key password.

Then increment both the app version and build number in pubspec.yaml, commit,
and push a matching v-prefixed tag. CI verifies the project, builds signed
universal/ABI APKs and an AAB, computes SHA-256 checksums, and publishes the tag's
GitHub release. A manual workflow run builds signed artifacts without publishing
a release unless it runs against a version tag.

Without signing secrets CI still validates the tag and uploads a debug artifact,
but deliberately skips automatic release publication. A fresh CI debug key would
break in-place updates; ordinary CI debug artifacts must not be used as replacement
release assets. Configure all four secrets, not just the keystore.

Android requires the same certificate for in-place updates. Keep the original
development key if maintaining this initial development install, or clearly
document the uninstall/settings-export migration when switching to a production
key. Never commit either keystore or passwords. Keep source and GPL notices
available alongside each binary release.

The [Obtainium configuration](OBTAINIUM.md) tracks the universal APK. Keep a
universal APK with `universal` in its filename in future releases so this filter
continues to select the correct artifact. Obtainium cannot override certificate
or version-code checks.

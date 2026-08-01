# Releasing Natter

Public builds are distributed directly as a notarized Developer ID app. The app
currently supports Apple silicon and macOS 15 or later.

## One-time setup

The release Mac needs a `Developer ID Application` certificate in Keychain and
an App Store Connect app-specific password stored for `notarytool`:

```sh
xcrun notarytool store-credentials natter-notary \
  --apple-id "APPLE_ID" \
  --team-id TEAMID \
  --password "APP_SPECIFIC_PASSWORD"
```

Do not commit credentials or export the signing certificate into the repository.
`SIGN_IDENTITY` must be the full certificate name printed by
`security find-identity -v -p codesigning`. The certificate and private key stay
in Keychain; only the value is passed to the release process.

## Build, sign and notarize

Start from a clean commit, choose a semantic version and increment the numeric
build number:

```sh
swift test
node --test ProductCorpus/tests/scenarios.test.mjs

VERSION=0.1.0 \
BUILD_NUMBER=1 \
SIGN_IDENTITY="Developer ID Application: Name (TEAMID)" \
NOTARY_PROFILE=natter-notary \
./scripts/release-app.sh
```

The script:

1. builds with Xcode so MLX Metal resources are present;
2. copies the Apache app licence and every dependency licence into the bundle;
3. signs with Developer ID, hardened runtime and the required audio-input entitlement;
4. creates and submits the ZIP to Apple's notary service;
5. staples the ticket, recreates the ZIP and writes a SHA-256 file.

The final files are `dist/Natter-VERSION.zip` and its `.sha256` sibling.
Model weights are not included.

## Verify before publishing

```sh
codesign --verify --deep --strict --verbose=2 dist/Natter.app
spctl --assess --type execute --verbose=4 dist/Natter.app
xcrun stapler validate dist/Natter.app
shasum -a 256 -c dist/Natter-VERSION.zip.sha256
```

Test the archive on a Mac user account that has never granted the app
permissions. Complete onboarding, download the speech model, dictate into the
release matrix, revoke each permission once, and confirm recovery.

Required destinations before a public release:

- native text field and text editor;
- Safari and Chrome address bars and standard web inputs;
- Gmail and X composers;
- ChatGPT and Claude desktop composers;
- Terminal, iTerm and Ghostty;
- a focus switch during Raw and during buffered Agent delivery.

The release is not ready if any transcript disappears. A failed destination
must leave a local recovery record and copy either the undelivered tail or the
complete transcript.

## Product release blockers

Before the first public build, add a proper app icon, decide the initial version,
run the clean-account matrix above and create the first notarization profile.
Auto-update can wait until after the first manually distributed build.

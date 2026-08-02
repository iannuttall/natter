# Releasing Natter

Natter ships as a notarized Developer ID app inside a DMG. Sparkle reads `appcast.xml` from
the public GitHub repository and verifies each update with an EdDSA signature.

## Set up the release Mac once

The Mac needs a `Developer ID Application` certificate and its private key in Keychain.
Natter can use the same App Store Connect notarization profile as Portman because both apps
ship under the same developer team:

```sh
xcrun notarytool store-credentials portmanager \
  --apple-id "APPLE_ID" \
  --team-id TEAMID \
  --password "APP_SPECIFIC_PASSWORD"
```

Sparkle uses the existing `ed25519` update key in the login keychain. Its public half is
pinned in `scripts/build-app.sh`. The private half never enters the repository.

```sh
.build/artifacts/sparkle/Sparkle/bin/generate_keys -p
```

That command must print the same public key used by `SPARKLE_PUBLIC_KEY` in the build script.

## Build, sign, and notarize

Start from a clean commit. Choose a semantic version and increment the numeric build number.

```sh
make check

VERSION=0.1.0 \
BUILD_NUMBER=1 \
SIGN_IDENTITY="Developer ID Application: Iancredible Ltd (JXNCT3BEVQ)" \
NOTARY_PROFILE=portmanager \
./scripts/release-app.sh
```

The release script builds with Xcode, embeds MLX resources and Sparkle, signs every nested
component, verifies hardened runtime, launches the finished app, builds a DMG, notarizes it,
staples the ticket, signs the Sparkle update, and writes a SHA-256 file.

The final files are:

```text
dist/Natter-VERSION.dmg
dist/Natter-VERSION.dmg.sha256
```

## Publish the update

The script prints a complete Sparkle `<item>` with the DMG length and EdDSA signature.
Add it to the top of `appcast.xml`, include a plain release description, and commit that
change before publishing the GitHub release.

Create the tagged release with both files:

```sh
gh release create v0.1.0 \
  dist/Natter-0.1.0.dmg \
  dist/Natter-0.1.0.dmg.sha256 \
  --title "Natter 0.1.0" \
  --notes-file RELEASE_NOTES.md
```

Older installed copies fetch the raw appcast from the `main` branch, so the feed URL and
public key must not move after the first public release.

## Check the exact artifact

```sh
codesign --verify --deep --strict --verbose=2 dist/Natter.app
spctl --assess --type execute --verbose=4 dist/Natter.app
xcrun stapler validate dist/Natter-0.1.0.dmg
shasum -a 256 -c dist/Natter-0.1.0.dmg.sha256
```

Test the DMG from a clean macOS account. Complete onboarding, download the speech model, and
exercise native fields, Safari, Chrome, Gmail, ChatGPT Desktop, Claude Desktop, Terminal,
iTerm, and Ghostty. Include a focus change during Raw and buffered Agent delivery.

A release is blocked if any transcript disappears. Failure must leave a recovery record and
the complete intended transcript on the clipboard.

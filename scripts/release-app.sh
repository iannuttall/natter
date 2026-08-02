#!/bin/zsh

set -euo pipefail

repo_dir="${0:A:h:h}"
version="${VERSION:-}"
build_number="${BUILD_NUMBER:-}"
notary_profile="${NOTARY_PROFILE:-}"
sign_identity="${SIGN_IDENTITY:-}"
app_name="${APP_NAME:-Natter}"
executable_name="${EXECUTABLE_NAME:-dictation}"

if [[ -z "$version" || -z "$build_number" || -z "$sign_identity" ]]; then
    echo "Usage: VERSION=1.0.0 BUILD_NUMBER=1 SIGN_IDENTITY='Developer ID Application: Name (TEAMID)' [NOTARY_PROFILE=name] ./scripts/release-app.sh" >&2
    exit 64
fi

cd "$repo_dir"

VERSION="$version" \
BUILD_NUMBER="$build_number" \
SIGN_IDENTITY="$sign_identity" \
APP_NAME="$app_name" \
./scripts/build-app.sh

app_path="$repo_dir/dist/$app_name.app"
dmg_path="$repo_dir/dist/$app_name-$version.dmg"

echo "Verifying Developer ID signature"
codesign --verify --deep --strict --verbose=2 "$app_path"
sign_info="$(codesign -d --verbose=2 "$app_path" 2>&1 || true)"
if [[ "$sign_info" != *"flags="*"runtime"* ]]; then
    echo "hardened runtime is missing" >&2
    exit 65
fi

echo "Checking the signed app launches"
"$app_path/Contents/MacOS/$executable_name" & launch_pid=$!
sleep 5
if kill -0 "$launch_pid" 2>/dev/null; then
    kill "$launch_pid"
else
    echo "the signed app exited during launch" >&2
    exit 65
fi

echo "Building DMG"
SKIP_BUILD=1 VERSION="$version" APP_NAME="$app_name" ./scripts/build-dmg.sh
codesign --force --sign "$sign_identity" --timestamp "$dmg_path"

if [[ -n "$notary_profile" ]]; then
    echo "Submitting DMG for notarization"
    xcrun notarytool submit "$dmg_path" \
        --keychain-profile "$notary_profile" \
        --wait
    xcrun stapler staple "$dmg_path"
    xcrun stapler validate "$dmg_path"
    spctl --assess --type open --context context:primary-signature --verbose=2 "$dmg_path"
else
    echo "warning: NOTARY_PROFILE is empty; other Macs will reject this build" >&2
fi

sign_update="$(
    find "$repo_dir/.xcode-build" "$repo_dir/.build" \
        -type f -name sign_update -perm -u+x -print -quit 2>/dev/null
)"
ed_signature="PASTE_SIGNATURE"
if [[ -n "$sign_update" ]]; then
    if sign_output="$("$sign_update" "$dmg_path" 2>&1)"; then
        parsed_signature="$(
            print -r -- "$sign_output" \
                | sed -n 's/.*sparkle:edSignature="\([^"]*\)".*/\1/p'
        )"
        if [[ -n "$parsed_signature" ]]; then
            ed_signature="$parsed_signature"
        fi
    else
        echo "warning: Sparkle sign_update failed: $sign_output" >&2
    fi
else
    echo "warning: Sparkle sign_update was not found" >&2
fi

size="$(stat -f%z "$dmg_path")"
sha256="$(shasum -a 256 "$dmg_path" | cut -d' ' -f1)"
print -r -- "$sha256  ${dmg_path:t}" > "$dmg_path.sha256"

printf '\nRelease artifact: %s\nSHA-256: %s\n\n' "$dmg_path" "$sha256"
printf '%s\n' \
    'Add this item to appcast.xml before publishing:' \
    '' \
    '  <item>' \
    "    <title>$version</title>" \
    "    <sparkle:version>$build_number</sparkle:version>" \
    "    <sparkle:shortVersionString>$version</sparkle:shortVersionString>" \
    '    <sparkle:minimumSystemVersion>15.0</sparkle:minimumSystemVersion>' \
    '    <enclosure' \
    "      url=\"https://github.com/iannuttall/natter/releases/download/v$version/$app_name-$version.dmg\"" \
    "      length=\"$size\"" \
    '      type="application/octet-stream"' \
    "      sparkle:edSignature=\"$ed_signature\" />" \
    '  </item>'

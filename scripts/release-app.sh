#!/bin/zsh

set -euo pipefail

repo_dir="${0:A:h:h}"
version="${VERSION:-}"
build_number="${BUILD_NUMBER:-}"
notary_profile="${NOTARY_PROFILE:-}"
sign_identity="${SIGN_IDENTITY:-}"
app_name="${APP_NAME:-Natter}"

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
archive_path="$repo_dir/dist/$app_name-$version.zip"

codesign --verify --deep --strict --verbose=2 "$app_path"
rm -f "$archive_path"
ditto -c -k --keepParent "$app_path" "$archive_path"

if [[ -n "$notary_profile" ]]; then
    xcrun notarytool submit "$archive_path" \
        --keychain-profile "$notary_profile" \
        --wait
    xcrun stapler staple "$app_path"
    xcrun stapler validate "$app_path"
    rm -f "$archive_path"
    ditto -c -k --keepParent "$app_path" "$archive_path"
else
    echo "warning: NOTARY_PROFILE is empty; archive is signed but not notarized" >&2
fi

shasum -a 256 "$archive_path" > "$archive_path.sha256"
ls -lh "$app_path" "$archive_path" "$archive_path.sha256"

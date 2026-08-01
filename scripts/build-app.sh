#!/bin/zsh

set -euo pipefail

repo_dir="${0:A:h:h}"
configuration="${CONFIGURATION:-release}"
app_name="${APP_NAME:-Natter}"
executable_name="${EXECUTABLE_NAME:-dictation}"
bundle_id="${BUNDLE_ID:-is.ian.natter}"
version="${VERSION:-0.1.0}"
build_number="${BUILD_NUMBER:-1}"
sign_identity="${SIGN_IDENTITY:-}"
signing_identity_file="${SIGNING_IDENTITY_FILE:-$repo_dir/.signing-identity}"
dist_dir="$repo_dir/dist"
app_dir="$dist_dir/$app_name.app"
legacy_app_dir="$dist_dir/Dictation.app"
contents_dir="$app_dir/Contents"
entitlements="$repo_dir/Config/Natter.entitlements"

cd "$repo_dir"

configuration_name="Release"
if [[ "$configuration" == "debug" || "$configuration" == "Debug" ]]; then
    configuration_name="Debug"
fi
products_dir="$repo_dir/.xcode-build/Build/Products/$configuration_name"

xcodebuild build \
    -quiet \
    -scheme dictation \
    -destination 'platform=macOS,arch=arm64' \
    -configuration "$configuration_name" \
    -derivedDataPath .xcode-build \
    CODE_SIGNING_ALLOWED=NO \
    -skipPackagePluginValidation \
    -skipMacroValidation

case "$app_dir" in
    "$dist_dir"/*.app) rm -rf "$app_dir" ;;
    *)
        echo "refusing to replace unexpected app path: $app_dir" >&2
        exit 70
        ;;
esac

if [[ "$app_name" == "Natter" && -d "$legacy_app_dir" ]]; then
    rm -rf "$legacy_app_dir"
fi

mkdir -p "$contents_dir/MacOS" "$contents_dir/Resources"
cp "$products_dir/$executable_name" "$contents_dir/MacOS/$executable_name"
strip -S "$contents_dir/MacOS/$executable_name"
for resource_bundle in "$products_dir"/*.bundle(N/); do
    ditto "$resource_bundle" "$contents_dir/Resources/$(basename "$resource_bundle")"
done

legal_dir="$contents_dir/Resources/Legal"
dependency_legal_dir="$legal_dir/Dependencies"
mkdir -p "$dependency_legal_dir"
cp "$repo_dir/LICENSE" "$legal_dir/APP_LICENSE.txt"
cp "$repo_dir/THIRD_PARTY_NOTICES.md" "$legal_dir/THIRD_PARTY_NOTICES.md"

checkout_root="$repo_dir/.xcode-build/SourcePackages/checkouts"
for checkout in "$checkout_root"/*(N/); do
    package_name="$(basename "$checkout")"
    package_legal_dir="$dependency_legal_dir/$package_name"
    legal_files=("$checkout"/(LICENSE*|NOTICE*|COPYING*)(N.))
    if (( ${#legal_files} > 0 )); then
        mkdir -p "$package_legal_dir"
        for legal_file in "${legal_files[@]}"; do
            cp "$legal_file" "$package_legal_dir/$(basename "$legal_file")"
        done
    fi
done

/usr/libexec/PlistBuddy -c "Clear dict" "$contents_dir/Info.plist" 2>/dev/null || true
/usr/libexec/PlistBuddy -c "Add :CFBundleDisplayName string $app_name" "$contents_dir/Info.plist"
/usr/libexec/PlistBuddy -c "Add :CFBundleExecutable string $executable_name" "$contents_dir/Info.plist"
/usr/libexec/PlistBuddy -c "Add :CFBundleIdentifier string $bundle_id" "$contents_dir/Info.plist"
/usr/libexec/PlistBuddy -c "Add :CFBundleInfoDictionaryVersion string 6.0" "$contents_dir/Info.plist"
/usr/libexec/PlistBuddy -c "Add :CFBundleName string $app_name" "$contents_dir/Info.plist"
/usr/libexec/PlistBuddy -c "Add :CFBundlePackageType string APPL" "$contents_dir/Info.plist"
/usr/libexec/PlistBuddy -c "Add :CFBundleShortVersionString string $version" "$contents_dir/Info.plist"
/usr/libexec/PlistBuddy -c "Add :CFBundleVersion string $build_number" "$contents_dir/Info.plist"
/usr/libexec/PlistBuddy -c "Add :NSHumanReadableCopyright string Copyright © 2026 Ian Nuttall" "$contents_dir/Info.plist"
/usr/libexec/PlistBuddy -c "Add :LSMinimumSystemVersion string 15.0" "$contents_dir/Info.plist"
/usr/libexec/PlistBuddy -c "Add :LSUIElement bool true" "$contents_dir/Info.plist"
/usr/libexec/PlistBuddy -c "Add :NSHighResolutionCapable bool true" "$contents_dir/Info.plist"
/usr/libexec/PlistBuddy -c "Add :NSMicrophoneUsageDescription string $app_name uses the microphone only while you are speaking." "$contents_dir/Info.plist"
/usr/libexec/PlistBuddy -c "Add :CFBundleURLTypes array" "$contents_dir/Info.plist"
/usr/libexec/PlistBuddy -c "Add :CFBundleURLTypes:0 dict" "$contents_dir/Info.plist"
/usr/libexec/PlistBuddy -c "Add :CFBundleURLTypes:0:CFBundleURLName string $bundle_id" "$contents_dir/Info.plist"
/usr/libexec/PlistBuddy -c "Add :CFBundleURLTypes:0:CFBundleURLSchemes array" "$contents_dir/Info.plist"
/usr/libexec/PlistBuddy -c "Add :CFBundleURLTypes:0:CFBundleURLSchemes:0 string natter" "$contents_dir/Info.plist"
/usr/libexec/PlistBuddy -c "Add :CFBundleURLTypes:0:CFBundleURLSchemes:1 string ian-dictation" "$contents_dir/Info.plist"

if [[ -z "$sign_identity" ]]; then
    if [[ -f "$signing_identity_file" ]]; then
        IFS= read -r sign_identity < "$signing_identity_file"
    else
        available_identities="$(
            security find-identity -v -p codesigning 2>/dev/null \
                | sed -n 's/^[^"]*"\([^"]*\)".*$/\1/p'
        )"
        sign_identity="$(
            print -r -- "$available_identities" \
                | sed -n '/^Developer ID Application: /{p;q;}'
        )"
        if [[ -z "$sign_identity" ]]; then
            sign_identity="$(print -r -- "$available_identities" | sed -n '1p')"
        fi
    fi
fi

if [[ -z "$sign_identity" ]]; then
    sign_identity="-"
    echo "warning: no signing identity found; macOS permissions may reset after rebuilds" >&2
fi

if [[ "$sign_identity" == "-" ]]; then
    codesign --force --deep --entitlements "$entitlements" --sign "$sign_identity" "$app_dir"
else
    codesign --force --deep --options runtime --timestamp \
        --entitlements "$entitlements" --sign "$sign_identity" "$app_dir"
fi
echo "Signed with: $sign_identity"
echo "$app_dir"

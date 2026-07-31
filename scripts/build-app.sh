#!/bin/zsh

set -euo pipefail

repo_dir="${0:A:h:h}"
configuration="${CONFIGURATION:-release}"
app_name="${APP_NAME:-Dictation}"
executable_name="${EXECUTABLE_NAME:-dictation}"
bundle_id="${BUNDLE_ID:-is.ian.dictation}"
version="${VERSION:-0.1.0}"
build_number="${BUILD_NUMBER:-1}"
sign_identity="${SIGN_IDENTITY:-}"
dist_dir="$repo_dir/dist"
app_dir="$dist_dir/$app_name.app"
contents_dir="$app_dir/Contents"

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

mkdir -p "$contents_dir/MacOS" "$contents_dir/Resources"
cp "$products_dir/$executable_name" "$contents_dir/MacOS/$executable_name"
strip -S "$contents_dir/MacOS/$executable_name"
for resource_bundle in "$products_dir"/*.bundle(N/); do
    ditto "$resource_bundle" "$contents_dir/Resources/$(basename "$resource_bundle")"
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
/usr/libexec/PlistBuddy -c "Add :LSMinimumSystemVersion string 15.0" "$contents_dir/Info.plist"
/usr/libexec/PlistBuddy -c "Add :LSUIElement bool true" "$contents_dir/Info.plist"
/usr/libexec/PlistBuddy -c "Add :NSHighResolutionCapable bool true" "$contents_dir/Info.plist"
/usr/libexec/PlistBuddy -c "Add :NSMicrophoneUsageDescription string Dictation uses the microphone only while you are speaking." "$contents_dir/Info.plist"
/usr/libexec/PlistBuddy -c "Add :CFBundleURLTypes array" "$contents_dir/Info.plist"
/usr/libexec/PlistBuddy -c "Add :CFBundleURLTypes:0 dict" "$contents_dir/Info.plist"
/usr/libexec/PlistBuddy -c "Add :CFBundleURLTypes:0:CFBundleURLName string is.ian.dictation" "$contents_dir/Info.plist"
/usr/libexec/PlistBuddy -c "Add :CFBundleURLTypes:0:CFBundleURLSchemes array" "$contents_dir/Info.plist"
/usr/libexec/PlistBuddy -c "Add :CFBundleURLTypes:0:CFBundleURLSchemes:0 string ian-dictation" "$contents_dir/Info.plist"

if [[ -z "$sign_identity" ]]; then
    sign_identity="$(
        security find-identity -v -p codesigning 2>/dev/null \
            | sed -n 's/^[^"]*"\([^"]*\)".*$/\1/p' \
            | sed -n '1p'
    )"
fi

if [[ -z "$sign_identity" ]]; then
    sign_identity="-"
    echo "warning: no signing identity found; macOS permissions may reset after rebuilds" >&2
fi

codesign --force --deep --sign "$sign_identity" "$app_dir"
echo "Signed with: $sign_identity"
echo "$app_dir"

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
sparkle_feed_url="${SPARKLE_FEED_URL:-https://raw.githubusercontent.com/iannuttall/natter/main/appcast.xml}"
sparkle_public_key="${SPARKLE_PUBLIC_KEY:-nwuSNKWY2YAhvGb8G4DF2Zxmpugdei3TaQekrb2S/vg=}"
dist_dir="$repo_dir/dist"
app_dir="$dist_dir/$app_name.app"
legacy_app_dir="$dist_dir/Dictation.app"
contents_dir="$app_dir/Contents"
frameworks_dir="$contents_dir/Frameworks"
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

mkdir -p "$contents_dir/MacOS" "$contents_dir/Resources" "$frameworks_dir"
cp "$products_dir/$executable_name" "$contents_dir/MacOS/$executable_name"
strip -S "$contents_dir/MacOS/$executable_name"
for resource_bundle in "$products_dir"/*.bundle(N/); do
    ditto "$resource_bundle" "$contents_dir/Resources/$(basename "$resource_bundle")"
done

sparkle_framework="$(
    find "$products_dir" "$repo_dir/.xcode-build/SourcePackages/artifacts" \
        -type d -name Sparkle.framework -print -quit 2>/dev/null
)"
if [[ -z "$sparkle_framework" ]]; then
    echo "Sparkle.framework was not produced by the Xcode build" >&2
    exit 65
fi
ditto "$sparkle_framework" "$frameworks_dir/Sparkle.framework"
install_name_tool -add_rpath '@executable_path/../Frameworks' \
    "$contents_dir/MacOS/$executable_name" 2>/dev/null || true

icon_source="$repo_dir/Resources/AppIcon.icon"
icon_output="$repo_dir/.xcode-build/NatterIcon"
case "$icon_output" in
    "$repo_dir/.xcode-build/"*) rm -rf "$icon_output" ;;
    *)
        echo "refusing to replace unexpected icon output path: $icon_output" >&2
        exit 70
        ;;
esac
mkdir -p "$icon_output"
if ! xcrun actool "$icon_source" \
    --compile "$icon_output" \
    --platform macosx \
    --minimum-deployment-target 15.0 \
    --app-icon AppIcon \
    --output-partial-info-plist "$icon_output/partial.plist" \
    --errors --warnings > "$icon_output/actool.log" 2>&1; then
    cat "$icon_output/actool.log" >&2
    echo "failed to compile the Natter app icon" >&2
    exit 65
fi
for icon_resource in Assets.car AppIcon.icns; do
    if [[ ! -f "$icon_output/$icon_resource" ]]; then
        echo "actool did not produce $icon_resource" >&2
        exit 65
    fi
    cp "$icon_output/$icon_resource" "$contents_dir/Resources/$icon_resource"
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
/usr/libexec/PlistBuddy -c "Add :CFBundleIconFile string AppIcon" "$contents_dir/Info.plist"
/usr/libexec/PlistBuddy -c "Add :CFBundleIconName string AppIcon" "$contents_dir/Info.plist"
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
/usr/libexec/PlistBuddy -c "Add :SUFeedURL string $sparkle_feed_url" "$contents_dir/Info.plist"
/usr/libexec/PlistBuddy -c "Add :SUPublicEDKey string $sparkle_public_key" "$contents_dir/Info.plist"
/usr/libexec/PlistBuddy -c "Add :SUEnableAutomaticChecks bool true" "$contents_dir/Info.plist"
/usr/libexec/PlistBuddy -c "Add :SUScheduledCheckInterval integer 86400" "$contents_dir/Info.plist"

# actool's fallback ICNS stops at 256px. Render the vector-backed icon from the
# finished bundle and merge larger renditions for macOS 15 Finder and Get Info.
render_tool="$repo_dir/.xcode-build/Tools/render-natter-icon"
render_source="$repo_dir/scripts/icon/render-icon.swift"
if [[ ! -x "$render_tool" || "$render_source" -nt "$render_tool" ]]; then
    mkdir -p "${render_tool:h}"
    swiftc -swift-version 6 -O "$render_source" -o "$render_tool"
fi

icon_work="$(mktemp -d)"
iconset="$icon_work/AppIcon.iconset"
if iconutil -c iconset "$contents_dir/Resources/AppIcon.icns" -o "$iconset"; then
    "$render_tool" "$app_dir" 256 "$iconset/icon_256x256.png"
    "$render_tool" "$app_dir" 512 "$iconset/icon_512x512.png"
    "$render_tool" "$app_dir" 1024 "$iconset/icon_512x512@2x.png"
    iconutil -c icns "$iconset" -o "$contents_dir/Resources/AppIcon.icns"
fi
rm -rf "$icon_work"

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

sign_flags=(--force)
if [[ "$sign_identity" != "-" ]]; then
    sign_flags+=(--options runtime --timestamp)
fi

sign_component() {
    codesign "${sign_flags[@]}" --sign "$sign_identity" "$1"
}

sparkle_version_dir="$frameworks_dir/Sparkle.framework/Versions/B"
for xpc in "$sparkle_version_dir"/XPCServices/*.xpc(N); do
    sign_component "$xpc"
done
if [[ -e "$sparkle_version_dir/Updater.app" ]]; then
    sign_component "$sparkle_version_dir/Updater.app"
fi
if [[ -e "$sparkle_version_dir/Autoupdate" ]]; then
    sign_component "$sparkle_version_dir/Autoupdate"
fi
sign_component "$frameworks_dir/Sparkle.framework"

codesign "${sign_flags[@]}" --entitlements "$entitlements" \
    --sign "$sign_identity" "$app_dir"
echo "Signed with: $sign_identity"
echo "$app_dir"

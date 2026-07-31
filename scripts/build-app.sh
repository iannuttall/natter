#!/bin/zsh

set -euo pipefail

repo_dir="${0:A:h:h}"
configuration="${CONFIGURATION:-release}"
app_name="${APP_NAME:-Dictation}"
executable_name="${EXECUTABLE_NAME:-dictation}"
bundle_id="${BUNDLE_ID:-is.ian.dictation}"
version="${VERSION:-0.1.0}"
build_number="${BUILD_NUMBER:-1}"
dist_dir="$repo_dir/dist"
app_dir="$dist_dir/$app_name.app"
contents_dir="$app_dir/Contents"

cd "$repo_dir"

swift build -c "$configuration" --product dictation
bin_dir="$(swift build -c "$configuration" --show-bin-path)"

mkdir -p "$contents_dir/MacOS" "$contents_dir/Resources"
cp "$bin_dir/$executable_name" "$contents_dir/MacOS/$executable_name"

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

codesign --force --deep --sign - "$app_dir"
echo "$app_dir"

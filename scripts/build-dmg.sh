#!/bin/zsh

set -euo pipefail

repo_dir="${0:A:h:h}"
app_name="${APP_NAME:-Natter}"
version="${VERSION:-0.1.0}"
dist_dir="$repo_dir/dist"
app_dir="$dist_dir/$app_name.app"
dmg_path="$dist_dir/$app_name-$version.dmg"
staging_dir="$(mktemp -d)"

cleanup() {
    rm -r "$staging_dir"
}
trap cleanup EXIT

if [[ "${SKIP_BUILD:-0}" != "1" ]]; then
    "$repo_dir/scripts/build-app.sh"
fi

if [[ ! -d "$app_dir" ]]; then
    echo "$app_dir does not exist" >&2
    exit 66
fi

ditto "$app_dir" "$staging_dir/$app_name.app"
ln -s /Applications "$staging_dir/Applications"
rm -f "$dmg_path"

hdiutil create \
    -volname "$app_name" \
    -srcfolder "$staging_dir" \
    -ov \
    -format UDZO \
    "$dmg_path"

echo "$dmg_path"

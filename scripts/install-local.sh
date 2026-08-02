#!/bin/zsh

set -euo pipefail

repo_dir="${0:A:h:h}"
app_name="${APP_NAME:-Natter}"
executable_name="${EXECUTABLE_NAME:-dictation}"
source_app="$repo_dir/dist/$app_name.app"
install_dir="${INSTALL_DIR:-$HOME/Applications}"
installed_app="$install_dir/$app_name.app"
enable_login="${ENABLE_LOGIN:-1}"

"$repo_dir/scripts/build-app.sh"
mkdir -p "$install_dir"

pkill -f "$installed_app/Contents/MacOS/$executable_name" 2>/dev/null || true
if [[ -e "$installed_app" ]]; then
    case "$installed_app" in
        "$install_dir/$app_name.app") rm -r "$installed_app" ;;
        *)
            echo "refusing to replace unexpected app path: $installed_app" >&2
            exit 70
            ;;
    esac
fi

ditto "$source_app" "$installed_app"
xattr -dr com.apple.quarantine "$installed_app" 2>/dev/null || true
codesign --verify --deep --strict "$installed_app"

if [[ "$enable_login" == "1" ]]; then
    login_status="$("$installed_app/Contents/MacOS/$executable_name" --enable-login)"
    if [[ "$login_status" == "requires-approval" ]]; then
        echo "Open at Login needs approval in System Settings > General > Login Items."
    else
        echo "Open at Login: $login_status"
    fi
fi

open -n "$installed_app"
echo "Installed $installed_app"

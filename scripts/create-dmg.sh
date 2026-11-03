#!/bin/bash
set -euo pipefail
cd "$(dirname "$0")/.."

app_path="$PWD/build/Codex Usage.app"
dmg_path="$PWD/build/Codex-Usage.dmg"

if [[ ! -d "$app_path" ]]; then
    printf 'Build the app before creating the DMG.\n' >&2
    exit 1
fi

staging_dir=$(mktemp -d "${TMPDIR:-/tmp}/codex-usage-dmg.XXXXXX")
trap 'rm -rf "$staging_dir"' EXIT
ditto "$app_path" "$staging_dir/Codex Usage.app"
ln -s /Applications "$staging_dir/Applications"

hdiutil create -ov -volname "Codex Usage" -fs HFS+ -srcfolder "$staging_dir" -format UDZO "$dmg_path"
printf 'Created: %s\n' "$dmg_path"

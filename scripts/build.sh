#!/bin/bash
set -euo pipefail
cd "$(dirname "$0")/.."
app_path="$PWD/build/Codex Usage.app"
module_cache="${SWIFT_MODULE_CACHE_PATH:-${TMPDIR:-/tmp}/codex-usage-swift-module-cache}"
mkdir -p "$app_path/Contents/MacOS" "$module_cache"
sources=()
while IFS= read -r -d '' source_file; do
    sources+=("$source_file")
done < <(find Sources -type f -name '*.swift' -print0)

xcrun swiftc -O -module-cache-path "$module_cache" -framework AppKit -framework UserNotifications "${sources[@]}" -o "$app_path/Contents/MacOS/CodexUsage"
cp Info.plist "$app_path/Contents/Info.plist"
codesign --force --sign - "$app_path"
printf 'Built: %s\n' "$app_path"

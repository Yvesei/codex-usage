#!/bin/bash
set -euo pipefail
cd "$(dirname "$0")/.."
app_path="$PWD/build/Codex Usage.app"
module_cache="${SWIFT_MODULE_CACHE_PATH:-${TMPDIR:-/tmp}/codex-usage-swift-module-cache}"
mkdir -p "$app_path/Contents/MacOS" "$app_path/Contents/Resources" "$module_cache"
sources=()
while IFS= read -r -d '' source_file; do
    sources+=("$source_file")
done < <(find Sources -type f -name '*.swift' -print0)

if [[ "${BUILD_UNIVERSAL:-0}" == "1" ]]; then
    build_dir=$(mktemp -d "${TMPDIR:-/tmp}/codex-usage-build.XXXXXX")
    trap 'rm -rf "$build_dir"' EXIT

    for architecture in x86_64 arm64; do
        xcrun swiftc -O -target "${architecture}-apple-macos12.0" \
            -module-cache-path "$module_cache" -framework AppKit -framework UserNotifications \
            "${sources[@]}" -o "$build_dir/CodexUsage-$architecture"
    done

    xcrun lipo -create "$build_dir/CodexUsage-x86_64" "$build_dir/CodexUsage-arm64" \
        -output "$app_path/Contents/MacOS/CodexUsage"
else
    xcrun swiftc -O -module-cache-path "$module_cache" -framework AppKit -framework UserNotifications \
        "${sources[@]}" -o "$app_path/Contents/MacOS/CodexUsage"
fi
cp Info.plist "$app_path/Contents/Info.plist"
if [[ -n "${APP_VERSION:-}" ]]; then
    if [[ ! "$APP_VERSION" =~ ^[0-9]+\.[0-9]+\.[0-9]+$ ]]; then
        printf 'APP_VERSION must have the form x.y.z\n' >&2
        exit 1
    fi
    /usr/libexec/PlistBuddy -c "Set :CFBundleShortVersionString $APP_VERSION" "$app_path/Contents/Info.plist"
    /usr/libexec/PlistBuddy -c "Set :CFBundleVersion $APP_VERSION" "$app_path/Contents/Info.plist"
fi
cp Resources/AppIcon.icns "$app_path/Contents/Resources/AppIcon.icns"
codesign --force --sign - "$app_path"
printf 'Built: %s\n' "$app_path"

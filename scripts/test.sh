#!/bin/bash
set -euo pipefail
cd "$(dirname "$0")/.."

test_dir=$(mktemp -d "${TMPDIR:-/tmp}/codex-usage-tests.XXXXXX")
trap 'rm -rf "$test_dir"' EXIT
module_cache="${SWIFT_MODULE_CACHE_PATH:-${TMPDIR:-/tmp}/codex-usage-swift-module-cache}"
mkdir -p "$module_cache"

swiftc=(xcrun swiftc -module-cache-path "$module_cache")

"${swiftc[@]}" Sources/Models/Usage.swift Sources/Codex/UsageParser.swift \
    Tests/main.swift -o "$test_dir/parser-tests"
"$test_dir/parser-tests"

"${swiftc[@]}" Sources/Models/Usage.swift Sources/Codex/UsageParser.swift \
    Sources/Codex/CodexExecutableLocator.swift Sources/Codex/CodexUsageReader.swift \
    Tests/Reader/main.swift -o "$test_dir/reader-tests"
"$test_dir/reader-tests" "$PWD/Tests/Reader/fake-codex.sh"

"${swiftc[@]}" Sources/Models/DailyTokenUsage.swift Sources/Codex/CodexExecutableLocator.swift \
    Sources/Codex/DailyTokenReader.swift Tests/Daily/main.swift -o "$test_dir/daily-tests"
"$test_dir/daily-tests" "$PWD/Tests/Daily/fake-codex.sh"

"${swiftc[@]}" Sources/Analytics/*.swift Tests/Analytics/main.swift -o "$test_dir/analytics-tests"
"$test_dir/analytics-tests"

"${swiftc[@]}" -framework AppKit Sources/Models/Usage.swift Sources/Analytics/ModelAnalytics.swift \
    Sources/UI/UsageProgressView.swift Sources/UI/UsageSummaryView.swift \
    Sources/UI/ModelUsageChartView.swift Sources/UI/DailyTokenUsageView.swift \
    Sources/UI/UsageMenuBuilder.swift Tests/Menu/main.swift -o "$test_dir/menu-tests"
"$test_dir/menu-tests"

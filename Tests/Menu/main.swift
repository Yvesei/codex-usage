import AppKit
import Foundation

func expect(_ condition: @autoclosure () -> Bool, _ message: String) {
    if !condition() {
        fatalError(message)
    }
}

let window = UsageWindow(usedPercent: 25, durationMinutes: 300, resetsAt: nil)
let weekly = UsageWindow(usedPercent: 40, durationMinutes: 10_080, resetsAt: nil)
let snapshot = UsageSnapshot(fiveHour: window, weekly: weekly, plan: "plus", allowed: true)
let builder = UsageMenuBuilder()
let state = UsageMenuState(
    snapshot: snapshot,
    refreshedAt: nil,
    isRefreshing: false,
    errorMessage: nil,
    cacheWarning: nil,
    showBothPercentages: true,
    alertsEnabled: false,
    alertThreshold: 10
)

let menu = builder.makeMenu(for: state)
expect(menu.minimumWidth == 320, "The menu should keep a consistent minimum width.")
expect(menu.items.contains { $0.view is UsageSummaryView }, "The menu should display the usage summary.")
guard let summary = menu.items.compactMap({ $0.view as? UsageSummaryView }).first else {
    fatalError("The usage summary is missing.")
}
expect(summary.frame.height > 70, "The usage summary should have enough height for its contents.")

func descendants(of view: NSView) -> [NSView] {
    return view.subviews + view.subviews.flatMap { descendants(of: $0) }
}

let elements = descendants(of: summary)
let progress = elements.compactMap { $0 as? UsageProgressView }.first
expect(progress?.remaining == 75, "The session progress bar should show remaining usage.")
let labels = elements.compactMap { $0 as? NSTextField }.map { $0.stringValue }
expect(labels.contains("75% left"), "The session percentage should be visible.")
expect(labels.contains("60% left"), "The weekly percentage should be visible.")
expect(labels.contains("Plus"), "The account plan should be visible in the header.")
expect(menu.item(withTitle: "Refresh Now") != nil, "The refresh action should be available.")

guard let unavailable = menu.items.compactMap({ $0.view as? DailyTokenUsageView }).first else {
    fatalError("The daily token activity section is missing.")
}
let unavailableLabels = descendants(of: unavailable).compactMap { $0 as? NSTextField }.map { $0.stringValue }
expect(unavailableLabels.contains("Daily token activity"), "The activity section should remain visible.")
expect(menu.item(withTitle: "Please refresh") != nil, "Unavailable activity should prompt a refresh.")

var dailyState = state
let buckets = (1...8).map { day in
    DailyTokenBucket(startDate: String(format: "2026-11-%02d", day), tokens: Int64(day * 1_000))
}
dailyState.dailyUsage = DailyTokenUsage(accountEmail: nil, buckets: buckets, fetchedAt: Date())
let dailyMenu = builder.makeMenu(for: dailyState)
guard let dailyView = dailyMenu.items.compactMap({ $0.view as? DailyTokenUsageView }).first else {
    fatalError("The daily token activity section is missing.")
}
guard let chart = descendants(of: dailyView).compactMap({ $0 as? DailyTokenChartView }).first else {
    fatalError("The daily token chart is missing.")
}
expect(chart.buckets.count == 7, "The chart should show seven reported days.")
expect(chart.buckets.first?.startDate == "2026-11-02", "The oldest bar should be on the left.")
expect(chart.buckets.last?.startDate == "2026-11-08", "The newest bar should be on the right.")
expect(chart.buckets.last?.tokens == 8_000, "The chart should preserve exact token totals.")
let numberFormatter = NumberFormatter()
numberFormatter.numberStyle = .decimal
let expectedTotal = numberFormatter.string(from: 8_000) ?? "8000"
let lastBarPoint = NSPoint(x: chart.bounds.width * 6.5 / 7, y: 50)
let tooltip = chart.view(chart, stringForToolTip: 0, point: lastBarPoint, userData: nil)
expect(tooltip == "8 Nov 2026 · \(expectedTotal) tokens", "Hover details should identify the bar and its exact token count.")

dailyState.dailyUsage = DailyTokenUsage(accountEmail: nil, buckets: [], fetchedAt: Date())
let emptyMenu = builder.makeMenu(for: dailyState)
guard let emptyView = emptyMenu.items.compactMap({ $0.view as? DailyTokenUsageView }).first else {
    fatalError("The daily token activity section is missing.")
}
let emptyLabels = descendants(of: emptyView).compactMap { $0 as? NSTextField }.map { $0.stringValue }
expect(emptyLabels.contains("No daily token activity reported"), "An empty response should be explained.")

guard let settings = menu.item(withTitle: "Settings")?.submenu else {
    fatalError("The settings submenu is missing.")
}
expect(settings.item(withTitle: "Show Both Percentages")?.state == .on, "The display setting should be checked.")

let failed = UsageMenuState(
    snapshot: snapshot,
    refreshedAt: nil,
    isRefreshing: false,
    errorMessage: "Couldn't update usage.",
    cacheWarning: "Saved reading",
    showBothPercentages: true,
    alertsEnabled: true,
    alertThreshold: 5
)
let failedMenu = builder.makeMenu(for: failed)
expect(failedMenu.minimumWidth == menu.minimumWidth, "The menu width should stay the same after a failure.")
expect(failedMenu.items.contains { $0.view is UsageSummaryView }, "A failed refresh should keep the reading visible.")
expect(failedMenu.item(withTitle: "Refresh Now") != nil, "A failed refresh should offer a retry.")
expect(failedMenu.items.filter { $0.title == "Please refresh" }.count == 1, "Failures should use one short message.")
expect(failedMenu.item(withTitle: "Couldn't update usage.") == nil, "Detailed errors should not appear in the menu.")
expect(failedMenu.item(withTitle: "Saved reading") == nil, "Cache warnings should not appear in the menu.")

var multipleFailures = failed
multipleFailures.dailyError = "A very long daily activity error."
multipleFailures.dailyCacheWarning = "A very long saved activity warning."
let multipleFailuresMenu = builder.makeMenu(for: multipleFailures)
expect(multipleFailuresMenu.items.filter { $0.title == "Please refresh" }.count == 1, "Multiple failures should share one message.")
expect(multipleFailuresMenu.item(withTitle: "A very long daily activity error.") == nil, "Daily errors should not appear in the menu.")
expect(multipleFailuresMenu.item(withTitle: "A very long saved activity warning.") == nil, "Daily cache warnings should not appear in the menu.")

print("Native menu checks passed.")

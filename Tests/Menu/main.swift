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
expect(unavailableLabels.contains("Daily model usage"), "The activity section should remain visible.")
expect(menu.item(withTitle: "Please refresh") != nil, "Unavailable activity should prompt a refresh.")

let now = ISO8601DateFormatter().date(from: "2026-11-03T12:00:00Z")!
let dates = AnalyticsDateRange(endingAt: now).dates
let modelUsage = ModelAnalyticsSnapshot(
    accountID: "test-account",
    userID: "test-user",
    days: [
        ModelUsageDay(date: dates[4], models: []),
        ModelUsageDay(date: dates[5], models: [
            ModelUsageValue(model: "alpha", value: 2.1234),
            ModelUsageValue(model: "beta", value: 3.4321)
        ])
    ],
    unit: "Credits",
    fetchedAt: now
)
let modelView = DailyTokenUsageView(usage: modelUsage, now: now)
guard let chart = descendants(of: modelView).compactMap({ $0 as? ModelUsageChartView }).first else {
    fatalError("The daily model chart is missing.")
}
expect(chart.days.map(\.date) == dates, "The chart should show the current seven calendar days in order.")
expect(chart.days[4].models?.isEmpty == true, "A reported empty day should remain empty.")
expect(chart.days[6].models == nil, "An unreported today should not be replaced with zero usage.")
let yesterdayPoint = NSPoint(x: chart.bounds.width * 5.5 / 7, y: 50)
let tooltip = chart.view(chart, stringForToolTip: 0, point: yesterdayPoint, userData: nil)
let formatter = NumberFormatter()
formatter.numberStyle = .decimal
formatter.maximumFractionDigits = 2
let expectedTotal = formatter.string(from: 5.5555)!
let expectedAlpha = formatter.string(from: 2.1234)!
let expectedBeta = formatter.string(from: 3.4321)!
expect(tooltip.contains("\(expectedTotal) credits"), "The combined total should be rounded to two decimal places.")
expect(tooltip.contains("alpha: \(expectedAlpha) credits"), "The first model should be rounded to two decimal places.")
expect(tooltip.contains("beta: \(expectedBeta) credits"), "The second model should be rounded to two decimal places.")
let selectedDay = ModelUsageDay(date: dates[5], models: [
    ModelUsageValue(model: "alpha", value: 99),
    ModelUsageValue(model: "beta", value: 1),
    ModelUsageValue(model: "tiny", value: 0.5),
    ModelUsageValue(model: "zero", value: 0)
])
expect(chart.legendPercentage(for: "alpha", day: selectedDay) == "99%", "The legend should show the model's share of the hovered day.")
expect(chart.legendPercentage(for: "beta", day: selectedDay) == nil, "Shares under one percent should stay hidden.")
expect(chart.legendPercentage(for: "tiny", day: selectedDay) == nil, "Tiny shares should stay hidden.")
expect(chart.legendPercentage(for: "zero", day: selectedDay) == nil, "Zero usage should stay hidden.")
let thresholdDay = ModelUsageDay(date: dates[5], models: [
    ModelUsageValue(model: "alpha", value: 99),
    ModelUsageValue(model: "beta", value: 1)
])
expect(chart.legendPercentage(for: "beta", day: thresholdDay) == "1%", "A one percent share should be shown.")
expect(chart.legendPercentage(for: "alpha", day: nil) == nil, "The legend should show only names when no day is hovered.")
let todayPoint = NSPoint(x: chart.bounds.width * 6.5 / 7, y: 50)
let missingTooltip = chart.view(chart, stringForToolTip: 0, point: todayPoint, userData: nil)
expect(missingTooltip.contains("No data reported"), "Missing today should be described as unavailable.")

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
multipleFailures.modelError = "A very long daily activity error."
let multipleFailuresMenu = builder.makeMenu(for: multipleFailures)
expect(multipleFailuresMenu.items.filter { $0.title == "Please refresh" }.count == 1, "Multiple failures should share one message.")
expect(multipleFailuresMenu.item(withTitle: "A very long daily activity error.") == nil, "Daily errors should not appear in the menu.")

print("Native menu checks passed.")

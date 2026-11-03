import AppKit

final class ModelUsageChartView: NSView, NSViewToolTipOwner {
    let days: [ModelUsageDay]
    private let unit: String
    private let models: [String]
    private let colors: [String: NSColor]
    private var selectedIndex: Int?
    private var hoverTrackingArea: NSTrackingArea?

    private let chartTop: CGFloat = 25
    private let chartBottom: CGFloat = 93
    private let legendTop: CGFloat = 116
    private let legendRowHeight: CGFloat = 18

    override var isFlipped: Bool {
        return true
    }

    init(days: [ModelUsageDay], unit: String) {
        let modelNames = Array(Set(days.flatMap { day in
            (day.models ?? []).map(\.model)
        })).sorted()
        self.days = days
        self.unit = unit
        self.models = modelNames
        self.colors = Self.modelColors(for: modelNames)

        let legendRows = (modelNames.count + 1) / 2
        let height = 116 + CGFloat(legendRows) * 18
        super.init(frame: NSRect(x: 0, y: 0, width: 280, height: height))
        setAccessibilityElement(true)
        setAccessibilityLabel("Daily model usage, last seven days")
    }

    required init?(coder: NSCoder) {
        return nil
    }

    override func updateTrackingAreas() {
        super.updateTrackingAreas()
        if let hoverTrackingArea {
            removeTrackingArea(hoverTrackingArea)
        }
        let area = NSTrackingArea(
            rect: .zero,
            options: [.activeAlways, .mouseMoved, .mouseEnteredAndExited, .inVisibleRect],
            owner: self,
            userInfo: nil
        )
        addTrackingArea(area)
        hoverTrackingArea = area

        removeAllToolTips()
        for index in days.indices {
            addToolTip(columnRect(at: index), owner: self, userData: nil)
        }
    }

    override func mouseEntered(with event: NSEvent) {
        updateSelection(for: event)
    }

    override func mouseMoved(with event: NSEvent) {
        updateSelection(for: event)
    }

    override func mouseExited(with event: NSEvent) {
        selectedIndex = nil
        needsDisplay = true
    }

    func view(
        _ view: NSView,
        stringForToolTip tag: NSView.ToolTipTag,
        point: NSPoint,
        userData: UnsafeMutableRawPointer?
    ) -> String {
        guard let index = index(at: point) else {
            return ""
        }
        return detail(for: days[index])
    }

    override func draw(_ dirtyRect: NSRect) {
        super.draw(dirtyRect)
        drawHeading()
        drawBars()
        drawLegend()
    }

    private func drawHeading() {
        let heading: String
        if let selectedIndex {
            heading = summary(for: days[selectedIndex])
        } else {
            heading = "Last 7 days · \(unit)"
        }
        drawText(heading, in: NSRect(x: 0, y: 0, width: bounds.width, height: 16), size: 11)
    }

    private func drawBars() {
        guard !days.isEmpty else {
            return
        }
        let maximum = days.map { total(for: $0) ?? 0 }.max() ?? 0
        let availableHeight = chartBottom - chartTop
        let baseline = NSBezierPath()
        baseline.move(to: NSPoint(x: 0, y: chartBottom))
        baseline.line(to: NSPoint(x: bounds.width, y: chartBottom))
        NSColor.separatorColor.setStroke()
        baseline.lineWidth = 1
        baseline.stroke()

        for index in days.indices {
            let day = days[index]
            let column = columnRect(at: index)
            let barWidth = min(22, column.width - 8)

            if let values = day.models, let total = total(for: day), total > 0, maximum > 0 {
                let height = availableHeight * CGFloat(total / maximum)
                let bar = NSRect(x: column.midX - barWidth / 2, y: chartBottom - height, width: barWidth, height: height)
                drawStack(values, total: total, in: bar, selected: selectedIndex == nil || selectedIndex == index)
            } else if day.models == nil {
                let unknown = NSRect(x: column.minX, y: chartBottom - 14, width: column.width, height: 14)
                drawText("–", in: unknown, size: 10, alignment: .center)
            }

            let dateRect = NSRect(x: column.minX, y: chartBottom + 5, width: column.width, height: 15)
            drawText(date(day.date, format: "d MMM"), in: dateRect, size: 9, alignment: .center)
        }
    }

    private func drawStack(_ values: [ModelUsageValue], total: Double, in bar: NSRect, selected: Bool) {
        NSGraphicsContext.saveGraphicsState()
        NSBezierPath(roundedRect: bar, xRadius: 3, yRadius: 3).addClip()

        var bottom = bar.maxY
        for value in values.sorted(by: { $0.model < $1.model }) {
            guard value.value.isFinite, value.value > 0 else {
                continue
            }
            let height = bar.height * CGFloat(value.value / total)
            let rect = NSRect(x: bar.minX, y: bottom - height, width: bar.width, height: height)
            let color = colors[value.model] ?? .systemBlue
            color.withAlphaComponent(selected ? 1 : 0.45).setFill()
            NSBezierPath(rect: rect).fill()
            bottom -= height
        }

        NSGraphicsContext.restoreGraphicsState()
    }

    private func drawLegend() {
        let columnWidth = bounds.width / 2
        for (index, model) in models.enumerated() {
            let x = CGFloat(index % 2) * columnWidth
            let y = legendTop + CGFloat(index / 2) * legendRowHeight
            let swatch = NSRect(x: x, y: y + 3, width: 8, height: 8)
            (colors[model] ?? .systemBlue).setFill()
            NSBezierPath(roundedRect: swatch, xRadius: 2, yRadius: 2).fill()
            let label = NSRect(x: x + 13, y: y, width: columnWidth - 17, height: 15)
            let day = selectedIndex.map { days[$0] }
            drawLegendLabel(model, day: day, in: label)
        }
    }

    private func drawLegendLabel(_ model: String, day: ModelUsageDay?, in rect: NSRect) {
        let paragraph = NSMutableParagraphStyle()
        paragraph.lineBreakMode = .byTruncatingTail
        let percentage = legendPercentage(for: model, day: day)
        let weight: NSFont.Weight = percentage == nil ? .medium : .bold
        let color: NSColor = percentage == nil ? .secondaryLabelColor : .labelColor
        let attributes: [NSAttributedString.Key: Any] = [
            .font: NSFont.systemFont(ofSize: 10, weight: weight),
            .foregroundColor: color,
            .paragraphStyle: paragraph
        ]
        guard let percentage = percentage else {
            (model as NSString).draw(in: rect, withAttributes: attributes)
            return
        }

        let percentageWidth = (percentage as NSString).size(withAttributes: attributes).width
        let nameWidth = (model as NSString).size(withAttributes: attributes).width
        let availableNameWidth = max(0, rect.width - percentageWidth - 4)
        let drawnNameWidth = min(nameWidth, availableNameWidth)
        let nameRect = NSRect(x: rect.minX, y: rect.minY, width: drawnNameWidth, height: rect.height)
        (model as NSString).draw(in: nameRect, withAttributes: attributes)

        let percentageRect = NSRect(
            x: nameRect.maxX + 4,
            y: rect.minY,
            width: percentageWidth,
            height: rect.height
        )
        (percentage as NSString).draw(in: percentageRect, withAttributes: attributes)
    }

    func legendPercentage(for model: String, day: ModelUsageDay?) -> String? {
        guard let day = day,
              let total = total(for: day),
              total > 0,
              let value = day.models?.first(where: { $0.model == model })?.value else {
            return nil
        }

        let percentage = value / total * 100
        guard percentage.isFinite, percentage >= 1 else {
            return nil
        }
        return "\(Int(percentage.rounded()))%"
    }

    private func columnRect(at index: Int) -> NSRect {
        let width = bounds.width / CGFloat(max(days.count, 1))
        return NSRect(x: CGFloat(index) * width, y: chartTop, width: width, height: chartBottom + 20 - chartTop)
    }

    private func index(at point: NSPoint) -> Int? {
        return days.indices.first { columnRect(at: $0).contains(point) }
    }

    private func updateSelection(for event: NSEvent) {
        let point = convert(event.locationInWindow, from: nil)
        let index = index(at: point)
        guard selectedIndex != index else {
            return
        }
        selectedIndex = index
        needsDisplay = true
    }

    private func total(for day: ModelUsageDay) -> Double? {
        guard let values = day.models else {
            return nil
        }
        return values.reduce(0) { total, value in
            guard value.value.isFinite, value.value > 0 else {
                return total
            }
            return total + value.value
        }
    }

    private func summary(for day: ModelUsageDay) -> String {
        let formattedDate = date(day.date, format: "d MMM yyyy")
        guard let total = total(for: day) else {
            return "\(formattedDate) · No data reported"
        }
        return "\(formattedDate) · \(format(total)) \(unit.lowercased())"
    }

    private func detail(for day: ModelUsageDay) -> String {
        guard let values = day.models else {
            return summary(for: day)
        }
        let details = values.sorted { $0.model < $1.model }.map { value in
            "\(value.model): \(format(value.value)) \(unit.lowercased())"
        }
        return ([summary(for: day)] + details).joined(separator: "\n")
    }

    private func format(_ value: Double) -> String {
        let formatter = NumberFormatter()
        formatter.numberStyle = .decimal
        formatter.maximumFractionDigits = 2
        return formatter.string(from: NSNumber(value: value)) ?? String(value)
    }

    private func date(_ source: String, format: String) -> String {
        let formatter = DateFormatter()
        formatter.locale = Locale(identifier: "en_GB")
        formatter.timeZone = TimeZone(secondsFromGMT: 0)
        formatter.dateFormat = "yyyy-MM-dd"
        guard let date = formatter.date(from: source) else {
            return source
        }
        formatter.dateFormat = format
        return formatter.string(from: date)
    }

    private func drawText(_ text: String, in rect: NSRect, size: CGFloat, alignment: NSTextAlignment = .left) {
        let paragraph = NSMutableParagraphStyle()
        paragraph.alignment = alignment
        paragraph.lineBreakMode = .byTruncatingTail
        let attributes: [NSAttributedString.Key: Any] = [
            .font: NSFont.systemFont(ofSize: size),
            .foregroundColor: NSColor.secondaryLabelColor,
            .paragraphStyle: paragraph
        ]
        (text as NSString).draw(in: rect, withAttributes: attributes)
    }

    private static func modelColors(for models: [String]) -> [String: NSColor] {
        let palette: [NSColor] = [
            .systemBlue, .systemTeal, .systemPurple, .systemOrange,
            .systemGreen, .systemPink, .systemIndigo, .systemYellow,
            .systemRed, .systemBrown, .systemCyan, .systemMint
        ]
        var result: [String: NSColor] = [:]
        var taken: Set<Int> = []
        for model in models {
            var hash: UInt64 = 14695981039346656037
            for byte in model.utf8 {
                hash = (hash ^ UInt64(byte)) &* 1099511628211
            }
            var index = Int(hash % UInt64(palette.count))
            while taken.contains(index) && taken.count < palette.count {
                index = (index + 1) % palette.count
            }
            result[model] = palette[index]
            taken.insert(index)
        }
        return result
    }
}

import AppKit

final class DailyTokenChartView: NSView, NSViewToolTipOwner {
    let buckets: [DailyTokenBucket]
    private var selectedIndex: Int?
    private var hoverTrackingArea: NSTrackingArea?
    private let chartTop: CGFloat = 23
    private let chartBottom: CGFloat = 91

    override var isFlipped: Bool {
        return true
    }

    init(buckets: [DailyTokenBucket]) {
        let latest = buckets.sorted { $0.startDate > $1.startDate }.prefix(7)
        self.buckets = latest.sorted { $0.startDate < $1.startDate }
        super.init(frame: NSRect(x: 0, y: 0, width: 280, height: 112))
        setAccessibilityElement(true)
        setAccessibilityLabel("Daily token activity, latest \(self.buckets.count) reported days")
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
        for index in buckets.indices {
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

    func view(_ view: NSView, stringForToolTip tag: NSView.ToolTipTag, point: NSPoint, userData: UnsafeMutableRawPointer?) -> String {
        guard let index = index(at: point) else {
            return ""
        }
        return detail(for: buckets[index])
    }

    override func draw(_ dirtyRect: NSRect) {
        super.draw(dirtyRect)
        drawHeading()
        drawBars()
    }

    private func drawHeading() {
        let heading: String
        if let selectedIndex {
            heading = detail(for: buckets[selectedIndex])
        } else {
            heading = "Last \(buckets.count) reported days"
        }
        drawText(heading, in: NSRect(x: 0, y: 0, width: bounds.width, height: 16), size: 11, alignment: .left)
    }

    private func drawBars() {
        guard !buckets.isEmpty else {
            return
        }
        let maximum = buckets.map(\.tokens).max() ?? 0
        let availableHeight = chartBottom - chartTop
        let baseline = NSBezierPath()
        baseline.move(to: NSPoint(x: 0, y: chartBottom))
        baseline.line(to: NSPoint(x: bounds.width, y: chartBottom))
        NSColor.separatorColor.setStroke()
        baseline.lineWidth = 1
        baseline.stroke()

        for index in buckets.indices {
            let bucket = buckets[index]
            let column = columnRect(at: index)
            let barWidth = min(22, column.width - 8)
            let ratio = maximum > 0 ? CGFloat(Double(bucket.tokens) / Double(maximum)) : 0
            let height = bucket.tokens > 0 ? max(2, availableHeight * ratio) : 0
            let bar = NSRect(x: column.midX - barWidth / 2, y: chartBottom - height, width: barWidth, height: height)

            if height > 0 {
                let opacity: CGFloat = selectedIndex == nil || selectedIndex == index ? 0.9 : 0.45
                NSColor.controlAccentColor.withAlphaComponent(opacity).setFill()
                NSBezierPath(roundedRect: bar, xRadius: 3, yRadius: 3).fill()
            }

            let dateRect = NSRect(x: column.minX, y: chartBottom + 5, width: column.width, height: 15)
            drawText(shortDate(bucket.startDate), in: dateRect, size: 9, alignment: .center)
        }
    }

    private func columnRect(at index: Int) -> NSRect {
        let width = bounds.width / CGFloat(max(buckets.count, 1))
        return NSRect(x: CGFloat(index) * width, y: chartTop, width: width, height: bounds.height - chartTop)
    }

    private func index(at point: NSPoint) -> Int? {
        return buckets.indices.first { columnRect(at: $0).contains(point) }
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

    private func detail(for bucket: DailyTokenBucket) -> String {
        let formatter = NumberFormatter()
        formatter.numberStyle = .decimal
        let tokens = formatter.string(from: NSNumber(value: bucket.tokens)) ?? String(bucket.tokens)
        return "\(fullDate(bucket.startDate)) · \(tokens) tokens"
    }

    private func shortDate(_ source: String) -> String {
        return date(source, format: "d MMM")
    }

    private func fullDate(_ source: String) -> String {
        return date(source, format: "d MMM yyyy")
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

    private func drawText(_ text: String, in rect: NSRect, size: CGFloat, alignment: NSTextAlignment) {
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
}

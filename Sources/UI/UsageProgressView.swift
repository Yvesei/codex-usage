import AppKit

final class UsageProgressView: NSView {
    let remaining: Int

    init(remaining: Int) {
        self.remaining = max(0, min(100, remaining))
        super.init(frame: .zero)
        setAccessibilityElement(true)
        setAccessibilityRole(.progressIndicator)
        setAccessibilityLabel("\(self.remaining)% remaining")
    }

    required init?(coder: NSCoder) {
        return nil
    }

    override func draw(_ dirtyRect: NSRect) {
        super.draw(dirtyRect)

        let radius = bounds.height / 2
        let track = NSBezierPath(roundedRect: bounds, xRadius: radius, yRadius: radius)
        NSColor.separatorColor.withAlphaComponent(0.35).setFill()
        track.fill()

        guard remaining > 0 else {
            return
        }

        let width = bounds.width * CGFloat(remaining) / 100
        let filled = NSRect(x: 0, y: 0, width: width, height: bounds.height)
        let path = NSBezierPath(roundedRect: filled, xRadius: radius, yRadius: radius)
        NSColor.systemTeal.setFill()
        path.fill()
    }
}

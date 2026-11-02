import AppKit

enum UsageStatusIcon {
    static func make(fiveHour: Int?, weekly: Int?) -> NSImage {
        let image = NSImage(size: NSSize(width: 17, height: 14), flipped: true) { _ in
            drawBar(y: 1, remaining: fiveHour)
            drawBar(y: 8, remaining: weekly)
            return true
        }
        image.isTemplate = true
        image.accessibilityDescription = "Codex usage"
        return image
    }

    private static func drawBar(y: CGFloat, remaining: Int?) {
        let track = NSRect(x: 0, y: y, width: 17, height: 5)
        NSColor.black.withAlphaComponent(0.25).setFill()
        NSBezierPath(roundedRect: track, xRadius: 2.5, yRadius: 2.5).fill()

        guard let remaining else {
            return
        }

        let percent = max(0, min(100, remaining))
        guard percent > 0 else {
            return
        }

        let width = track.width * CGFloat(percent) / 100
        let filled = NSRect(x: track.minX, y: track.minY, width: width, height: track.height)
        NSColor.black.setFill()
        NSBezierPath(roundedRect: filled, xRadius: 2.5, yRadius: 2.5).fill()
    }
}

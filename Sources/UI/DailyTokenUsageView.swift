import AppKit

final class DailyTokenUsageView: NSView {
    private let contentWidth: CGFloat = 280
    private let stack = NSStackView()

    override var isFlipped: Bool {
        return true
    }

    init(usage: DailyTokenUsage?, isRefreshing: Bool = false) {
        super.init(frame: NSRect(x: 0, y: 0, width: 320, height: 1))

        stack.orientation = .vertical
        stack.alignment = .leading
        stack.spacing = 5
        stack.translatesAutoresizingMaskIntoConstraints = false
        addSubview(stack)

        NSLayoutConstraint.activate([
            stack.leadingAnchor.constraint(equalTo: leadingAnchor, constant: 20),
            stack.trailingAnchor.constraint(equalTo: trailingAnchor, constant: -20),
            stack.topAnchor.constraint(equalTo: topAnchor, constant: 8),
            stack.bottomAnchor.constraint(equalTo: bottomAnchor, constant: -8)
        ])

        addFullWidth(label("Daily token activity", size: 13, weight: .medium))

        if let buckets = usage?.buckets {
            if buckets.isEmpty {
                addMessage("No daily token activity reported")
            } else {
                let chart = DailyTokenChartView(buckets: buckets)
                chart.heightAnchor.constraint(equalToConstant: 112).isActive = true
                addFullWidth(chart)
            }
        } else if isRefreshing && usage == nil {
            addMessage("Loading daily token activity…")
        }

        layoutSubtreeIfNeeded()
        setFrameSize(NSSize(width: 320, height: stack.fittingSize.height + 16))
    }

    required init?(coder: NSCoder) {
        return nil
    }

    private func addMessage(_ message: String) {
        let field = label(message, size: 11, color: .secondaryLabelColor)
        addFullWidth(field)
    }

    private func addFullWidth(_ view: NSView) {
        stack.addArrangedSubview(view)
        view.widthAnchor.constraint(equalToConstant: contentWidth).isActive = true
    }

    private func label(
        _ text: String,
        size: CGFloat,
        weight: NSFont.Weight = .regular,
        color: NSColor = .labelColor
    ) -> NSTextField {
        let field = NSTextField(labelWithString: text)
        field.font = NSFont.systemFont(ofSize: size, weight: weight)
        field.textColor = color
        return field
    }
}

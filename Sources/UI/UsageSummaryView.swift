import AppKit

final class UsageSummaryView: NSView {
    private let contentWidth: CGFloat = 280
    private let stack = NSStackView()

    override var isFlipped: Bool {
        return true
    }

    init(snapshot: UsageSnapshot, refreshedAt: Date?) {
        super.init(frame: NSRect(x: 0, y: 0, width: 320, height: 1))

        stack.orientation = .vertical
        stack.alignment = .leading
        stack.spacing = 0
        stack.translatesAutoresizingMaskIntoConstraints = false
        addSubview(stack)

        NSLayoutConstraint.activate([
            stack.leadingAnchor.constraint(equalTo: leadingAnchor, constant: 20),
            stack.trailingAnchor.constraint(equalTo: trailingAnchor, constant: -20),
            stack.topAnchor.constraint(equalTo: topAnchor, constant: 8),
            stack.bottomAnchor.constraint(equalTo: bottomAnchor, constant: -8)
        ])

        let header = makeHeader(snapshot: snapshot, refreshedAt: refreshedAt)
        addFullWidth(header, to: stack)
        stack.setCustomSpacing(10, after: header)

        let divider = NSBox()
        divider.boxType = .separator
        addFullWidth(divider, to: stack)
        stack.setCustomSpacing(12, after: divider)

        let session = makeWindow("Session", window: snapshot.fiveHour, weekly: false)
        addFullWidth(session, to: stack)
        stack.setCustomSpacing(12, after: session)

        let weekly = makeWindow("Weekly", window: snapshot.weekly, weekly: true)
        addFullWidth(weekly, to: stack)

        layoutSubtreeIfNeeded()
        setFrameSize(NSSize(width: 320, height: stack.fittingSize.height + 16))
    }

    required init?(coder: NSCoder) {
        return nil
    }

    private func makeHeader(snapshot: UsageSnapshot, refreshedAt: Date?) -> NSStackView {
        let header = verticalStack(spacing: 4)
        let titleRow = horizontalStack()
        let title = label("Codex", size: 13, weight: .semibold)
        titleRow.addArrangedSubview(title)
        titleRow.addArrangedSubview(spacer())

        if let email = snapshot.accountEmail {
            let account = label(email, size: 11, color: .secondaryLabelColor)
            account.lineBreakMode = .byTruncatingMiddle
            titleRow.addArrangedSubview(account)
        }
        addFullWidth(titleRow, to: header)

        let detailRow = horizontalStack()
        let updated = updateText(refreshedAt)
        detailRow.addArrangedSubview(label(updated, size: 11, color: .secondaryLabelColor))
        detailRow.addArrangedSubview(spacer())

        if let plan = snapshot.plan {
            let name = plan.replacingOccurrences(of: "_", with: " ").capitalized
            detailRow.addArrangedSubview(label(name, size: 11, color: .secondaryLabelColor))
        }
        addFullWidth(detailRow, to: header)

        return header
    }

    private func makeWindow(_ title: String, window: UsageWindow?, weekly: Bool) -> NSStackView {
        let section = verticalStack(spacing: 6)
        addFullWidth(label(title, size: 13, weight: .medium), to: section)

        guard let window else {
            addFullWidth(label("Unavailable", size: 11, color: .secondaryLabelColor), to: section)
            return section
        }

        let progress = UsageProgressView(remaining: window.remainingPercent)
        progress.heightAnchor.constraint(equalToConstant: 6).isActive = true
        addFullWidth(progress, to: section)

        let details = horizontalStack()
        let amount = label("\(window.remainingPercent)% left", size: 11)
        details.addArrangedSubview(amount)
        details.addArrangedSubview(spacer())

        if let reset = window.resetsAt {
            let text = "Resets \(resetDate(reset, weekly: weekly)) (\(relativeDate(reset)))"
            let resetLabel = label(text, size: 11, color: .secondaryLabelColor)
            resetLabel.alignment = .right
            resetLabel.lineBreakMode = .byTruncatingTail
            details.addArrangedSubview(resetLabel)
        }
        addFullWidth(details, to: section)

        return section
    }

    private func verticalStack(spacing: CGFloat) -> NSStackView {
        let view = NSStackView()
        view.orientation = .vertical
        view.alignment = .leading
        view.spacing = spacing
        return view
    }

    private func horizontalStack() -> NSStackView {
        let view = NSStackView()
        view.orientation = .horizontal
        view.alignment = .centerY
        view.spacing = 8
        return view
    }

    private func spacer() -> NSView {
        let view = NSView()
        view.setContentHuggingPriority(.defaultLow, for: .horizontal)
        return view
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

    private func addFullWidth(_ view: NSView, to container: NSStackView) {
        container.addArrangedSubview(view)
        view.widthAnchor.constraint(equalToConstant: contentWidth).isActive = true
    }

    private func updateText(_ date: Date?) -> String {
        guard let date else {
            return "Waiting for update"
        }
        if abs(date.timeIntervalSinceNow) < 60 {
            return "Updated just now"
        }
        return "Updated \(relativeDate(date))"
    }

    private func resetDate(_ date: Date, weekly: Bool) -> String {
        let formatter = DateFormatter()
        formatter.locale = Locale(identifier: "en_GB")
        formatter.dateFormat = weekly ? "d MMM, yyyy 'at' HH:mm" : "HH:mm"
        return formatter.string(from: date)
    }

    private func relativeDate(_ date: Date) -> String {
        let formatter = RelativeDateTimeFormatter()
        formatter.unitsStyle = .full
        return formatter.localizedString(for: date, relativeTo: Date())
    }
}

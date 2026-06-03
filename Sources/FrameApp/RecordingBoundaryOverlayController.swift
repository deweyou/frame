import AppKit

@MainActor
final class RecordingBoundaryOverlayController {
    private var panel: NSPanel?

    func show(rect: CGRect) {
        close()

        let normalizedRect = rect.integral
        let panel = NSPanel(
            contentRect: normalizedRect,
            styleMask: [.borderless, .nonactivatingPanel],
            backing: .buffered,
            defer: false
        )
        panel.collectionBehavior = [.canJoinAllSpaces, .fullScreenAuxiliary, .stationary, .transient]
        panel.level = .screenSaver
        panel.isOpaque = false
        panel.backgroundColor = .clear
        panel.hasShadow = false
        panel.ignoresMouseEvents = true
        panel.isReleasedWhenClosed = false
        panel.sharingType = .none
        panel.contentView = RecordingBoundaryView(frame: CGRect(origin: .zero, size: normalizedRect.size))
        panel.orderFrontRegardless()

        self.panel = panel
    }

    func close() {
        panel?.orderOut(nil)
        panel?.close()
        panel = nil
    }

    func frameForTesting() -> CGRect? {
        panel?.frame
    }

    func ignoresMouseEventsForTesting() -> Bool? {
        panel?.ignoresMouseEvents
    }

    func sharingTypeForTesting() -> NSWindow.SharingType? {
        panel?.sharingType
    }
}

private final class RecordingBoundaryView: NSView {
    override var isOpaque: Bool {
        false
    }

    override init(frame frameRect: NSRect) {
        super.init(frame: frameRect)
        wantsLayer = true
        layer?.backgroundColor = NSColor.clear.cgColor
    }

    @available(*, unavailable)
    required init?(coder: NSCoder) {
        nil
    }

    override func draw(_ dirtyRect: NSRect) {
        super.draw(dirtyRect)

        let borderRect = bounds.insetBy(dx: 1.5, dy: 1.5)
        NSColor.white.withAlphaComponent(0.75).setStroke()
        let outerPath = NSBezierPath(roundedRect: borderRect, xRadius: 2, yRadius: 2)
        outerPath.lineWidth = 3
        outerPath.stroke()

        NSColor.systemRed.setStroke()
        let innerPath = NSBezierPath(roundedRect: borderRect, xRadius: 2, yRadius: 2)
        innerPath.lineWidth = 2
        innerPath.stroke()

        drawCornerTicks(in: borderRect)
    }

    private func drawCornerTicks(in rect: CGRect) {
        let tickLength: CGFloat = min(18, max(8, min(rect.width, rect.height) * 0.12))
        let tickPath = NSBezierPath()
        tickPath.lineWidth = 3
        tickPath.lineCapStyle = .round

        tickPath.move(to: CGPoint(x: rect.minX, y: rect.minY + tickLength))
        tickPath.line(to: CGPoint(x: rect.minX, y: rect.minY))
        tickPath.line(to: CGPoint(x: rect.minX + tickLength, y: rect.minY))

        tickPath.move(to: CGPoint(x: rect.maxX - tickLength, y: rect.minY))
        tickPath.line(to: CGPoint(x: rect.maxX, y: rect.minY))
        tickPath.line(to: CGPoint(x: rect.maxX, y: rect.minY + tickLength))

        tickPath.move(to: CGPoint(x: rect.maxX, y: rect.maxY - tickLength))
        tickPath.line(to: CGPoint(x: rect.maxX, y: rect.maxY))
        tickPath.line(to: CGPoint(x: rect.maxX - tickLength, y: rect.maxY))

        tickPath.move(to: CGPoint(x: rect.minX + tickLength, y: rect.maxY))
        tickPath.line(to: CGPoint(x: rect.minX, y: rect.maxY))
        tickPath.line(to: CGPoint(x: rect.minX, y: rect.maxY - tickLength))

        NSColor.systemRed.setStroke()
        tickPath.stroke()
    }
}

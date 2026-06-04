import AppKit

@MainActor
final class RecordingBoundaryOverlayController {
    private var panel: NSPanel?
    private var displayedSelectionRect: CGRect?

    func show(rect: CGRect) {
        close()

        let normalizedRect = rect.integral
        let screenFrame = preferredScreenFrame(containing: normalizedRect).integral
        let localSelectionRect = normalizedRect.offsetBy(dx: -screenFrame.minX, dy: -screenFrame.minY)
        let panel = NSPanel(
            contentRect: screenFrame,
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
        panel.contentView = RecordingBoundaryView(
            frame: CGRect(origin: .zero, size: screenFrame.size),
            selectionRect: localSelectionRect
        )
        panel.orderFrontRegardless()

        self.panel = panel
        displayedSelectionRect = localSelectionRect
    }

    func close() {
        panel?.orderOut(nil)
        panel?.close()
        panel = nil
        displayedSelectionRect = nil
    }

    func frameForTesting() -> CGRect? {
        panel?.frame
    }

    func selectionRectForTesting() -> CGRect? {
        displayedSelectionRect
    }

    func ignoresMouseEventsForTesting() -> Bool? {
        panel?.ignoresMouseEvents
    }

    func sharingTypeForTesting() -> NSWindow.SharingType? {
        panel?.sharingType
    }

    private func preferredScreenFrame(containing rect: CGRect) -> CGRect {
        let fallbackFrame = NSScreen.main?.frame ?? rect
        return NSScreen.screens.max { firstScreen, secondScreen in
            intersectionArea(firstScreen.frame, rect) < intersectionArea(secondScreen.frame, rect)
        }?.frame ?? fallbackFrame
    }

    private func intersectionArea(_ firstRect: CGRect, _ secondRect: CGRect) -> CGFloat {
        let intersection = firstRect.intersection(secondRect)
        guard !intersection.isNull else {
            return 0
        }

        return intersection.width * intersection.height
    }
}

private final class RecordingBoundaryView: NSView {
    private let selectionRect: CGRect

    override var isOpaque: Bool {
        false
    }

    init(frame frameRect: NSRect, selectionRect: CGRect) {
        self.selectionRect = selectionRect
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

        drawDimmedBackdrop(excluding: selectionRect)
        drawSelectionChrome(selectionRect)
    }

    private func drawDimmedBackdrop(excluding selectionRect: CGRect) {
        NSColor.black.withAlphaComponent(0.34).setFill()

        NSGraphicsContext.saveGraphicsState()
        NSGraphicsContext.current?.shouldAntialias = false
        let backdropPath = NSBezierPath(rect: bounds)
        backdropPath.append(NSBezierPath(rect: selectionRect))
        backdropPath.windingRule = .evenOdd
        backdropPath.fill()
        NSGraphicsContext.restoreGraphicsState()
    }

    private func drawSelectionChrome(_ selectionRect: CGRect) {
        let lineWidth: CGFloat = 2.5
        for cornerPath in selectionChromeCornerPaths(in: selectionRect, lineWidth: lineWidth) {
            let path = NSBezierPath()
            path.lineWidth = lineWidth
            path.lineCapStyle = .round
            path.lineJoinStyle = .round
            guard let firstPoint = cornerPath.points.first else {
                continue
            }

            path.move(to: firstPoint)
            for point in cornerPath.points.dropFirst() {
                path.line(to: point)
            }

            let shadow = NSShadow()
            shadow.shadowColor = NSColor.black.withAlphaComponent(0.28)
            shadow.shadowBlurRadius = 1.5
            shadow.shadowOffset = CGSize(width: 0, height: -0.5)

            NSGraphicsContext.saveGraphicsState()
            shadow.set()
            NSColor.white.withAlphaComponent(0.92).setStroke()
            path.stroke()
            NSGraphicsContext.restoreGraphicsState()
        }
    }
}

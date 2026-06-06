import AppKit

@MainActor
final class RecordingBoundaryOverlayController {
    private var panel: NSPanel?
    private var boundaryView: RecordingBoundaryView?
    private var displayedSelectionRect: CGRect?

    func show(rect: CGRect, countdownText: String? = nil) {
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
        let boundaryView = RecordingBoundaryView(
            frame: CGRect(origin: .zero, size: screenFrame.size),
            selectionRect: localSelectionRect
        )
        boundaryView.countdownText = countdownText
        panel.contentView = boundaryView
        panel.orderFrontRegardless()

        self.panel = panel
        self.boundaryView = boundaryView
        displayedSelectionRect = localSelectionRect
    }

    func updateCountdown(_ text: String?) {
        boundaryView?.countdownText = text
    }

    func close() {
        panel?.orderOut(nil)
        panel?.close()
        panel = nil
        boundaryView = nil
        displayedSelectionRect = nil
    }

    func frameForTesting() -> CGRect? {
        panel?.frame
    }

    func selectionRectForTesting() -> CGRect? {
        displayedSelectionRect
    }

    func countdownTextForTesting() -> String? {
        boundaryView?.countdownText
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
    private let countdownLabel = NSTextField(labelWithString: "")
    var countdownText: String? {
        didSet {
            countdownLabel.stringValue = countdownText ?? ""
            countdownLabel.isHidden = countdownText == nil
        }
    }

    override var isOpaque: Bool {
        false
    }

    init(frame frameRect: NSRect, selectionRect: CGRect) {
        self.selectionRect = selectionRect
        super.init(frame: frameRect)
        wantsLayer = true
        layer?.backgroundColor = NSColor.clear.cgColor
        configureCountdownLabel()
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

    override func layout() {
        super.layout()
        countdownLabel.frame = countdownLabelFrame()
    }

    private func configureCountdownLabel() {
        countdownLabel.isHidden = true
        countdownLabel.alignment = .center
        countdownLabel.font = .monospacedDigitSystemFont(ofSize: 42, weight: .semibold)
        countdownLabel.textColor = .labelColor
        countdownLabel.translatesAutoresizingMaskIntoConstraints = true
        countdownLabel.wantsLayer = true
        countdownLabel.layer?.cornerRadius = 28
        countdownLabel.layer?.cornerCurve = .continuous
        countdownLabel.layer?.backgroundColor = NSColor.controlBackgroundColor.withAlphaComponent(0.72).cgColor
        countdownLabel.layer?.borderWidth = 0.5
        countdownLabel.layer?.borderColor = NSColor.white.withAlphaComponent(0.38).cgColor
        addSubview(countdownLabel)
    }

    private func countdownLabelFrame() -> CGRect {
        let side: CGFloat = 72
        let center = CGPoint(x: selectionRect.midX, y: selectionRect.midY)
        let x = min(max(center.x - side / 2, bounds.minX + 12), bounds.maxX - side - 12)
        let y = min(max(center.y - side / 2, bounds.minY + 12), bounds.maxY - side - 12)
        return CGRect(x: x, y: y, width: side, height: side)
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

import AppKit

@MainActor
final class RecordingBoundaryOverlayController {
    private var panel: NSPanel?
    private var boundaryView: RecordingBoundaryView?
    private var displayedSelectionRect: CGRect?

    func show(rect: CGRect, preparationState: RecordingPreparationState? = nil) {
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
        boundaryView.preparationState = preparationState
        panel.contentView = boundaryView
        panel.orderFrontRegardless()

        self.panel = panel
        self.boundaryView = boundaryView
        displayedSelectionRect = localSelectionRect
    }

    func updatePreparationState(_ state: RecordingPreparationState?) {
        boundaryView?.preparationState = state
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

    func preparationStateForTesting() -> RecordingPreparationState? {
        boundaryView?.preparationState
    }

    func preparationIndicatorFrameForTesting() -> CGRect? {
        boundaryView?.preparationIndicatorFrameForTesting()
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

enum RecordingPreparationState: Equatable {
    case loading
}

private final class RecordingPreparationSpinnerView: NSView {
    private var timer: Timer?
    private var phase: CGFloat = 0

    override var isOpaque: Bool {
        false
    }

    func startAnimating() {
        guard timer == nil else {
            return
        }

        let timer = Timer(timeInterval: 1.0 / 30.0, repeats: true) { [weak self] _ in
            Task { @MainActor [weak self] in
                guard let self else {
                    return
                }

                phase = (phase + 0.075).truncatingRemainder(dividingBy: 1)
                needsDisplay = true
            }
        }
        self.timer = timer
        RunLoop.main.add(timer, forMode: .common)
        needsDisplay = true
    }

    func stopAnimating() {
        timer?.invalidate()
        timer = nil
        phase = 0
        needsDisplay = true
    }

    override func draw(_ dirtyRect: NSRect) {
        super.draw(dirtyRect)

        let center = CGPoint(x: bounds.midX, y: bounds.midY)
        let radius = min(bounds.width, bounds.height) * 0.26
        let lineWidth: CGFloat = 2.3
        let startAngle = 360 * phase
        let endAngle = startAngle + 250
        let path = NSBezierPath()
        path.appendArc(
            withCenter: center,
            radius: radius,
            startAngle: startAngle,
            endAngle: endAngle,
            clockwise: false
        )
        path.lineWidth = lineWidth
        path.lineCapStyle = .round
        NSColor.white.withAlphaComponent(0.9).setStroke()
        path.stroke()
    }
}

private final class RecordingBoundaryView: NSView {
    private let selectionRect: CGRect
    private let preparationIndicator = RecordingPreparationSpinnerView()
    var preparationState: RecordingPreparationState? {
        didSet {
            updatePreparationIndicator()
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
        configurePreparationIndicator()
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
        preparationIndicator.frame = preparationIndicatorFrame()
    }

    private func configurePreparationIndicator() {
        preparationIndicator.isHidden = true
        preparationIndicator.translatesAutoresizingMaskIntoConstraints = true
        preparationIndicator.wantsLayer = true
        preparationIndicator.layer?.cornerRadius = 15
        preparationIndicator.layer?.cornerCurve = .continuous
        preparationIndicator.layer?.backgroundColor = NSColor.black.withAlphaComponent(0.42).cgColor
        preparationIndicator.layer?.borderWidth = 0.5
        preparationIndicator.layer?.borderColor = NSColor.white.withAlphaComponent(0.22).cgColor
        addSubview(preparationIndicator)
    }

    private func preparationIndicatorFrame() -> CGRect {
        let side: CGFloat = 30
        let center = CGPoint(x: selectionRect.midX, y: selectionRect.midY)
        let x = min(max(center.x - side / 2, bounds.minX + 12), bounds.maxX - side - 12)
        let y = min(max(center.y - side / 2, bounds.minY + 12), bounds.maxY - side - 12)
        return CGRect(x: x, y: y, width: side, height: side)
    }

    private func updatePreparationIndicator() {
        let isLoading = preparationState == .loading
        preparationIndicator.isHidden = !isLoading
        if isLoading {
            preparationIndicator.startAnimating()
        } else {
            preparationIndicator.stopAnimating()
        }
    }

    func preparationIndicatorFrameForTesting() -> CGRect {
        preparationIndicator.frame
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

import AppKit

@MainActor
final class RecordingLiveOverlayController {
    private var panel: NSPanel?
    private var overlayView: RecordingLiveOverlayView?
    private var refreshTimer: Timer?

    func show(
        screenFrame: CGRect,
        selectionRect: CGRect,
        pixelSize: CGSize,
        eventStore: RecordingOverlayEventStore
    ) {
        close()

        let normalizedScreenFrame = screenFrame.integral
        let localSelectionRect = selectionRect.integral.offsetBy(
            dx: -normalizedScreenFrame.minX,
            dy: -normalizedScreenFrame.minY
        )
        let panel = NSPanel(
            contentRect: normalizedScreenFrame,
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

        let overlayView = RecordingLiveOverlayView(
            frame: CGRect(origin: .zero, size: normalizedScreenFrame.size),
            selectionRect: localSelectionRect,
            pixelSize: pixelSize,
            eventStore: eventStore
        )
        panel.contentView = overlayView
        panel.orderFrontRegardless()

        self.panel = panel
        self.overlayView = overlayView
        startRefreshTimer()
    }

    func close() {
        refreshTimer?.invalidate()
        refreshTimer = nil
        panel?.orderOut(nil)
        panel?.close()
        panel = nil
        overlayView = nil
    }

    var windowNumber: Int? {
        panel?.windowNumber
    }

    func isVisibleForTesting() -> Bool {
        panel?.isVisible == true
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

    private func startRefreshTimer() {
        let timer = Timer(timeInterval: 1.0 / 60.0, repeats: true) { [weak self] _ in
            Task { @MainActor [weak self] in
                self?.overlayView?.needsDisplay = true
            }
        }
        refreshTimer = timer
        RunLoop.main.add(timer, forMode: .common)
    }
}

enum RecordingOverlayCaptureExclusion {
    static func shouldExclude(windowID: CGWindowID, liveOverlayWindowNumber: Int?) -> Bool {
        guard let liveOverlayWindowNumber else {
            return false
        }

        return windowID == CGWindowID(liveOverlayWindowNumber)
    }
}

private final class RecordingLiveOverlayView: NSView {
    private let selectionRect: CGRect
    private let pixelSize: CGSize
    private let eventStore: RecordingOverlayEventStore

    override var isOpaque: Bool {
        false
    }

    init(
        frame frameRect: NSRect,
        selectionRect: CGRect,
        pixelSize: CGSize,
        eventStore: RecordingOverlayEventStore
    ) {
        self.selectionRect = selectionRect
        self.pixelSize = pixelSize
        self.eventStore = eventStore
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

        let snapshot = eventStore.snapshot(at: ProcessInfo.processInfo.systemUptime)
        guard !snapshot.isEmpty else {
            return
        }

        for click in snapshot.clicks {
            drawClick(click)
        }
        if let keyHint = snapshot.keyHint {
            drawKeyHint(keyHint)
        }
    }

    private func drawClick(_ click: RecordingOverlaySnapshot.Click) {
        let progress = min(1, max(0, click.age / 0.45))
        let radius = 12 + progress * 20
        let alpha = 1 - progress
        let point = viewPoint(for: click.point)
        let rect = CGRect(
            x: point.x - radius,
            y: point.y - radius,
            width: radius * 2,
            height: radius * 2
        )

        NSColor.systemRed.withAlphaComponent(0.18 * alpha).setFill()
        NSBezierPath(ovalIn: rect).fill()

        let outerPath = NSBezierPath(ovalIn: rect)
        outerPath.lineWidth = 3
        NSColor.white.withAlphaComponent(0.92 * alpha).setStroke()
        outerPath.stroke()

        let innerPath = NSBezierPath(ovalIn: rect.insetBy(dx: 4, dy: 4))
        innerPath.lineWidth = 1.5
        NSColor.systemRed.withAlphaComponent(0.78 * alpha).setStroke()
        innerPath.stroke()
    }

    private func drawKeyHint(_ keyHint: RecordingOverlaySnapshot.KeyHint) {
        let progress = min(1, max(0, keyHint.age / 0.9))
        let alpha = keyHint.isTransient && progress >= 0.78 ? max(0, 1 - ((progress - 0.78) / 0.22)) : 1
        let minDimension = min(selectionRect.width, selectionRect.height)
        let fontSize = min(46, max(20, minDimension * 0.16))
        let attributes: [NSAttributedString.Key: Any] = [
            .font: NSFont.monospacedSystemFont(ofSize: fontSize, weight: .semibold),
            .foregroundColor: NSColor.white.withAlphaComponent(0.95 * alpha),
        ]
        let textSize = (keyHint.label as NSString).size(withAttributes: attributes)
        let horizontalPadding = max(12, fontSize * 0.48)
        let verticalPadding = max(6, fontSize * 0.28)
        let maxPillWidth = max(48, selectionRect.width - 24)
        let pillSize = CGSize(
            width: min(maxPillWidth, max(fontSize * 2.2, textSize.width + horizontalPadding * 2)),
            height: textSize.height + verticalPadding * 2
        )
        let rect = CGRect(
            x: floor(selectionRect.midX - pillSize.width / 2),
            y: max(selectionRect.minY + max(12, fontSize * 0.6), bounds.minY + 10),
            width: pillSize.width,
            height: pillSize.height
        )
        let radius = min(22, pillSize.height / 2)
        let path = NSBezierPath(roundedRect: rect, xRadius: radius, yRadius: radius)
        NSColor.black.withAlphaComponent(0.58 * alpha).setFill()
        path.fill()

        (keyHint.label as NSString).draw(
            in: CGRect(
                x: rect.midX - textSize.width / 2,
                y: rect.midY - textSize.height / 2,
                width: textSize.width,
                height: textSize.height
            ),
            withAttributes: attributes
        )
    }

    private func viewPoint(for pixelPoint: CGPoint) -> CGPoint {
        CGPoint(
            x: selectionRect.minX + (pixelPoint.x / max(1, pixelSize.width)) * selectionRect.width,
            y: selectionRect.maxY - (pixelPoint.y / max(1, pixelSize.height)) * selectionRect.height
        )
    }
}

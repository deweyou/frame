import AppKit
import FrameCore

@MainActor
final class SelectionOverlayWindow {
    private let window: NSWindow
    private let overlayView: SelectionOverlayView

    init(screen: NSScreen, onComplete: @escaping (CGRect?) -> Void) {
        overlayView = SelectionOverlayView(screen: screen, onComplete: onComplete)

        window = NSWindow(
            contentRect: screen.frame,
            styleMask: [.borderless],
            backing: .buffered,
            defer: false,
            screen: screen
        )

        window.backgroundColor = .clear
        window.collectionBehavior = [.canJoinAllSpaces, .fullScreenAuxiliary, .stationary]
        window.contentView = overlayView
        window.hasShadow = false
        window.ignoresMouseEvents = false
        window.isMovable = false
        window.isOpaque = false
        window.level = .screenSaver
        window.isReleasedWhenClosed = false
        window.acceptsMouseMovedEvents = true
    }

    func orderFrontRegardless() {
        window.orderFrontRegardless()
    }

    func makeKey() {
        window.makeKey()
        window.makeFirstResponder(overlayView)
    }

    func orderOut(_ sender: Any?) {
        window.orderOut(sender)
    }

    func close() {
        window.close()
    }
}

@MainActor
private final class SelectionOverlayView: NSView {
    private let screenFrame: CGRect
    private let onComplete: (CGRect?) -> Void

    private var dragStartPoint: CGPoint?
    private var dragCurrentPoint: CGPoint?
    private var hasCompleted = false

    init(screen: NSScreen, onComplete: @escaping (CGRect?) -> Void) {
        self.screenFrame = screen.frame
        self.onComplete = onComplete

        super.init(frame: CGRect(origin: .zero, size: screen.frame.size))

        wantsLayer = true
    }

    @available(*, unavailable)
    required init?(coder: NSCoder) {
        nil
    }

    override var acceptsFirstResponder: Bool {
        true
    }

    override func viewDidMoveToWindow() {
        super.viewDidMoveToWindow()
        window?.makeFirstResponder(self)
    }

    override func resetCursorRects() {
        addCursorRect(bounds, cursor: .crosshair)
    }

    override func mouseDown(with event: NSEvent) {
        let point = clampedPoint(event.locationInWindow)
        dragStartPoint = point
        dragCurrentPoint = point
        needsDisplay = true
    }

    override func mouseDragged(with event: NSEvent) {
        guard dragStartPoint != nil else {
            return
        }

        dragCurrentPoint = clampedPoint(event.locationInWindow)
        needsDisplay = true
    }

    override func mouseUp(with event: NSEvent) {
        guard let dragStartPoint else {
            completeSelection(with: nil)
            return
        }

        let dragEndPoint = clampedPoint(event.locationInWindow)
        let localRect = SelectionGeometry.normalizedRect(
            from: dragStartPoint,
            to: dragEndPoint
        )

        guard SelectionGeometry.isValidSelection(localRect) else {
            completeSelection(with: nil)
            return
        }

        completeSelection(with: globalRect(fromLocalRect: localRect))
    }

    override func keyDown(with event: NSEvent) {
        if event.keyCode == escapeKeyCode {
            completeSelection(with: nil)
            return
        }

        super.keyDown(with: event)
    }

    override func draw(_ dirtyRect: NSRect) {
        super.draw(dirtyRect)

        NSColor.black.withAlphaComponent(0.32).setFill()
        bounds.fill()

        guard let selectionRect else {
            return
        }

        NSGraphicsContext.saveGraphicsState()
        NSColor.clear.setFill()
        selectionRect.fill(using: .clear)
        NSGraphicsContext.restoreGraphicsState()

        NSColor.systemGreen.withAlphaComponent(0.32).setFill()
        selectionRect.fill()

        NSColor.white.withAlphaComponent(0.92).setStroke()
        let borderPath = NSBezierPath(rect: selectionRect)
        borderPath.lineWidth = 1
        borderPath.stroke()
    }

    private var selectionRect: CGRect? {
        guard let dragStartPoint,
              let dragCurrentPoint else {
            return nil
        }

        return SelectionGeometry.normalizedRect(
            from: dragStartPoint,
            to: dragCurrentPoint
        )
    }

    private func completeSelection(with selectedRect: CGRect?) {
        guard !hasCompleted else {
            return
        }

        hasCompleted = true
        onComplete(selectedRect)
    }

    private func clampedPoint(_ point: CGPoint) -> CGPoint {
        CGPoint(
            x: min(max(point.x, bounds.minX), bounds.maxX),
            y: min(max(point.y, bounds.minY), bounds.maxY)
        )
    }

    private func globalRect(fromLocalRect localRect: CGRect) -> CGRect {
        CGRect(
            x: screenFrame.minX + localRect.minX,
            y: screenFrame.minY + localRect.minY,
            width: localRect.width,
            height: localRect.height
        )
    }
}

private let escapeKeyCode: UInt16 = 53

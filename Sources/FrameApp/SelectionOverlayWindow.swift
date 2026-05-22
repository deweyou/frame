import AppKit
import FrameCore

@MainActor
final class SelectionOverlayWindow {
    private let window: NSWindow
    private let overlayView: SelectionOverlayView

    init(
        screen: NSScreen,
        initialGlobalRect: CGRect?,
        onInteraction: @escaping () -> Void,
        onComplete: @escaping (CGRect?) -> Void
    ) {
        overlayView = SelectionOverlayView(
            screen: screen,
            initialGlobalRect: initialGlobalRect,
            onInteraction: onInteraction,
            onComplete: onComplete
        )

        window = NSWindow(
            contentRect: screen.frame,
            styleMask: [.borderless],
            backing: .buffered,
            defer: false,
            screen: screen
        )

        window.backgroundColor = .clear
        window.setFrame(screen.frame, display: false)
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

    var hasSelection: Bool {
        overlayView.hasSelection
    }

    var selectedGlobalRect: CGRect? {
        overlayView.selectedGlobalRect
    }

    func clearSelection() {
        overlayView.clearSelection()
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
    private let hudSize = CGSize(width: 174, height: 48)
    private let screenFrame: CGRect
    private let onInteraction: () -> Void
    private let onComplete: (CGRect?) -> Void
    private let hudStackView = NSStackView()
    private let metricsView = NSVisualEffectView()
    private let widthValueLabel = NSTextField(labelWithString: "0")
    private let heightValueLabel = NSTextField(labelWithString: "0")

    private var selectionRect: CGRect?
    private var dragOperation: SelectionDragOperation?
    private var hasCompleted = false

    init(
        screen: NSScreen,
        initialGlobalRect: CGRect?,
        onInteraction: @escaping () -> Void,
        onComplete: @escaping (CGRect?) -> Void
    ) {
        self.screenFrame = screen.frame
        self.onInteraction = onInteraction
        self.onComplete = onComplete

        super.init(frame: CGRect(origin: .zero, size: screen.frame.size))

        wantsLayer = true
        selectionRect = localRect(fromGlobalRect: initialGlobalRect)
        configureHUD()
        updateMetrics()
    }

    @available(*, unavailable)
    required init?(coder: NSCoder) {
        nil
    }

    override var acceptsFirstResponder: Bool {
        true
    }

    var hasSelection: Bool {
        selectionRect != nil
    }

    var selectedGlobalRect: CGRect? {
        guard let selectionRect else {
            return nil
        }

        return globalRect(fromLocalRect: selectionRect)
    }

    func clearSelection() {
        selectionRect = nil
        dragOperation = nil
        updateMetrics()
        needsDisplay = true
    }

    override func viewDidMoveToWindow() {
        super.viewDidMoveToWindow()
        window?.makeFirstResponder(self)
    }

    override func layout() {
        super.layout()
        positionHUD()
    }

    override func resetCursorRects() {
        addCursorRect(bounds, cursor: .crosshair)
    }

    override func mouseDown(with event: NSEvent) {
        onInteraction()
        let point = clampedPoint(event.locationInWindow)
        dragOperation = dragOperation(startingAt: point)
        updateMetrics()
        needsDisplay = true
    }

    override func mouseDragged(with event: NSEvent) {
        guard let dragOperation else {
            return
        }

        updateSelection(for: dragOperation, currentPoint: clampedPoint(event.locationInWindow))
        updateMetrics()
        needsDisplay = true
    }

    override func mouseUp(with event: NSEvent) {
        dragOperation = nil
    }

    override func keyDown(with event: NSEvent) {
        if event.keyCode == escapeKeyCode {
            completeSelection(with: nil)
            return
        }

        if event.keyCode == returnKeyCode || event.keyCode == keypadEnterKeyCode {
            confirmSelection()
            return
        }

        super.keyDown(with: event)
    }

    override func draw(_ dirtyRect: NSRect) {
        super.draw(dirtyRect)

        guard let selectionRect else {
            NSColor.black.withAlphaComponent(0.26).setFill()
            bounds.fill()
            return
        }

        drawDimmedBackdrop(excluding: selectionRect)
        drawSelectionChrome(selectionRect)
    }

    private func configureHUD() {
        hudStackView.orientation = .horizontal
        hudStackView.alignment = .centerY
        hudStackView.distribution = .gravityAreas
        hudStackView.spacing = 0
        hudStackView.translatesAutoresizingMaskIntoConstraints = true

        configureGlass(metricsView, cornerRadius: 16)
        metricsView.isHidden = true
        metricsView.addSubview(makeMetricsStack())
        let metricsStack = metricsView.subviews.compactMap { $0 as? NSStackView }.first
        metricsStack?.translatesAutoresizingMaskIntoConstraints = false

        hudStackView.addArrangedSubview(metricsView)
        addSubview(hudStackView)

        NSLayoutConstraint.activate([
            metricsView.widthAnchor.constraint(equalToConstant: hudSize.width),
            metricsView.heightAnchor.constraint(equalToConstant: hudSize.height),
        ])

        if let metricsStack {
            NSLayoutConstraint.activate([
                metricsStack.leadingAnchor.constraint(equalTo: metricsView.leadingAnchor, constant: 10),
                metricsStack.trailingAnchor.constraint(equalTo: metricsView.trailingAnchor, constant: -10),
                metricsStack.centerYAnchor.constraint(equalTo: metricsView.centerYAnchor),
            ])
        }

        positionHUD()
    }

    private func configureGlass(_ view: NSVisualEffectView, cornerRadius: CGFloat) {
        view.material = .hudWindow
        view.blendingMode = .behindWindow
        view.state = .active
        view.wantsLayer = true
        view.layer?.cornerRadius = cornerRadius
        view.layer?.cornerCurve = .continuous
        view.layer?.masksToBounds = true
        view.layer?.borderWidth = 0.5
        view.layer?.borderColor = NSColor.white.withAlphaComponent(0.24).cgColor
        view.layer?.backgroundColor = NSColor.black.withAlphaComponent(0.12).cgColor
    }

    private func makeMetricsStack() -> NSStackView {
        let stackView = NSStackView()
        stackView.orientation = .horizontal
        stackView.alignment = .centerY
        stackView.spacing = 6

        stackView.addArrangedSubview(makeMetricValueLabel(widthValueLabel))
        stackView.addArrangedSubview(makeMetricSeparator("x"))
        stackView.addArrangedSubview(makeMetricValueLabel(heightValueLabel))
        stackView.addArrangedSubview(makeConfirmButton())

        return stackView
    }

    private func makeConfirmButton() -> NSButton {
        let button = NSButton(title: "", target: self, action: #selector(confirmButtonClicked))
        button.bezelStyle = .texturedRounded
        button.controlSize = .regular
        button.image = NSImage(systemSymbolName: "checkmark", accessibilityDescription: "确认截图")
        button.symbolConfiguration = NSImage.SymbolConfiguration(pointSize: 13, weight: .semibold)
        button.contentTintColor = .white
        button.translatesAutoresizingMaskIntoConstraints = false

        NSLayoutConstraint.activate([
            button.widthAnchor.constraint(equalToConstant: 28),
            button.heightAnchor.constraint(equalToConstant: 26),
        ])

        return button
    }

    private func makeMetricValueLabel(_ label: NSTextField) -> NSView {
        label.font = .monospacedDigitSystemFont(ofSize: 13, weight: .semibold)
        label.textColor = .white.withAlphaComponent(0.94)
        label.alignment = .center
        label.wantsLayer = true
        label.layer?.cornerRadius = 7
        label.layer?.cornerCurve = .continuous
        label.layer?.backgroundColor = NSColor.black.withAlphaComponent(0.22).cgColor
        label.translatesAutoresizingMaskIntoConstraints = false

        NSLayoutConstraint.activate([
            label.widthAnchor.constraint(equalToConstant: 38),
            label.heightAnchor.constraint(equalToConstant: 28),
        ])

        return label
    }

    private func makeMetricSeparator(_ value: String) -> NSTextField {
        let label = NSTextField(labelWithString: value)
        label.font = .systemFont(ofSize: 11, weight: .medium)
        label.textColor = .white.withAlphaComponent(0.55)
        return label
    }

    private func drawDimmedBackdrop(excluding selectionRect: CGRect) {
        NSColor.black.withAlphaComponent(0.28).setFill()

        let topRect = CGRect(
            x: bounds.minX,
            y: selectionRect.maxY,
            width: bounds.width,
            height: bounds.maxY - selectionRect.maxY
        )
        let bottomRect = CGRect(
            x: bounds.minX,
            y: bounds.minY,
            width: bounds.width,
            height: selectionRect.minY - bounds.minY
        )
        let leftRect = CGRect(
            x: bounds.minX,
            y: selectionRect.minY,
            width: selectionRect.minX - bounds.minX,
            height: selectionRect.height
        )
        let rightRect = CGRect(
            x: selectionRect.maxX,
            y: selectionRect.minY,
            width: bounds.maxX - selectionRect.maxX,
            height: selectionRect.height
        )

        [topRect, bottomRect, leftRect, rightRect].forEach { rect in
            guard !rect.isEmpty, rect.width > 0, rect.height > 0 else {
                return
            }

            rect.fill()
        }
    }

    private func drawSelectionChrome(_ selectionRect: CGRect) {
        let roundedSelection = NSBezierPath(roundedRect: selectionRect, xRadius: 7, yRadius: 7)

        NSColor.systemCyan.withAlphaComponent(0.20).setFill()
        roundedSelection.fill()

        NSColor.white.withAlphaComponent(0.42).setStroke()
        roundedSelection.lineWidth = 1
        roundedSelection.stroke()

        drawCornerHandles(in: selectionRect)
    }

    private func drawCornerHandles(in selectionRect: CGRect) {
        guard selectionRect.width >= 4, selectionRect.height >= 4 else {
            return
        }

        let cornerLength = min(16, selectionRect.width / 3, selectionRect.height / 3)
        let inset: CGFloat = 1.5
        let rect = selectionRect.insetBy(dx: inset, dy: inset)
        guard rect.width > 0, rect.height > 0 else {
            return
        }

        let path = NSBezierPath()

        path.move(to: CGPoint(x: rect.minX, y: rect.minY + cornerLength))
        path.line(to: CGPoint(x: rect.minX, y: rect.minY))
        path.line(to: CGPoint(x: rect.minX + cornerLength, y: rect.minY))

        path.move(to: CGPoint(x: rect.maxX - cornerLength, y: rect.minY))
        path.line(to: CGPoint(x: rect.maxX, y: rect.minY))
        path.line(to: CGPoint(x: rect.maxX, y: rect.minY + cornerLength))

        path.move(to: CGPoint(x: rect.minX, y: rect.maxY - cornerLength))
        path.line(to: CGPoint(x: rect.minX, y: rect.maxY))
        path.line(to: CGPoint(x: rect.minX + cornerLength, y: rect.maxY))

        path.move(to: CGPoint(x: rect.maxX - cornerLength, y: rect.maxY))
        path.line(to: CGPoint(x: rect.maxX, y: rect.maxY))
        path.line(to: CGPoint(x: rect.maxX, y: rect.maxY - cornerLength))

        NSColor.white.withAlphaComponent(0.96).setStroke()
        path.lineWidth = 3
        path.lineCapStyle = .round
        path.lineJoinStyle = .round
        path.stroke()
    }

    private func completeSelection(with selectedRect: CGRect?) {
        guard !hasCompleted else {
            return
        }

        hasCompleted = true
        onComplete(selectedRect)
    }

    @objc private func confirmButtonClicked() {
        confirmSelection()
    }

    private func confirmSelection() {
        guard let selectionRect,
              SelectionGeometry.isValidSelection(selectionRect) else {
            NSSound.beep()
            return
        }

        completeSelection(with: globalRect(fromLocalRect: selectionRect))
    }

    private func updateMetrics() {
        guard let selectionRect else {
            hudStackView.isHidden = true
            metricsView.isHidden = true
            widthValueLabel.stringValue = "0"
            heightValueLabel.stringValue = "0"
            positionHUD()
            return
        }

        hudStackView.isHidden = false
        metricsView.isHidden = false
        widthValueLabel.stringValue = String(Int(selectionRect.width.rounded()))
        heightValueLabel.stringValue = String(Int(selectionRect.height.rounded()))
        positionHUD()
    }

    private func positionHUD() {
        let visibleSize = CGSize(width: min(hudSize.width, bounds.width - 24), height: hudSize.height)
        let fallbackOrigin = CGPoint(
            x: max(bounds.minX + 12, bounds.midX - visibleSize.width / 2),
            y: bounds.minY + 34
        )

        guard let selectionRect else {
            hudStackView.frame = CGRect(origin: fallbackOrigin, size: visibleSize)
            return
        }

        let spacing: CGFloat = 14
        let horizontalCenter = selectionRect.midX - visibleSize.width / 2
        var origin = CGPoint(
            x: horizontalCenter,
            y: selectionRect.minY - visibleSize.height - spacing
        )

        if origin.y < bounds.minY + 18 {
            origin.y = selectionRect.maxY + spacing
        }

        origin.x = min(max(origin.x, bounds.minX + 12), bounds.maxX - visibleSize.width - 12)
        origin.y = min(max(origin.y, bounds.minY + 18), bounds.maxY - visibleSize.height - 18)

        hudStackView.frame = CGRect(origin: origin, size: visibleSize)
    }

    private func clampedPoint(_ point: CGPoint) -> CGPoint {
        CGPoint(
            x: min(max(point.x, bounds.minX), bounds.maxX),
            y: min(max(point.y, bounds.minY), bounds.maxY)
        )
    }

    private func dragOperation(startingAt point: CGPoint) -> SelectionDragOperation {
        guard let selectionRect else {
            return .create(startPoint: point)
        }

        if let handle = SelectionHandle.hitTest(point: point, in: selectionRect) {
            return .resize(handle: handle, startRect: selectionRect, startPoint: point)
        }

        if selectionRect.isNearlyEqual(to: bounds) {
            return .create(startPoint: point)
        }

        if selectionRect.contains(point) {
            return .move(startRect: selectionRect, startPoint: point)
        }

        return .create(startPoint: point)
    }

    private func updateSelection(for operation: SelectionDragOperation, currentPoint: CGPoint) {
        switch operation {
        case let .create(startPoint):
            selectionRect = SelectionGeometry.normalizedRect(from: startPoint, to: currentPoint)
        case let .move(startRect, startPoint):
            let delta = CGPoint(x: currentPoint.x - startPoint.x, y: currentPoint.y - startPoint.y)
            selectionRect = clampedRect(
                CGRect(
                    x: startRect.minX + delta.x,
                    y: startRect.minY + delta.y,
                    width: startRect.width,
                    height: startRect.height
                )
            )
        case let .resize(handle, startRect, startPoint):
            let delta = CGPoint(x: currentPoint.x - startPoint.x, y: currentPoint.y - startPoint.y)
            selectionRect = clampedRect(handle.resizedRect(from: startRect, delta: delta))
        }
    }

    private func clampedRect(_ rect: CGRect) -> CGRect {
        let width = min(max(rect.width, 1), bounds.width)
        let height = min(max(rect.height, 1), bounds.height)
        let origin = CGPoint(
            x: min(max(rect.minX, bounds.minX), bounds.maxX - width),
            y: min(max(rect.minY, bounds.minY), bounds.maxY - height)
        )

        return CGRect(origin: origin, size: CGSize(width: width, height: height))
    }

    private func globalRect(fromLocalRect localRect: CGRect) -> CGRect {
        CGRect(
            x: screenFrame.minX + localRect.minX,
            y: screenFrame.minY + localRect.minY,
            width: localRect.width,
            height: localRect.height
        )
    }

    private func localRect(fromGlobalRect globalRect: CGRect?) -> CGRect? {
        guard let globalRect,
              screenFrame.intersects(globalRect) else {
            return nil
        }

        let clippedRect = globalRect.intersection(screenFrame)
        return clampedRect(
            CGRect(
                x: clippedRect.minX - screenFrame.minX,
                y: clippedRect.minY - screenFrame.minY,
                width: clippedRect.width,
                height: clippedRect.height
            )
        )
    }
}

private let escapeKeyCode: UInt16 = 53
private let returnKeyCode: UInt16 = 36
private let keypadEnterKeyCode: UInt16 = 76

private enum SelectionDragOperation {
    case create(startPoint: CGPoint)
    case move(startRect: CGRect, startPoint: CGPoint)
    case resize(handle: SelectionHandle, startRect: CGRect, startPoint: CGPoint)
}

private enum SelectionHandle {
    case topLeft
    case topRight
    case bottomLeft
    case bottomRight

    static func hitTest(point: CGPoint, in rect: CGRect) -> SelectionHandle? {
        let hitSize: CGFloat = 18
        let handles: [(SelectionHandle, CGRect)] = [
            (.bottomLeft, CGRect(x: rect.minX - hitSize / 2, y: rect.minY - hitSize / 2, width: hitSize, height: hitSize)),
            (.bottomRight, CGRect(x: rect.maxX - hitSize / 2, y: rect.minY - hitSize / 2, width: hitSize, height: hitSize)),
            (.topLeft, CGRect(x: rect.minX - hitSize / 2, y: rect.maxY - hitSize / 2, width: hitSize, height: hitSize)),
            (.topRight, CGRect(x: rect.maxX - hitSize / 2, y: rect.maxY - hitSize / 2, width: hitSize, height: hitSize)),
        ]

        return handles.first { _, hitRect in
            hitRect.contains(point)
        }?.0
    }

    func resizedRect(from rect: CGRect, delta: CGPoint) -> CGRect {
        switch self {
        case .topLeft:
            return SelectionGeometry.normalizedRect(
                from: CGPoint(x: rect.maxX, y: rect.minY),
                to: CGPoint(x: rect.minX + delta.x, y: rect.maxY + delta.y)
            )
        case .topRight:
            return SelectionGeometry.normalizedRect(
                from: CGPoint(x: rect.minX, y: rect.minY),
                to: CGPoint(x: rect.maxX + delta.x, y: rect.maxY + delta.y)
            )
        case .bottomLeft:
            return SelectionGeometry.normalizedRect(
                from: CGPoint(x: rect.maxX, y: rect.maxY),
                to: CGPoint(x: rect.minX + delta.x, y: rect.minY + delta.y)
            )
        case .bottomRight:
            return SelectionGeometry.normalizedRect(
                from: CGPoint(x: rect.minX, y: rect.maxY),
                to: CGPoint(x: rect.maxX + delta.x, y: rect.minY + delta.y)
            )
        }
    }
}

private extension CGRect {
    func isNearlyEqual(to other: CGRect) -> Bool {
        abs(minX - other.minX) < 1
            && abs(minY - other.minY) < 1
            && abs(width - other.width) < 1
            && abs(height - other.height) < 1
    }
}

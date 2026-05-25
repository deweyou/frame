import AppKit
import CoreGraphics
import FrameCore

@MainActor
final class SelectionOverlayWindow {
    private let window: NSWindow
    private let overlayView: SelectionOverlayView

    init(
        screen: NSScreen,
        initialGlobalRect: CGRect?,
        showsCenteredHUDWhenEmpty: Bool,
        onInteraction: @escaping () -> Void,
        onWindowSelectionRequested: @escaping (CGPoint) -> WindowCandidate?,
        onComplete: @escaping (SelectionCapture?) -> Void
    ) {
        overlayView = SelectionOverlayView(
            screen: screen,
            initialGlobalRect: initialGlobalRect,
            showsCenteredHUDWhenEmpty: showsCenteredHUDWhenEmpty,
            onInteraction: onInteraction,
            onWindowSelectionRequested: onWindowSelectionRequested,
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

    var activeSelection: SelectionCapture? {
        overlayView.activeSelection
    }

    func clearSelection() {
        overlayView.clearSelection()
    }

    func setShowsCenteredHUDWhenEmpty(_ showsCenteredHUDWhenEmpty: Bool) {
        overlayView.setShowsCenteredHUDWhenEmpty(showsCenteredHUDWhenEmpty)
    }

    func contains(globalPoint: CGPoint) -> Bool {
        window.frame.contains(globalPoint)
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
    private let hudSize = CGSize(width: 158, height: 42)
    private let screenFrame: CGRect
    private let onInteraction: () -> Void
    private let onWindowSelectionRequested: (CGPoint) -> WindowCandidate?
    private let onComplete: (SelectionCapture?) -> Void
    private let hudStackView = NSStackView()
    private let modeView = NSVisualEffectView()
    private let sizeView = NSVisualEffectView()
    private let sizeLabel = NSTextField(labelWithString: "0 x 0")
    private var hudTheme: HUDTheme = .lightContent

    private var selectionRect: CGRect?
    private var windowCandidate: WindowCandidate?
    private var dragOperation: SelectionDragOperation?
    private var hasCompleted = false
    private var showsCenteredHUDWhenEmpty: Bool

    init(
        screen: NSScreen,
        initialGlobalRect: CGRect?,
        showsCenteredHUDWhenEmpty: Bool,
        onInteraction: @escaping () -> Void,
        onWindowSelectionRequested: @escaping (CGPoint) -> WindowCandidate?,
        onComplete: @escaping (SelectionCapture?) -> Void
    ) {
        self.screenFrame = screen.frame
        self.showsCenteredHUDWhenEmpty = showsCenteredHUDWhenEmpty
        self.onInteraction = onInteraction
        self.onWindowSelectionRequested = onWindowSelectionRequested
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

    var activeSelection: SelectionCapture? {
        if let windowCandidate {
            return SelectionCapture(rect: windowCandidate.bounds, kind: .window)
        }

        guard let selectedGlobalRect else {
            return nil
        }

        return SelectionCapture(rect: selectedGlobalRect, kind: .region)
    }

    func clearSelection() {
        selectionRect = nil
        windowCandidate = nil
        dragOperation = nil
        updateMetrics()
        needsDisplay = true
    }

    func setShowsCenteredHUDWhenEmpty(_ showsCenteredHUDWhenEmpty: Bool) {
        self.showsCenteredHUDWhenEmpty = showsCenteredHUDWhenEmpty
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
        updateVisibleHUDTheme()
    }

    override func resetCursorRects() {
        addCursorRect(bounds, cursor: .crosshair)
    }

    override func mouseDown(with event: NSEvent) {
        let point = clampedPoint(event.locationInWindow)

        if event.clickCount == 2 {
            selectWindowCandidate(at: point)
            return
        }

        onInteraction()
        dragOperation = dragOperation(startingAt: point)
        updateMetrics()
        needsDisplay = true
    }

    override func mouseDragged(with event: NSEvent) {
        guard let dragOperation else {
            return
        }

        windowCandidate = nil
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

        guard let displayedLocalRect else {
            NSColor.black.withAlphaComponent(0.38).setFill()
            bounds.fill()
            return
        }

        drawDimmedBackdrop(excluding: displayedLocalRect)
        drawSelectionChrome(displayedLocalRect)
    }

    private func configureHUD() {
        hudStackView.orientation = .horizontal
        hudStackView.alignment = .centerY
        hudStackView.distribution = .fill
        hudStackView.spacing = 7
        hudStackView.translatesAutoresizingMaskIntoConstraints = true

        configureGlass(modeView, cornerRadius: 21)
        modeView.isHidden = true
        modeView.addSubview(makeRegionModeButton())

        configureGlass(sizeView, cornerRadius: 21)
        sizeView.isHidden = true
        sizeView.addSubview(sizeLabel)
        configureSizeLabel()

        hudStackView.addArrangedSubview(modeView)
        hudStackView.addArrangedSubview(sizeView)
        addSubview(hudStackView)

        guard let modeButton = modeView.subviews.first else {
            return
        }

        NSLayoutConstraint.activate([
            modeView.widthAnchor.constraint(equalToConstant: 42),
            modeView.heightAnchor.constraint(equalToConstant: hudSize.height),
            sizeView.widthAnchor.constraint(equalToConstant: 109),
            sizeView.heightAnchor.constraint(equalToConstant: hudSize.height),
        ])

        modeButton.translatesAutoresizingMaskIntoConstraints = false
        sizeLabel.translatesAutoresizingMaskIntoConstraints = false
        NSLayoutConstraint.activate([
            modeButton.centerXAnchor.constraint(equalTo: modeView.centerXAnchor),
            modeButton.centerYAnchor.constraint(equalTo: modeView.centerYAnchor),
            modeButton.widthAnchor.constraint(equalToConstant: 42),
            modeButton.heightAnchor.constraint(equalToConstant: 42),
            sizeLabel.leadingAnchor.constraint(equalTo: sizeView.leadingAnchor, constant: 12),
            sizeLabel.trailingAnchor.constraint(equalTo: sizeView.trailingAnchor, constant: -12),
            sizeLabel.centerYAnchor.constraint(equalTo: sizeView.centerYAnchor),
        ])

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
        view.layer?.borderColor = NSColor.white.withAlphaComponent(0.38).cgColor
        view.layer?.backgroundColor = NSColor.white.withAlphaComponent(0.04).cgColor
    }

    private func makeRegionModeButton() -> NSButton {
        let button = HUDIconButton(
            symbolName: "rectangle.dashed",
            accessibilityDescription: "区域截图"
        )
        button.target = self
        button.action = #selector(regionModeButtonClicked)
        button.toolTip = "区域截图"
        button.contentTintColor = hudTheme.foregroundColor
        return button
    }

    private func configureSizeLabel() {
        sizeLabel.font = .monospacedDigitSystemFont(ofSize: 12, weight: .medium)
        sizeLabel.textColor = hudTheme.foregroundColor
        sizeLabel.alignment = .center
        sizeLabel.lineBreakMode = .byClipping
    }

    private func applyHUDTheme(_ theme: HUDTheme) {
        hudTheme = theme
        [modeView, sizeView].forEach { view in
            view.layer?.borderColor = theme.borderColor.cgColor
            view.layer?.backgroundColor = theme.backgroundColor.cgColor
        }
        modeButton?.contentTintColor = theme.foregroundColor
        modeButton?.hoverColor = theme.hoverColor
        sizeLabel.textColor = theme.foregroundColor
    }

    private func drawDimmedBackdrop(excluding selectionRect: CGRect) {
        NSColor.black.withAlphaComponent(0.42).setFill()

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

        NSColor.white.withAlphaComponent(0.42).setStroke()
        roundedSelection.lineWidth = 1
        roundedSelection.stroke()

        drawCornerHandles(in: selectionRect)
    }

    private func drawCornerHandles(in selectionRect: CGRect) {
        guard selectionRect.width >= 4, selectionRect.height >= 4 else {
            return
        }

        let dotSize = min(8, max(5, min(selectionRect.width, selectionRect.height) / 12))
        let dotRadius = dotSize / 2
        let points = [
            CGPoint(x: selectionRect.minX, y: selectionRect.minY),
            CGPoint(x: selectionRect.maxX, y: selectionRect.minY),
            CGPoint(x: selectionRect.minX, y: selectionRect.maxY),
            CGPoint(x: selectionRect.maxX, y: selectionRect.maxY),
        ]

        for point in points {
            let dotRect = CGRect(
                x: point.x - dotRadius,
                y: point.y - dotRadius,
                width: dotSize,
                height: dotSize
            )
            let dotPath = NSBezierPath(ovalIn: dotRect)
            let isBottomRight = point.x == selectionRect.maxX && point.y == selectionRect.minY
            (isBottomRight ? NSColor.systemGreen : NSColor.white).withAlphaComponent(0.96).setFill()
            dotPath.fill()
        }
    }

    private func completeSelection(with selection: SelectionCapture?) {
        guard !hasCompleted else {
            return
        }

        hasCompleted = true
        onComplete(selection)
    }

    @objc private func regionModeButtonClicked() {
        confirmSelection()
    }

    private func confirmSelection() {
        guard let activeSelection,
              SelectionGeometry.isValidSelection(activeSelection.rect) else {
            NSSound.beep()
            return
        }

        completeSelection(with: activeSelection)
    }

    private func selectWindowCandidate(at localPoint: CGPoint) {
        guard !hudStackView.frame.contains(localPoint) else {
            return
        }

        onInteraction()
        dragOperation = nil

        guard let candidate = onWindowSelectionRequested(globalPoint(fromLocalPoint: localPoint)) else {
            clearSelection()
            return
        }

        windowCandidate = candidate
        selectionRect = localRect(fromGlobalRect: candidate.bounds)
        updateMetrics()
        needsDisplay = true
    }

    private func updateMetrics() {
        guard let displayedLocalRect else {
            hudStackView.isHidden = !showsCenteredHUDWhenEmpty
            modeView.isHidden = !showsCenteredHUDWhenEmpty
            sizeView.isHidden = !showsCenteredHUDWhenEmpty
            sizeLabel.stringValue = "0 x 0"
            positionHUD()
            updateVisibleHUDTheme()
            return
        }

        hudStackView.isHidden = false
        modeView.isHidden = false
        sizeView.isHidden = false
        sizeLabel.stringValue = "\(Int(displayedLocalRect.width.rounded())) x \(Int(displayedLocalRect.height.rounded()))"
        positionHUD()
        updateVisibleHUDTheme()
    }

    private func positionHUD() {
        let hasDisplayedSelection = displayedLocalRect != nil
        let desiredHUDSize = hasDisplayedSelection ? hudSize : hudSize
        let visibleSize = CGSize(width: min(desiredHUDSize.width, bounds.width - 24), height: desiredHUDSize.height)
        let fallbackOrigin = CGPoint(
            x: min(max(bounds.midX - visibleSize.width / 2, bounds.minX + 12), bounds.maxX - visibleSize.width - 12),
            y: min(max(bounds.midY - visibleSize.height / 2, bounds.minY + 18), bounds.maxY - visibleSize.height - 18)
        )

        guard let displayedLocalRect else {
            hudStackView.frame = CGRect(origin: fallbackOrigin, size: visibleSize)
            return
        }

        let inset: CGFloat = 10
        let spacing: CGFloat = 10
        let horizontalCenter = displayedLocalRect.midX - visibleSize.width / 2
        let insideBottomY = displayedLocalRect.minY + inset
        let belowY = displayedLocalRect.minY - visibleSize.height - spacing
        let aboveY = displayedLocalRect.maxY + spacing
        let canFitBelow = belowY >= bounds.minY + 18
        let canFitInside = displayedLocalRect.height >= visibleSize.height + inset * 2
        let canFitAbove = aboveY + visibleSize.height <= bounds.maxY - 18
        let y = if canFitBelow {
            belowY
        } else if canFitInside {
            insideBottomY
        } else if canFitAbove {
            aboveY
        } else {
            belowY
        }
        var origin = CGPoint(x: horizontalCenter, y: y)

        origin.x = min(max(origin.x, bounds.minX + 12), bounds.maxX - visibleSize.width - 12)
        origin.y = min(max(origin.y, bounds.minY + 18), bounds.maxY - visibleSize.height - 18)

        hudStackView.frame = CGRect(origin: origin, size: visibleSize)
    }

    private var modeButton: HUDIconButton? {
        modeView.subviews.first as? HUDIconButton
    }

    private var displayedLocalRect: CGRect? {
        if let windowCandidate {
            return localRect(fromGlobalRect: windowCandidate.bounds)
        }

        return selectionRect
    }

    private func updateHUDTheme() {
        let sampleRect = globalRect(fromLocalRect: hudStackView.frame.insetBy(dx: -10, dy: -10))
        guard let luminance = ScreenLuminanceSampler.averageLuminance(in: sampleRect) else {
            return
        }

        applyHUDTheme(luminance < 0.48 ? .lightContent : .darkContent)
    }

    private func updateVisibleHUDTheme() {
        guard !hudStackView.isHidden else {
            return
        }

        updateHUDTheme()
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

    private func globalPoint(fromLocalPoint localPoint: CGPoint) -> CGPoint {
        CGPoint(
            x: screenFrame.minX + localPoint.x,
            y: screenFrame.minY + localPoint.y
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

private final class HUDIconButton: NSButton {
    private let hoverLayer = CALayer()
    private var trackingArea: NSTrackingArea?
    var hoverColor: NSColor = HUDTheme.lightContent.hoverColor {
        didSet {
            hoverLayer.backgroundColor = hoverColor.cgColor
        }
    }
    private var isHovering = false {
        didSet {
            updateHoverAppearance()
        }
    }

    init(symbolName: String, accessibilityDescription: String) {
        super.init(frame: .zero)

        title = ""
        image = NSImage(systemSymbolName: symbolName, accessibilityDescription: accessibilityDescription)
        imagePosition = .imageOnly
        symbolConfiguration = NSImage.SymbolConfiguration(pointSize: 17, weight: .semibold)
        bezelStyle = .regularSquare
        isBordered = false
        setButtonType(.momentaryChange)
        focusRingType = .none
        wantsLayer = true
        layer?.masksToBounds = false
        hoverLayer.backgroundColor = hoverColor.cgColor
        hoverLayer.opacity = 0
        layer?.insertSublayer(hoverLayer, at: 0)
        setAccessibilityLabel(accessibilityDescription)
    }

    @available(*, unavailable)
    required init?(coder: NSCoder) {
        nil
    }

    override func layout() {
        super.layout()

        let hoverDiameter: CGFloat = 32
        hoverLayer.cornerRadius = hoverDiameter / 2
        hoverLayer.bounds = CGRect(
            x: 0,
            y: 0,
            width: hoverDiameter,
            height: hoverDiameter
        )
        hoverLayer.position = CGPoint(
            x: bounds.midX,
            y: bounds.midY
        )
    }

    override func updateTrackingAreas() {
        super.updateTrackingAreas()

        if let trackingArea {
            removeTrackingArea(trackingArea)
        }

        let newTrackingArea = NSTrackingArea(
            rect: bounds,
            options: [.activeAlways, .mouseEnteredAndExited, .inVisibleRect],
            owner: self
        )
        addTrackingArea(newTrackingArea)
        trackingArea = newTrackingArea
    }

    override func mouseEntered(with event: NSEvent) {
        isHovering = true
    }

    override func mouseExited(with event: NSEvent) {
        isHovering = false
    }

    override func mouseDown(with event: NSEvent) {
        animateHoverLayer(opacity: 0.16)
        super.mouseDown(with: event)
        updateHoverAppearance()
    }

    private func updateHoverAppearance() {
        animateHoverLayer(opacity: isHovering ? 1 : 0)
    }

    private func animateHoverLayer(opacity: Float) {
        let animation = CABasicAnimation(keyPath: "opacity")
        animation.fromValue = hoverLayer.presentation()?.opacity ?? hoverLayer.opacity
        animation.toValue = opacity
        animation.duration = 0.14
        animation.timingFunction = CAMediaTimingFunction(name: .easeOut)
        hoverLayer.opacity = opacity
        hoverLayer.add(animation, forKey: "opacity")
    }
}

private enum HUDTheme {
    case lightContent
    case darkContent

    var foregroundColor: NSColor {
        switch self {
        case .lightContent:
            .white.withAlphaComponent(0.92)
        case .darkContent:
            .labelColor.withAlphaComponent(0.86)
        }
    }

    var backgroundColor: NSColor {
        switch self {
        case .lightContent:
            .black.withAlphaComponent(0.10)
        case .darkContent:
            .white.withAlphaComponent(0.04)
        }
    }

    var borderColor: NSColor {
        switch self {
        case .lightContent:
            .white.withAlphaComponent(0.22)
        case .darkContent:
            .white.withAlphaComponent(0.38)
        }
    }

    var hoverColor: NSColor {
        switch self {
        case .lightContent:
            .white.withAlphaComponent(0.14)
        case .darkContent:
            .labelColor.withAlphaComponent(0.08)
        }
    }
}

private enum ScreenLuminanceSampler {
    static func averageLuminance(in cocoaRect: CGRect) -> CGFloat? {
        guard SelectionGeometry.isValidSelection(cocoaRect) else {
            return nil
        }

        let sampleRect = quartzCaptureRect(for: cocoaRect)
        guard !sampleRect.isEmpty,
              let image = CGWindowListCreateImage(
                sampleRect,
                .optionOnScreenOnly,
                kCGNullWindowID,
                [.bestResolution]
              ) else {
            return nil
        }

        return averageLuminance(in: image)
    }

    private static func quartzCaptureRect(for cocoaRect: CGRect) -> CGRect {
        guard let screen = screen(for: cocoaRect),
              let displayNumber = screen.deviceDescription[NSDeviceDescriptionKey("NSScreenNumber")] as? NSNumber else {
            return cocoaRect
        }

        let displayID = CGDirectDisplayID(displayNumber.uint32Value)
        let displayBounds = CGDisplayBounds(displayID)
        let flippedY = displayBounds.maxY - (cocoaRect.maxY - screen.frame.minY)

        return CGRect(
            x: cocoaRect.minX - screen.frame.minX + displayBounds.minX,
            y: flippedY,
            width: cocoaRect.width,
            height: cocoaRect.height
        ).integral
    }

    private static func screen(for rect: CGRect) -> NSScreen? {
        let rectCenter = CGPoint(x: rect.midX, y: rect.midY)
        if let containingScreen = NSScreen.screens.first(where: { $0.frame.contains(rectCenter) }) {
            return containingScreen
        }

        return NSScreen.screens.max { firstScreen, secondScreen in
            intersectionArea(firstScreen.frame, rect) < intersectionArea(secondScreen.frame, rect)
        }
    }

    private static func intersectionArea(_ firstRect: CGRect, _ secondRect: CGRect) -> CGFloat {
        let intersection = firstRect.intersection(secondRect)
        guard !intersection.isNull else {
            return 0
        }

        return intersection.width * intersection.height
    }

    private static func averageLuminance(in image: CGImage) -> CGFloat? {
        let sampleWidth = 16
        let sampleHeight = 8
        let bytesPerPixel = 4
        let bytesPerRow = sampleWidth * bytesPerPixel
        var pixels = [UInt8](repeating: 0, count: sampleHeight * bytesPerRow)

        guard let colorSpace = CGColorSpace(name: CGColorSpace.sRGB),
              let context = CGContext(
                data: &pixels,
                width: sampleWidth,
                height: sampleHeight,
                bitsPerComponent: 8,
                bytesPerRow: bytesPerRow,
                space: colorSpace,
                bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue
              ) else {
            return nil
        }

        context.interpolationQuality = .low
        context.draw(image, in: CGRect(x: 0, y: 0, width: sampleWidth, height: sampleHeight))

        var luminance: CGFloat = 0
        for index in stride(from: 0, to: pixels.count, by: bytesPerPixel) {
            let red = CGFloat(pixels[index]) / 255
            let green = CGFloat(pixels[index + 1]) / 255
            let blue = CGFloat(pixels[index + 2]) / 255
            luminance += 0.2126 * red + 0.7152 * green + 0.0722 * blue
        }

        return luminance / CGFloat(sampleWidth * sampleHeight)
    }
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

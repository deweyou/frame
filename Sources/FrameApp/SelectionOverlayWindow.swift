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
        placeholderText: String,
        ocrActionText: String,
        onInteraction: @escaping () -> Void,
        onWindowSelectionRequested: @escaping (CGPoint) -> WindowCandidate?,
        onComplete: @escaping (SelectionOverlayCompletion?) -> Void
    ) {
        overlayView = SelectionOverlayView(
            screen: screen,
            initialGlobalRect: initialGlobalRect,
            showsCenteredHUDWhenEmpty: showsCenteredHUDWhenEmpty,
            placeholderText: placeholderText,
            ocrActionText: ocrActionText,
            onInteraction: onInteraction,
            onWindowSelectionRequested: onWindowSelectionRequested,
            onComplete: onComplete
        )

        window = SelectionOverlayNativeWindow(
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
        window.sharingType = .none
        window.level = .screenSaver
        window.isReleasedWhenClosed = false
        window.acceptsMouseMovedEvents = true
    }

    func orderFrontRegardless() {
        window.orderFrontRegardless()
    }

    func makeKey() {
        window.makeKeyAndOrderFront(nil)
        window.makeFirstResponder(overlayView)
    }

    var hasSelection: Bool {
        overlayView.hasSelection
    }

    var isEditingSize: Bool {
        overlayView.isEditingSize
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

private final class SelectionOverlayNativeWindow: NSWindow {
    override var canBecomeKey: Bool {
        true
    }

    override var canBecomeMain: Bool {
        true
    }
}

@MainActor
private final class SelectionOverlayView: NSView {
    private let hudSize = CGSize(width: 218, height: 42)
    private let screenFrame: CGRect
    private let onInteraction: () -> Void
    private let onWindowSelectionRequested: (CGPoint) -> WindowCandidate?
    private let onComplete: (SelectionOverlayCompletion?) -> Void
    private let hudStackView = NSStackView()
    private let modeView = NSVisualEffectView()
    private let sizeView = NSVisualEffectView()
    private let sizeControl = HUDSizeControl()
    private let placeholderView = NSVisualEffectView()
    private let placeholderLabel: NSTextField
    private let ocrActionText: String
    private let tooltipView = HUDTooltipView()
    private var pendingTooltipTask: Task<Void, Never>?
    private var hudTheme: HUDTheme = .lightContent

    private var selectionRect: CGRect?
    private var windowCandidate: WindowCandidate?
    private var dragOperation: SelectionDragOperation?
    private var hasCompleted = false
    private var showsCenteredHUDWhenEmpty: Bool
    private var sizingMode: SelectionSizingMode = .unlocked
    private var isShiftTemporarilyLocking = false

    init(
        screen: NSScreen,
        initialGlobalRect: CGRect?,
        showsCenteredHUDWhenEmpty: Bool,
        placeholderText: String,
        ocrActionText: String,
        onInteraction: @escaping () -> Void,
        onWindowSelectionRequested: @escaping (CGPoint) -> WindowCandidate?,
        onComplete: @escaping (SelectionOverlayCompletion?) -> Void
    ) {
        self.screenFrame = screen.frame
        self.showsCenteredHUDWhenEmpty = showsCenteredHUDWhenEmpty
        self.onInteraction = onInteraction
        self.onWindowSelectionRequested = onWindowSelectionRequested
        self.onComplete = onComplete
        self.ocrActionText = ocrActionText
        self.placeholderLabel = NSTextField(labelWithString: placeholderText)

        super.init(frame: CGRect(origin: .zero, size: screen.frame.size))

        wantsLayer = true
        selectionRect = localRect(fromGlobalRect: initialGlobalRect)
        configureHUD()
        configurePlaceholder()
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

    var isEditingSize: Bool {
        sizeControl.isEditingSize
    }

    var selectedGlobalRect: CGRect? {
        guard let selectionRect else {
            return nil
        }

        return globalRect(fromLocalRect: selectionRect)
    }

    var activeSelection: SelectionCapture? {
        if let windowCandidate {
            return SelectionCapture(rect: windowCandidate.bounds, kind: .window(id: windowCandidate.id))
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
        positionPlaceholder()
        scheduleHUDThemeUpdate()
    }

    override func resetCursorRects() {
        super.resetCursorRects()
        addCursorRect(bounds, cursor: .crosshair)
        if let selectionRect {
            if !selectionRect.isNearlyEqual(to: bounds) {
                addCursorRect(selectionRect, cursor: .openHand)
            }
            for (handle, hitRect) in SelectionHandle.hitRects(in: selectionRect) {
                addCursorRect(hitRect, cursor: handle.cursor)
            }
        }
        addCursorRect(hudStackView.frame, cursor: .pointingHand)
    }

    override func mouseDown(with event: NSEvent) {
        let point = clampedPoint(event.locationInWindow)

        if event.clickCount == 2 {
            selectWindowCandidate(at: point)
            return
        }

        onInteraction()
        isShiftTemporarilyLocking = event.modifierFlags.contains(.shift)
        dragOperation = dragOperation(startingAt: point, modifiers: event.modifierFlags)
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
        isShiftTemporarilyLocking = false
        updateMetrics()
    }

    override func flagsChanged(with event: NSEvent) {
        guard dragOperation != nil else {
            isShiftTemporarilyLocking = false
            updateMetrics()
            super.flagsChanged(with: event)
            return
        }

        let isShiftPressed = event.modifierFlags.contains(.shift)
        if !isShiftPressed,
           activeRatio == nil,
           case let .create(startPoint, _) = dragOperation {
            dragOperation = .create(startPoint: startPoint, ratio: nil)
        }

        isShiftTemporarilyLocking = isShiftPressed
        updateMetrics()
        super.flagsChanged(with: event)
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

        let drawingSelectionRect = pixelAlignedSelectionRect(
            displayedLocalRect,
            scale: window?.backingScaleFactor ?? 1
        )
        drawDimmedBackdrop(excluding: drawingSelectionRect)
        drawSelectionChrome(drawingSelectionRect)
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
        modeView.addSubview(makeOCRButton())

        configureGlass(sizeView, cornerRadius: 21)
        sizeView.isHidden = true
        sizeView.addSubview(sizeControl)
        configureSizeControl()

        hudStackView.addArrangedSubview(modeView)
        hudStackView.addArrangedSubview(sizeView)
        addSubview(hudStackView)
        tooltipView.isHidden = true
        addSubview(tooltipView)

        let actionButtons = modeView.subviews.compactMap { $0 as? HUDIconButton }
        guard actionButtons.count == 2 else {
            return
        }
        let modeButton = actionButtons[0]
        let ocrButton = actionButtons[1]

        NSLayoutConstraint.activate([
            modeView.widthAnchor.constraint(equalToConstant: 84),
            modeView.heightAnchor.constraint(equalToConstant: hudSize.height),
            sizeView.widthAnchor.constraint(equalToConstant: 127),
            sizeView.heightAnchor.constraint(equalToConstant: hudSize.height),
        ])

        modeButton.translatesAutoresizingMaskIntoConstraints = false
        ocrButton.translatesAutoresizingMaskIntoConstraints = false
        sizeControl.translatesAutoresizingMaskIntoConstraints = false
        NSLayoutConstraint.activate([
            modeButton.leadingAnchor.constraint(equalTo: modeView.leadingAnchor),
            modeButton.centerYAnchor.constraint(equalTo: modeView.centerYAnchor),
            modeButton.widthAnchor.constraint(equalToConstant: 42),
            modeButton.heightAnchor.constraint(equalToConstant: 42),
            ocrButton.leadingAnchor.constraint(equalTo: modeButton.trailingAnchor),
            ocrButton.centerYAnchor.constraint(equalTo: modeView.centerYAnchor),
            ocrButton.widthAnchor.constraint(equalToConstant: 42),
            ocrButton.heightAnchor.constraint(equalToConstant: 42),
            sizeControl.leadingAnchor.constraint(equalTo: sizeView.leadingAnchor),
            sizeControl.trailingAnchor.constraint(equalTo: sizeView.trailingAnchor),
            sizeControl.topAnchor.constraint(equalTo: sizeView.topAnchor),
            sizeControl.bottomAnchor.constraint(equalTo: sizeView.bottomAnchor),
        ])

        positionHUD()
    }

    private func configurePlaceholder() {
        configureGlass(placeholderView, cornerRadius: 22)
        placeholderView.isHidden = true
        placeholderView.translatesAutoresizingMaskIntoConstraints = true
        placeholderLabel.font = .systemFont(ofSize: 13, weight: .medium)
        placeholderLabel.textColor = hudTheme.foregroundColor
        placeholderLabel.alignment = .center
        placeholderLabel.lineBreakMode = .byTruncatingTail
        placeholderLabel.translatesAutoresizingMaskIntoConstraints = false

        placeholderView.addSubview(placeholderLabel)
        addSubview(placeholderView)

        NSLayoutConstraint.activate([
            placeholderLabel.leadingAnchor.constraint(equalTo: placeholderView.leadingAnchor, constant: 18),
            placeholderLabel.trailingAnchor.constraint(equalTo: placeholderView.trailingAnchor, constant: -18),
            placeholderLabel.centerYAnchor.constraint(equalTo: placeholderView.centerYAnchor),
        ])

        positionPlaceholder()
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
        button.onHoverChange = { [weak self, weak button] isHovering in
            self?.setHUDTooltip(isHovering ? "区域截图" : nil, anchorView: button)
        }
        button.contentTintColor = hudTheme.foregroundColor
        return button
    }

    private func makeOCRButton() -> NSButton {
        let button = HUDIconButton(
            symbolName: "text.viewfinder",
            accessibilityDescription: ocrActionText
        )
        button.target = self
        button.action = #selector(ocrButtonClicked)
        button.onHoverChange = { [weak self, weak button] isHovering in
            guard let self else {
                return
            }

            self.setHUDTooltip(isHovering ? self.ocrActionText : nil, anchorView: button)
        }
        button.contentTintColor = hudTheme.foregroundColor
        return button
    }

    private func configureSizeControl() {
        sizeControl.onWidthCommit = { [weak self] width in
            self?.applySizeEdit(.width, value: width)
        }
        sizeControl.onHeightCommit = { [weak self] height in
            self?.applySizeEdit(.height, value: height)
        }
        sizeControl.onLockToggle = { [weak self] in
            self?.toggleRatioLock()
        }
        sizeControl.onRatioPreset = { [weak self] ratio in
            self?.applyRatioPreset(ratio)
        }
        sizeControl.onTooltipChange = { [weak self] text, anchorView in
            self?.setHUDTooltip(text, anchorView: anchorView)
        }
    }

    private func applyHUDTheme(_ theme: HUDTheme) {
        hudTheme = theme
        [modeView, sizeView].forEach { view in
            view.layer?.borderColor = theme.borderColor.cgColor
            view.layer?.backgroundColor = theme.backgroundColor.cgColor
        }
        placeholderView.layer?.borderColor = theme.borderColor.cgColor
        placeholderView.layer?.backgroundColor = theme.backgroundColor.cgColor
        placeholderLabel.textColor = theme.foregroundColor
        modeButton?.contentTintColor = theme.foregroundColor
        modeButton?.hoverColor = theme.hoverColor
        ocrButton?.contentTintColor = theme.foregroundColor
        ocrButton?.hoverColor = theme.hoverColor
        tooltipView.applyTheme(theme)
        if let displayedLocalRect {
            updateSizeControl(
                width: Int(displayedLocalRect.width.rounded()),
                height: Int(displayedLocalRect.height.rounded())
            )
        } else {
            updateSizeControl(width: 0, height: 0)
        }
    }

    private func drawDimmedBackdrop(excluding selectionRect: CGRect) {
        NSColor.black.withAlphaComponent(0.42).setFill()

        NSGraphicsContext.saveGraphicsState()
        NSGraphicsContext.current?.shouldAntialias = false
        let backdropPath = NSBezierPath(rect: bounds)
        backdropPath.append(NSBezierPath(rect: selectionRect))
        backdropPath.windingRule = .evenOdd
        backdropPath.fill()
        NSGraphicsContext.restoreGraphicsState()
    }

    private func drawSelectionChrome(_ selectionRect: CGRect) {
        drawSelectionHandles(in: selectionRect)
    }

    private func drawSelectionHandles(in selectionRect: CGRect) {
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

            let strokeStyle = selectionChromeStrokeStyle(
                backgroundLuminance: averageLuminance(under: cornerPath),
                foregroundLineWidth: lineWidth
            )
            path.lineWidth = strokeStyle.lineWidth
            NSGraphicsContext.saveGraphicsState()
            strokeStyle.shadow.set()
            strokeStyle.color.setStroke()
            path.stroke()
            NSGraphicsContext.restoreGraphicsState()
        }
    }

    private func averageLuminance(under cornerPath: SelectionChromeCornerPath) -> CGFloat? {
        let sampleRect = globalRect(fromLocalRect: cornerPath.bounds.insetBy(dx: -6, dy: -6))
        return ScreenLuminanceSampler.averageLuminance(in: sampleRect)
    }

    private func setHUDTooltip(_ text: String?, anchorView: NSView?) {
        pendingTooltipTask?.cancel()
        pendingTooltipTask = nil

        guard let text, let anchorView, !hudStackView.isHidden else {
            tooltipView.isHidden = true
            return
        }

        pendingTooltipTask = Task { [weak self, weak anchorView] in
            try? await Task.sleep(nanoseconds: 900_000_000)
            guard !Task.isCancelled else {
                return
            }

            await MainActor.run {
                self?.showHUDTooltip(text, anchorView: anchorView)
            }
        }
    }

    private func showHUDTooltip(_ text: String, anchorView: NSView?) {
        guard let anchorView, !hudStackView.isHidden else {
            tooltipView.isHidden = true
            return
        }

        tooltipView.stringValue = text

        let anchorRect = anchorView.convert(anchorView.bounds, to: self)
        let tooltipSize = tooltipView.fittingSize
        let preferredBelowY = anchorRect.minY - tooltipSize.height - 8
        let fallbackAboveY = anchorRect.maxY + 8
        let y = preferredBelowY >= bounds.minY + 8 ? preferredBelowY : fallbackAboveY
        var origin = CGPoint(x: anchorRect.midX - tooltipSize.width / 2, y: y)
        origin.x = min(max(origin.x, bounds.minX + 8), bounds.maxX - tooltipSize.width - 8)
        origin.y = min(max(origin.y, bounds.minY + 8), bounds.maxY - tooltipSize.height - 8)

        tooltipView.frame = CGRect(origin: origin, size: tooltipSize)
        tooltipView.isHidden = false
    }

    private func completeSelection(with completion: SelectionOverlayCompletion?) {
        guard !hasCompleted else {
            return
        }

        hasCompleted = true
        onComplete(completion)
    }

    @objc private func regionModeButtonClicked() {
        confirmSelection()
    }

    @objc private func ocrButtonClicked() {
        guard let activeSelection,
              SelectionGeometry.isValidSelection(activeSelection.rect) else {
            NSSound.beep()
            return
        }

        completeSelection(with: .recognizeText(activeSelection))
    }

    private func confirmSelection() {
        guard let activeSelection,
              SelectionGeometry.isValidSelection(activeSelection.rect) else {
            NSSound.beep()
            return
        }

        completeSelection(with: .capture(activeSelection))
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
            hudStackView.isHidden = true
            modeView.isHidden = true
            sizeView.isHidden = true
            placeholderView.isHidden = !showsCenteredHUDWhenEmpty
            updateSizeControl(width: 0, height: 0)
            positionHUD()
            positionPlaceholder()
            scheduleHUDThemeUpdate()
            return
        }

        placeholderView.isHidden = true
        hudStackView.isHidden = false
        modeView.isHidden = false
        sizeView.isHidden = false
        updateSizeControl(
            width: Int(displayedLocalRect.width.rounded()),
            height: Int(displayedLocalRect.height.rounded())
        )
        positionHUD()
        positionPlaceholder()
        scheduleHUDThemeUpdate()
    }

    private func updateSizeControl(width: Int, height: Int) {
        sizeControl.update(
            width: width,
            height: height,
            maximumWidth: Int(bounds.width.rounded(.down)),
            maximumHeight: Int(bounds.height.rounded(.down)),
            isLocked: effectiveSizingMode != .unlocked,
            foregroundColor: hudTheme.foregroundColor
        )
    }

    private func positionHUD() {
        let visibleSize = CGSize(width: min(hudSize.width, bounds.width - 24), height: hudSize.height)
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

    private func positionPlaceholder() {
        let fittingSize = placeholderLabel.fittingSize
        let width = min(max(fittingSize.width + 36, 180), max(bounds.width - 48, 120))
        let height: CGFloat = 44
        let origin = CGPoint(
            x: min(max(bounds.midX - width / 2, bounds.minX + 24), bounds.maxX - width - 24),
            y: min(max(bounds.midY - height / 2, bounds.minY + 24), bounds.maxY - height - 24)
        )

        placeholderView.frame = CGRect(
            origin: origin,
            size: CGSize(width: width, height: height)
        )
    }

    private var modeButton: HUDIconButton? {
        modeView.subviews.first as? HUDIconButton
    }

    private var ocrButton: HUDIconButton? {
        modeView.subviews.compactMap { $0 as? HUDIconButton }.dropFirst().first
    }

    private var displayedLocalRect: CGRect? {
        if let windowCandidate {
            return localRect(fromGlobalRect: windowCandidate.bounds)
        }

        return selectionRect
    }

    private var effectiveSizingMode: SelectionSizingMode {
        if isShiftTemporarilyLocking,
           let displayedLocalRect,
           displayedLocalRect.width > 0,
           displayedLocalRect.height > 0 {
            return .locked(SelectionAspectRatio(width: displayedLocalRect.width, height: displayedLocalRect.height))
        }

        return sizingMode
    }

    private func applySizeEdit(_ dimension: SelectionSizeDimension, value: Int) {
        let clampedValue = CGFloat(clampedSizeEditValue(value, for: dimension))

        let currentRect = displayedLocalRect ?? SelectionSizing.defaultSelection(
            aspectRatio: activeRatio ?? .sixteenNine,
            screenBounds: bounds
        )
        let requestedSize = SelectionSizing.size(
            editing: dimension,
            value: clampedValue,
            currentSize: currentRect.size,
            mode: sizingMode
        )
        let finalSize = clampedRequestedSize(requestedSize, preserving: activeRatio)

        selectionRect = SelectionSizing.centeredRect(
            around: currentRect.center,
            size: finalSize,
            inside: bounds,
            preserving: activeRatio
        )
        windowCandidate = nil
        updateMetrics()
        needsDisplay = true
    }

    private func clampedSizeEditValue(_ value: Int, for dimension: SelectionSizeDimension) -> Int {
        min(max(value, Int(SelectionGeometry.minimumSelectionSize)), maximumSizeEditValue(for: dimension))
    }

    private func maximumSizeEditValue(for dimension: SelectionSizeDimension) -> Int {
        switch dimension {
        case .width:
            Int(bounds.width.rounded(.down))
        case .height:
            Int(bounds.height.rounded(.down))
        }
    }

    private func clampedRequestedSize(_ size: CGSize, preserving ratio: SelectionAspectRatio?) -> CGSize {
        let minimum = SelectionGeometry.minimumSelectionSize
        let size = CGSize(
            width: max(size.width, minimum),
            height: max(size.height, minimum)
        )

        guard size.width > bounds.width || size.height > bounds.height else {
            return size
        }

        if let ratio {
            return SelectionSizing.sizeThatFits(aspectRatio: ratio, inside: bounds.size)
        }

        return CGSize(width: min(size.width, bounds.width), height: min(size.height, bounds.height))
    }

    private func toggleRatioLock() {
        switch sizingMode {
        case .unlocked:
            if let displayedLocalRect,
               displayedLocalRect.width > 0,
               displayedLocalRect.height > 0 {
                sizingMode = .locked(SelectionAspectRatio(width: displayedLocalRect.width, height: displayedLocalRect.height))
            } else {
                sizingMode = .locked(.square)
            }
        case .locked:
            sizingMode = .unlocked
        }

        updateMetrics()
    }

    private func applyRatioPreset(_ ratio: SelectionAspectRatio) {
        let nextRect: CGRect
        if let displayedLocalRect {
            nextRect = SelectionSizing.fit(aspectRatio: ratio, inside: displayedLocalRect)
        } else {
            nextRect = SelectionSizing.defaultSelection(aspectRatio: ratio, screenBounds: bounds)
        }

        guard SelectionGeometry.isValidSelection(nextRect) else {
            NSSound.beep()
            updateMetrics()
            return
        }

        sizingMode = .locked(ratio)
        selectionRect = clampedRect(nextRect)
        windowCandidate = nil
        updateMetrics()
        needsDisplay = true
    }

    private var activeRatio: SelectionAspectRatio? {
        if case let .locked(ratio) = sizingMode {
            return ratio
        }

        return nil
    }

    private func updateHUDTheme() {
        let visibleControlFrame = hudStackView.isHidden ? placeholderView.frame : hudStackView.frame
        let sampleRect = globalRect(fromLocalRect: visibleControlFrame.insetBy(dx: -10, dy: -10))
        guard let luminance = ScreenLuminanceSampler.averageLuminance(in: sampleRect) else {
            return
        }

        applyHUDTheme(luminance < 0.48 ? .lightContent : .darkContent)
    }

    private func updateVisibleHUDTheme() {
        guard !hudStackView.isHidden || !placeholderView.isHidden else {
            return
        }

        updateHUDTheme()
    }

    private func scheduleHUDThemeUpdate() {
        updateVisibleHUDTheme()

        DispatchQueue.main.async { [weak self] in
            self?.updateVisibleHUDTheme()
        }
    }

    private func clampedPoint(_ point: CGPoint) -> CGPoint {
        CGPoint(
            x: min(max(point.x, bounds.minX), bounds.maxX),
            y: min(max(point.y, bounds.minY), bounds.maxY)
        )
    }

    private func ratioForCreateDrag(modifiers: NSEvent.ModifierFlags) -> SelectionAspectRatio? {
        if activeRatio != nil {
            return nil
        }

        guard modifiers.contains(.shift) else {
            return nil
        }

        if let displayedLocalRect,
           displayedLocalRect.width > 0,
           displayedLocalRect.height > 0 {
            return SelectionAspectRatio(width: displayedLocalRect.width, height: displayedLocalRect.height)
        }

        return nil
    }

    private func ratioForResizeDrag(startRect: CGRect, modifiers: NSEvent.ModifierFlags) -> SelectionAspectRatio? {
        if let activeRatio {
            return activeRatio
        }

        guard modifiers.contains(.shift) else {
            return nil
        }

        return SelectionAspectRatio(width: startRect.width, height: startRect.height)
    }

    private func dragOperation(startingAt point: CGPoint, modifiers: NSEvent.ModifierFlags) -> SelectionDragOperation {
        guard let selectionRect else {
            return .create(startPoint: point, ratio: ratioForCreateDrag(modifiers: modifiers))
        }

        if let handle = SelectionHandle.hitTest(point: point, in: selectionRect) {
            return .resize(
                handle: handle,
                startRect: selectionRect,
                ratio: ratioForResizeDrag(startRect: selectionRect, modifiers: modifiers)
            )
        }

        if selectionRect.isNearlyEqual(to: bounds) {
            return .create(startPoint: point, ratio: ratioForCreateDrag(modifiers: modifiers))
        }

        if selectionRect.contains(point) {
            return .move(startRect: selectionRect, startPoint: point)
        }

        return .create(startPoint: point, ratio: ratioForCreateDrag(modifiers: modifiers))
    }

    private func updateSelection(for operation: SelectionDragOperation, currentPoint: CGPoint) {
        switch operation {
        case let .create(startPoint, ratio):
            let proposed = SelectionGeometry.normalizedRect(from: startPoint, to: currentPoint)
            guard proposed.width > 0, proposed.height > 0 else {
                selectionRect = proposed
                return
            }

            if let activeRatio {
                selectionRect = ratioConstrainedRect(from: startPoint, to: currentPoint, aspectRatio: activeRatio)
            } else if let ratio, isShiftTemporarilyLocking {
                selectionRect = ratioConstrainedRect(from: startPoint, to: currentPoint, aspectRatio: ratio)
            } else if isShiftTemporarilyLocking,
                      SelectionGeometry.isValidSelection(proposed) {
                let capturedRatio = SelectionAspectRatio(width: proposed.width, height: proposed.height)
                dragOperation = .create(startPoint: startPoint, ratio: capturedRatio)
                selectionRect = ratioConstrainedRect(from: startPoint, to: currentPoint, aspectRatio: capturedRatio)
            } else {
                selectionRect = proposed
            }
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
        case let .resize(handle, startRect, ratio):
            let rect = handle.resizedRect(from: startRect, to: currentPoint, aspectRatio: activeRatio ?? ratio)
            selectionRect = clampedRect(rect)
        }
    }

    private func ratioConstrainedRect(
        from fixedPoint: CGPoint,
        to movingPoint: CGPoint,
        aspectRatio: SelectionAspectRatio
    ) -> CGRect {
        let delta = CGPoint(x: movingPoint.x - fixedPoint.x, y: movingPoint.y - fixedPoint.y)
        let proposedWidth = abs(delta.x)
        let proposedHeight = abs(delta.y)
        guard proposedWidth > 0, proposedHeight > 0 else {
            return SelectionGeometry.normalizedRect(from: fixedPoint, to: movingPoint)
        }

        let fittedSize = SelectionSizing.sizeThatFits(
            aspectRatio: aspectRatio,
            inside: CGSize(width: proposedWidth, height: proposedHeight)
        )
        let xDirection: CGFloat = delta.x < 0 ? -1 : 1
        let yDirection: CGFloat = delta.y < 0 ? -1 : 1
        let fittedPoint = CGPoint(
            x: fixedPoint.x + fittedSize.width * xDirection,
            y: fixedPoint.y + fittedSize.height * yDirection
        )

        return SelectionGeometry.normalizedRect(from: fixedPoint, to: fittedPoint)
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
    case create(startPoint: CGPoint, ratio: SelectionAspectRatio?)
    case move(startRect: CGRect, startPoint: CGPoint)
    case resize(handle: SelectionHandle, startRect: CGRect, ratio: SelectionAspectRatio?)
}

struct SelectionChromeCornerPath: Equatable {
    let points: [CGPoint]
}

enum SelectionChromeStrokeRole: Equatable {
    case darkForeground
    case lightForeground
}

struct SelectionChromeStrokeStyle: Equatable {
    let role: SelectionChromeStrokeRole
    let lineWidth: CGFloat
    let whiteComponent: CGFloat
    let alpha: CGFloat
    let shadow: SelectionChromeShadowStyle

    @MainActor
    var color: NSColor {
        switch role {
        case .darkForeground:
            NSColor(calibratedWhite: whiteComponent, alpha: alpha)
        case .lightForeground:
            NSColor(calibratedWhite: whiteComponent, alpha: alpha)
        }
    }
}

struct SelectionChromeShadowStyle: Equatable {
    let role: SelectionChromeStrokeRole
    let alpha: CGFloat
    let blurRadius: CGFloat
    let offset: CGSize

    @MainActor
    func set() {
        let shadow = NSShadow()
        shadow.shadowBlurRadius = blurRadius
        shadow.shadowOffset = offset
        switch role {
        case .darkForeground:
            shadow.shadowColor = NSColor.white.withAlphaComponent(alpha)
        case .lightForeground:
            shadow.shadowColor = NSColor.black.withAlphaComponent(alpha)
        }
        shadow.set()
    }
}

func selectionChromeStrokeStyle(
    backgroundLuminance: CGFloat?,
    foregroundLineWidth: CGFloat
) -> SelectionChromeStrokeStyle {
    let luminance = backgroundLuminance ?? 0.45
    let role: SelectionChromeStrokeRole = luminance > 0.58 ? .darkForeground : .lightForeground
    let whiteComponent: CGFloat = role == .darkForeground ? 0.22 : 0.92
    let alpha: CGFloat = role == .darkForeground ? 0.68 : 0.88
    let shadowAlpha: CGFloat = role == .darkForeground ? 0.08 : 0.14

    return SelectionChromeStrokeStyle(
        role: role,
        lineWidth: foregroundLineWidth,
        whiteComponent: whiteComponent,
        alpha: alpha,
        shadow: SelectionChromeShadowStyle(
            role: role,
            alpha: shadowAlpha,
            blurRadius: 1.2,
            offset: CGSize(width: 0, height: -0.5)
        )
    )
}

func selectionChromeCornerPaths(in selectionRect: CGRect, lineWidth: CGFloat) -> [SelectionChromeCornerPath] {
    let inset = max(0, lineWidth / 2)
    let rect = selectionRect.insetBy(dx: inset, dy: inset)
    guard rect.width >= 4, rect.height >= 4 else {
        return []
    }

    let legLength = min(14, max(9, min(rect.width, rect.height) / 5))
    return [
        SelectionChromeCornerPath(
            points: [
                CGPoint(x: rect.minX, y: rect.minY + legLength),
                CGPoint(x: rect.minX, y: rect.minY),
                CGPoint(x: rect.minX + legLength, y: rect.minY),
            ]
        ),
        SelectionChromeCornerPath(
            points: [
                CGPoint(x: rect.maxX - legLength, y: rect.minY),
                CGPoint(x: rect.maxX, y: rect.minY),
                CGPoint(x: rect.maxX, y: rect.minY + legLength),
            ]
        ),
        SelectionChromeCornerPath(
            points: [
                CGPoint(x: rect.minX, y: rect.maxY - legLength),
                CGPoint(x: rect.minX, y: rect.maxY),
                CGPoint(x: rect.minX + legLength, y: rect.maxY),
            ]
        ),
        SelectionChromeCornerPath(
            points: [
                CGPoint(x: rect.maxX - legLength, y: rect.maxY),
                CGPoint(x: rect.maxX, y: rect.maxY),
                CGPoint(x: rect.maxX, y: rect.maxY - legLength),
            ]
        ),
    ]
}

extension SelectionChromeCornerPath {
    var bounds: CGRect {
        points.reduce(CGRect.null) { rect, point in
            rect.union(CGRect(origin: point, size: .zero))
        }
    }
}

func pixelAlignedSelectionRect(_ rect: CGRect, scale: CGFloat) -> CGRect {
    let safeScale = max(scale, 1)
    let minX = (rect.minX * safeScale).rounded() / safeScale
    let minY = (rect.minY * safeScale).rounded() / safeScale
    let maxX = (rect.maxX * safeScale).rounded() / safeScale
    let maxY = (rect.maxY * safeScale).rounded() / safeScale
    let minimumLength = 1 / safeScale

    return CGRect(
        x: minX,
        y: minY,
        width: max(maxX - minX, minimumLength),
        height: max(maxY - minY, minimumLength)
    )
}

private enum SelectionHandle {
    case topLeft
    case topRight
    case bottomLeft
    case bottomRight
    case top
    case right
    case bottom
    case left

    static func hitTest(point: CGPoint, in rect: CGRect) -> SelectionHandle? {
        hitRects(in: rect).first { _, hitRect in
            hitRect.contains(point)
        }?.0
    }

    static func hitRects(in rect: CGRect) -> [(SelectionHandle, CGRect)] {
        let cornerSize: CGFloat = 18
        let edgeThickness: CGFloat = 12
        let horizontalEdgeWidth = max(0, rect.width - cornerSize * 2)
        let verticalEdgeHeight = max(0, rect.height - cornerSize * 2)

        return [
            (.bottomLeft, CGRect(x: rect.minX - cornerSize / 2, y: rect.minY - cornerSize / 2, width: cornerSize, height: cornerSize)),
            (.bottomRight, CGRect(x: rect.maxX - cornerSize / 2, y: rect.minY - cornerSize / 2, width: cornerSize, height: cornerSize)),
            (.topLeft, CGRect(x: rect.minX - cornerSize / 2, y: rect.maxY - cornerSize / 2, width: cornerSize, height: cornerSize)),
            (.topRight, CGRect(x: rect.maxX - cornerSize / 2, y: rect.maxY - cornerSize / 2, width: cornerSize, height: cornerSize)),
            (.bottom, CGRect(x: rect.minX + cornerSize, y: rect.minY - edgeThickness / 2, width: horizontalEdgeWidth, height: edgeThickness)),
            (.top, CGRect(x: rect.minX + cornerSize, y: rect.maxY - edgeThickness / 2, width: horizontalEdgeWidth, height: edgeThickness)),
            (.left, CGRect(x: rect.minX - edgeThickness / 2, y: rect.minY + cornerSize, width: edgeThickness, height: verticalEdgeHeight)),
            (.right, CGRect(x: rect.maxX - edgeThickness / 2, y: rect.minY + cornerSize, width: edgeThickness, height: verticalEdgeHeight)),
        ].filter { _, hitRect in
            hitRect.width > 0 && hitRect.height > 0
        }
    }

    func resizedRect(from rect: CGRect, to movingPoint: CGPoint, aspectRatio: SelectionAspectRatio?) -> CGRect {
        guard let aspectRatio else {
            return resizedRect(from: rect, to: movingPoint)
        }

        let fixedPoint = fixedPoint(for: rect)
        guard let fixedPoint else {
            return ratioResizedEdgeRect(from: rect, to: movingPoint, aspectRatio: aspectRatio)
        }

        let delta = CGPoint(x: movingPoint.x - fixedPoint.x, y: movingPoint.y - fixedPoint.y)
        let proposedWidth = abs(delta.x)
        let proposedHeight = abs(delta.y)
        guard proposedWidth > 0, proposedHeight > 0 else {
            return SelectionGeometry.normalizedRect(from: fixedPoint, to: movingPoint)
        }

        let fittedSize = SelectionSizing.sizeThatFits(
            aspectRatio: aspectRatio,
            inside: CGSize(width: proposedWidth, height: proposedHeight)
        )
        let xDirection: CGFloat = delta.x < 0 ? -1 : 1
        let yDirection: CGFloat = delta.y < 0 ? -1 : 1
        let fittedPoint = CGPoint(
            x: fixedPoint.x + fittedSize.width * xDirection,
            y: fixedPoint.y + fittedSize.height * yDirection
        )

        return SelectionGeometry.normalizedRect(from: fixedPoint, to: fittedPoint)
    }

    private func resizedRect(from rect: CGRect, to movingPoint: CGPoint) -> CGRect {
        switch self {
        case .topLeft:
            SelectionGeometry.normalizedRect(from: CGPoint(x: rect.maxX, y: rect.minY), to: movingPoint)
        case .topRight:
            SelectionGeometry.normalizedRect(from: CGPoint(x: rect.minX, y: rect.minY), to: movingPoint)
        case .bottomLeft:
            SelectionGeometry.normalizedRect(from: CGPoint(x: rect.maxX, y: rect.maxY), to: movingPoint)
        case .bottomRight:
            SelectionGeometry.normalizedRect(from: CGPoint(x: rect.minX, y: rect.maxY), to: movingPoint)
        case .top:
            CGRect(x: rect.minX, y: min(rect.minY, movingPoint.y), width: rect.width, height: abs(movingPoint.y - rect.minY))
        case .right:
            CGRect(x: min(rect.minX, movingPoint.x), y: rect.minY, width: abs(movingPoint.x - rect.minX), height: rect.height)
        case .bottom:
            CGRect(x: rect.minX, y: min(rect.maxY, movingPoint.y), width: rect.width, height: abs(rect.maxY - movingPoint.y))
        case .left:
            CGRect(x: min(rect.maxX, movingPoint.x), y: rect.minY, width: abs(rect.maxX - movingPoint.x), height: rect.height)
        }
    }

    private func ratioResizedEdgeRect(
        from rect: CGRect,
        to movingPoint: CGPoint,
        aspectRatio: SelectionAspectRatio
    ) -> CGRect {
        switch self {
        case .left:
            let width = abs(rect.maxX - movingPoint.x)
            let height = width / aspectRatio.value
            return CGRect(x: rect.maxX - width, y: rect.midY - height / 2, width: width, height: height)
        case .right:
            let width = abs(movingPoint.x - rect.minX)
            let height = width / aspectRatio.value
            return CGRect(x: rect.minX, y: rect.midY - height / 2, width: width, height: height)
        case .top:
            let height = abs(movingPoint.y - rect.minY)
            let width = height * aspectRatio.value
            return CGRect(x: rect.midX - width / 2, y: rect.minY, width: width, height: height)
        case .bottom:
            let height = abs(rect.maxY - movingPoint.y)
            let width = height * aspectRatio.value
            return CGRect(x: rect.midX - width / 2, y: rect.maxY - height, width: width, height: height)
        case .topLeft, .topRight, .bottomLeft, .bottomRight:
            return resizedRect(from: rect, to: movingPoint)
        }
    }

    private func fixedPoint(for rect: CGRect) -> CGPoint? {
        switch self {
        case .topLeft:
            CGPoint(x: rect.maxX, y: rect.minY)
        case .topRight:
            CGPoint(x: rect.minX, y: rect.minY)
        case .bottomLeft:
            CGPoint(x: rect.maxX, y: rect.maxY)
        case .bottomRight:
            CGPoint(x: rect.minX, y: rect.maxY)
        case .top, .right, .bottom, .left:
            nil
        }
    }

    @MainActor
    var cursor: NSCursor {
        switch self {
        case .left, .right:
            .resizeLeftRight
        case .top, .bottom:
            .resizeUpDown
        case .topLeft, .bottomRight:
            .resizeDiagonalTopRightBottomLeft
        case .topRight, .bottomLeft:
            .resizeDiagonalTopLeftBottomRight
        }
    }
}

@MainActor
private extension NSCursor {
    static let resizeDiagonalTopLeftBottomRight = resizeDiagonalCursor(
        start: CGPoint(x: 5, y: 5),
        end: CGPoint(x: 17, y: 17),
        startWingA: CGPoint(x: 5, y: 10),
        startWingB: CGPoint(x: 10, y: 5),
        endWingA: CGPoint(x: 17, y: 12),
        endWingB: CGPoint(x: 12, y: 17)
    )

    static let resizeDiagonalTopRightBottomLeft = resizeDiagonalCursor(
        start: CGPoint(x: 17, y: 5),
        end: CGPoint(x: 5, y: 17),
        startWingA: CGPoint(x: 12, y: 5),
        startWingB: CGPoint(x: 17, y: 10),
        endWingA: CGPoint(x: 10, y: 17),
        endWingB: CGPoint(x: 5, y: 12)
    )

    private static func resizeDiagonalCursor(
        start: CGPoint,
        end: CGPoint,
        startWingA: CGPoint,
        startWingB: CGPoint,
        endWingA: CGPoint,
        endWingB: CGPoint
    ) -> NSCursor {
        let image = NSImage(size: CGSize(width: 22, height: 22), flipped: false) { rect in
            NSColor.clear.setFill()
            rect.fill()

            drawResizeCursorPath(
                start: start,
                end: end,
                startWingA: startWingA,
                startWingB: startWingB,
                endWingA: endWingA,
                endWingB: endWingB,
                color: .white.withAlphaComponent(0.95),
                lineWidth: 4
            )
            drawResizeCursorPath(
                start: start,
                end: end,
                startWingA: startWingA,
                startWingB: startWingB,
                endWingA: endWingA,
                endWingB: endWingB,
                color: .black.withAlphaComponent(0.88),
                lineWidth: 2
            )

            return true
        }
        image.isTemplate = false
        return NSCursor(image: image, hotSpot: CGPoint(x: 11, y: 11))
    }

    private static func drawResizeCursorPath(
        start: CGPoint,
        end: CGPoint,
        startWingA: CGPoint,
        startWingB: CGPoint,
        endWingA: CGPoint,
        endWingB: CGPoint,
        color: NSColor,
        lineWidth: CGFloat
    ) {
        let path = NSBezierPath()
        path.lineCapStyle = .round
        path.lineJoinStyle = .round
        path.lineWidth = lineWidth

        path.move(to: start)
        path.line(to: end)
        path.move(to: startWingA)
        path.line(to: start)
        path.line(to: startWingB)
        path.move(to: endWingA)
        path.line(to: end)
        path.line(to: endWingB)

        color.setStroke()
        path.stroke()
    }
}

private final class HUDIconButton: NSButton {
    private let hoverLayer = CALayer()
    private var trackingArea: NSTrackingArea?
    var onHoverChange: ((Bool) -> Void)?
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

    override func resetCursorRects() {
        super.resetCursorRects()
        addCursorRect(bounds, cursor: .pointingHand)
    }

    override func mouseEntered(with event: NSEvent) {
        isHovering = true
        onHoverChange?(true)
    }

    override func mouseExited(with event: NSEvent) {
        isHovering = false
        onHoverChange?(false)
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

private final class HUDTooltipView: NSView {
    private let label = NSTextField(labelWithString: "")
    private let horizontalPadding: CGFloat = 9
    private let verticalPadding: CGFloat = 5

    override init(frame frameRect: NSRect) {
        super.init(frame: frameRect)

        wantsLayer = true
        layer?.cornerRadius = 6
        layer?.cornerCurve = .continuous
        layer?.masksToBounds = true

        label.font = .systemFont(ofSize: 11, weight: .medium)
        label.alignment = .center
        label.lineBreakMode = .byClipping
        addSubview(label)
        applyTheme(.lightContent)
    }

    @available(*, unavailable)
    required init?(coder: NSCoder) {
        nil
    }

    var stringValue: String {
        get {
            label.stringValue
        }
        set {
            label.stringValue = newValue
        }
    }

    override var fittingSize: NSSize {
        let labelSize = label.intrinsicContentSize
        return CGSize(
            width: ceil(labelSize.width + horizontalPadding * 2),
            height: ceil(labelSize.height + verticalPadding * 2)
        )
    }

    override func layout() {
        super.layout()
        label.frame = bounds.insetBy(dx: horizontalPadding, dy: verticalPadding)
    }

    func applyTheme(_ theme: HUDTheme) {
        label.textColor = theme.foregroundColor
        layer?.backgroundColor = switch theme {
        case .lightContent:
            NSColor.black.withAlphaComponent(0.42).cgColor
        case .darkContent:
            NSColor.white.withAlphaComponent(0.64).cgColor
        }
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

private extension CGRect {
    func isNearlyEqual(to other: CGRect) -> Bool {
        abs(minX - other.minX) < 1
            && abs(minY - other.minY) < 1
            && abs(width - other.width) < 1
            && abs(height - other.height) < 1
    }
}

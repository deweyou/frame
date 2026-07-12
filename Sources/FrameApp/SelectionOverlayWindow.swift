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
        initialWindowCandidate: WindowCandidate? = nil,
        initialMode: SelectionOverlayInitialMode = .screenshot,
        showsCenteredHUDWhenEmpty: Bool,
        placeholderText: String,
        scrollingActionText: String = "滚动长截图",
        ocrActionText: String,
        delayCountdownNanoseconds: UInt64 = 5_000_000_000,
        onInteraction: @escaping () -> Void,
        onWindowSelectionRequested: @escaping (CGPoint, Int?) -> WindowCandidate?,
        onStartRecording: @escaping (SelectionCapture, RecordingOptions) -> Void = { _, _ in },
        onComplete: @escaping (SelectionOverlayCompletion?) -> Void
    ) {
        overlayView = SelectionOverlayView(
            screen: screen,
            initialGlobalRect: initialGlobalRect,
            initialWindowCandidate: initialWindowCandidate,
            initialMode: initialMode,
            showsCenteredHUDWhenEmpty: showsCenteredHUDWhenEmpty,
            placeholderText: placeholderText,
            scrollingActionText: scrollingActionText,
            ocrActionText: ocrActionText,
            delayCountdownNanoseconds: delayCountdownNanoseconds,
            onInteraction: onInteraction,
            onWindowSelectionRequested: onWindowSelectionRequested,
            onStartRecording: onStartRecording,
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
        overlayView.overlayWindowNumber = { [weak window] in
            window?.windowNumber
        }
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

    func hudButtonAccessibilityLabelsForTesting() -> [String] {
        overlayView.hudButtonAccessibilityLabelsForTesting()
    }

    func hudButtonImageDescriptionsForTesting() -> [String] {
        overlayView.hudButtonImageDescriptionsForTesting()
    }

    func hudButtonVisibleTitlesForTesting() -> [String] {
        overlayView.hudButtonVisibleTitlesForTesting()
    }

    func hudButtonSlashStatesForTesting() -> [String: Bool] {
        overlayView.hudButtonSlashStatesForTesting()
    }

    func hudButtonIconPointSizesForTesting() -> [String: CGFloat] {
        overlayView.hudButtonIconPointSizesForTesting()
    }

    func hudChromeColorsForTesting() -> (
        foreground: NSColor,
        background: NSColor,
        border: NSColor,
        hover: NSColor
    ) {
        overlayView.hudChromeColorsForTesting()
    }

    func hudButtonTintColorsForTesting() -> [String: NSColor] {
        overlayView.hudButtonTintColorsForTesting()
    }

    func hudHasDrawnChromeFillForTesting() -> Bool {
        overlayView.hudHasDrawnChromeFillForTesting()
    }

    func hudButtonLayoutMetricsForTesting() -> (buttonWidth: CGFloat, hoverDiameter: CGFloat, screenshotModeWidth: CGFloat) {
        overlayView.hudButtonLayoutMetricsForTesting()
    }

    func performHUDActionForTesting(accessibilityLabel: String) -> Bool {
        overlayView.performHUDActionForTesting(accessibilityLabel: accessibilityLabel)
    }

    func recordingHUDModeForTesting() -> String {
        overlayView.recordingHUDModeForTesting()
    }

    func enterActiveRecordingModeForTesting(elapsed: TimeInterval, isPaused: Bool) {
        overlayView.enterActiveRecordingMode(elapsed: elapsed, isPaused: isPaused)
    }

    func enterActiveRecordingMode(elapsed: TimeInterval = 0, isPaused: Bool = false) {
        overlayView.enterActiveRecordingMode(elapsed: elapsed, isPaused: isPaused)
    }

    func updateRecordingElapsed(_ elapsed: TimeInterval) {
        overlayView.updateRecordingElapsed(elapsed)
    }

    func setActiveRecordingHandlers(
        pause: @escaping () -> Void,
        resume: @escaping () -> Void,
        stop: @escaping () -> Void
    ) {
        overlayView.setActiveRecordingHandlers(pause: pause, resume: resume, stop: stop)
    }

    func recordingElapsedTextForTesting() -> String {
        overlayView.recordingElapsedTextForTesting()
    }

    func activeSelectionForTesting() -> SelectionCapture? {
        overlayView.activeSelectionForTesting()
    }

    func moveMouseForTesting(toGlobalPoint globalPoint: CGPoint) {
        overlayView.moveMouseForTesting(toLocalPoint: localPoint(fromGlobalPoint: globalPoint))
    }

    func mouseDownForTesting(atGlobalPoint globalPoint: CGPoint) {
        overlayView.mouseDownForTesting(atLocalPoint: localPoint(fromGlobalPoint: globalPoint))
    }

    func mouseDraggedForTesting(toGlobalPoint globalPoint: CGPoint) {
        overlayView.mouseDraggedForTesting(toLocalPoint: localPoint(fromGlobalPoint: globalPoint))
    }

    func mouseUpForTesting(atGlobalPoint globalPoint: CGPoint) {
        overlayView.mouseUpForTesting(atLocalPoint: localPoint(fromGlobalPoint: globalPoint))
    }

    func cursorNameForTesting(atGlobalPoint globalPoint: CGPoint) -> String {
        overlayView.cursorNameForTesting(atLocalPoint: localPoint(fromGlobalPoint: globalPoint))
    }

    func hitTestIsPassthroughForTesting(localPoint: CGPoint) -> Bool {
        overlayView.hitTest(localPoint) == nil
    }

    func recordingHUDFrameForTesting() -> CGRect {
        overlayView.recordingHUDFrameForTesting()
    }

    func startRecordingButtonIsPrimaryForTesting() -> Bool {
        overlayView.startRecordingButtonIsPrimaryForTesting()
    }

    func isDelayCountdownActiveForTesting() -> Bool {
        overlayView.isDelayCountdownActiveForTesting()
    }

    func isHUDHiddenForTesting() -> Bool {
        overlayView.isHUDHiddenForTesting()
    }

    func countdownFrameForTesting() -> CGRect? {
        overlayView.countdownFrameForTesting()
    }

    func countdownFontSizeForTesting() -> CGFloat? {
        overlayView.countdownFontSizeForTesting()
    }

    func countdownTextFrameForTesting() -> CGRect? {
        overlayView.countdownTextFrameForTesting()
    }

    func countdownColorsForTesting() -> (foreground: NSColor, background: NSColor)? {
        overlayView.countdownColorsForTesting()
    }

    func countdownBorderAlphaForTesting() -> CGFloat {
        overlayView.countdownBorderAlphaForTesting()
    }

    func placeholderIsVisibleForTesting() -> Bool {
        overlayView.placeholderIsVisibleForTesting()
    }

    func sizeHUDIsHiddenForTesting() -> Bool {
        overlayView.sizeHUDIsHiddenForTesting()
    }

    func sizeHUDTextForTesting() -> String? {
        overlayView.sizeHUDTextForTesting()
    }

    func ignoresMouseEventsForTesting() -> Bool {
        window.ignoresMouseEvents
    }

    func tooltipLayoutForTesting(text: String) -> (size: CGSize, textFrame: CGRect) {
        overlayView.tooltipLayoutForTesting(text: text)
    }

    func tooltipColorsForTesting() -> (foreground: NSColor, background: NSColor) {
        overlayView.tooltipColorsForTesting()
    }

    func setTooltipThemeForTesting(_ theme: String) {
        overlayView.setTooltipThemeForTesting(theme)
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

    private func localPoint(fromGlobalPoint globalPoint: CGPoint) -> CGPoint {
        CGPoint(
            x: globalPoint.x - window.frame.minX,
            y: globalPoint.y - window.frame.minY
        )
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
    private let hudHeight: CGFloat = 42
    private let buttonWidth: CGFloat = 36
    private let defaultHUDSpacing: CGFloat = 7
    private let activeRecordingHUDSpacing: CGFloat = 4
    private let modeViewHorizontalPadding: CGFloat = 3
    private let setupPrimaryButtonWidth: CGFloat = 92
    private let sizeViewWidth: CGFloat = 127
    private let activeRecordingElapsedWidth: CGFloat = 56
    private let screenFrame: CGRect
    private let onInteraction: () -> Void
    private let onWindowSelectionRequested: (CGPoint, Int?) -> WindowCandidate?
    private let onStartRecording: (SelectionCapture, RecordingOptions) -> Void
    private let onComplete: (SelectionOverlayCompletion?) -> Void
    private let hudStackView = NSStackView()
    private let modeView = NSVisualEffectView()
    private var modeViewWidthConstraint: NSLayoutConstraint?
    private var sizeViewWidthConstraint: NSLayoutConstraint?
    private var modeButtonConstraints: [NSLayoutConstraint] = []
    private let sizeView = NSVisualEffectView()
    private let sizeControl = HUDSizeControl()
    private let recordingElapsedLabel = NSTextField(labelWithString: "00:00")
    private let placeholderView = NSVisualEffectView()
    private let placeholderLabel: NSTextField
    private let scrollingActionText: String
    private let ocrActionText: String
    private let delayCountdownNanoseconds: UInt64
    private let countdownView = CountdownView()
    private let tooltipView = HUDTooltipView()
    private var pendingTooltipTask: Task<Void, Never>?
    private var pendingDelayWorkItems: [DispatchWorkItem] = []
    private var hudTheme: HUDTheme = .lightContent
    private var recordingHUDMode: RecordingHUDMode = .screenshot
    private var currentRecordingOptions = SettingsStore.recordingOptions()
    private var recordingElapsed: TimeInterval = 0
    private var onRecordingPause: () -> Void = {}
    private var onRecordingResume: () -> Void = {}
    private var onRecordingStop: () -> Void = {}

    private var selectionRect: CGRect?
    private var windowCandidate: WindowCandidate?
    private var pendingAutoWindowClickCandidate: WindowCandidate?
    private var isWindowHoverPreselectionEnabled = false
    private var delaySnapshotSelection: SelectionCapture?
    private var dragOperation: SelectionDragOperation?
    private var hasCompleted = false
    private var isDelayCountdownActive = false
    private var showsCenteredHUDWhenEmpty: Bool
    private var sizingMode: SelectionSizingMode = .unlocked
    private var isShiftTemporarilyLocking = false
    var overlayWindowNumber: () -> Int? = { nil }

    private enum RecordingHUDMode: Equatable {
        case screenshot
        case setup
        case active(isPaused: Bool)
    }

    init(
        screen: NSScreen,
        initialGlobalRect: CGRect?,
        initialWindowCandidate: WindowCandidate?,
        initialMode: SelectionOverlayInitialMode,
        showsCenteredHUDWhenEmpty: Bool,
        placeholderText: String,
        scrollingActionText: String,
        ocrActionText: String,
        delayCountdownNanoseconds: UInt64,
        onInteraction: @escaping () -> Void,
        onWindowSelectionRequested: @escaping (CGPoint, Int?) -> WindowCandidate?,
        onStartRecording: @escaping (SelectionCapture, RecordingOptions) -> Void,
        onComplete: @escaping (SelectionOverlayCompletion?) -> Void
    ) {
        self.screenFrame = screen.frame
        self.showsCenteredHUDWhenEmpty = showsCenteredHUDWhenEmpty
        self.onInteraction = onInteraction
        self.onWindowSelectionRequested = onWindowSelectionRequested
        self.onStartRecording = onStartRecording
        self.onComplete = onComplete
        self.scrollingActionText = scrollingActionText
        self.ocrActionText = ocrActionText
        self.delayCountdownNanoseconds = delayCountdownNanoseconds
        self.placeholderLabel = NSTextField(labelWithString: placeholderText)

        super.init(frame: CGRect(origin: .zero, size: screen.frame.size))

        wantsLayer = true
        windowCandidate = initialWindowCandidate
        selectionRect = localRect(fromGlobalRect: initialWindowCandidate?.bounds ?? initialGlobalRect)
        isWindowHoverPreselectionEnabled = initialGlobalRect == nil && initialWindowCandidate == nil
        configureHUD()
        configurePlaceholder()
        if initialMode == .recordingSetup {
            enterRecordingSetupMode()
        }
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
        pendingAutoWindowClickCandidate = nil
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
        guard !isActiveRecordingHUD else {
            addCursorRect(hudStackView.frame, cursor: .pointingHand)
            return
        }

        addCursorRect(bounds, cursor: .crosshair)
        if let selectionRect,
           !isShowingAutoWindowPreselection {
            if !selectionRect.isNearlyEqual(to: bounds) {
                addCursorRect(selectionRect, cursor: .openHand)
            }
            for (handle, hitRect) in SelectionHandle.hitRects(in: selectionRect) {
                addCursorRect(hitRect, cursor: handle.cursor)
            }
        }
        addCursorRect(hudStackView.frame, cursor: .pointingHand)
    }

    override func hitTest(_ point: NSPoint) -> NSView? {
        guard isActiveRecordingHUD else {
            return super.hitTest(point)
        }

        guard hudStackView.frame.contains(point) else {
            return nil
        }

        return super.hitTest(point)
    }

    override func mouseDown(with event: NSEvent) {
        handleMouseDown(
            at: clampedPoint(event.locationInWindow),
            clickCount: event.clickCount,
            modifiers: event.modifierFlags
        )
    }

    override func mouseMoved(with event: NSEvent) {
        handleMouseMoved(at: clampedPoint(event.locationInWindow))
    }

    override func mouseDragged(with event: NSEvent) {
        handleMouseDragged(at: clampedPoint(event.locationInWindow))
    }

    override func mouseUp(with event: NSEvent) {
        handleMouseUp()
    }

    private func handleMouseDown(
        at point: CGPoint,
        clickCount: Int,
        modifiers: NSEvent.ModifierFlags
    ) {
        guard !isDelayCountdownActive else {
            return
        }

        guard !isActiveRecordingHUD else {
            return
        }

        if clickCount == 2 {
            isWindowHoverPreselectionEnabled = false
            pendingAutoWindowClickCandidate = nil
            selectWindowCandidate(at: point)
            return
        }

        if let windowCandidate,
           isWindowHoverPreselectionEnabled,
           let candidateLocalRect = localRect(fromGlobalRect: windowCandidate.bounds),
           candidateLocalRect.contains(point) {
            onInteraction()
            pendingAutoWindowClickCandidate = windowCandidate
            isWindowHoverPreselectionEnabled = false
            isShiftTemporarilyLocking = modifiers.contains(.shift)
            dragOperation = .create(startPoint: point, ratio: ratioForCreateDrag(modifiers: modifiers))
            updateMetrics()
            needsDisplay = true
            return
        }

        onInteraction()
        pendingAutoWindowClickCandidate = nil
        clearAutoWindowPreselectionBeforeManualInteraction()
        isWindowHoverPreselectionEnabled = false
        isShiftTemporarilyLocking = modifiers.contains(.shift)
        dragOperation = dragOperation(startingAt: point, modifiers: modifiers)
        updateMetrics()
        needsDisplay = true
    }

    private func handleMouseMoved(at point: CGPoint) {
        guard !isDelayCountdownActive else {
            return
        }

        guard !isActiveRecordingHUD else {
            return
        }

        guard isWindowHoverPreselectionEnabled else {
            return
        }

        updateAutoWindowPreselection(at: point)
    }

    private func handleMouseDragged(at point: CGPoint) {
        guard !isDelayCountdownActive else {
            return
        }

        guard !isActiveRecordingHUD else {
            return
        }

        guard let dragOperation else {
            return
        }

        pendingAutoWindowClickCandidate = nil
        isWindowHoverPreselectionEnabled = false
        windowCandidate = nil
        updateSelection(for: dragOperation, currentPoint: point)
        updateMetrics()
        needsDisplay = true
    }

    private func handleMouseUp() {
        if let pendingAutoWindowClickCandidate {
            self.pendingAutoWindowClickCandidate = nil
            dragOperation = nil
            isShiftTemporarilyLocking = false
            windowCandidate = pendingAutoWindowClickCandidate
            selectionRect = localRect(fromGlobalRect: pendingAutoWindowClickCandidate.bounds)
            updateMetrics()
            needsDisplay = true
            return
        }

        dragOperation = nil
        isShiftTemporarilyLocking = false
        updateMetrics()
    }

    override func flagsChanged(with event: NSEvent) {
        guard !isDelayCountdownActive else {
            super.flagsChanged(with: event)
            return
        }

        guard !isActiveRecordingHUD else {
            super.flagsChanged(with: event)
            return
        }

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
        guard !isActiveRecordingHUD else {
            super.keyDown(with: event)
            return
        }

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
        hudStackView.spacing = defaultHUDSpacing
        hudStackView.translatesAutoresizingMaskIntoConstraints = true

        configureGlass(modeView, cornerRadius: 21)
        modeView.isHidden = true
        installModeButtons(makeScreenshotModeButtons())

        configureGlass(sizeView, cornerRadius: 21)
        sizeView.isHidden = true
        sizeView.addSubview(sizeControl)
        sizeView.addSubview(recordingElapsedLabel)
        configureSizeControl()
        configureRecordingElapsedLabel()

        hudStackView.addArrangedSubview(modeView)
        hudStackView.addArrangedSubview(sizeView)
        addSubview(hudStackView)
        configureCountdownLabel()
        tooltipView.isHidden = true
        addSubview(tooltipView)

        let modeViewWidthConstraint = modeView.widthAnchor.constraint(equalToConstant: modeViewWidth)
        let sizeViewWidthConstraint = sizeView.widthAnchor.constraint(equalToConstant: currentSizeViewWidth)
        self.modeViewWidthConstraint = modeViewWidthConstraint
        self.sizeViewWidthConstraint = sizeViewWidthConstraint
        sizeControl.translatesAutoresizingMaskIntoConstraints = false
        NSLayoutConstraint.activate([
            modeViewWidthConstraint,
            modeView.heightAnchor.constraint(equalToConstant: hudHeight),
            sizeViewWidthConstraint,
            sizeView.heightAnchor.constraint(equalToConstant: hudHeight),
            sizeControl.leadingAnchor.constraint(equalTo: sizeView.leadingAnchor),
            sizeControl.trailingAnchor.constraint(equalTo: sizeView.trailingAnchor),
            sizeControl.topAnchor.constraint(equalTo: sizeView.topAnchor),
            sizeControl.bottomAnchor.constraint(equalTo: sizeView.bottomAnchor),
            recordingElapsedLabel.centerXAnchor.constraint(equalTo: sizeView.centerXAnchor),
            recordingElapsedLabel.centerYAnchor.constraint(equalTo: sizeView.centerYAnchor),
        ])

        positionHUD()
    }

    private func configureRecordingElapsedLabel() {
        recordingElapsedLabel.font = .monospacedDigitSystemFont(ofSize: 13, weight: .semibold)
        recordingElapsedLabel.alignment = .center
        recordingElapsedLabel.lineBreakMode = .byTruncatingTail
        recordingElapsedLabel.translatesAutoresizingMaskIntoConstraints = false
        recordingElapsedLabel.isHidden = true
    }

    private var modeViewWidth: CGFloat {
        modeView.subviews
            .compactMap { $0 as? HUDIconButton }
            .reduce(modeViewHorizontalPadding * 2) { $0 + $1.preferredHUDWidth }
    }

    private var currentHUDSpacing: CGFloat {
        switch recordingHUDMode {
        case .active:
            activeRecordingHUDSpacing
        case .screenshot, .setup:
            defaultHUDSpacing
        }
    }

    private var currentSizeViewWidth: CGFloat {
        switch recordingHUDMode {
        case .active:
            activeRecordingElapsedWidth
        case .screenshot, .setup:
            sizeViewWidth
        }
    }

    private var hudSize: CGSize {
        CGSize(width: modeViewWidth + currentHUDSpacing + currentSizeViewWidth, height: hudHeight)
    }

    private func installModeButtons(_ buttons: [HUDIconButton]) {
        NSLayoutConstraint.deactivate(modeButtonConstraints)
        modeButtonConstraints.removeAll()
        modeView.subviews
            .compactMap { $0 as? HUDIconButton }
            .forEach { $0.removeFromSuperview() }

        var previousButton: HUDIconButton?
        for button in buttons {
            button.translatesAutoresizingMaskIntoConstraints = false
            modeView.addSubview(button)
            modeButtonConstraints.append(contentsOf: [
                button.centerYAnchor.constraint(equalTo: modeView.centerYAnchor),
                button.widthAnchor.constraint(equalToConstant: button.preferredHUDWidth),
                button.heightAnchor.constraint(equalToConstant: hudHeight),
            ])

            if let previousButton {
                modeButtonConstraints.append(button.leadingAnchor.constraint(equalTo: previousButton.trailingAnchor))
            } else {
                modeButtonConstraints.append(
                    button.leadingAnchor.constraint(equalTo: modeView.leadingAnchor, constant: modeViewHorizontalPadding)
                )
            }

            previousButton = button
        }

        if let previousButton {
            modeButtonConstraints.append(
                previousButton.trailingAnchor.constraint(equalTo: modeView.trailingAnchor, constant: -modeViewHorizontalPadding)
            )
        }

        NSLayoutConstraint.activate(modeButtonConstraints)
        modeViewWidthConstraint?.constant = modeViewWidth
        updateHUDLayoutMetrics()
    }

    private func updateHUDLayoutMetrics() {
        hudStackView.spacing = currentHUDSpacing
        sizeViewWidthConstraint?.constant = currentSizeViewWidth
    }

    private func configureCountdownLabel() {
        countdownView.isHidden = true
        countdownView.translatesAutoresizingMaskIntoConstraints = true
        countdownView.wantsLayer = true
        countdownView.layer?.shadowColor = NSColor.black.cgColor
        countdownView.layer?.shadowOpacity = 0.32
        countdownView.layer?.shadowRadius = 14
        countdownView.layer?.shadowOffset = CGSize(width: 0, height: -4)
        addSubview(countdownView)
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
        view.layer?.shadowOpacity = 0
        view.layer?.shadowPath = nil
        view.layer?.borderWidth = 0.5
        view.layer?.borderColor = HUDChromePalette.deepGlassBorderColor.cgColor
        view.layer?.backgroundColor = HUDChromePalette.deepGlassBackgroundColor.cgColor
        let fillView = HUDChromeFillView(cornerRadius: cornerRadius)
        fillView.frame = view.bounds
        fillView.autoresizingMask = [.width, .height]
        view.addSubview(fillView, positioned: .below, relativeTo: nil)
    }

    private func makeScreenshotModeButtons() -> [HUDIconButton] {
        [
            makeRegionModeButton(),
            makeFullScreenButton(),
            makeDelayButton(),
            makeScrollingScreenshotButton(),
            makeOCRButton(),
            makeRecordingButton(),
        ]
    }

    private func makeRecordingSetupButtons() -> [HUDIconButton] {
        [
            makeStartRecordingButton(),
            makeRecordingFormatButton(),
            makeShowMouseClickHighlightsButton(),
            makeShowKeyboardHintsButton(),
        ]
    }

    private func makeActiveRecordingButtons(isPaused: Bool) -> [HUDIconButton] {
        [
            makeStopRecordingButton(),
            makeRestartRecordingButton(),
            makeDeleteRecordingButton(),
        ]
    }

    private func makeRegionModeButton() -> HUDIconButton {
        let button = HUDIconButton(
            symbolName: "crop",
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

    private func makeFullScreenButton() -> HUDIconButton {
        let button = HUDIconButton(
            symbolName: "display",
            accessibilityDescription: "全屏截图"
        )
        button.target = self
        button.action = #selector(fullScreenButtonClicked)
        button.onHoverChange = { [weak self, weak button] isHovering in
            self?.setHUDTooltip(isHovering ? "全屏截图" : nil, anchorView: button)
        }
        button.contentTintColor = hudTheme.foregroundColor
        return button
    }

    private func makeDelayButton() -> HUDIconButton {
        let button = HUDIconButton(
            symbolName: "timer",
            accessibilityDescription: "延迟截图"
        )
        button.target = self
        button.action = #selector(delayButtonClicked)
        button.onHoverChange = { [weak self, weak button] isHovering in
            self?.setHUDTooltip(isHovering ? "延迟截图" : nil, anchorView: button)
        }
        button.contentTintColor = hudTheme.foregroundColor
        return button
    }

    private func makeScrollingScreenshotButton() -> HUDIconButton {
        let button = HUDIconButton(
            symbolName: "scroll",
            accessibilityDescription: scrollingActionText
        )
        button.target = self
        button.action = #selector(scrollingScreenshotButtonClicked)
        button.onHoverChange = { [weak self, weak button] isHovering in
            guard let self else {
                return
            }

            self.setHUDTooltip(isHovering ? self.scrollingActionText : nil, anchorView: button)
        }
        button.contentTintColor = hudTheme.foregroundColor
        return button
    }

    private func makeOCRButton() -> HUDIconButton {
        let button = HUDIconButton(
            symbolName: "character.textbox",
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

    private func makeRecordingButton() -> HUDIconButton {
        let button = HUDIconButton(
            symbolName: "record.circle",
            accessibilityDescription: "录屏"
        )
        button.target = self
        button.action = #selector(recordingButtonClicked)
        button.onHoverChange = { [weak self, weak button] isHovering in
            self?.setHUDTooltip(isHovering ? "录屏" : nil, anchorView: button)
        }
        button.contentTintColor = hudTheme.foregroundColor
        return button
    }

    private func makeStartRecordingButton() -> HUDIconButton {
        let button = HUDIconButton(
            symbolName: "record.circle.fill",
            accessibilityDescription: "开始录制"
        )
        button.preferredHUDWidth = setupPrimaryButtonWidth
        button.isPrimaryAction = true
        button.image = nil
        button.title = "开始录制"
        button.attributedTitle = NSAttributedString(
            string: "开始录制",
            attributes: [
                .foregroundColor: NSColor.white,
                .font: NSFont.systemFont(ofSize: 13, weight: .semibold),
            ]
        )
        button.target = self
        button.action = #selector(startRecordingButtonClicked)
        button.onHoverChange = { [weak self, weak button] isHovering in
            self?.setHUDTooltip(isHovering ? "开始录制" : nil, anchorView: button)
        }
        button.contentTintColor = hudTheme.foregroundColor
        return button
    }

    private func makeRecordingFormatButton() -> HUDIconButton {
        let label = currentRecordingOptions.format == .mp4 ? "MP4" : "GIF"
        let button = HUDIconButton(
            symbolName: currentRecordingOptions.format == .mp4 ? "film" : "gif",
            accessibilityDescription: label
        )
        button.preferredHUDWidth = 48
        button.isFormatToggle = true
        button.image = nil
        button.imagePosition = .noImage
        button.title = label
        button.attributedTitle = formatButtonTitle(label, color: hudTheme.foregroundColor)
        button.target = self
        button.action = #selector(recordingFormatButtonClicked)
        button.onHoverChange = { [weak self, weak button] isHovering in
            self?.setHUDTooltip(isHovering ? label : nil, anchorView: button)
        }
        button.contentTintColor = hudTheme.foregroundColor
        return button
    }

    private func makeShowMouseClickHighlightsButton() -> HUDIconButton {
        let showsMouseHints = currentRecordingOptions.showsCursor || currentRecordingOptions.showsMouseClickHighlights
        let button = HUDIconButton(
            symbolName: "cursorarrow.rays",
            accessibilityDescription: "显示鼠标提示",
            showsSlashOverlay: !showsMouseHints
        )
        button.target = self
        button.action = #selector(showMouseClickHighlightsButtonClicked)
        button.onHoverChange = { [weak self, weak button] isHovering in
            self?.setHUDTooltip(isHovering ? "显示鼠标提示" : nil, anchorView: button)
        }
        button.contentTintColor = hudTheme.foregroundColor
        return button
    }

    private func makeShowKeyboardHintsButton() -> HUDIconButton {
        let button = HUDIconButton(
            symbolName: "keyboard.badge.eye",
            accessibilityDescription: "显示键盘提示",
            iconPointSize: 14.5,
            showsSlashOverlay: !currentRecordingOptions.showsKeyboardHints
        )
        button.target = self
        button.action = #selector(showKeyboardHintsButtonClicked)
        button.onHoverChange = { [weak self, weak button] isHovering in
            self?.setHUDTooltip(isHovering ? "显示键盘提示" : nil, anchorView: button)
        }
        button.contentTintColor = hudTheme.foregroundColor
        return button
    }

    private func makePauseRecordingButton() -> HUDIconButton {
        let button = HUDIconButton(
            symbolName: "pause.fill",
            accessibilityDescription: "暂停"
        )
        button.target = self
        button.action = #selector(pauseRecordingButtonClicked)
        button.onHoverChange = { [weak self, weak button] isHovering in
            self?.setHUDTooltip(isHovering ? "暂停" : nil, anchorView: button)
        }
        button.contentTintColor = hudTheme.foregroundColor
        return button
    }

    private func makeResumeRecordingButton() -> HUDIconButton {
        let button = HUDIconButton(
            symbolName: "play.fill",
            accessibilityDescription: "继续"
        )
        button.target = self
        button.action = #selector(resumeRecordingButtonClicked)
        button.onHoverChange = { [weak self, weak button] isHovering in
            self?.setHUDTooltip(isHovering ? "继续" : nil, anchorView: button)
        }
        button.contentTintColor = hudTheme.foregroundColor
        return button
    }

    private func makeStopRecordingButton() -> HUDIconButton {
        let button = HUDIconButton(
            symbolName: "stop.fill",
            accessibilityDescription: "停止录制"
        )
        button.target = self
        button.action = #selector(stopRecordingButtonClicked)
        button.onHoverChange = { [weak self, weak button] isHovering in
            self?.setHUDTooltip(isHovering ? "停止录制" : nil, anchorView: button)
        }
        button.contentTintColor = hudTheme.foregroundColor
        return button
    }

    private func makeRestartRecordingButton() -> HUDIconButton {
        let button = HUDIconButton(
            symbolName: "arrow.clockwise",
            accessibilityDescription: "重新开始"
        )
        button.target = self
        button.action = #selector(restartRecordingButtonClicked)
        button.onHoverChange = { [weak self, weak button] isHovering in
            self?.setHUDTooltip(isHovering ? "重新开始" : nil, anchorView: button)
        }
        button.contentTintColor = hudTheme.foregroundColor
        return button
    }

    private func makeDeleteRecordingButton() -> HUDIconButton {
        let button = HUDIconButton(
            symbolName: "trash",
            accessibilityDescription: "删除录制"
        )
        button.target = self
        button.action = #selector(deleteRecordingButtonClicked)
        button.onHoverChange = { [weak self, weak button] isHovering in
            self?.setHUDTooltip(isHovering ? "删除录制" : nil, anchorView: button)
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
            view.subviews
                .compactMap { $0 as? HUDChromeFillView }
                .forEach { $0.applyTheme(theme) }
        }
        placeholderView.layer?.borderColor = theme.borderColor.cgColor
        placeholderView.layer?.backgroundColor = theme.backgroundColor.cgColor
        placeholderView.subviews
            .compactMap { $0 as? HUDChromeFillView }
            .forEach { $0.applyTheme(theme) }
        placeholderLabel.textColor = theme.foregroundColor
        for button in modeView.subviews.compactMap({ $0 as? HUDIconButton }) {
            let tintColor = hudTintColor(for: button, theme: theme)
            button.contentTintColor = tintColor
            button.slashColor = tintColor
            button.hoverColor = theme.hoverColor
            if button.isFormatToggle {
                button.attributedTitle = formatButtonTitle(button.title, color: tintColor)
            }
        }
        updateRecordingElapsedColor()
        tooltipView.applyTheme(theme)
        if let displayedLocalRect {
            updateSizeControl(
                width: Int(displayedLocalRect.width.rounded()),
                height: Int(displayedLocalRect.height.rounded())
            )
        }
    }

    private func hudTintColor(for button: HUDIconButton, theme: HUDTheme) -> NSColor {
        if button.accessibilityLabel() == "停止录制" {
            return .systemRed
        }
        return theme.foregroundColor
    }

    private func formatButtonTitle(_ label: String, color: NSColor) -> NSAttributedString {
        NSAttributedString(
            string: label,
            attributes: [
                .foregroundColor: color,
                .font: NSFont.monospacedSystemFont(ofSize: 12, weight: .bold),
            ]
        )
    }

    private func updateRecordingElapsedColor() {
        switch recordingHUDMode {
        case .active:
            recordingElapsedLabel.textColor = .systemRed
        case .screenshot, .setup:
            recordingElapsedLabel.textColor = hudTheme.foregroundColor
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
        cancelDelayCountdown()
        isDelayCountdownActive = false
        delaySnapshotSelection = nil
        countdownView.isHidden = true
        window?.ignoresMouseEvents = false
        onComplete(completion)
    }

    @objc private func regionModeButtonClicked() {
        guard !isDelayCountdownActive else {
            return
        }

        confirmSelection()
    }

    @objc private func fullScreenButtonClicked() {
        guard !isDelayCountdownActive else {
            return
        }

        completeSelection(with: .fullScreen)
    }

    @objc private func delayButtonClicked() {
        guard !isDelayCountdownActive else {
            return
        }

        guard let activeSelection,
              SelectionGeometry.isValidSelection(activeSelection.rect) else {
            NSSound.beep()
            return
        }

        beginDelayCountdown(for: activeSelection)
    }

    @objc private func ocrButtonClicked() {
        guard !isDelayCountdownActive else {
            return
        }

        guard let activeSelection,
              SelectionGeometry.isValidSelection(activeSelection.rect) else {
            NSSound.beep()
            return
        }

        completeSelection(with: .recognizeText(activeSelection))
    }

    @objc private func scrollingScreenshotButtonClicked() {
        guard !isDelayCountdownActive else {
            return
        }

        guard let activeSelection,
              SelectionGeometry.isValidSelection(activeSelection.rect) else {
            NSSound.beep()
            return
        }

        completeSelection(with: .scrollingScreenshot(activeSelection))
    }

    @objc private func recordingButtonClicked() {
        guard !isDelayCountdownActive else {
            return
        }

        enterRecordingSetupMode()
    }

    private func enterRecordingSetupMode() {
        recordingHUDMode = .setup
        sizeControl.isHidden = false
        recordingElapsedLabel.isHidden = true
        installModeButtons(makeRecordingSetupButtons())
        applyHUDTheme(hudTheme)
        positionHUD()
    }

    @objc private func startRecordingButtonClicked() {
        guard !isDelayCountdownActive else {
            return
        }

        guard let activeSelection,
              SelectionGeometry.isValidSelection(activeSelection.rect) else {
            NSSound.beep()
            return
        }

        cancelDelayCountdown()
        pendingTooltipTask?.cancel()
        tooltipView.isHidden = true
        onStartRecording(activeSelection, currentRecordingOptions)
    }

    @objc private func recordingFormatButtonClicked() {
        let newFormat: RecordingFormat = currentRecordingOptions.format == .mp4 ? .gif : .mp4
        updateRecordingOptions(format: newFormat)
    }

    @objc private func showMouseClickHighlightsButtonClicked() {
        let showsMouseHints = currentRecordingOptions.showsCursor || currentRecordingOptions.showsMouseClickHighlights
        updateRecordingOptions(showsCursor: !showsMouseHints, showsMouseClickHighlights: !showsMouseHints)
    }

    @objc private func showKeyboardHintsButtonClicked() {
        updateRecordingOptions(showsKeyboardHints: !currentRecordingOptions.showsKeyboardHints)
    }

    @objc private func pauseRecordingButtonClicked() {
        enterActiveRecordingMode(elapsed: recordingElapsed, isPaused: true)
        onRecordingPause()
    }

    @objc private func resumeRecordingButtonClicked() {
        enterActiveRecordingMode(elapsed: recordingElapsed, isPaused: false)
        onRecordingResume()
    }

    @objc private func stopRecordingButtonClicked() {
        onRecordingStop()
    }

    @objc private func restartRecordingButtonClicked() {}

    @objc private func deleteRecordingButtonClicked() {}

    private func updateRecordingOptions(
        format: RecordingFormat? = nil,
        showsCursor: Bool? = nil,
        showsMouseClickHighlights: Bool? = nil,
        showsKeyboardHints: Bool? = nil
    ) {
        currentRecordingOptions = RecordingOptions(
            format: format ?? currentRecordingOptions.format,
            showsCursor: showsCursor ?? currentRecordingOptions.showsCursor,
            showsMouseClickHighlights: showsMouseClickHighlights ?? currentRecordingOptions.showsMouseClickHighlights,
            showsKeyboardHints: showsKeyboardHints ?? currentRecordingOptions.showsKeyboardHints,
            audioSource: currentRecordingOptions.audioSource
        )
        SettingsStore.setRecordingOptions(currentRecordingOptions)
        sizeControl.isHidden = false
        recordingElapsedLabel.isHidden = true
        installModeButtons(makeRecordingSetupButtons())
        applyHUDTheme(hudTheme)
        positionHUD()
    }

    func enterActiveRecordingMode(elapsed: TimeInterval = 0, isPaused: Bool = false) {
        recordingHUDMode = .active(isPaused: isPaused)
        recordingElapsed = elapsed
        recordingElapsedLabel.stringValue = formattedRecordingElapsed(elapsed)
        sizeControl.isHidden = true
        recordingElapsedLabel.isHidden = false
        installModeButtons(makeActiveRecordingButtons(isPaused: isPaused))
        applyHUDTheme(hudTheme)
        positionHUD()
    }

    func updateRecordingElapsed(_ elapsed: TimeInterval) {
        recordingElapsed = elapsed
        recordingElapsedLabel.stringValue = formattedRecordingElapsed(elapsed)
    }

    func setActiveRecordingHandlers(
        pause: @escaping () -> Void,
        resume: @escaping () -> Void,
        stop: @escaping () -> Void
    ) {
        onRecordingPause = pause
        onRecordingResume = resume
        onRecordingStop = stop
    }

    private func formattedRecordingElapsed(_ elapsed: TimeInterval) -> String {
        let wholeSeconds = max(0, Int(elapsed.rounded(.down)))
        return String(format: "%02d:%02d", wholeSeconds / 60, wholeSeconds % 60)
    }

    private func confirmSelection() {
        guard !isDelayCountdownActive else {
            return
        }

        guard let activeSelection,
              SelectionGeometry.isValidSelection(activeSelection.rect) else {
            NSSound.beep()
            return
        }

        completeSelection(with: .capture(activeSelection))
    }

    private func beginDelayCountdown(for selection: SelectionCapture) {
        delaySnapshotSelection = selection
        isDelayCountdownActive = true
        window?.ignoresMouseEvents = true
        dragOperation = nil
        pendingTooltipTask?.cancel()
        tooltipView.isHidden = true
        hudStackView.isHidden = true
        modeView.isHidden = true
        sizeView.isHidden = true
        showCountdown(secondsRemaining: 5)

        guard delayCountdownNanoseconds > 0 else {
            completeSelection(with: .capture(selection))
            return
        }

        let tickCount: UInt64 = 5
        let tickDuration = max(1, delayCountdownNanoseconds / tickCount)
        for tickIndex in 1..<tickCount {
            let secondsRemaining = Int(tickCount - tickIndex)
            scheduleDelayWorkItem(afterNanoseconds: tickDuration * tickIndex) { [weak self] in
                self?.showCountdown(secondsRemaining: secondsRemaining)
            }
        }

        scheduleDelayWorkItem(afterNanoseconds: delayCountdownNanoseconds) { [weak self, selection] in
            guard let self, self.delaySnapshotSelection != nil else {
                return
            }

            self.completeSelection(with: .capture(selection))
        }
    }

    private func scheduleDelayWorkItem(afterNanoseconds nanoseconds: UInt64, action: @escaping () -> Void) {
        let workItem = DispatchWorkItem(block: action)
        pendingDelayWorkItems.append(workItem)
        DispatchQueue.main.asyncAfter(
            deadline: .now() + .nanoseconds(Int(min(nanoseconds, UInt64(Int.max)))),
            execute: workItem
        )
    }

    private func cancelDelayCountdown() {
        for workItem in pendingDelayWorkItems {
            workItem.cancel()
        }
        pendingDelayWorkItems.removeAll()
    }

    private func showCountdown(secondsRemaining: Int) {
        countdownView.secondsRemaining = secondsRemaining
        let size = CountdownView.preferredSize(for: secondsRemaining)
        let center = CGPoint(x: bounds.midX, y: bounds.minY + bounds.height * 0.04)
        let x = min(max(center.x - size.width / 2, bounds.minX + 8), bounds.maxX - size.width - 8)
        let y = min(max(center.y - size.height / 2, bounds.minY + 8), bounds.maxY - size.height - 8)
        countdownView.frame = CGRect(origin: CGPoint(x: x, y: y), size: size)
        countdownView.layer?.shadowPath = CGPath(
            roundedRect: countdownView.bounds,
            cornerWidth: CountdownView.cornerRadius,
            cornerHeight: CountdownView.cornerRadius,
            transform: nil
        )
        countdownView.isHidden = false
        needsDisplay = true
    }

    private func selectWindowCandidate(at localPoint: CGPoint) {
        guard !hudStackView.frame.contains(localPoint) else {
            return
        }

        onInteraction()
        pendingAutoWindowClickCandidate = nil
        dragOperation = nil

        guard let candidate = onWindowSelectionRequested(
            globalPoint(fromLocalPoint: localPoint),
            overlayWindowNumber()
        ) else {
            clearSelection()
            return
        }

        windowCandidate = candidate
        selectionRect = localRect(fromGlobalRect: candidate.bounds)
        updateMetrics()
        needsDisplay = true
    }

    private func updateAutoWindowPreselection(at localPoint: CGPoint) {
        guard hudStackView.isHidden || !hudStackView.frame.contains(localPoint) else {
            return
        }

        onInteraction()
        dragOperation = nil

        guard let candidate = onWindowSelectionRequested(
            globalPoint(fromLocalPoint: localPoint),
            overlayWindowNumber()
        ) else {
            if selectionRect != nil || windowCandidate != nil {
                selectionRect = nil
                windowCandidate = nil
                pendingAutoWindowClickCandidate = nil
                updateMetrics()
                needsDisplay = true
            }
            return
        }

        guard windowCandidate != candidate else {
            return
        }

        windowCandidate = candidate
        pendingAutoWindowClickCandidate = nil
        selectionRect = localRect(fromGlobalRect: candidate.bounds)
        updateMetrics()
        needsDisplay = true
    }

    private func clearAutoWindowPreselectionBeforeManualInteraction() {
        guard isWindowHoverPreselectionEnabled,
              windowCandidate != nil else {
            return
        }

        windowCandidate = nil
        pendingAutoWindowClickCandidate = nil
        selectionRect = nil
    }

    private func updateMetrics() {
        if isDelayCountdownActive {
            hudStackView.isHidden = true
            modeView.isHidden = true
            sizeView.isHidden = true
            placeholderView.isHidden = true
            return
        }

        guard let displayedLocalRect else {
            hudStackView.isHidden = true
            modeView.isHidden = true
            sizeView.isHidden = true
            placeholderView.isHidden = !showsCenteredHUDWhenEmpty
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

        if recordingHUDMode == .setup {
            let centeredOrigin = CGPoint(
                x: displayedLocalRect.midX - visibleSize.width / 2,
                y: displayedLocalRect.midY - visibleSize.height / 2
            )
            let origin = CGPoint(
                x: min(max(centeredOrigin.x, bounds.minX + 12), bounds.maxX - visibleSize.width - 12),
                y: min(max(centeredOrigin.y, bounds.minY + 18), bounds.maxY - visibleSize.height - 18)
            )
            hudStackView.frame = CGRect(origin: origin, size: visibleSize)
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

    private var fullScreenButton: HUDIconButton? {
        Array(modeView.subviews.compactMap { $0 as? HUDIconButton }).dropFirst().first
    }

    private var delayButton: HUDIconButton? {
        Array(modeView.subviews.compactMap { $0 as? HUDIconButton }).dropFirst(2).first
    }

    private var ocrButton: HUDIconButton? {
        Array(modeView.subviews.compactMap { $0 as? HUDIconButton }).dropFirst(3).first
    }

    func hudButtonAccessibilityLabelsForTesting() -> [String] {
        modeView.subviews
            .compactMap { $0 as? NSButton }
            .compactMap { $0.accessibilityLabel() }
    }

    func hudButtonImageDescriptionsForTesting() -> [String] {
        modeView.subviews
            .compactMap { $0 as? HUDIconButton }
            .map(\.symbolName)
    }

    func hudButtonVisibleTitlesForTesting() -> [String] {
        modeView.subviews
            .compactMap { $0 as? HUDIconButton }
            .map(\.title)
            .filter { !$0.isEmpty }
    }

    func hudButtonSlashStatesForTesting() -> [String: Bool] {
        Dictionary(
            uniqueKeysWithValues: modeView.subviews
                .compactMap { $0 as? HUDIconButton }
                .compactMap { button in
                    button.accessibilityLabel().map { ($0, button.showsSlashOverlay) }
                }
        )
    }

    func hudButtonIconPointSizesForTesting() -> [String: CGFloat] {
        Dictionary(
            uniqueKeysWithValues: modeView.subviews
                .compactMap { $0 as? HUDIconButton }
                .compactMap { button in
                    button.accessibilityLabel().map { ($0, button.iconPointSize) }
                }
        )
    }

    func hudChromeColorsForTesting() -> (
        foreground: NSColor,
        background: NSColor,
        border: NSColor,
        hover: NSColor
    ) {
        (
            foreground: hudTheme.foregroundColor,
            background: NSColor(cgColor: modeView.layer?.backgroundColor ?? NSColor.clear.cgColor) ?? .clear,
            border: NSColor(cgColor: modeView.layer?.borderColor ?? NSColor.clear.cgColor) ?? .clear,
            hover: hudTheme.hoverColor
        )
    }

    func hudHasDrawnChromeFillForTesting() -> Bool {
        modeView.subviews.contains { $0 is HUDChromeFillView }
            && sizeView.subviews.contains { $0 is HUDChromeFillView }
    }

    func hudButtonTintColorsForTesting() -> [String: NSColor] {
        Dictionary(
            uniqueKeysWithValues: modeView.subviews
                .compactMap { $0 as? HUDIconButton }
                .compactMap { button in
                    guard let label = button.accessibilityLabel() else {
                        return nil
                    }

                    return (label, button.contentTintColor ?? .clear)
                }
        )
    }

    func hudButtonLayoutMetricsForTesting() -> (buttonWidth: CGFloat, hoverDiameter: CGFloat, screenshotModeWidth: CGFloat) {
        (
            buttonWidth: buttonWidth,
            hoverDiameter: HUDIconButton.hoverDiameter,
            screenshotModeWidth: CGFloat(makeScreenshotModeButtons().count) * buttonWidth + modeViewHorizontalPadding * 2
        )
    }

    func performHUDActionForTesting(accessibilityLabel: String) -> Bool {
        guard modeView.subviews.compactMap({ $0 as? NSButton }).contains(where: {
            $0.accessibilityLabel() == accessibilityLabel
        }) else {
            return false
        }

        switch accessibilityLabel {
        case "区域截图":
            regionModeButtonClicked()
        case "全屏截图":
            fullScreenButtonClicked()
        case "延迟截图":
            delayButtonClicked()
        case scrollingActionText:
            scrollingScreenshotButtonClicked()
        case "录屏":
            recordingButtonClicked()
        case "开始录制":
            startRecordingButtonClicked()
        case "MP4", "GIF":
            recordingFormatButtonClicked()
        case "显示鼠标提示", "显示鼠标指针", "显示点击提示":
            showMouseClickHighlightsButtonClicked()
        case "显示键盘提示":
            showKeyboardHintsButtonClicked()
        case "暂停":
            pauseRecordingButtonClicked()
        case "继续":
            resumeRecordingButtonClicked()
        case "停止录制":
            stopRecordingButtonClicked()
        case "重新开始":
            restartRecordingButtonClicked()
        case "删除录制":
            deleteRecordingButtonClicked()
        case ocrActionText:
            ocrButtonClicked()
        default:
            return false
        }
        return true
    }

    func recordingHUDModeForTesting() -> String {
        switch recordingHUDMode {
        case .screenshot:
            "screenshot"
        case .setup:
            "setup"
        case .active:
            "active"
        }
    }

    func recordingElapsedTextForTesting() -> String {
        recordingElapsedLabel.stringValue
    }

    func activeSelectionForTesting() -> SelectionCapture? {
        activeSelection
    }

    func moveMouseForTesting(toLocalPoint localPoint: CGPoint) {
        handleMouseMoved(at: clampedPoint(localPoint))
    }

    func mouseDownForTesting(atLocalPoint localPoint: CGPoint) {
        handleMouseDown(at: clampedPoint(localPoint), clickCount: 1, modifiers: [])
    }

    func mouseDraggedForTesting(toLocalPoint localPoint: CGPoint) {
        handleMouseDragged(at: clampedPoint(localPoint))
    }

    func mouseUpForTesting(atLocalPoint localPoint: CGPoint) {
        handleMouseUp()
    }

    func cursorNameForTesting(atLocalPoint localPoint: CGPoint) -> String {
        let point = clampedPoint(localPoint)

        guard !isActiveRecordingHUD else {
            return hudStackView.frame.contains(point) ? "pointingHand" : "arrow"
        }

        if hudStackView.frame.contains(point) {
            return "pointingHand"
        }

        if let selectionRect,
           !isShowingAutoWindowPreselection,
           !selectionRect.isNearlyEqual(to: bounds) {
            if SelectionHandle.hitTest(point: point, in: selectionRect) != nil {
                return "resize"
            }

            if selectionRect.contains(point) {
                return "openHand"
            }
        }

        return "crosshair"
    }

    func recordingHUDFrameForTesting() -> CGRect {
        hudStackView.frame
    }

    func startRecordingButtonIsPrimaryForTesting() -> Bool {
        modeView.subviews
            .compactMap { $0 as? HUDIconButton }
            .first { $0.accessibilityLabel() == "开始录制" }?
            .isPrimaryAction == true
    }

    func isDelayCountdownActiveForTesting() -> Bool {
        isDelayCountdownActive
    }

    func isHUDHiddenForTesting() -> Bool {
        hudStackView.isHidden
    }

    func countdownFrameForTesting() -> CGRect? {
        countdownView.isHidden ? nil : countdownView.frame
    }

    func countdownFontSizeForTesting() -> CGFloat? {
        countdownView.font.pointSize
    }

    func countdownTextFrameForTesting() -> CGRect? {
        guard !countdownView.isHidden else {
            return nil
        }

        return countdownView.textFrame
    }

    func countdownColorsForTesting() -> (foreground: NSColor, background: NSColor)? {
        guard !countdownView.isHidden else {
            return nil
        }

        return countdownView.colorsForTesting()
    }

    func countdownBorderAlphaForTesting() -> CGFloat {
        countdownView.borderAlphaForTesting()
    }

    func placeholderIsVisibleForTesting() -> Bool {
        !placeholderView.isHidden
    }

    func sizeHUDIsHiddenForTesting() -> Bool {
        sizeView.isHidden
    }

    func sizeHUDTextForTesting() -> String? {
        guard !sizeView.isHidden else {
            return nil
        }

        return sizeControl.textForTesting()
    }

    func tooltipLayoutForTesting(text: String) -> (size: CGSize, textFrame: CGRect) {
        tooltipView.layoutMetrics(for: text)
    }

    func tooltipColorsForTesting() -> (foreground: NSColor, background: NSColor) {
        tooltipView.colorsForTesting()
    }

    func setTooltipThemeForTesting(_ theme: String) {
        tooltipView.applyTheme(theme == "darkContent" ? .darkContent : .lightContent)
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

    private var isActiveRecordingHUD: Bool {
        if case .active = recordingHUDMode {
            return true
        }

        return false
    }

    private func applySizeEdit(_ dimension: SelectionSizeDimension, value: Int) {
        guard !isActiveRecordingHUD else {
            return
        }

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
        guard !isActiveRecordingHUD else {
            return
        }

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
        guard !isActiveRecordingHUD else {
            return
        }

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

    private var isShowingAutoWindowPreselection: Bool {
        isWindowHoverPreselectionEnabled && windowCandidate != nil
    }

    private func updateHUDTheme() {
        applyHUDTheme(.lightContent)
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
    static let hoverDiameter: CGFloat = 36

    let symbolName: String
    let showsSlashOverlay: Bool
    let iconPointSize: CGFloat
    var preferredHUDWidth: CGFloat = 36
    var isPrimaryAction = false {
        didSet {
            updatePrimaryAppearance()
        }
    }
    var isFormatToggle = false
    private let hoverLayer = CALayer()
    private let primaryLayer = CALayer()
    private let slashLayer = CAShapeLayer()
    private var trackingArea: NSTrackingArea?
    var onHoverChange: ((Bool) -> Void)?
    var hoverColor: NSColor = HUDTheme.lightContent.hoverColor {
        didSet {
            hoverLayer.backgroundColor = hoverColor.cgColor
        }
    }
    var slashColor: NSColor = HUDTheme.lightContent.foregroundColor {
        didSet {
            slashLayer.strokeColor = slashColor.cgColor
        }
    }
    private var isHovering = false {
        didSet {
            updateHoverAppearance()
        }
    }

    init(
        symbolName: String,
        accessibilityDescription: String,
        iconPointSize: CGFloat = 17,
        showsSlashOverlay: Bool = false
    ) {
        self.symbolName = symbolName
        self.showsSlashOverlay = showsSlashOverlay
        self.iconPointSize = iconPointSize
        super.init(frame: .zero)

        title = ""
        image = NSImage(systemSymbolName: symbolName, accessibilityDescription: accessibilityDescription)
            ?? NSImage(systemSymbolName: "questionmark.circle", accessibilityDescription: accessibilityDescription)
        imagePosition = .imageOnly
        imageScaling = .scaleNone
        symbolConfiguration = NSImage.SymbolConfiguration(pointSize: iconPointSize, weight: .semibold)
        bezelStyle = .regularSquare
        isBordered = false
        setButtonType(.momentaryChange)
        focusRingType = .none
        wantsLayer = true
        layer?.masksToBounds = false
        primaryLayer.backgroundColor = NSColor.systemRed.cgColor
        primaryLayer.opacity = 0
        layer?.insertSublayer(primaryLayer, at: 0)
        hoverLayer.backgroundColor = hoverColor.cgColor
        hoverLayer.opacity = 0
        layer?.insertSublayer(hoverLayer, above: primaryLayer)
        slashLayer.fillColor = nil
        slashLayer.strokeColor = slashColor.cgColor
        slashLayer.lineCap = .round
        slashLayer.lineWidth = 2.5
        slashLayer.isHidden = !showsSlashOverlay
        layer?.insertSublayer(slashLayer, above: hoverLayer)
        setAccessibilityLabel(accessibilityDescription)
    }

    @available(*, unavailable)
    required init?(coder: NSCoder) {
        nil
    }

    override func layout() {
        super.layout()

        primaryLayer.cornerRadius = 16
        primaryLayer.cornerCurve = .continuous
        primaryLayer.frame = bounds.insetBy(dx: 4, dy: 5)
        hoverLayer.cornerRadius = Self.hoverDiameter / 2
        hoverLayer.bounds = CGRect(
            x: 0,
            y: 0,
            width: Self.hoverDiameter,
            height: Self.hoverDiameter
        )
        hoverLayer.position = CGPoint(
            x: bounds.midX,
            y: bounds.midY
        )
        slashLayer.frame = CGRect(
            x: bounds.midX - 11,
            y: bounds.midY - 11,
            width: 22,
            height: 22
        )
        let slashPath = CGMutablePath()
        slashPath.move(to: CGPoint(x: 5, y: 17))
        slashPath.addLine(to: CGPoint(x: 17, y: 5))
        slashLayer.path = slashPath
        updatePrimaryAppearance()
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
        animateHoverLayer(opacity: isPrimaryAction ? 0 : (isHovering ? 1 : 0))
    }

    private func updatePrimaryAppearance() {
        primaryLayer.opacity = isPrimaryAction ? 1 : 0
        if isPrimaryAction {
            hoverLayer.opacity = 0
        }
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

private final class CountdownView: NSView {
    static let cornerRadius: CGFloat = 18
    private static let minimumSize = CGSize(width: 72, height: 58)
    private static let horizontalPadding: CGFloat = 28
    private static let verticalPadding: CGFloat = 12
    private static let foregroundColor = NSColor.white
    private static let backgroundColor = NSColor(calibratedRed: 0.62, green: 0.02, blue: 0.04, alpha: 0.58)

    let font = NSFont.monospacedDigitSystemFont(ofSize: 36, weight: .bold)

    var secondsRemaining = 5 {
        didSet {
            needsDisplay = true
        }
    }

    var textFrame: CGRect {
        centeredTextFrame(in: bounds)
    }

    static func preferredSize(for secondsRemaining: Int) -> CGSize {
        let attributes = textAttributes()
        let textSize = "\(secondsRemaining)".size(withAttributes: attributes)
        return CGSize(
            width: max(minimumSize.width, ceil(textSize.width + horizontalPadding)),
            height: max(minimumSize.height, ceil(textSize.height + verticalPadding))
        )
    }

    override var isFlipped: Bool {
        false
    }

    override func draw(_ dirtyRect: NSRect) {
        super.draw(dirtyRect)

        let path = NSBezierPath(
            roundedRect: bounds,
            xRadius: Self.cornerRadius,
            yRadius: Self.cornerRadius
        )
        Self.backgroundColor.setFill()
        path.fill()

        "\(secondsRemaining)".draw(
            with: textFrame,
            options: [.usesLineFragmentOrigin, .usesFontLeading],
            attributes: Self.textAttributes(font: font)
        )
    }

    private func centeredTextFrame(in bounds: CGRect) -> CGRect {
        let attributes = Self.textAttributes(font: font)
        let textSize = "\(secondsRemaining)".size(withAttributes: attributes)
        return CGRect(
            x: bounds.midX - textSize.width / 2,
            y: bounds.midY - textSize.height / 2,
            width: textSize.width,
            height: textSize.height
        ).integral
    }

    private static func textAttributes(font: NSFont? = nil) -> [NSAttributedString.Key: Any] {
        [
            .font: font ?? NSFont.monospacedDigitSystemFont(ofSize: 36, weight: .bold),
            .foregroundColor: foregroundColor,
        ]
    }

    func colorsForTesting() -> (foreground: NSColor, background: NSColor) {
        (Self.foregroundColor, Self.backgroundColor)
    }

    func borderAlphaForTesting() -> CGFloat {
        0
    }
}

private final class HUDTooltipView: NSView {
    private var foregroundColor = NSColor.white
    private var backgroundColor = NSColor.black.withAlphaComponent(0.42)
    private let font = NSFont.systemFont(ofSize: 11, weight: .medium)
    private let horizontalPadding: CGFloat = 9
    private let verticalPadding: CGFloat = 5
    private var text = ""

    override init(frame frameRect: NSRect) {
        super.init(frame: frameRect)

        wantsLayer = true
        layer?.cornerRadius = 6
        layer?.cornerCurve = .continuous
        layer?.masksToBounds = true

        applyTheme(.lightContent)
    }

    @available(*, unavailable)
    required init?(coder: NSCoder) {
        nil
    }

    var stringValue: String {
        get {
            text
        }
        set {
            text = newValue
            needsDisplay = true
        }
    }

    override var fittingSize: NSSize {
        layoutMetrics(for: text).size
    }

    override func draw(_ dirtyRect: NSRect) {
        super.draw(dirtyRect)

        guard !text.isEmpty else {
            return
        }

        let metrics = layoutMetrics(for: text, size: bounds.size)
        text.draw(with: metrics.textFrame, options: [.usesLineFragmentOrigin], attributes: textAttributes)
    }

    func layoutMetrics(for text: String) -> (size: CGSize, textFrame: CGRect) {
        let textSize = measuredTextSize(for: text)
        let size = CGSize(
            width: ceil(textSize.width + horizontalPadding * 2),
            height: ceil(textSize.height + verticalPadding * 2)
        )

        return layoutMetrics(for: text, size: size)
    }

    private func layoutMetrics(for text: String, size: CGSize) -> (size: CGSize, textFrame: CGRect) {
        let textSize = measuredTextSize(for: text)
        let textFrame = CGRect(
            x: (size.width - textSize.width) / 2,
            y: (size.height - textSize.height) / 2,
            width: textSize.width,
            height: textSize.height
        )

        return (size: size, textFrame: textFrame)
    }

    func applyTheme(_ theme: HUDTheme) {
        switch theme {
        case .lightContent:
            foregroundColor = .white.withAlphaComponent(0.92)
            backgroundColor = .black.withAlphaComponent(0.42)
        case .darkContent:
            foregroundColor = .black.withAlphaComponent(0.86)
            backgroundColor = .white.withAlphaComponent(0.92)
        }
        layer?.backgroundColor = backgroundColor.cgColor
        needsDisplay = true
    }

    func colorsForTesting() -> (foreground: NSColor, background: NSColor) {
        (foregroundColor, backgroundColor)
    }

    private var textAttributes: [NSAttributedString.Key: Any] {
        [
            .font: font,
            .foregroundColor: foregroundColor,
        ]
    }

    private func measuredTextSize(for text: String) -> CGSize {
        let size = (text as NSString).size(withAttributes: textAttributes)
        return CGSize(width: ceil(size.width), height: ceil(size.height))
    }
}

private enum HUDTheme {
    case lightContent
    case darkContent

    var foregroundColor: NSColor {
        switch self {
        case .lightContent:
            HUDChromePalette.deepGlassForegroundColor
        case .darkContent:
            .init(calibratedWhite: 0.06, alpha: 0.86)
        }
    }

    var backgroundColor: NSColor {
        switch self {
        case .lightContent:
            HUDChromePalette.deepGlassBackgroundColor
        case .darkContent:
            .white.withAlphaComponent(0.96)
        }
    }

    var borderColor: NSColor {
        switch self {
        case .lightContent:
            HUDChromePalette.deepGlassBorderColor
        case .darkContent:
            .init(calibratedWhite: 0.06, alpha: 0.18)
        }
    }

    var hoverColor: NSColor {
        switch self {
        case .lightContent:
            HUDChromePalette.deepGlassHoverColor
        case .darkContent:
            .init(calibratedWhite: 0.06, alpha: 0.08)
        }
    }
}

private final class HUDChromeFillView: NSView {
    private let cornerRadius: CGFloat
    private var fillColor = HUDChromePalette.deepGlassBackgroundColor

    init(cornerRadius: CGFloat) {
        self.cornerRadius = cornerRadius
        super.init(frame: .zero)
    }

    @available(*, unavailable)
    required init?(coder: NSCoder) {
        nil
    }

    override var isOpaque: Bool {
        false
    }

    override func hitTest(_ point: NSPoint) -> NSView? {
        nil
    }

    func applyTheme(_ theme: HUDTheme) {
        fillColor = theme.backgroundColor
        needsDisplay = true
    }

    override func draw(_ dirtyRect: NSRect) {
        super.draw(dirtyRect)

        let path = NSBezierPath(
            roundedRect: bounds,
            xRadius: cornerRadius,
            yRadius: cornerRadius
        )
        fillColor.setFill()
        path.fill()
    }
}

enum ScreenLuminanceSampler {
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

    static func estimatedBackgroundLuminance(in cocoaRect: CGRect) -> CGFloat? {
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

        return estimatedBackgroundLuminance(in: image)
    }

    static func estimatedBackgroundLuminance(from samples: [CGFloat]) -> CGFloat? {
        guard !samples.isEmpty else {
            return nil
        }

        let sortedSamples = samples.sorted()
        let maximumIndex = sortedSamples.count - 1
        let lowerMedianIndex = max(0, Int(floor(CGFloat(maximumIndex) * 0.5)))
        let lowerMedian = sortedSamples[lowerMedianIndex]
        if lowerMedian >= 0.58 {
            return lowerMedian
        }

        let lowerQuartileIndex = max(0, Int(floor(CGFloat(maximumIndex) * 0.25)))
        return sortedSamples[lowerQuartileIndex]
    }

    static func prefersLightHUDContent(backgroundLuminance: CGFloat) -> Bool {
        false
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
        let luminanceSamples = luminanceSamples(in: image)
        guard !luminanceSamples.isEmpty else {
            return nil
        }

        return luminanceSamples.reduce(0, +) / CGFloat(luminanceSamples.count)
    }

    private static func estimatedBackgroundLuminance(in image: CGImage) -> CGFloat? {
        estimatedBackgroundLuminance(from: luminanceSamples(in: image))
    }

    private static func luminanceSamples(in image: CGImage) -> [CGFloat] {
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
            return []
        }

        context.interpolationQuality = .low
        context.draw(image, in: CGRect(x: 0, y: 0, width: sampleWidth, height: sampleHeight))

        var luminanceSamples: [CGFloat] = []
        luminanceSamples.reserveCapacity(sampleWidth * sampleHeight)
        for index in stride(from: 0, to: pixels.count, by: bytesPerPixel) {
            let red = CGFloat(pixels[index]) / 255
            let green = CGFloat(pixels[index + 1]) / 255
            let blue = CGFloat(pixels[index + 2]) / 255
            luminanceSamples.append(0.2126 * red + 0.7152 * green + 0.0722 * blue)
        }

        return luminanceSamples
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

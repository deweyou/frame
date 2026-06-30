import AppKit
import FrameCore

@MainActor
protocol ScrollingScreenshotSessionControlling: AnyObject {
    var isActive: Bool { get }

    func start(
        selection: SelectionCapture,
        strings: AppStrings,
        onComplete: @escaping (CapturedScreenshot) -> Void,
        onCancel: @escaping () -> Void,
        onFailure: @escaping (Error) -> Void
    )
}

@MainActor
final class ScrollingScreenshotSessionController: ScrollingScreenshotSessionControlling {
    typealias CaptureRegion = (CGRect) throws -> CapturedScreenshot
    typealias ScrollRegion = @MainActor (CGRect) -> Void
    typealias StitchScreenshots = ([CapturedScreenshot]) throws -> CapturedScreenshot
    typealias ScheduleStep = @MainActor (TimeInterval, @escaping @MainActor @Sendable () -> Void) -> Void
    typealias PerformStitch = (@escaping () -> Void) -> Void

    private let stepDelay: TimeInterval
    private let maximumScrollSteps: Int
    private let showsInterface: Bool
    private let captureRegion: CaptureRegion
    private let scrollRegion: ScrollRegion
    private let stitchScreenshots: StitchScreenshots
    private let scheduleStep: ScheduleStep
    private let performStitch: PerformStitch
    private let boundaryOverlayController = RecordingBoundaryOverlayController()
    private var activeSession: ScrollingScreenshotSession?
    private var scheduledStepGeneration = 0
    private var hudPanel: NSPanel?
    private var hudStackView: NSStackView?
    private var hudChromeView: ScrollingScreenshotHUDChromeView?

    var isActive: Bool {
        activeSession != nil
    }

    init(
        stepDelay: TimeInterval = 0.65,
        maximumScrollSteps: Int = 30,
        showsInterface: Bool = true,
        captureRegion: @escaping CaptureRegion,
        scrollRegion: ScrollRegion? = nil,
        scheduleStep: ScheduleStep? = nil,
        stitch: StitchScreenshots? = nil,
        performStitch: PerformStitch? = nil
    ) {
        self.stepDelay = stepDelay
        self.maximumScrollSteps = maximumScrollSteps
        self.showsInterface = showsInterface
        self.captureRegion = captureRegion
        self.scrollRegion = scrollRegion ?? ScrollingScreenshotSessionController.defaultScroll
        self.stitchScreenshots = stitch ?? Self.defaultStitch
        self.scheduleStep = scheduleStep ?? ScrollingScreenshotSessionController.defaultScheduleStep
        self.performStitch = performStitch ?? ScrollingScreenshotSessionController.defaultPerformStitch
    }

    convenience init(captureService: CaptureService = CaptureService()) {
        self.init(
            captureRegion: { rect in
                try captureService.capture(rect: rect)
            }
        )
    }

    func start(
        selection: SelectionCapture,
        strings: AppStrings,
        onComplete: @escaping (CapturedScreenshot) -> Void,
        onCancel: @escaping () -> Void,
        onFailure: @escaping (Error) -> Void
    ) {
        closeInterface()
        activeSession = ScrollingScreenshotSession(
            selection: selection,
            strings: strings,
            onComplete: onComplete,
            onCancel: onCancel,
            onFailure: onFailure
        )

        if showsInterface {
            showInterface(selection: selection, strings: strings)
        }
    }

    func beginScrolling() {
        guard var session = activeSession,
              session.phase == .waiting else {
            return
        }

        session.phase = .running
        activeSession = session
        updateHUDControls()
        captureInitialSampleAndSchedule()
    }

    func finish() {
        guard let session = activeSession else {
            return
        }

        finishSession()
        let samples = session.samples
        if samples.count == 1, let screenshot = samples.first {
            session.onComplete(screenshot)
            return
        }

        let stitchScreenshots = stitchScreenshots
        performStitch {
            do {
                let screenshot = try stitchScreenshots(samples)
                DispatchQueue.main.async {
                    session.onComplete(screenshot)
                }
            } catch {
                DispatchQueue.main.async {
                    session.onFailure(error)
                }
            }
        }
    }

    func cancel() {
        guard let session = activeSession else {
            return
        }

        finishSession()
        session.onCancel()
    }

    func toggleAutoScroll() {
        guard var session = activeSession,
              session.phase == .running else {
            return
        }

        session.isAutoScrollingEnabled.toggle()
        activeSession = session
        updateHUDControls()
        if session.isAutoScrollingEnabled {
            scrollRegion(session.selection.rect)
            incrementAutoScrollStepCount()
        }
    }

    private func captureInitialSampleAndSchedule() {
        guard var session = activeSession else {
            return
        }

        do {
            let screenshot = try captureRegion(session.selection.rect)
            session.samples.append(screenshot)
            activeSession = session
            scheduleNextSample()
        } catch {
            finishSession()
            session.onFailure(error)
        }
    }

    private func captureScheduledSample() {
        guard var session = activeSession,
              session.phase == .running
        else {
            return
        }

        do {
            let screenshot = try captureRegion(session.selection.rect)
            session.samples.append(screenshot)
            activeSession = session

            if session.isAutoScrollingEnabled {
                scrollRegion(session.selection.rect)
                incrementAutoScrollStepCount()
            }
            scheduleNextSample()
        } catch {
            finishSession()
            session.onFailure(error)
        }
    }

    private func scheduleNextSample() {
        scheduledStepGeneration += 1
        let generation = scheduledStepGeneration
        scheduleStep(stepDelay) { [weak self] in
            guard let self,
                  self.scheduledStepGeneration == generation else {
                return
            }

            self.captureScheduledSample()
        }
    }

    private func incrementAutoScrollStepCount() {
        guard var session = activeSession else {
            return
        }

        session.completedScrollSteps += 1
        if session.completedScrollSteps >= maximumScrollSteps {
            session.isAutoScrollingEnabled = false
        }
        activeSession = session
        updateHUDControls()
    }

    private func finishSession() {
        scheduledStepGeneration += 1
        closeInterface()
        activeSession = nil
    }

    private func showInterface(selection: SelectionCapture, strings: AppStrings) {
        boundaryOverlayController.show(rect: selection.rect)

        let panel = NSPanel(
            contentRect: CGRect(origin: .zero, size: CGSize(width: 250, height: 40)),
            styleMask: [.borderless, .nonactivatingPanel],
            backing: .buffered,
            defer: false
        )
        panel.collectionBehavior = [.canJoinAllSpaces, .fullScreenAuxiliary, .stationary, .transient]
        panel.level = .statusBar
        panel.isOpaque = false
        panel.backgroundColor = .clear
        panel.hasShadow = false
        panel.isReleasedWhenClosed = false
        panel.sharingType = .none

        let contentView = ScrollingScreenshotHUDRootView(frame: CGRect(origin: .zero, size: Self.waitingHUDPanelSize))
        contentView.autoresizingMask = [.width, .height]
        let chromeView = ScrollingScreenshotHUDChromeView(frame: contentView.bounds)
        chromeView.translatesAutoresizingMaskIntoConstraints = false
        contentView.chromeView = chromeView

        let stackView = NSStackView()
        stackView.translatesAutoresizingMaskIntoConstraints = false
        stackView.orientation = .horizontal
        stackView.alignment = .centerY
        stackView.distribution = .fillEqually
        stackView.spacing = 0
        chromeView.addSubview(stackView)
        contentView.addSubview(chromeView)
        panel.contentView = contentView

        NSLayoutConstraint.activate([
            chromeView.leadingAnchor.constraint(equalTo: contentView.leadingAnchor),
            chromeView.trailingAnchor.constraint(equalTo: contentView.trailingAnchor),
            chromeView.topAnchor.constraint(equalTo: contentView.topAnchor),
            chromeView.bottomAnchor.constraint(equalTo: contentView.bottomAnchor),

            stackView.leadingAnchor.constraint(equalTo: chromeView.leadingAnchor, constant: 6),
            stackView.trailingAnchor.constraint(equalTo: chromeView.trailingAnchor, constant: -6),
            stackView.topAnchor.constraint(equalTo: chromeView.topAnchor),
            stackView.bottomAnchor.constraint(equalTo: chromeView.bottomAnchor),
        ])

        self.hudPanel = panel
        self.hudStackView = stackView
        self.hudChromeView = chromeView
        updateHUDControls()
        panel.setFrame(positionedHUDFrame(near: selection.rect, size: panel.frame.size), display: false)
        panel.orderFrontRegardless()
    }

    private func closeInterface() {
        boundaryOverlayController.close()
        hudPanel?.orderOut(nil)
        hudPanel?.close()
        hudPanel = nil
        hudStackView = nil
        hudChromeView = nil
    }

    private func updateHUDControls() {
        guard let stackView = hudStackView,
              let session = activeSession else {
            return
        }

        stackView.arrangedSubviews.forEach { view in
            stackView.removeArrangedSubview(view)
            view.removeFromSuperview()
        }

        switch session.phase {
        case .waiting:
            stackView.addArrangedSubview(makeHUDButton(title: session.strings.scrollingScreenshotStart, symbolName: "play.fill", action: #selector(startButtonClicked)))
            stackView.addArrangedSubview(makeHUDButton(title: session.strings.scrollingScreenshotCancel, symbolName: "xmark", action: #selector(cancelButtonClicked)))
            hudPanel?.setContentSize(Self.waitingHUDPanelSize)
        case .running:
            stackView.addArrangedSubview(makeHUDButton(title: session.strings.scrollingScreenshotFinish, symbolName: "checkmark", action: #selector(finishButtonClicked)))
            stackView.addArrangedSubview(makeHUDButton(
                title: session.isAutoScrollingEnabled ? session.strings.scrollingScreenshotStopAutoScroll : session.strings.scrollingScreenshotAutoScroll,
                symbolName: session.isAutoScrollingEnabled ? "stop.circle.fill" : "arrow.down.circle.fill",
                action: #selector(autoScrollButtonClicked)
            ))
            stackView.addArrangedSubview(makeHUDButton(title: session.strings.scrollingScreenshotCancel, symbolName: "xmark", action: #selector(cancelButtonClicked)))
            hudPanel?.setContentSize(Self.runningHUDPanelSize)
        }
        if let panel = hudPanel {
            panel.setFrame(positionedHUDFrame(near: session.selection.rect, size: panel.frame.size), display: false)
        }
    }

    private func makeHUDButton(title: String, symbolName: String, action: Selector) -> NSButton {
        let button = ScrollingScreenshotHUDButton(
            image: NSImage(systemSymbolName: symbolName, accessibilityDescription: title) ?? NSImage(),
            target: self,
            action: action
        )
        button.identifier = NSUserInterfaceItemIdentifier(symbolName)
        button.title = ""
        button.imagePosition = .imageOnly
        button.imageScaling = .scaleNone
        button.symbolConfiguration = NSImage.SymbolConfiguration(pointSize: 13, weight: .semibold)
        button.bezelStyle = .regularSquare
        button.isBordered = false
        button.contentTintColor = HUDChromePalette.deepGlassForegroundColor
        button.toolTip = title
        button.setAccessibilityLabel(title)
        button.setButtonType(.momentaryChange)
        return button
    }

    private func positionedHUDFrame(near selectionRect: CGRect, size: CGSize) -> CGRect {
        let screenFrame = NSScreen.screens.max { firstScreen, secondScreen in
            intersectionArea(firstScreen.frame, selectionRect) < intersectionArea(secondScreen.frame, selectionRect)
        }?.frame ?? NSScreen.main?.frame ?? selectionRect
        let x = min(
            max(selectionRect.midX - size.width / 2, screenFrame.minX + 12),
            screenFrame.maxX - size.width - 12
        )
        let preferredY = selectionRect.minY - size.height - 10
        let fallbackY = selectionRect.maxY + 10
        let y = preferredY >= screenFrame.minY + 12
            ? preferredY
            : min(fallbackY, screenFrame.maxY - size.height - 12)
        return CGRect(origin: CGPoint(x: x, y: y), size: size)
    }

    private func intersectionArea(_ firstRect: CGRect, _ secondRect: CGRect) -> CGFloat {
        let intersection = firstRect.intersection(secondRect)
        guard !intersection.isNull else {
            return 0
        }

        return intersection.width * intersection.height
    }

    @objc private func startButtonClicked() {
        beginScrolling()
    }

    @objc private func finishButtonClicked() {
        finish()
    }

    @objc private func autoScrollButtonClicked() {
        toggleAutoScroll()
    }

    @objc private func cancelButtonClicked() {
        cancel()
    }

    nonisolated private static func defaultStitch(_ screenshots: [CapturedScreenshot]) throws -> CapturedScreenshot {
        guard screenshots.count >= 2 else {
            throw ScrollingScreenshotStitchingError.insufficientFrames
        }

        let frames = try screenshots.map { screenshot in
            guard let image = screenshot.image.cgImage(forProposedRect: nil, context: nil, hints: nil) else {
                throw ScrollingScreenshotStitchingError.outputEncodingFailed
            }

            let scale = image.width > 0 ? CGFloat(image.width) / max(screenshot.image.size.width, 1) : 1
            return ScrollingScreenshotFrame(image: image, scale: scale)
        }
        let stitchedImage = try ScrollingScreenshotStitcher().stitch(frames)
        let firstScreenshot = screenshots[0]
        let scale = frames[0].scale
        let imageSize = CGSize(
            width: CGFloat(stitchedImage.width) / max(scale, 1),
            height: CGFloat(stitchedImage.height) / max(scale, 1)
        )
        let image = NSImage(cgImage: stitchedImage, size: imageSize)
        let bitmapRepresentation = NSBitmapImageRep(cgImage: stitchedImage)
        guard let pngData = bitmapRepresentation.representation(using: .png, properties: [:]) else {
            throw ScrollingScreenshotStitchingError.outputEncodingFailed
        }

        return CapturedScreenshot(
            pngData: pngData,
            image: image,
            rect: CGRect(origin: firstScreenshot.rect.origin, size: imageSize)
        )
    }

    private static func defaultScroll(_ rect: CGRect) {
        let currentMouseLocation = CGEvent(source: nil)?.location
        guard let event = CGEvent(
            scrollWheelEvent2Source: nil,
            units: .pixel,
            wheelCount: 1,
            wheel1: -scrollWheelDelta(for: rect),
            wheel2: 0,
            wheel3: 0
        ) else {
            return
        }

        event.location = CGPoint(x: rect.midX, y: rect.midY)
        event.post(tap: .cghidEventTap)
        if let currentMouseLocation {
            CGWarpMouseCursorPosition(currentMouseLocation)
        }
    }

    private static func scrollWheelDelta(for rect: CGRect) -> Int32 {
        Int32(max(24, rect.height * 0.22))
    }

    private static func defaultScheduleStep(after delay: TimeInterval, _ step: @escaping @MainActor @Sendable () -> Void) {
        Timer.scheduledTimer(withTimeInterval: delay, repeats: false) { _ in
            Task { @MainActor in
                step()
            }
        }
    }

    private static func defaultPerformStitch(_ work: @escaping () -> Void) {
        let workItem = DispatchWorkItem(block: work)
        DispatchQueue.global(qos: .userInitiated).async(execute: workItem)
    }

    func boundaryOverlayFrameForTesting() -> CGRect? {
        boundaryOverlayController.frameForTesting()
    }

    func boundaryOverlaySelectionRectForTesting() -> CGRect? {
        boundaryOverlayController.selectionRectForTesting()
    }

    func hudChromeColorsForTesting() -> (background: NSColor, border: NSColor)? {
        hudChromeView?.colorsForTesting()
    }

    func hudButtonAttributesForTesting() -> [(label: String, symbolName: String?, tintColor: NSColor?, imagePosition: NSControl.ImagePosition, bezelStyle: NSButton.BezelStyle)] {
        hudStackView?.arrangedSubviews
            .compactMap { $0 as? NSButton }
            .map { button in
                (
                    label: button.accessibilityLabel() ?? "",
                    symbolName: button.identifier?.rawValue,
                    tintColor: button.contentTintColor,
                    imagePosition: button.imagePosition,
                    bezelStyle: button.bezelStyle
                )
            } ?? []
    }

    static func scrollWheelDeltaForTesting(rect: CGRect) -> Int32 {
        scrollWheelDelta(for: rect)
    }

    private static let waitingHUDPanelSize = CGSize(width: 92, height: 42)
    private static let runningHUDPanelSize = CGSize(width: 132, height: 42)
}

private struct ScrollingScreenshotSession {
    let selection: SelectionCapture
    let strings: AppStrings
    let onComplete: (CapturedScreenshot) -> Void
    let onCancel: () -> Void
    let onFailure: (Error) -> Void
    var phase: ScrollingScreenshotSessionPhase = .waiting
    var samples: [CapturedScreenshot] = []
    var completedScrollSteps = 0
    var isAutoScrollingEnabled = false
}

private enum ScrollingScreenshotSessionPhase {
    case waiting
    case running
}

private final class ScrollingScreenshotHUDRootView: NSView {
    weak var chromeView: NSView?

    override var isOpaque: Bool {
        false
    }

    override func hitTest(_ point: NSPoint) -> NSView? {
        guard let chromeView,
              chromeView.frame.contains(point) else {
            return nil
        }

        return super.hitTest(point)
    }
}

private final class ScrollingScreenshotHUDChromeView: NSView {
    override var isOpaque: Bool {
        false
    }

    func colorsForTesting() -> (background: NSColor, border: NSColor) {
        (HUDChromePalette.deepGlassBackgroundColor, HUDChromePalette.deepGlassBorderColor)
    }

    override func draw(_ dirtyRect: NSRect) {
        super.draw(dirtyRect)

        let path = NSBezierPath(
            roundedRect: bounds.insetBy(dx: 0.5, dy: 0.5),
            xRadius: 20.5,
            yRadius: 20.5
        )
        HUDChromePalette.deepGlassBackgroundColor.setFill()
        path.fill()
        HUDChromePalette.deepGlassBorderColor.setStroke()
        path.lineWidth = 0.5
        path.stroke()
    }
}

private final class ScrollingScreenshotHUDButton: NSButton {
    override func resetCursorRects() {
        super.resetCursorRects()
        if isEnabled {
            addCursorRect(bounds, cursor: .pointingHand)
        }
    }
}

import AppKit
import FrameCore

typealias ScrollingScreenshotStitch = ([CapturedScreenshot]) throws -> CapturedScreenshot
typealias ScrollingScreenshotPreviewStitch = ([CapturedScreenshot]) throws -> ScrollingScreenshotPreviewSnapshot

@MainActor
protocol ScrollingScreenshotSessionControlling: AnyObject {
    var isActive: Bool { get }

    func start(
        selection: SelectionCapture,
        strings: AppStrings,
        onPreviewUpdate: @escaping (CapturedScreenshot) -> Void,
        onFinishStarted: @escaping (CapturedScreenshot?) -> Void,
        onComplete: @escaping (CapturedScreenshot) -> Void,
        onCancel: @escaping () -> Void,
        onRetryableFailure: @escaping (Error) -> Void,
        onFailure: @escaping (Error) -> Void
    )
}

extension ScrollingScreenshotSessionControlling {
    func start(
        selection: SelectionCapture,
        strings: AppStrings,
        onComplete: @escaping (CapturedScreenshot) -> Void,
        onCancel: @escaping () -> Void,
        onFailure: @escaping (Error) -> Void
    ) {
        start(
            selection: selection,
            strings: strings,
            onPreviewUpdate: { _ in },
            onFinishStarted: { _ in },
            onComplete: onComplete,
            onCancel: onCancel,
            onRetryableFailure: onFailure,
            onFailure: onFailure
        )
    }
}

@MainActor
final class ScrollingScreenshotSessionController: ScrollingScreenshotSessionControlling {
    typealias CaptureRegion = (CGRect) throws -> CapturedScreenshot
    typealias ScrollRegion = @MainActor (CGRect) -> Void
    typealias ScrollRegionWithFraction = @MainActor (CGRect, CGFloat) -> Void
    typealias ScheduleStep = @MainActor (TimeInterval, @escaping @MainActor @Sendable () -> Void) -> Void
    typealias PerformStitch = (@escaping () -> Void) -> Void
    typealias IncrementalPipelineFactory = () -> any ScrollingScreenshotIncrementalProcessing

    private let stepDelay: TimeInterval
    private let maximumScrollSteps: Int
    private let maximumConsecutiveAutoScrollNoProgressSamples = 2
    private let maximumConsecutiveIncrementalNoProgressSamples = 3
    private let showsInterface: Bool
    private let captureRegion: CaptureRegion
    private let scrollRegion: ScrollRegion
    private let scrollRegionWithFraction: ScrollRegionWithFraction
    private let stitchScreenshots: ScrollingScreenshotStitch
    private let recoverScreenshots: ScrollingScreenshotStitch
    private let stitchPreview: ScrollingScreenshotPreviewStitch
    private let scheduleStep: ScheduleStep
    private let performStitch: PerformStitch
    private let performPreviewStitch: PerformStitch
    private let usesDefaultFinalPipeline: Bool
    private let usesDefaultPreviewPipeline: Bool
    private let incrementalPipelineFactory: IncrementalPipelineFactory?
    private let previewPresenter: (any ScrollingScreenshotPreviewPresenting)?
    private let boundaryOverlayController = RecordingBoundaryOverlayController()
    private var activeSession: ScrollingScreenshotSession?
    private var scheduledStepGeneration = 0
    private var hudPanel: NSPanel?
    private var hudStackView: NSStackView?
    private var hudChromeView: ScrollingScreenshotHUDChromeView?
    private var previewRenderGeneration = 0
    private var isPreviewRendering = false
    private var pendingPreviewSamples: [CapturedScreenshot]?
    private var lastPreviewPixelHeight = 0
    private var incrementalPipeline: (any ScrollingScreenshotIncrementalProcessing)?
    private var incrementalProcessingSessionID: UUID?

    var isActive: Bool {
        activeSession != nil
    }

    init(
        stepDelay: TimeInterval = 0.65,
        maximumScrollSteps: Int = 200,
        showsInterface: Bool = true,
        captureRegion: @escaping CaptureRegion,
        scrollRegion: ScrollRegion? = nil,
        scheduleStep: ScheduleStep? = nil,
        stitch: ScrollingScreenshotStitch? = nil,
        recoverStitch: ScrollingScreenshotStitch? = nil,
        previewStitch: ScrollingScreenshotPreviewStitch? = nil,
        performStitch: PerformStitch? = nil,
        performPreviewStitch: PerformStitch? = nil,
        previewPresenter: (any ScrollingScreenshotPreviewPresenting)? = nil,
        incrementalPipelineFactory: IncrementalPipelineFactory? = nil
    ) {
        self.stepDelay = stepDelay
        self.maximumScrollSteps = maximumScrollSteps
        self.showsInterface = showsInterface
        self.captureRegion = captureRegion
        if let scrollRegion {
            self.scrollRegion = scrollRegion
            self.scrollRegionWithFraction = { rect, _ in scrollRegion(rect) }
        } else {
            self.scrollRegion = { rect in
                ScrollingScreenshotSessionController.defaultScroll(rect, scrollFraction: 0.22)
            }
            self.scrollRegionWithFraction = ScrollingScreenshotSessionController.defaultScroll
        }
        self.stitchScreenshots = stitch ?? Self.defaultStitch
        self.recoverScreenshots = recoverStitch ?? Self.defaultRecoveringStitch
        self.stitchPreview = previewStitch ?? Self.defaultPreviewStitch
        self.scheduleStep = scheduleStep ?? ScrollingScreenshotSessionController.defaultScheduleStep
        self.performStitch = performStitch ?? ScrollingScreenshotSessionController.defaultPerformStitch
        self.performPreviewStitch = performPreviewStitch ?? ScrollingScreenshotSessionController.defaultPerformStitch
        self.usesDefaultFinalPipeline = stitch == nil && recoverStitch == nil && performStitch == nil
        self.usesDefaultPreviewPipeline = previewStitch == nil && performPreviewStitch == nil
        self.previewPresenter = previewPresenter ?? (showsInterface ? ScrollingScreenshotPreviewPanelController() : nil)
        self.incrementalPipelineFactory = incrementalPipelineFactory
    }

    convenience init(captureService: CaptureService = CaptureService()) {
        self.init(
            captureRegion: { rect in
                try captureService.captureScrollingFrame(rect: rect)
            },
            incrementalPipelineFactory: {
                ScrollingScreenshotIncrementalPipeline()
            }
        )
    }

    func start(
        selection: SelectionCapture,
        strings: AppStrings,
        onPreviewUpdate: @escaping (CapturedScreenshot) -> Void,
        onFinishStarted: @escaping (CapturedScreenshot?) -> Void,
        onComplete: @escaping (CapturedScreenshot) -> Void,
        onCancel: @escaping () -> Void,
        onRetryableFailure: @escaping (Error) -> Void,
        onFailure: @escaping (Error) -> Void
    ) {
        closeInterface()
        previewRenderGeneration += 1
        isPreviewRendering = false
        pendingPreviewSamples = nil
        lastPreviewPixelHeight = 0
        incrementalPipeline = incrementalPipelineFactory?()
        incrementalProcessingSessionID = nil
        activeSession = ScrollingScreenshotSession(
            selection: selection,
            strings: strings,
            onPreviewUpdate: onPreviewUpdate,
            onFinishStarted: onFinishStarted,
            onComplete: onComplete,
            onCancel: onCancel,
            onRetryableFailure: onRetryableFailure,
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
        previewPresenter?.show(selectionRect: session.selection.rect)
        if incrementalPipeline != nil {
            captureIncrementalSample()
        } else {
            captureInitialSampleAndSchedule()
        }
    }

    func finish() {
        guard var session = activeSession,
              session.phase == .running else {
            return
        }

        scheduledStepGeneration += 1
        previewRenderGeneration += 1
        isPreviewRendering = false
        pendingPreviewSamples = nil
        session.phase = .finishing
        session.isAutoScrollingEnabled = false
        activeSession = session
        hideInterfaceForFinalization()
        previewPresenter?.close()
        session.onFinishStarted(session.latestPreview)

        if incrementalPipeline != nil {
            if incrementalProcessingSessionID != session.id {
                scheduleIncrementalFinalization(for: session)
            }
            return
        }

        let samples = session.samples
        if samples.count == 1, let screenshot = samples.first {
            completeFinalScreenshot(screenshot, sessionID: session.id)
            return
        }

        if usesDefaultFinalPipeline {
            Self.scheduleDefaultFinalStitch(samples) { [weak self] result in
                self?.completeFinalStitch(result, sessionID: session.id)
            }
            return
        }

        performStitch { [weak self] in
            Task { @MainActor [weak self] in
                guard let self else {
                    return
                }
                let result = Result<CapturedScreenshot, Error> {
                    do {
                        return try self.stitchScreenshots(samples)
                    } catch {
                        return try self.recoverScreenshots(samples)
                    }
                }
                self.completeFinalStitch(result, sessionID: session.id)
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
        session.consecutiveAutoScrollNoProgressSamples = 0
        activeSession = session
        updateHUDControls()

        if incrementalPipeline != nil {
            if session.isAutoScrollingEnabled,
               incrementalProcessingSessionID != session.id {
                scheduledStepGeneration += 1
                postIncrementalAutoScrollAndScheduleCapture(sessionID: session.id)
            }
            return
        }

        if session.isAutoScrollingEnabled {
            scrollRegion(session.selection.rect)
            incrementAutoScrollStepCount()
        }
    }

    private func captureIncrementalSample() {
        guard let session = activeSession,
              session.phase == .running,
              let pipeline = incrementalPipeline,
              incrementalProcessingSessionID == nil else {
            return
        }

        do {
            let screenshot = try captureRegion(session.selection.rect)
            guard let image = screenshot.image.cgImage(
                forProposedRect: nil,
                context: nil,
                hints: nil
            ) else {
                throw ScrollingScreenshotStitchingError.outputEncodingFailed
            }
            let scale = CGFloat(image.width) / max(screenshot.image.size.width, 1)
            let processingFrame = ScrollingScreenshotProcessingFrame(
                image: image,
                scale: scale,
                rect: screenshot.rect
            )
            incrementalProcessingSessionID = session.id
            let input = ScrollingScreenshotIncrementalIngestInput(
                pipeline: pipeline,
                frame: processingFrame,
                sessionID: session.id
            )
            let work = Self.incrementalIngestWork(input: input) { [weak self] result, sessionID in
                self?.completeIncrementalSample(result, sessionID: sessionID)
            }
            performStitch(work)
        } catch {
            finishSession()
            session.onFailure(error)
        }
    }

    private func completeIncrementalSample(
        _ result: Result<ScrollingScreenshotProcessedSample, Error>,
        sessionID: UUID
    ) {
        guard var session = activeSession,
              session.id == sessionID,
              incrementalProcessingSessionID == sessionID else {
            return
        }
        incrementalProcessingSessionID = nil

        switch result {
        case let .success(sample):
            session.processedSampleCount += 1
            activeSession = session
            applyIncrementalProgress(sample, sessionID: sessionID)
            guard let currentSession = activeSession,
                  currentSession.id == sessionID else {
                return
            }
            if currentSession.phase == .finishing {
                scheduleIncrementalFinalization(for: currentSession)
            } else {
                advanceIncrementalCapture(after: sample.progress, sessionID: sessionID)
            }
        case let .failure(error):
            session.isAutoScrollingEnabled = false
            activeSession = session
            previewPresenter?.update(image: nil, status: .unreliableOverlap)
            updateHUDControls()
            if session.phase == .finishing {
                if session.processedSampleCount > 0 {
                    scheduleIncrementalFinalization(for: session)
                } else {
                    resumeAfterFinalStitchFailure(error, sessionID: sessionID)
                }
            } else if error as? ScrollingScreenshotStitchingError != .resourceLimitExceeded {
                scheduleNextIncrementalSample()
            }
        }
    }

    private func applyIncrementalProgress(
        _ sample: ScrollingScreenshotProcessedSample,
        sessionID: UUID
    ) {
        let status: ScrollingScreenshotPreviewStatus
        switch sample.progress.state {
        case .initialized, .appended:
            status = .capturing
        case .noProgress, .historicalRepeat:
            status = .noNewContent
        case .unreliableOverlap:
            status = .unreliableOverlap
        }

        previewPresenter?.update(image: sample.previewImage, status: status)
        if let previewImage = sample.previewImage {
            lastPreviewPixelHeight = sample.progress.totalPixelHeight
            publishPreview(
                image: previewImage,
                pixelHeight: sample.progress.totalPixelHeight,
                sessionID: sessionID
            )
        }
    }

    private func advanceIncrementalCapture(
        after progress: ScrollingScreenshotIngestResult,
        sessionID: UUID
    ) {
        guard var session = activeSession,
              session.id == sessionID,
              session.phase == .running else {
            return
        }

        guard session.isAutoScrollingEnabled else {
            scheduleNextIncrementalSample()
            return
        }

        switch progress.state {
        case .initialized, .appended:
            session.consecutiveAutoScrollNoProgressSamples = 0
            session.autoScrollFraction = Self.autoScrollFraction(for: progress.confidence)
            activeSession = session
            postIncrementalAutoScrollAndScheduleCapture(sessionID: sessionID)
        case .noProgress:
            session.consecutiveAutoScrollNoProgressSamples += 1
            if session.consecutiveAutoScrollNoProgressSamples >= maximumConsecutiveIncrementalNoProgressSamples {
                session.isAutoScrollingEnabled = false
            }
            activeSession = session
            updateHUDControls()
            scheduleNextIncrementalSample()
        case .historicalRepeat, .unreliableOverlap:
            session.isAutoScrollingEnabled = false
            activeSession = session
            updateHUDControls()
            scheduleNextIncrementalSample()
        }
    }

    private func postIncrementalAutoScrollAndScheduleCapture(sessionID: UUID) {
        guard var session = activeSession,
              session.id == sessionID,
              session.phase == .running,
              session.isAutoScrollingEnabled else {
            return
        }

        if session.completedScrollSteps >= maximumScrollSteps {
            session.isAutoScrollingEnabled = false
            activeSession = session
            updateHUDControls()
            scheduleNextIncrementalSample()
            return
        }

        scrollRegionWithFraction(session.selection.rect, session.autoScrollFraction)
        session.completedScrollSteps += 1
        activeSession = session
        updateHUDControls()
        scheduleNextIncrementalSample()
    }

    private func scheduleNextIncrementalSample() {
        scheduledStepGeneration += 1
        let generation = scheduledStepGeneration
        scheduleStep(stepDelay) { [weak self] in
            guard let self,
                  self.scheduledStepGeneration == generation else {
                return
            }
            self.captureIncrementalSample()
        }
    }

    private func scheduleIncrementalFinalization(for session: ScrollingScreenshotSession) {
        guard let pipeline = incrementalPipeline else {
            resumeAfterFinalStitchFailure(
                ScrollingScreenshotStitchingError.insufficientFrames,
                sessionID: session.id
            )
            return
        }

        let input = ScrollingScreenshotIncrementalFinalizationInput(
            pipeline: pipeline,
            outputID: session.outputID,
            sessionID: session.id
        )
        let work = Self.incrementalFinalizationWork(input: input) { [weak self] result, sessionID in
            self?.completeFinalStitch(result, sessionID: sessionID)
        }
        performStitch(work)
    }

    private func captureInitialSampleAndSchedule() {
        guard var session = activeSession else {
            return
        }

        do {
            let screenshot = try captureRegion(session.selection.rect)
            session.samples.append(screenshot)
            activeSession = session
            requestPreviewUpdate(for: session.samples, sessionID: session.id)
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
            requestPreviewUpdate(for: session.samples, sessionID: session.id)

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
        previewRenderGeneration += 1
        isPreviewRendering = false
        pendingPreviewSamples = nil
        previewPresenter?.close()
        closeInterface()
        incrementalPipeline = nil
        incrementalProcessingSessionID = nil
        activeSession = nil
    }

    private func completeFinalStitch(
        _ result: Result<CapturedScreenshot, Error>,
        sessionID: UUID
    ) {
        switch result {
        case let .success(screenshot):
            completeFinalScreenshot(screenshot, sessionID: sessionID)
        case let .failure(error):
            resumeAfterFinalStitchFailure(error, sessionID: sessionID)
        }
    }

    private func completeFinalScreenshot(_ screenshot: CapturedScreenshot, sessionID: UUID) {
        guard let session = activeSession,
              session.id == sessionID,
              session.phase == .finishing else {
            return
        }

        let completedScreenshot = CapturedScreenshot(
            id: session.outputID,
            pngData: screenshot.pngData,
            image: screenshot.image,
            rect: screenshot.rect
        )
        finishSession()
        session.onComplete(completedScreenshot)
    }

    private func resumeAfterFinalStitchFailure(_ error: Error, sessionID: UUID) {
        guard var session = activeSession,
              session.id == sessionID,
              session.phase == .finishing else {
            return
        }

        session.phase = .running
        activeSession = session
        restoreInterfaceAfterFinalizationFailure(for: session)
        previewPresenter?.show(selectionRect: session.selection.rect)
        previewPresenter?.update(image: session.latestPreview?.image, status: .unreliableOverlap)
        if incrementalPipeline != nil {
            scheduleNextIncrementalSample()
        } else {
            scheduleNextSample()
        }
        session.onRetryableFailure(error)
    }

    private func requestPreviewUpdate(
        for samples: [CapturedScreenshot],
        sessionID: UUID
    ) {
        guard let latestSample = samples.last else {
            return
        }

        if samples.count == 1 {
            let pixelHeight = Self.pixelHeight(of: latestSample)
            lastPreviewPixelHeight = pixelHeight
            previewPresenter?.update(image: latestSample.image, status: .capturing)
            publishPreview(image: latestSample.image, pixelHeight: pixelHeight, sessionID: sessionID)
            return
        }

        pendingPreviewSamples = samples
        startPendingPreviewRender(sessionID: sessionID)
    }

    private func startPendingPreviewRender(sessionID: UUID) {
        guard !isPreviewRendering,
              let samples = pendingPreviewSamples else {
            return
        }

        pendingPreviewSamples = nil
        isPreviewRendering = true
        let generation = previewRenderGeneration
        if usesDefaultPreviewPipeline {
            Self.scheduleDefaultPreviewStitch(samples) { [weak self] result in
                self?.completePreviewRender(
                    result,
                    sessionID: sessionID,
                    generation: generation
                )
            }
            return
        }

        let stitchPreview = stitchPreview
        performPreviewStitch {
            let result = Result { try stitchPreview(samples) }
            DispatchQueue.main.async { [weak self] in
                self?.completePreviewRender(
                    result,
                    sessionID: sessionID,
                    generation: generation
                )
            }
        }
    }

    private func completePreviewRender(
        _ result: Result<ScrollingScreenshotPreviewSnapshot, Error>,
        sessionID: UUID,
        generation: Int
    ) {
        guard activeSession?.id == sessionID,
              previewRenderGeneration == generation else {
            return
        }

        isPreviewRendering = false
        switch result {
        case let .success(snapshot):
            let status: ScrollingScreenshotPreviewStatus = snapshot.pixelHeight > lastPreviewPixelHeight
                ? .capturing
                : .noNewContent
            lastPreviewPixelHeight = max(lastPreviewPixelHeight, snapshot.pixelHeight)
            previewPresenter?.update(image: snapshot.image, status: status)
            publishPreview(image: snapshot.image, pixelHeight: snapshot.pixelHeight, sessionID: sessionID)
            updateAutoScrollProgress(status, sessionID: sessionID)
        case let .failure(error):
            let status: ScrollingScreenshotPreviewStatus = error as? ScrollingScreenshotStitchingError == .noScrollProgress
                ? .noNewContent
                : .unreliableOverlap
            previewPresenter?.update(image: nil, status: status)
            updateAutoScrollProgress(status, sessionID: sessionID)
        }

        startPendingPreviewRender(sessionID: sessionID)
    }

    private func updateAutoScrollProgress(
        _ status: ScrollingScreenshotPreviewStatus,
        sessionID: UUID
    ) {
        guard var session = activeSession,
              session.id == sessionID,
              session.isAutoScrollingEnabled else {
            return
        }

        switch status {
        case .capturing:
            session.consecutiveAutoScrollNoProgressSamples = 0
        case .noNewContent:
            session.consecutiveAutoScrollNoProgressSamples += 1
            if session.consecutiveAutoScrollNoProgressSamples >= maximumConsecutiveAutoScrollNoProgressSamples {
                session.isAutoScrollingEnabled = false
            }
        case .waiting, .unreliableOverlap:
            break
        }

        activeSession = session
        updateHUDControls()
    }

    private func publishPreview(image: NSImage, pixelHeight: Int, sessionID: UUID) {
        guard var session = activeSession,
              session.id == sessionID else {
            return
        }

        let imageWidth = max(image.size.width, 1)
        let imageHeight = max(image.size.height, 1)
        let previewSize = CGSize(
            width: imageWidth * CGFloat(pixelHeight) / imageHeight,
            height: CGFloat(pixelHeight)
        )
        let preview = CapturedScreenshot(
            id: session.outputID,
            pngData: Data(),
            image: image,
            rect: CGRect(origin: session.selection.rect.origin, size: previewSize)
        )
        session.latestPreview = preview
        activeSession = session
        session.onPreviewUpdate(preview)
    }

    private static func pixelHeight(of screenshot: CapturedScreenshot) -> Int {
        screenshot.image.cgImage(forProposedRect: nil, context: nil, hints: nil)?.height
            ?? Int(screenshot.image.size.height.rounded())
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

    private func hideInterfaceForFinalization() {
        closeInterface()
    }

    private func restoreInterfaceAfterFinalizationFailure(for session: ScrollingScreenshotSession) {
        guard showsInterface else {
            return
        }

        showInterface(selection: session.selection, strings: session.strings)
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
        case .finishing:
            return
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

    nonisolated private static func incrementalIngestWork(
        input: ScrollingScreenshotIncrementalIngestInput,
        completion: @escaping @MainActor @Sendable (
            Result<ScrollingScreenshotProcessedSample, Error>,
            UUID
        ) -> Void
    ) -> @Sendable () -> Void {
        {
            let output = ScrollingScreenshotIncrementalIngestOutput(
                result: Result {
                    try input.pipeline.ingest(input.frame)
                }
            )
            Task { @MainActor in
                completion(output.result, input.sessionID)
            }
        }
    }

    nonisolated private static func incrementalFinalizationWork(
        input: ScrollingScreenshotIncrementalFinalizationInput,
        completion: @escaping @MainActor @Sendable (
            Result<CapturedScreenshot, Error>,
            UUID
        ) -> Void
    ) -> @Sendable () -> Void {
        {
            let output = ScrollingScreenshotIncrementalFinalizationOutput(
                result: Result {
                    try input.pipeline.finish(outputID: input.outputID)
                }
            )
            Task { @MainActor in
                completion(output.result, input.sessionID)
            }
        }
    }

    nonisolated private static func defaultStitch(_ screenshots: [CapturedScreenshot]) throws -> CapturedScreenshot {
        let frames = try scrollingFrames(from: screenshots)
        let stitchedImage = try ScrollingScreenshotStitcher().stitch(frames)
        return try capturedScreenshot(from: stitchedImage, frames: frames, screenshots: screenshots)
    }

    nonisolated private static func defaultRecoveringStitch(_ screenshots: [CapturedScreenshot]) throws -> CapturedScreenshot {
        let frames = try scrollingFrames(from: screenshots)
        let stitchedImage = try ScrollingScreenshotStitcher().stitchRecovering(
            frames,
            maximumSkippedFrames: 2
        )
        return try capturedScreenshot(from: stitchedImage, frames: frames, screenshots: screenshots)
    }

    nonisolated private static func scrollingFrames(
        from screenshots: [CapturedScreenshot]
    ) throws -> [ScrollingScreenshotFrame] {
        guard screenshots.count >= 2 else {
            throw ScrollingScreenshotStitchingError.insufficientFrames
        }

        return try screenshots.map { screenshot in
            guard let image = screenshot.image.cgImage(forProposedRect: nil, context: nil, hints: nil) else {
                throw ScrollingScreenshotStitchingError.outputEncodingFailed
            }

            let scale = image.width > 0 ? CGFloat(image.width) / max(screenshot.image.size.width, 1) : 1
            return ScrollingScreenshotFrame(image: image, scale: scale)
        }
    }

    nonisolated private static func capturedScreenshot(
        from stitchedImage: CGImage,
        frames: [ScrollingScreenshotFrame],
        screenshots: [CapturedScreenshot]
    ) throws -> CapturedScreenshot {
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

    nonisolated private static func defaultPreviewStitch(
        _ screenshots: [CapturedScreenshot]
    ) throws -> ScrollingScreenshotPreviewSnapshot {
        guard screenshots.count >= 2 else {
            throw ScrollingScreenshotStitchingError.insufficientFrames
        }

        var previewScale: CGFloat = 1
        let frames = try screenshots.map { screenshot in
            guard let sourceImage = screenshot.image.cgImage(forProposedRect: nil, context: nil, hints: nil) else {
                throw ScrollingScreenshotStitchingError.outputEncodingFailed
            }
            let scale = min(1, CGFloat(previewMaximumPixelWidth) / CGFloat(max(sourceImage.width, 1)))
            previewScale = min(previewScale, scale)
            let image = scale < 1
                ? try downsample(sourceImage, scale: scale)
                : sourceImage
            return ScrollingScreenshotFrame(image: image, scale: 1)
        }
        let stitcher = ScrollingScreenshotStitcher()
        let stitchedImage: CGImage
        do {
            stitchedImage = try stitcher.stitch(frames)
        } catch {
            do {
                stitchedImage = try stitcher.stitchRecovering(frames, maximumSkippedFrames: 2)
            } catch {
                stitchedImage = try stitchPreviewByRemovingOneInterruptedFrame(frames, stitcher: stitcher)
            }
        }
        let image = NSImage(
            cgImage: stitchedImage,
            size: CGSize(width: stitchedImage.width, height: stitchedImage.height)
        )
        return ScrollingScreenshotPreviewSnapshot(
            image: image,
            pixelHeight: Int((CGFloat(stitchedImage.height) / max(previewScale, 0.001)).rounded())
        )
    }

    nonisolated private static func stitchPreviewByRemovingOneInterruptedFrame(
        _ frames: [ScrollingScreenshotFrame],
        stitcher: ScrollingScreenshotStitcher
    ) throws -> CGImage {
        guard frames.count >= 3 else {
            throw ScrollingScreenshotStitchingError.noReliableOverlap
        }

        for skippedIndex in frames.indices.dropFirst().dropLast().reversed() {
            var candidateFrames = frames
            candidateFrames.remove(at: skippedIndex)
            if let image = try? stitcher.stitch(candidateFrames) {
                return image
            }
        }

        throw ScrollingScreenshotStitchingError.noReliableOverlap
    }

    nonisolated private static func scheduleDefaultPreviewStitch(
        _ screenshots: [CapturedScreenshot],
        completion: @escaping @MainActor @Sendable (Result<ScrollingScreenshotPreviewSnapshot, Error>) -> Void
    ) {
        let input = ScrollingScreenshotPreviewInput(screenshots: screenshots)
        DispatchQueue.global(qos: .userInitiated).async {
            let result = Result { try defaultPreviewStitch(input.screenshots) }
            Task { @MainActor in
                completion(result)
            }
        }
    }

    nonisolated private static func scheduleDefaultFinalStitch(
        _ screenshots: [CapturedScreenshot],
        completion: @escaping @MainActor @Sendable (Result<CapturedScreenshot, Error>) -> Void
    ) {
        let input = ScrollingScreenshotFinalInput(screenshots: screenshots)
        DispatchQueue.global(qos: .userInitiated).async {
            let result = Result<CapturedScreenshot, Error> {
                do {
                    return try defaultStitch(input.screenshots)
                } catch {
                    return try defaultRecoveringStitch(input.screenshots)
                }
            }
            Task { @MainActor in
                completion(result)
            }
        }
    }

    nonisolated private static func downsample(_ image: CGImage, scale: CGFloat) throws -> CGImage {
        let width = max(1, Int((CGFloat(image.width) * scale).rounded()))
        let height = max(1, Int((CGFloat(image.height) * scale).rounded()))
        guard let context = CGContext(
            data: nil,
            width: width,
            height: height,
            bitsPerComponent: 8,
            bytesPerRow: width * 4,
            space: CGColorSpaceCreateDeviceRGB(),
            bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue
        ) else {
            throw ScrollingScreenshotStitchingError.outputEncodingFailed
        }

        context.interpolationQuality = .medium
        context.draw(image, in: CGRect(x: 0, y: 0, width: width, height: height))
        guard let downsampledImage = context.makeImage() else {
            throw ScrollingScreenshotStitchingError.outputEncodingFailed
        }
        return downsampledImage
    }

    private static func defaultScroll(_ rect: CGRect, scrollFraction: CGFloat) {
        let currentMouseLocation = CGEvent(source: nil)?.location
        guard let event = CGEvent(
            scrollWheelEvent2Source: nil,
            units: .pixel,
            wheelCount: 1,
            wheel1: -scrollWheelDelta(for: rect, scrollFraction: scrollFraction),
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

    private static func scrollWheelDelta(
        for rect: CGRect,
        scrollFraction: CGFloat = 0.22
    ) -> Int32 {
        Int32(max(24, rect.height * min(max(scrollFraction, 0.08), 0.28)))
    }

    private static func autoScrollFraction(for confidence: Double) -> CGFloat {
        if confidence >= 0.9 {
            return 0.22
        }
        if confidence >= 0.7 {
            return 0.16
        }
        return 0.1
    }

    private static func defaultScheduleStep(after delay: TimeInterval, _ step: @escaping @MainActor @Sendable () -> Void) {
        Timer.scheduledTimer(withTimeInterval: delay, repeats: false) { _ in
            Task { @MainActor in
                step()
            }
        }
    }

    nonisolated private static func defaultPerformStitch(_ work: @escaping () -> Void) {
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

    func hudPanelExistsForTesting() -> Bool {
        hudPanel != nil
    }

    func hudPanelIsVisibleForTesting() -> Bool {
        hudPanel?.isVisible ?? false
    }

    func isAutoScrollingEnabledForTesting() -> Bool {
        activeSession?.isAutoScrollingEnabled ?? false
    }

    func usesIncrementalPipelineForTesting() -> Bool {
        incrementalPipeline != nil
    }

    func clickFinishButtonForTesting() {
        let button = hudStackView?.arrangedSubviews
            .compactMap { $0 as? NSButton }
            .first { $0.identifier?.rawValue == "checkmark" }
        button?.performClick(nil)
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
    private nonisolated static let previewMaximumPixelWidth = 440
}

struct ScrollingScreenshotPreviewSnapshot: @unchecked Sendable {
    let image: NSImage
    let pixelHeight: Int
}

// CapturedScreenshot contains NSImage, which is not Sendable. The preview worker
// receives an immutable session snapshot and only reads its image representations.
private struct ScrollingScreenshotPreviewInput: @unchecked Sendable {
    let screenshots: [CapturedScreenshot]
}

private struct ScrollingScreenshotFinalInput: @unchecked Sendable {
    let screenshots: [CapturedScreenshot]
}

private struct ScrollingScreenshotIncrementalIngestInput: Sendable {
    let pipeline: any ScrollingScreenshotIncrementalProcessing
    let frame: ScrollingScreenshotProcessingFrame
    let sessionID: UUID
}

private struct ScrollingScreenshotIncrementalIngestOutput: @unchecked Sendable {
    let result: Result<ScrollingScreenshotProcessedSample, Error>
}

private struct ScrollingScreenshotIncrementalFinalizationInput: Sendable {
    let pipeline: any ScrollingScreenshotIncrementalProcessing
    let outputID: UUID
    let sessionID: UUID
}

private struct ScrollingScreenshotIncrementalFinalizationOutput: @unchecked Sendable {
    let result: Result<CapturedScreenshot, Error>
}

private struct ScrollingScreenshotSession {
    let id = UUID()
    let outputID = UUID()
    let selection: SelectionCapture
    let strings: AppStrings
    let onPreviewUpdate: (CapturedScreenshot) -> Void
    let onFinishStarted: (CapturedScreenshot?) -> Void
    let onComplete: (CapturedScreenshot) -> Void
    let onCancel: () -> Void
    let onRetryableFailure: (Error) -> Void
    let onFailure: (Error) -> Void
    var phase: ScrollingScreenshotSessionPhase = .waiting
    var samples: [CapturedScreenshot] = []
    var latestPreview: CapturedScreenshot?
    var processedSampleCount = 0
    var completedScrollSteps = 0
    var isAutoScrollingEnabled = false
    var consecutiveAutoScrollNoProgressSamples = 0
    var autoScrollFraction: CGFloat = 0.16
}

private enum ScrollingScreenshotSessionPhase {
    case waiting
    case running
    case finishing
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

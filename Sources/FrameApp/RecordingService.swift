import AppKit
import CoreMedia
import FrameCore
@preconcurrency import ScreenCaptureKit

struct CapturedRecording: Equatable, Identifiable, Sendable {
    let id: UUID
    let fileURL: URL
    let format: RecordingFormat
    let rect: CGRect
    let pixelSize: CGSize
    let byteSize: Int
    let duration: TimeInterval
}

struct RecordingRequest: Equatable, @unchecked Sendable {
    let selection: SelectionCapture
    let options: RecordingOptions
}

enum RecordingSessionState: Equatable, Sendable {
    case recording
    case paused
    case finishing
    case finished
    case failed(String)
}

protocol RecordingSessionControlling: AnyObject, Sendable {
    var state: RecordingSessionState { get }

    func pause() async throws
    func resume() async throws
    func stop() async throws -> CapturedRecording
    func cancel() async
}

protocol RecordingServicing: Sendable {
    func startRecording(_ request: RecordingRequest) async throws -> RecordingSessionControlling
}

struct RecordingDisplaySelection: Equatable {
    let displayID: CGDirectDisplayID
    let screenFrame: CGRect
    let selectionRect: CGRect
}

struct RecordingScreen: Equatable {
    let displayID: CGDirectDisplayID
    let frame: CGRect
}

enum RecordingServiceError: LocalizedError {
    case invalidSelectionRect(CGRect)
    case selectionSpansMultipleDisplays
    case displayNotFound
    case outputFailed(String)

    var errorDescription: String? {
        switch self {
        case let .invalidSelectionRect(rect):
            "录屏区域无效：\(rect.debugDescription)"
        case .selectionSpansMultipleDisplays:
            "录屏区域只能位于一个显示器内。请重新选择一个屏幕上的区域。"
        case .displayNotFound:
            "无法找到要录制的显示器。"
        case let .outputFailed(message):
            message
        }
    }
}

enum RecordingDisplayResolver {
    static func resolve(selection: CGRect, screenFrames: [CGRect]) throws -> RecordingDisplaySelection {
        try resolve(
            selection: selection,
            screens: screenFrames.map { RecordingScreen(displayID: 0, frame: $0) }
        )
    }

    static func resolve(selection: CGRect, screens: [RecordingScreen]) throws -> RecordingDisplaySelection {
        guard !selection.isNull,
              !selection.isEmpty,
              selection.width > 0,
              selection.height > 0 else {
            throw RecordingServiceError.invalidSelectionRect(selection)
        }

        let intersectingScreens = screens.filter { screen in
            let intersection = screen.frame.intersection(selection)
            return !intersection.isNull && !intersection.isEmpty
        }

        guard intersectingScreens.count == 1,
              let screen = intersectingScreens.first else {
            throw intersectingScreens.isEmpty
                ? RecordingServiceError.displayNotFound
                : RecordingServiceError.selectionSpansMultipleDisplays
        }

        guard screen.frame.contains(selection) else {
            throw RecordingServiceError.selectionSpansMultipleDisplays
        }

        return RecordingDisplaySelection(displayID: screen.displayID, screenFrame: screen.frame, selectionRect: selection)
    }
}

enum RecordingPixelDimensions {
    static func normalizedForVideo(_ size: CGSize) -> CGSize {
        CGSize(
            width: max(2, Int(size.width.rounded()).roundedDownToEven),
            height: max(2, Int(size.height.rounded()).roundedDownToEven)
        )
    }
}

final class ScreenCaptureRecordingService: RecordingServicing {
    func startRecording(_ request: RecordingRequest) async throws -> RecordingSessionControlling {
        let resolvedSelection = try RecordingDisplayResolver.resolve(
            selection: request.selection.rect,
            screens: NSScreen.screens.map { screen in
                RecordingScreen(displayID: displayID(for: screen), frame: screen.frame)
            }
        )
        let session = try await ScreenCaptureRecordingSession(
            request: request,
            resolvedSelection: resolvedSelection
        )
        try await session.start()
        return session
    }

    private func displayID(for screen: NSScreen) -> CGDirectDisplayID {
        let key = NSDeviceDescriptionKey("NSScreenNumber")
        return (screen.deviceDescription[key] as? NSNumber).map { CGDirectDisplayID($0.uint32Value) } ?? 0
    }
}

final class ScreenCaptureRecordingSession: NSObject, RecordingSessionControlling, @unchecked Sendable {
    private let request: RecordingRequest
    private let resolvedSelection: RecordingDisplaySelection
    private let sampleQueue = DispatchQueue(label: "dev.dewey.frame.recording.samples")
    private let stateLock = NSLock()
    private var stream: SCStream?
    private var encoder: RecordingFrameEncoding?
    private var outputURL: URL?
    private var overlayRenderer: RecordingOverlayRenderer?
    private var overlayEventMonitors: [Any] = []
    private var liveOverlayController: RecordingLiveOverlayController!
    private var startedAt = Date()
    private var isPaused = false
    private(set) var state: RecordingSessionState = .recording

    init(request: RecordingRequest, resolvedSelection: RecordingDisplaySelection) async throws {
        self.request = request
        self.resolvedSelection = resolvedSelection
        super.init()
        self.liveOverlayController = await MainActor.run {
            RecordingLiveOverlayController()
        }
    }

    func start() async throws {
        let pixelSize = normalizedRecordingPixelSize(for: resolvedSelection.selectionRect)
        let overlayConfiguration = RecordingOverlayConfiguration(options: request.options)
        let overlayEventStore: RecordingOverlayEventStore?
        let liveOverlayWindowNumber: Int?
        if overlayConfiguration.isEnabled {
            let eventStore = RecordingOverlayEventStore()
            overlayEventStore = eventStore
            overlayRenderer = RecordingOverlayRenderer(eventStore: eventStore, pixelSize: pixelSize)
            liveOverlayWindowNumber = await MainActor.run {
                liveOverlayController.show(
                    screenFrame: resolvedSelection.screenFrame,
                    selectionRect: resolvedSelection.selectionRect,
                    pixelSize: pixelSize,
                    eventStore: eventStore
                )
                return liveOverlayController.windowNumber
            }
        } else {
            overlayEventStore = nil
            overlayRenderer = nil
            liveOverlayWindowNumber = nil
        }

        do {
            let content = try await SCShareableContent.excludingDesktopWindows(false, onScreenWindowsOnly: true)
            guard let display = content.displays.first(where: { $0.displayID == resolvedSelection.displayID && resolvedSelection.displayID != 0 })
                ?? content.displays.first(where: { $0.frame.equalTo(resolvedSelection.screenFrame) })
                ?? content.displays.first(where: { !$0.frame.intersection(resolvedSelection.screenFrame).isNull })
                ?? content.displays.first else {
                throw RecordingServiceError.displayNotFound
            }

            let outputURL = makeTemporaryOutputURL(format: request.options.format)
            let encoder: RecordingFrameEncoding = switch request.options.format {
            case .mp4:
                try MP4RecordingFrameEncoder(outputURL: outputURL, pixelSize: pixelSize)
            case .gif:
                try GIFRecordingFrameEncoder(outputURL: outputURL)
            }

            let configuration = SCStreamConfiguration()
            configuration.width = Int(pixelSize.width)
            configuration.height = Int(pixelSize.height)
            configuration.sourceRect = sourceRect(for: resolvedSelection)
            configuration.queueDepth = 6
            configuration.minimumFrameInterval = CMTime(value: 1, timescale: 30)
            configuration.showsCursor = request.options.showsCursor
            configuration.capturesAudio = false
            configuration.pixelFormat = kCVPixelFormatType_32BGRA

            let excludedWindows = content.windows.filter { window in
                RecordingOverlayCaptureExclusion.shouldExclude(
                    windowID: window.windowID,
                    liveOverlayWindowNumber: liveOverlayWindowNumber
                )
            }
            let filter = SCContentFilter(display: display, excludingWindows: excludedWindows)
            let stream = SCStream(filter: filter, configuration: configuration, delegate: self)
            try stream.addStreamOutput(self, type: .screen, sampleHandlerQueue: sampleQueue)
            try await stream.startCapture()

            self.stream = stream
            self.encoder = encoder
            self.outputURL = outputURL
            startedAt = Date()
            if let overlayEventStore {
                await MainActor.run {
                    installOverlayEventMonitors(
                        configuration: overlayConfiguration,
                        eventStore: overlayEventStore,
                        pixelSize: pixelSize
                    )
                }
            }
            setState(.recording)
        } catch {
            await MainActor.run {
                removeOverlayEventMonitors()
                liveOverlayController.close()
            }
            overlayRenderer = nil
            throw error
        }
    }

    func pause() async throws {
        stateLock.withLock {
            isPaused = true
            state = .paused
        }
    }

    func resume() async throws {
        stateLock.withLock {
            isPaused = false
            state = .recording
        }
    }

    func stop() async throws -> CapturedRecording {
        setState(.finishing)
        await MainActor.run {
            removeOverlayEventMonitors()
            liveOverlayController.close()
        }
        if let stream {
            try await stream.stopCapture()
        }
        guard let encoder else {
            throw RecordingServiceError.outputFailed("录屏会话没有可写入的输出。")
        }

        let finalizedURL = try await encoder.finish()
        let byteSize = (try? FileManager.default.attributesOfItem(atPath: finalizedURL.path)[.size] as? NSNumber)?.intValue ?? 0
        setState(.finished)
        return CapturedRecording(
            id: UUID(),
            fileURL: finalizedURL,
            format: request.options.format,
            rect: request.selection.rect,
            pixelSize: normalizedRecordingPixelSize(for: resolvedSelection.selectionRect),
            byteSize: byteSize,
            duration: max(0, Date().timeIntervalSince(startedAt))
        )
    }

    func cancel() async {
        await MainActor.run {
            removeOverlayEventMonitors()
            liveOverlayController.close()
        }
        try? await stream?.stopCapture()
        setState(.finished)
    }

    private func setState(_ state: RecordingSessionState) {
        stateLock.withLock {
            self.state = state
        }
    }

    private func makeTemporaryOutputURL(format: RecordingFormat) -> URL {
        FileManager.default.temporaryDirectory
            .appendingPathComponent("Frame-\(UUID().uuidString)", isDirectory: false)
            .appendingPathExtension(format.fileExtension)
    }

    private func sourceRect(for selection: RecordingDisplaySelection) -> CGRect {
        CGRect(
            x: selection.selectionRect.minX - selection.screenFrame.minX,
            y: selection.screenFrame.maxY - selection.selectionRect.maxY,
            width: selection.selectionRect.width,
            height: selection.selectionRect.height
        )
    }

    private func recordingPixelSize(for rect: CGRect) -> CGSize {
        let scale = NSScreen.screens.first { $0.frame.intersects(rect) }?.backingScaleFactor
            ?? NSScreen.main?.backingScaleFactor
            ?? 1
        return CGSize(width: rect.width * scale, height: rect.height * scale)
    }

    private func normalizedRecordingPixelSize(for rect: CGRect) -> CGSize {
        RecordingPixelDimensions.normalizedForVideo(recordingPixelSize(for: rect))
    }

    @MainActor
    private func installOverlayEventMonitors(
        configuration: RecordingOverlayConfiguration,
        eventStore: RecordingOverlayEventStore,
        pixelSize: CGSize
    ) {
        removeOverlayEventMonitors()

        if configuration.recordsMouseClicks {
            let mouseMonitor = NSEvent.addGlobalMonitorForEvents(
                matching: [.leftMouseDown, .rightMouseDown, .otherMouseDown]
            ) { [weak self, weak eventStore] event in
                guard let self, let eventStore else {
                    return
                }

                let screenPoint = NSEvent.mouseLocation
                guard self.resolvedSelection.selectionRect.contains(screenPoint) else {
                    return
                }

                eventStore.recordClick(
                    at: RecordingOverlayCoordinateMapper.pixelPoint(
                        screenPoint: screenPoint,
                        selectionRect: self.resolvedSelection.selectionRect,
                        pixelSize: pixelSize
                    ),
                    time: event.timestamp
                )
            }
            if let mouseMonitor {
                overlayEventMonitors.append(mouseMonitor)
            }
        }

        if configuration.recordsKeyboardHints {
            let keyHandler: (NSEvent) -> Void = { [weak eventStore] event in
                eventStore?.recordKey(
                    label: RecordingOverlayKeyFormatter.label(
                        charactersIgnoringModifiers: event.charactersIgnoringModifiers,
                        modifierFlags: event.modifierFlags
                    ),
                    time: event.timestamp
                )
            }
            if let globalKeyMonitor = NSEvent.addGlobalMonitorForEvents(matching: .keyDown, handler: keyHandler) {
                overlayEventMonitors.append(globalKeyMonitor)
            }
            if let localKeyMonitor = NSEvent.addLocalMonitorForEvents(
                matching: .keyDown,
                handler: { event in
                    keyHandler(event)
                    return event
                }
            ) {
                overlayEventMonitors.append(localKeyMonitor)
            }
        }
    }

    @MainActor
    private func removeOverlayEventMonitors() {
        for monitor in overlayEventMonitors {
            NSEvent.removeMonitor(monitor)
        }
        overlayEventMonitors.removeAll()
    }
}

private extension Int {
    var roundedDownToEven: Int {
        self - (self % 2)
    }
}

extension ScreenCaptureRecordingSession: SCStreamOutput, SCStreamDelegate {
    func stream(_ stream: SCStream, didOutputSampleBuffer sampleBuffer: CMSampleBuffer, of type: SCStreamOutputType) {
        guard type == .screen else {
            return
        }

        let shouldAppend = stateLock.withLock {
            !isPaused && state == .recording
        }
        guard shouldAppend else {
            return
        }

        do {
            try encoder?.append(sampleBuffer, overlayRenderer: overlayRenderer)
        } catch {
            setState(.failed(error.localizedDescription))
        }
    }

    func stream(_ stream: SCStream, didStopWithError error: Error) {
        Task { @MainActor [weak self] in
            self?.removeOverlayEventMonitors()
            self?.liveOverlayController.close()
        }
        setState(.failed(error.localizedDescription))
    }
}

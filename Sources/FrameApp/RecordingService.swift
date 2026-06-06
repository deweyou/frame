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
    let screenFrame: CGRect
    let selectionRect: CGRect
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
        guard !selection.isNull,
              !selection.isEmpty,
              selection.width > 0,
              selection.height > 0 else {
            throw RecordingServiceError.invalidSelectionRect(selection)
        }

        let intersectingScreens = screenFrames.filter { screenFrame in
            let intersection = screenFrame.intersection(selection)
            return !intersection.isNull && !intersection.isEmpty
        }

        guard intersectingScreens.count == 1,
              let screenFrame = intersectingScreens.first else {
            throw intersectingScreens.isEmpty
                ? RecordingServiceError.displayNotFound
                : RecordingServiceError.selectionSpansMultipleDisplays
        }

        guard screenFrame.contains(selection) else {
            throw RecordingServiceError.selectionSpansMultipleDisplays
        }

        return RecordingDisplaySelection(screenFrame: screenFrame, selectionRect: selection)
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
            screenFrames: NSScreen.screens.map(\.frame)
        )
        let session = try await ScreenCaptureRecordingSession(
            request: request,
            resolvedSelection: resolvedSelection
        )
        try await session.start()
        return session
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
    private var startedAt = Date()
    private var isPaused = false
    private(set) var state: RecordingSessionState = .recording

    init(request: RecordingRequest, resolvedSelection: RecordingDisplaySelection) async throws {
        self.request = request
        self.resolvedSelection = resolvedSelection
        super.init()
    }

    func start() async throws {
        let content = try await SCShareableContent.excludingDesktopWindows(false, onScreenWindowsOnly: true)
        guard let display = content.displays.first(where: { $0.frame.equalTo(resolvedSelection.screenFrame) })
            ?? content.displays.first(where: { !$0.frame.intersection(resolvedSelection.screenFrame).isNull })
            ?? content.displays.first else {
            throw RecordingServiceError.displayNotFound
        }

        let pixelSize = normalizedRecordingPixelSize(for: resolvedSelection.selectionRect)
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

        let filter = SCContentFilter(display: display, excludingWindows: [])
        let stream = SCStream(filter: filter, configuration: configuration, delegate: self)
        try stream.addStreamOutput(self, type: .screen, sampleHandlerQueue: sampleQueue)
        try await stream.startCapture()

        self.stream = stream
        self.encoder = encoder
        self.outputURL = outputURL
        startedAt = Date()
        setState(.recording)
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
            try encoder?.append(sampleBuffer)
        } catch {
            setState(.failed(error.localizedDescription))
        }
    }

    func stream(_ stream: SCStream, didStopWithError error: Error) {
        setState(.failed(error.localizedDescription))
    }
}

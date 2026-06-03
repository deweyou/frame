import AppKit
import FrameCore

struct CapturedRecording: Equatable, Identifiable {
    let id: UUID
    let fileURL: URL
    let format: RecordingFormat
    let rect: CGRect
    let pixelSize: CGSize
    let byteSize: Int
    let duration: TimeInterval
}

struct RecordingRequest: Equatable {
    let selection: SelectionCapture
    let options: RecordingOptions
}

enum RecordingSessionState: Equatable {
    case recording
    case paused
    case finishing
    case finished
    case failed(String)
}

protocol RecordingSessionControlling: AnyObject {
    var state: RecordingSessionState { get }

    func pause() async throws
    func resume() async throws
    func stop() async throws -> CapturedRecording
    func cancel() async
}

protocol RecordingServicing {
    func startRecording(_ request: RecordingRequest) async throws -> RecordingSessionControlling
}

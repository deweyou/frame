import Foundation
import FrameCore

enum SelectionOverlayCompletion {
    case capture(SelectionCapture)
    case recognizeText(SelectionCapture)
    case fullScreen
    case startRecording(SelectionCapture, RecordingOptions)

    var selection: SelectionCapture? {
        switch self {
        case let .capture(selection), let .recognizeText(selection), let .startRecording(selection, _):
            selection
        case .fullScreen:
            nil
        }
    }

    var recordingOptions: RecordingOptions? {
        switch self {
        case let .startRecording(_, options):
            options
        case .capture, .recognizeText, .fullScreen:
            nil
        }
    }
}

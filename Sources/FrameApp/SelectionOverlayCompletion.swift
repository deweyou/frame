import Foundation
import FrameCore

enum SelectionOverlayCompletion {
    case capture(SelectionCapture)
    case recognizeText(SelectionCapture)
    case fullScreen

    var selection: SelectionCapture? {
        switch self {
        case let .capture(selection), let .recognizeText(selection):
            selection
        case .fullScreen:
            nil
        }
    }
}

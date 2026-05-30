import Foundation
import FrameCore

enum SelectionOverlayCompletion {
    case capture(SelectionCapture)
    case recognizeText(SelectionCapture)

    var selection: SelectionCapture {
        switch self {
        case let .capture(selection), let .recognizeText(selection):
            selection
        }
    }
}

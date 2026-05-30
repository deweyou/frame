import XCTest
@testable import FrameApp
@testable import FrameCore

final class SelectionOverlayCompletionTests: XCTestCase {
    func testCaptureCompletionExposesSelection() {
        let selection = SelectionCapture(
            rect: CGRect(x: 10, y: 20, width: 120, height: 80),
            kind: .region
        )

        let completion = SelectionOverlayCompletion.capture(selection)

        XCTAssertEqual(completion.selection.rect, selection.rect)
        XCTAssertEqual(completion.selection.kind, selection.kind)
    }

    func testRecognizeTextCompletionExposesSelection() {
        let selection = SelectionCapture(
            rect: CGRect(x: 10, y: 20, width: 120, height: 80),
            kind: .region
        )

        let completion = SelectionOverlayCompletion.recognizeText(selection)

        XCTAssertEqual(completion.selection.rect, selection.rect)
        XCTAssertEqual(completion.selection.kind, selection.kind)
    }
}

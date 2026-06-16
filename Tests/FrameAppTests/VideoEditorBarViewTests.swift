import XCTest
@testable import FrameApp
@testable import FrameCore

@MainActor
final class VideoEditorBarViewTests: XCTestCase {
    func testEditorBarEmitsTrimChangesFromTimeFields() throws {
        let state = try VideoEditingState(sourceDuration: 24)
        let editorBar = VideoEditorBarView(state: state)
        var emittedState: VideoEditingState?
        editorBar.onStateChanged = { emittedState = $0 }

        editorBar.enterTrimRangeForTesting(start: "00:03.274", end: "18.636")

        let emitted = try XCTUnwrap(emittedState)
        XCTAssertEqual(emitted.startTime, 3.27, accuracy: 0.0001)
        XCTAssertEqual(emitted.endTime, 18.64, accuracy: 0.0001)
    }

    func testEditorBarEmitsSpeedSelection() throws {
        let state = try VideoEditingState(sourceDuration: 24)
        let editorBar = VideoEditorBarView(state: state)
        var emittedState: VideoEditingState?
        editorBar.onStateChanged = { emittedState = $0 }

        editorBar.selectSpeedForTesting(.quadruple)

        XCTAssertEqual(try XCTUnwrap(emittedState).speed, .quadruple)
    }
}

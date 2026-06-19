import XCTest
@testable import FrameCore

final class VideoEditingStateTests: XCTestCase {
    func testSpeedPresetsAreFixedAndDisplayable() {
        XCTAssertEqual(VideoPlaybackSpeed.presets.map(\.rate), [0.5, 1, 1.25, 1.5, 2, 4, 8])
        XCTAssertEqual(VideoPlaybackSpeed.presets.map(\.displayName), ["0.5x", "1x", "1.25x", "1.5x", "2x", "4x", "8x"])
    }

    func testDefaultStateUsesFullDurationAtNormalSpeed() throws {
        let state = try VideoEditingState(sourceDuration: 24)

        XCTAssertEqual(state.startTime, 0, accuracy: 0.0001)
        XCTAssertEqual(state.endTime, 24, accuracy: 0.0001)
        XCTAssertEqual(state.speed, .one)
        XCTAssertEqual(state.selectedDuration, 24, accuracy: 0.0001)
        XCTAssertEqual(state.outputDuration, 24, accuracy: 0.0001)
        XCTAssertFalse(state.isDirty)
    }

    func testUpdatingRangeQuantizesToHundredthSecondAndMarksDirty() throws {
        var state = try VideoEditingState(sourceDuration: 24)

        try state.setTrimRange(start: 1.234, end: 12.345)

        XCTAssertEqual(state.startTime, 1.23, accuracy: 0.0001)
        XCTAssertEqual(state.endTime, 12.35, accuracy: 0.0001)
        XCTAssertEqual(state.selectedDuration, 11.12, accuracy: 0.0001)
        XCTAssertTrue(state.isDirty)
    }

    func testRejectsInvalidRangesAfterQuantization() throws {
        var state = try VideoEditingState(sourceDuration: 24)

        XCTAssertThrowsError(try state.setTrimRange(start: -0.01, end: 10)) { error in
            XCTAssertEqual(error as? VideoEditingStateError, .invalidTrimRange)
        }
        XCTAssertThrowsError(try state.setTrimRange(start: 2, end: 24.01)) { error in
            XCTAssertEqual(error as? VideoEditingStateError, .invalidTrimRange)
        }
        XCTAssertThrowsError(try state.setTrimRange(start: 4, end: 4.04)) { error in
            XCTAssertEqual(error as? VideoEditingStateError, .invalidTrimRange)
        }

        XCTAssertEqual(state.startTime, 0, accuracy: 0.0001)
        XCTAssertEqual(state.endTime, 24, accuracy: 0.0001)
        XCTAssertFalse(state.isDirty)
    }

    func testSpeedChangesOutputDurationAndDirtyState() throws {
        var state = try VideoEditingState(sourceDuration: 24)

        try state.setTrimRange(start: 6, end: 18)
        try state.setSpeed(.quadruple)

        XCTAssertEqual(state.selectedDuration, 12, accuracy: 0.0001)
        XCTAssertEqual(state.outputDuration, 3, accuracy: 0.0001)
        XCTAssertEqual(state.speed, .quadruple)
        XCTAssertTrue(state.isDirty)
    }

    func testRejectsCustomSpeedValues() throws {
        var state = try VideoEditingState(sourceDuration: 24)

        XCTAssertThrowsError(try state.setSpeed(VideoPlaybackSpeed(rate: 100, displayName: "100x"))) { error in
            XCTAssertEqual(error as? VideoEditingStateError, .unsupportedSpeed)
        }

        XCTAssertEqual(state.speed, .one)
        XCTAssertFalse(state.isDirty)
    }
}

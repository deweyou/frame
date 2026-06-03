import XCTest
@testable import FrameCore

final class RecordingOptionsTests: XCTestCase {
    func testDefaultOptionsAreMP4WithCursorAndKeyboardHintsAndNoAudio() {
        let options = RecordingOptions.defaults

        XCTAssertEqual(options.format, .mp4)
        XCTAssertTrue(options.showsCursor)
        XCTAssertTrue(options.showsKeyboardHints)
        XCTAssertEqual(options.audioSource, .none)
    }

    func testPausedElapsedTimeExcludesPausedDuration() {
        var clock = RecordingElapsedClock(startedAt: Date(timeIntervalSince1970: 10))
        clock.pause(at: Date(timeIntervalSince1970: 20))
        clock.resume(at: Date(timeIntervalSince1970: 50))

        XCTAssertEqual(clock.elapsed(at: Date(timeIntervalSince1970: 65)), 25, accuracy: 0.001)
    }
}

import XCTest
@testable import FrameCore

final class RecordingNamingTests: XCTestCase {
    func testFilenameUsesFrameTimestampAndSelectedExtension() {
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = TimeZone(secondsFromGMT: 0)!
        let naming = RecordingNaming(calendar: calendar, timeZone: calendar.timeZone)
        let date = Date(timeIntervalSince1970: 1_717_419_730)

        XCTAssertEqual(naming.filename(for: date, format: .mp4), "Frame 2024-06-03 13.02.10.mp4")
        XCTAssertEqual(naming.filename(for: date, format: .gif), "Frame 2024-06-03 13.02.10.gif")
    }
}

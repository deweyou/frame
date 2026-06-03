import XCTest
@testable import FrameApp
@testable import FrameCore

final class RecordingFileWriterTests: XCTestCase {
    func testCopyRecordingWritesToConfiguredDirectoryWithRecordingName() throws {
        let root = FileManager.default.temporaryDirectory
            .appendingPathComponent("FrameRecordingWriterTests-\(UUID().uuidString)", isDirectory: true)
        let source = root.appendingPathComponent("source.mp4")
        let destination = root.appendingPathComponent("dest", isDirectory: true)
        try FileManager.default.createDirectory(at: root, withIntermediateDirectories: true)
        try FileManager.default.createDirectory(at: destination, withIntermediateDirectories: true)
        try Data([1, 2, 3]).write(to: source)
        defer {
            try? FileManager.default.removeItem(at: root)
        }

        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = TimeZone(secondsFromGMT: 0)!
        let writer = RecordingFileWriter(
            naming: RecordingNaming(calendar: calendar, timeZone: calendar.timeZone),
            saveDirectory: { destination }
        )

        let written = try writer.copyRecording(
            from: source,
            format: .mp4,
            date: Date(timeIntervalSince1970: 1_717_419_730)
        )

        XCTAssertEqual(written.lastPathComponent, "Frame 2024-06-03 13.02.10.mp4")
        XCTAssertEqual(try Data(contentsOf: written), Data([1, 2, 3]))
    }
}

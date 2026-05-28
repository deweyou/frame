import XCTest
@testable import FrameApp

final class ScreenshotFileWriterTests: XCTestCase {
    func testWriteUsesConfiguredDirectory() throws {
        let temporaryDirectory = FileManager.default.temporaryDirectory
            .appendingPathComponent("FrameWriterTests-\(UUID().uuidString)", isDirectory: true)
        try FileManager.default.createDirectory(at: temporaryDirectory, withIntermediateDirectories: true)
        defer {
            try? FileManager.default.removeItem(at: temporaryDirectory)
        }

        let writer = ScreenshotFileWriter(
            fileManager: .default,
            saveDirectory: { temporaryDirectory },
            strings: AppStrings(language: .en)
        )

        let url = try writer.write(pngData: Data([1, 2, 3]), date: Date(timeIntervalSince1970: 0))

        XCTAssertEqual(url.deletingLastPathComponent(), temporaryDirectory)
        XCTAssertEqual(try Data(contentsOf: url), Data([1, 2, 3]))
    }
}

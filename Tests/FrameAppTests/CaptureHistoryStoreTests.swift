import AppKit
import XCTest
@testable import FrameApp

final class CaptureHistoryStoreTests: XCTestCase {
    private var rootDirectory: URL!
    private var store: CaptureHistoryStore!

    override func setUpWithError() throws {
        try super.setUpWithError()
        rootDirectory = FileManager.default.temporaryDirectory
            .appendingPathComponent("FrameHistoryTests-\(UUID().uuidString)", isDirectory: true)
        store = CaptureHistoryStore(rootDirectory: rootDirectory)
    }

    override func tearDownWithError() throws {
        if let rootDirectory {
            try? FileManager.default.removeItem(at: rootDirectory)
        }
        store = nil
        rootDirectory = nil
        try super.tearDownWithError()
    }

    func testAddScreenshotStoresMetadataAndPNGData() throws {
        let record = try XCTUnwrap(try store.addScreenshot(
            pngData: Data([1, 2, 3]),
            imageSize: CGSize(width: 40, height: 20),
            rect: CGRect(x: 10, y: 20, width: 40, height: 20),
            date: Date(timeIntervalSince1970: 100),
            configuration: .init(isEnabled: true, retention: .sevenDays, sizeLimit: .twoGB)
        ))

        XCTAssertEqual(record.kind, .screenshot)
        XCTAssertEqual(record.byteSize, 3)
        XCTAssertEqual(record.pixelWidth, 40)
        XCTAssertEqual(record.pixelHeight, 20)
        XCTAssertEqual(try store.data(for: record), Data([1, 2, 3]))
        XCTAssertEqual(try store.records(), [record])
    }

    func testDisabledHistoryDoesNotStoreScreenshot() throws {
        let record = try store.addScreenshot(
            pngData: Data([1, 2, 3]),
            imageSize: CGSize(width: 40, height: 20),
            rect: .zero,
            date: Date(timeIntervalSince1970: 100),
            configuration: .init(isEnabled: false, retention: .sevenDays, sizeLimit: .twoGB)
        )

        XCTAssertNil(record)
        XCTAssertEqual(try store.records(), [])
    }

    func testDeleteRecordRemovesMetadataAndCachedFile() throws {
        let record = try XCTUnwrap(try store.addScreenshot(
            pngData: Data([1, 2, 3]),
            imageSize: CGSize(width: 40, height: 20),
            rect: .zero,
            date: Date(timeIntervalSince1970: 100),
            configuration: .init(isEnabled: true, retention: .sevenDays, sizeLimit: .twoGB)
        ))

        try store.delete(recordID: record.id)

        XCTAssertEqual(try store.records(), [])
        XCTAssertThrowsError(try store.data(for: record))
    }

    func testClearRemovesAllRecordsAndFiles() throws {
        _ = try store.addScreenshot(
            pngData: Data([1]),
            imageSize: CGSize(width: 1, height: 1),
            rect: .zero,
            date: Date(timeIntervalSince1970: 100),
            configuration: .init(isEnabled: true, retention: .sevenDays, sizeLimit: .twoGB)
        )
        _ = try store.addScreenshot(
            pngData: Data([2]),
            imageSize: CGSize(width: 1, height: 1),
            rect: .zero,
            date: Date(timeIntervalSince1970: 101),
            configuration: .init(isEnabled: true, retention: .sevenDays, sizeLimit: .twoGB)
        )

        try store.clear()

        XCTAssertEqual(try store.records(), [])
    }

    func testCleanupRemovesRecordsOlderThanRetention() throws {
        let old = try XCTUnwrap(try store.addScreenshot(
            pngData: Data([1]),
            imageSize: CGSize(width: 1, height: 1),
            rect: .zero,
            date: Date(timeIntervalSince1970: 0),
            configuration: .init(isEnabled: true, retention: .forever, sizeLimit: .twoGB)
        ))
        let recent = try XCTUnwrap(try store.addScreenshot(
            pngData: Data([2]),
            imageSize: CGSize(width: 1, height: 1),
            rect: .zero,
            date: Date(timeIntervalSince1970: 8 * 24 * 60 * 60),
            configuration: .init(isEnabled: true, retention: .forever, sizeLimit: .twoGB)
        ))

        try store.cleanup(
            now: Date(timeIntervalSince1970: 8 * 24 * 60 * 60),
            configuration: .init(isEnabled: true, retention: .sevenDays, sizeLimit: .twoGB)
        )

        XCTAssertEqual(try store.records(), [recent])
        XCTAssertThrowsError(try store.data(for: old))
    }

    func testCleanupRemovesOldestRecordsWhenSizeLimitIsExceeded() throws {
        let first = try XCTUnwrap(try store.addScreenshot(
            pngData: Data(repeating: 1, count: 6),
            imageSize: CGSize(width: 1, height: 1),
            rect: .zero,
            date: Date(timeIntervalSince1970: 100),
            configuration: .init(isEnabled: true, retention: .forever, sizeLimit: .custom(bytes: 20))
        ))
        let second = try XCTUnwrap(try store.addScreenshot(
            pngData: Data(repeating: 2, count: 6),
            imageSize: CGSize(width: 1, height: 1),
            rect: .zero,
            date: Date(timeIntervalSince1970: 101),
            configuration: .init(isEnabled: true, retention: .forever, sizeLimit: .custom(bytes: 20))
        ))
        let newest = try XCTUnwrap(try store.addScreenshot(
            pngData: Data(repeating: 3, count: 6),
            imageSize: CGSize(width: 1, height: 1),
            rect: .zero,
            date: Date(timeIntervalSince1970: 102),
            configuration: .init(isEnabled: true, retention: .forever, sizeLimit: .custom(bytes: 12))
        ))

        XCTAssertEqual(try store.records(), [newest, second])
        XCTAssertThrowsError(try store.data(for: first))
    }

    func testOversizedSingleFileIsNotStored() throws {
        let record = try store.addScreenshot(
            pngData: Data(repeating: 1, count: 13),
            imageSize: CGSize(width: 1, height: 1),
            rect: .zero,
            date: Date(timeIntervalSince1970: 100),
            configuration: .init(isEnabled: true, retention: .sevenDays, sizeLimit: .custom(bytes: 12))
        )

        XCTAssertNil(record)
        XCTAssertEqual(try store.records(), [])
    }
}

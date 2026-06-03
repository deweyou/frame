import AppKit
import XCTest
@testable import FrameApp

@MainActor
final class StatusItemControllerTests: XCTestCase {
    func testMenuIncludesCaptureHistoryItem() {
        let statusItem = NSStatusBar.system.statusItem(withLength: NSStatusItem.variableLength)
        defer {
            NSStatusBar.system.removeStatusItem(statusItem)
        }

        _ = StatusItemController(
            statusItem: statusItem,
            strings: AppStrings(language: .en),
            onCapture: {},
            onHistory: {},
            onSettings: {}
        )

        let titles = statusItem.menu?.items.map(\.title) ?? []
        XCTAssertTrue(titles.contains("Capture History"))
        XCTAssertLessThan(
            titles.firstIndex(of: "Capture History") ?? Int.max,
            titles.firstIndex(of: "Settings...") ?? Int.max
        )
    }

    func testRecordingStateShowsStopRecordingItemBeforeCapture() throws {
        let statusItem = NSStatusBar.system.statusItem(withLength: NSStatusItem.variableLength)
        defer {
            NSStatusBar.system.removeStatusItem(statusItem)
        }
        var didStop = false

        let controller = StatusItemController(
            statusItem: statusItem,
            strings: AppStrings(language: .en),
            onCapture: {},
            onHistory: {},
            onSettings: {},
            onStopRecording: { didStop = true }
        )
        controller.setRecordingState(.recording)

        let titles = statusItem.menu?.items.map(\.title) ?? []
        XCTAssertEqual(titles.first, "Stop Recording")

        let stopItem = try XCTUnwrap(statusItem.menu?.items.first)
        NSApp.sendAction(try XCTUnwrap(stopItem.action), to: stopItem.target, from: stopItem)
        XCTAssertTrue(didStop)
    }
}

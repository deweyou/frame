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
}

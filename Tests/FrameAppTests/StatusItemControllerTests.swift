import AppKit
import FrameCore
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

    func testMenuExposesSeparateScreenshotAndRecordingActionsWithConfiguredShortcuts() throws {
        let statusItem = NSStatusBar.system.statusItem(withLength: NSStatusItem.variableLength)
        defer {
            NSStatusBar.system.removeStatusItem(statusItem)
        }
        var didCapture = false
        var didRecord = false

        let controller = StatusItemController(
            statusItem: statusItem,
            strings: AppStrings(language: .en),
            screenshotShortcut: .default,
            recordingShortcut: .defaultRecording,
            onCapture: { didCapture = true },
            onRecord: { didRecord = true },
            onHistory: {},
            onSettings: {}
        )

        let captureItem = try XCTUnwrap(statusItem.menu?.items.first { $0.title == "Capture Screenshot" })
        let recordItem = try XCTUnwrap(statusItem.menu?.items.first { $0.title == "Record Screen" })
        XCTAssertEqual(captureItem.keyEquivalent, "a")
        XCTAssertEqual(captureItem.keyEquivalentModifierMask, [.command, .shift])
        XCTAssertEqual(recordItem.keyEquivalent, "r")
        XCTAssertEqual(recordItem.keyEquivalentModifierMask, [.command, .shift])

        NSApp.sendAction(try XCTUnwrap(captureItem.action), to: captureItem.target, from: captureItem)
        NSApp.sendAction(try XCTUnwrap(recordItem.action), to: recordItem.target, from: recordItem)
        XCTAssertTrue(didCapture)
        XCTAssertTrue(didRecord)
        withExtendedLifetime(controller) {}
    }

    func testUnsetRecordingShortcutKeepsRecordMenuItemWithoutKeyEquivalent() throws {
        let statusItem = NSStatusBar.system.statusItem(withLength: NSStatusItem.variableLength)
        defer {
            NSStatusBar.system.removeStatusItem(statusItem)
        }

        _ = StatusItemController(
            statusItem: statusItem,
            strings: AppStrings(language: .en),
            screenshotShortcut: .default,
            recordingShortcut: nil,
            onCapture: {},
            onHistory: {},
            onSettings: {}
        )

        let recordItem = try XCTUnwrap(statusItem.menu?.items.first { $0.title == "Record Screen" })
        XCTAssertEqual(recordItem.keyEquivalent, "")
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

import AppKit
import XCTest
@testable import FrameApp

final class CaptureHistoryWindowControllerTests: XCTestCase {
    private var rootDirectory: URL!
    private var store: CaptureHistoryStore!

    override func setUpWithError() throws {
        try super.setUpWithError()
        rootDirectory = FileManager.default.temporaryDirectory
            .appendingPathComponent("FrameHistoryWindowTests-\(UUID().uuidString)", isDirectory: true)
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

    @MainActor
    func testShowCreatesWindowWithPreviewGrid() throws {
        _ = try addRecord(kind: .screenshot, date: Date(timeIntervalSince1970: 100))
        let controller = CaptureHistoryWindowController(store: store)

        controller.show(strings: AppStrings(language: .en))
        defer {
            controller.close()
        }

        XCTAssertTrue(controller.isWindowVisible)
        XCTAssertEqual(controller.visibleRecords().count, 1)
        XCTAssertEqual(controller.selectedFilter, .all)
        XCTAssertEqual(controller.visibleColumnIdentifiers(), [])
        XCTAssertEqual(controller.visibleTileCount(), 1)
        XCTAssertTrue(controller.usesTransparentTitlebar)
    }

    @MainActor
    func testFilterCanShowScreenshotsOrRecordings() throws {
        let screenshot = try addRecord(kind: .screenshot, date: Date(timeIntervalSince1970: 100))
        let recording = try addRecord(kind: .recording, date: Date(timeIntervalSince1970: 101))
        let controller = CaptureHistoryWindowController(store: store)

        controller.show(strings: AppStrings(language: .en))
        controller.setFilter(.screenshots)
        XCTAssertEqual(controller.visibleRecords(), [screenshot])

        controller.setFilter(.recordings)
        XCTAssertEqual(controller.visibleRecords(), [recording])

        controller.setFilter(.all)
        XCTAssertEqual(controller.visibleRecords(), [recording, screenshot])
        controller.close()
    }

    @MainActor
    func testFilterControlUsesToolbarPillButtons() throws {
        let screenshot = try addRecord(kind: .screenshot, date: Date(timeIntervalSince1970: 100))
        let recording = try addRecord(kind: .recording, date: Date(timeIntervalSince1970: 101))
        let controller = CaptureHistoryWindowController(store: store)

        controller.show(strings: AppStrings(language: .en))
        defer {
            controller.close()
        }

        let contentView = try XCTUnwrap(NSApp.windows.first {
            $0.title == "Capture History" && $0.isVisible
        }?.contentView)
        contentView.layoutSubtreeIfNeeded()

        XCTAssertNil(findView(in: contentView, ofType: NSSegmentedControl.self))
        let filterControl = try XCTUnwrap(findView(in: contentView, accessibilityLabel: "Capture History Filter"))
        XCTAssertEqual(filterControl.layer?.cornerRadius ?? 0, filterControl.frame.height / 2, accuracy: 1)

        let buttons = findButtons(in: filterControl)
        XCTAssertEqual(buttons.map(\.title), ["All", "Screenshots", "Recordings"])
        XCTAssertTrue(buttons.allSatisfy { $0.acceptsFirstMouse(for: nil) })

        buttons[1].performClick(nil)
        XCTAssertEqual(controller.selectedFilter, .screenshots)
        XCTAssertEqual(controller.visibleRecords(), [screenshot])

        buttons[2].performClick(nil)
        XCTAssertEqual(controller.selectedFilter, .recordings)
        XCTAssertEqual(controller.visibleRecords(), [recording])
    }

    @MainActor
    func testChineseFilterControlSizesToShortLabels() throws {
        _ = try addRecord(kind: .screenshot, date: Date(timeIntervalSince1970: 100))
        let controller = CaptureHistoryWindowController(store: store)

        controller.show(strings: AppStrings(language: .zhHans))
        defer {
            controller.close()
        }

        let contentView = try XCTUnwrap(NSApp.windows.first {
            $0.title == "截图历史" && $0.isVisible
        }?.contentView)
        contentView.layoutSubtreeIfNeeded()

        let filterControl = try XCTUnwrap(findView(in: contentView, accessibilityLabel: "Capture History Filter"))
        let buttons = findButtons(in: filterControl)
        XCTAssertEqual(buttons.map(\.title), ["全部", "截图", "录屏"])
        XCTAssertLessThanOrEqual(filterControl.frame.width, 152)
        XCTAssertGreaterThanOrEqual(buttons.map(\.frame.width).min() ?? 0, 40)
    }

    @MainActor
    func testRecordActionsCallConfiguredHandlers() throws {
        let record = try addRecord(kind: .screenshot, date: Date(timeIntervalSince1970: 100))
        var restored: CaptureHistoryRecord?
        var copied: CaptureHistoryRecord?
        var saved: CaptureHistoryRecord?
        var deleted: CaptureHistoryRecord?
        let controller = CaptureHistoryWindowController(
            store: store,
            restore: { restored = $0 },
            copy: { copied = $0 },
            save: { saved = $0 },
            delete: { deleted = $0 }
        )

        controller.show(strings: AppStrings(language: .en))
        controller.restoreRecord(record)
        controller.copyRecord(record)
        controller.saveRecord(record)
        controller.deleteRecord(record)

        XCTAssertEqual(restored, record)
        XCTAssertEqual(copied, record)
        XCTAssertEqual(saved, record)
        XCTAssertEqual(deleted, record)
        controller.close()
    }

    @MainActor
    func testTileActionsAreVisibleOnlyWhenHovered() throws {
        let record = try addRecord(kind: .screenshot, date: Date(timeIntervalSince1970: 100))
        let controller = CaptureHistoryWindowController(store: store)

        controller.show(strings: AppStrings(language: .en))
        defer {
            controller.close()
        }

        XCTAssertFalse(controller.areActionsVisible(for: record))
        controller.setActionsVisible(true, for: record)
        XCTAssertTrue(controller.areActionsVisible(for: record))
        controller.setActionsVisible(false, for: record)
        XCTAssertFalse(controller.areActionsVisible(for: record))
    }

    @MainActor
    func testOnlyOneTileShowsActionsAtATime() throws {
        let first = try addRecord(kind: .screenshot, date: Date(timeIntervalSince1970: 100))
        let second = try addRecord(kind: .screenshot, date: Date(timeIntervalSince1970: 101))
        let controller = CaptureHistoryWindowController(store: store)

        controller.show(strings: AppStrings(language: .en))
        defer {
            controller.close()
        }

        controller.setActionsVisible(true, for: first)
        XCTAssertTrue(controller.areActionsVisible(for: first))
        XCTAssertFalse(controller.areActionsVisible(for: second))

        controller.setActionsVisible(true, for: second)
        XCTAssertFalse(controller.areActionsVisible(for: first))
        XCTAssertTrue(controller.areActionsVisible(for: second))
    }

    @MainActor
    func testStaleHoverExitDoesNotHideCurrentTileActions() throws {
        let first = try addRecord(kind: .screenshot, date: Date(timeIntervalSince1970: 100))
        let second = try addRecord(kind: .screenshot, date: Date(timeIntervalSince1970: 101))
        let controller = CaptureHistoryWindowController(store: store)

        controller.show(strings: AppStrings(language: .en))
        defer {
            controller.close()
        }

        controller.setActionsVisible(true, for: first)
        controller.setActionsVisible(true, for: second)
        controller.setActionsVisible(false, for: first)

        XCTAssertFalse(controller.areActionsVisible(for: first))
        XCTAssertTrue(controller.areActionsVisible(for: second))
    }

    @MainActor
    func testTileActionButtonsExposePointerCursorAndTooltips() throws {
        _ = try addRecord(kind: .screenshot, date: Date(timeIntervalSince1970: 100))
        let controller = CaptureHistoryWindowController(store: store)

        controller.show(strings: AppStrings(language: .en))
        defer {
            controller.close()
        }

        let buttons = controller.visibleActionButtons()
        XCTAssertEqual(buttons.count, 4)
        XCTAssertTrue(buttons.allSatisfy { $0.acceptsFirstMouse(for: nil) })
        XCTAssertEqual(buttons.compactMap(\.toolTip).sorted(), ["Copy", "Delete", "Restore", "Save"])
    }

    @MainActor
    func testDeleteActionSitsInPreviewTopRightCorner() throws {
        let record = try addRecord(kind: .screenshot, date: Date(timeIntervalSince1970: 100))
        let controller = CaptureHistoryWindowController(store: store)

        controller.show(strings: AppStrings(language: .en))
        defer {
            controller.close()
        }

        controller.setActionsVisible(true, for: record)

        let saveFrame = try XCTUnwrap(controller.actionButtonFrame(title: "Save", for: record))
        let copyFrame = try XCTUnwrap(controller.actionButtonFrame(title: "Copy", for: record))
        let restoreFrame = try XCTUnwrap(controller.actionButtonFrame(title: "Restore", for: record))
        let deleteFrame = try XCTUnwrap(controller.actionButtonFrame(title: "Delete", for: record))

        XCTAssertGreaterThan(deleteFrame.minY, max(saveFrame.maxY, copyFrame.maxY, restoreFrame.maxY))
        XCTAssertGreaterThan(deleteFrame.minX, max(saveFrame.maxX, copyFrame.maxX, restoreFrame.maxX))
    }

    private func addRecord(kind: CaptureHistoryKind, date: Date) throws -> CaptureHistoryRecord {
        try XCTUnwrap(try store.addCapture(
            kind: kind,
            data: Data([UInt8(date.timeIntervalSince1970.truncatingRemainder(dividingBy: 255))]),
            imageSize: CGSize(width: 10, height: 8),
            rect: CGRect(x: 0, y: 0, width: 10, height: 8),
            date: date,
            configuration: .init(isEnabled: true, retention: .forever, sizeLimit: .twoGB)
        ))
    }

    @MainActor
    private func findButtons(in view: NSView) -> [NSButton] {
        var buttons: [NSButton] = []
        if let button = view as? NSButton {
            buttons.append(button)
        }

        for subview in view.subviews {
            buttons.append(contentsOf: findButtons(in: subview))
        }

        return buttons
    }

    @MainActor
    private func findView(in view: NSView, accessibilityLabel: String) -> NSView? {
        if view.accessibilityLabel() == accessibilityLabel {
            return view
        }

        for subview in view.subviews {
            if let matchingView = findView(in: subview, accessibilityLabel: accessibilityLabel) {
                return matchingView
            }
        }

        return nil
    }

    @MainActor
    private func findView<T: NSView>(in view: NSView, ofType type: T.Type) -> T? {
        if let matchingView = view as? T {
            return matchingView
        }

        for subview in view.subviews {
            if let matchingView = findView(in: subview, ofType: type) {
                return matchingView
            }
        }

        return nil
    }
}

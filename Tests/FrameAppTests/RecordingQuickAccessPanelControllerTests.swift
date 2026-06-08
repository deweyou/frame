import AppKit
import ImageIO
import UniformTypeIdentifiers
import XCTest
@testable import FrameApp
@testable import FrameCore

@MainActor
final class RecordingQuickAccessPanelControllerTests: XCTestCase {
    private var retainedPreviewControllers: [QuickAccessPanelController] = []

    func testRecordingQuickAccessExposesDownloadCopyPreviewAndDisabledEdit() throws {
        _ = NSApplication.shared
        let windowsBeforeShow = Set(NSApp.windows.map(ObjectIdentifier.init))
        let recording = CapturedRecording(
            id: UUID(),
            fileURL: URL(fileURLWithPath: "/tmp/test.mp4"),
            format: .mp4,
            rect: CGRect(x: 0, y: 0, width: 1282, height: 504),
            pixelSize: CGSize(width: 1282, height: 504),
            byteSize: 10,
            duration: 24
        )
        let controller = QuickAccessPanelController()
        retainedPreviewControllers.append(controller)
        let expectedPreviewSize = QuickAccessPanelController.recordingPreviewSize(forSourceSize: recording.pixelSize)

        controller.show(
            for: recording,
            preferredAnchor: CGRect(x: 0, y: 0, width: 100, height: 100),
            strings: AppStrings(language: .en),
            download: { true },
            copy: { true },
            preview: { true },
            close: {}
        )

        let panel = try XCTUnwrap(NSApp.windows.first { !windowsBeforeShow.contains(ObjectIdentifier($0)) } as? NSPanel)
        defer {
            panel.close()
        }
        XCTAssertEqual(panel.frame.size, expectedPreviewSize)
        XCTAssertFalse(panel.styleMask.contains(.nonactivatingPanel))
        XCTAssertFalse(panel.isMovable)
        XCTAssertTrue(panel.isVisible)

        RunLoop.main.run(until: Date().addingTimeInterval(0.1))
        let contentView = try XCTUnwrap(panel.contentView)
        contentView.layoutSubtreeIfNeeded()
        XCTAssertEqual(panel.frame.size, expectedPreviewSize)
        XCTAssertEqual(contentView.frame.size, expectedPreviewSize)
        XCTAssertEqual(try XCTUnwrap(findPreviewSurface(in: contentView)).frame.size, expectedPreviewSize)
        XCTAssertNotNil(findButton(in: contentView, accessibilityLabel: "Download"))
        XCTAssertNotNil(findButton(in: contentView, accessibilityLabel: "Copy"))
        XCTAssertNotNil(findButton(in: contentView, accessibilityLabel: "Preview"))
        let editButton = try XCTUnwrap(findButton(in: contentView, accessibilityLabel: "Edit"))
        XCTAssertFalse(editButton.isEnabled)
        XCTAssertNotNil(findButton(in: contentView, accessibilityLabel: "Close"))
    }

    func testRecordingQuickAccessScalesPreviewToRecordingAspectRatio() {
        XCTAssertEqual(
            QuickAccessPanelController.recordingPreviewSize(forSourceSize: CGSize(width: 1282, height: 504)),
            CapturePreviewMetrics.previewSize(forDesktopSize: nil)
        )
        XCTAssertEqual(
            QuickAccessPanelController.recordingPreviewSize(forSourceSize: CGSize(width: 998, height: 734)),
            CapturePreviewMetrics.previewSize(forDesktopSize: nil)
        )
    }

    func testRecordingQuickAccessUsesFirstFrameThumbnailWhenAvailable() throws {
        _ = NSApplication.shared
        let windowsBeforeShow = Set(NSApp.windows.map(ObjectIdentifier.init))
        let gifURL = FileManager.default.temporaryDirectory
            .appendingPathComponent("FrameVideoQuickAccess-\(UUID().uuidString).gif")
        try makeOneFrameGIF(at: gifURL)
        defer {
            try? FileManager.default.removeItem(at: gifURL)
        }

        let recording = CapturedRecording(
            id: UUID(),
            fileURL: gifURL,
            format: .gif,
            rect: CGRect(x: 0, y: 0, width: 8, height: 8),
            pixelSize: CGSize(width: 8, height: 8),
            byteSize: 16,
            duration: 1
        )
        let controller = QuickAccessPanelController()
        retainedPreviewControllers.append(controller)

        controller.show(
            for: recording,
            preferredAnchor: CGRect(x: 0, y: 0, width: 100, height: 100),
            strings: AppStrings(language: .en),
            download: { true },
            copy: { true },
            preview: { true },
            close: {}
        )

        let panel = try XCTUnwrap(NSApp.windows.first { !windowsBeforeShow.contains(ObjectIdentifier($0)) } as? NSPanel)
        defer {
            panel.close()
        }
        let contentView = try XCTUnwrap(panel.contentView)
        contentView.layoutSubtreeIfNeeded()
        let previewSurface = try XCTUnwrap(findPreviewSurface(in: contentView))
        XCTAssertEqual(previewSurface.frame, contentView.bounds)
        let thumbnailView = try XCTUnwrap(previewSurface as? RecordingThumbnailDrawableForTesting)
        XCTAssertTrue(thumbnailView.lastDrawRectForTesting.contains(contentView.bounds))
        XCTAssertEqual(RecordingThumbnailProvider().thumbnail(for: gifURL)?.size, CGSize(width: 2, height: 2))
    }

    func testClickingRecordingPlayOverlayOpensPreview() throws {
        _ = NSApplication.shared
        let windowsBeforeShow = Set(NSApp.windows.map(ObjectIdentifier.init))
        let recording = CapturedRecording(
            id: UUID(),
            fileURL: URL(fileURLWithPath: "/tmp/test.mp4"),
            format: .mp4,
            rect: CGRect(x: 0, y: 0, width: 1282, height: 504),
            pixelSize: CGSize(width: 1282, height: 504),
            byteSize: 10,
            duration: 24
        )
        let controller = QuickAccessPanelController()
        retainedPreviewControllers.append(controller)
        var previewCallCount = 0

        controller.show(
            for: recording,
            preferredAnchor: CGRect(x: 0, y: 0, width: 100, height: 100),
            strings: AppStrings(language: .en),
            download: { true },
            copy: { true },
            preview: {
                previewCallCount += 1
                return true
            },
            close: {}
        )

        let panel = try XCTUnwrap(NSApp.windows.first { !windowsBeforeShow.contains(ObjectIdentifier($0)) } as? NSPanel)
        defer {
            panel.close()
        }
        let contentView = try XCTUnwrap(panel.contentView)
        contentView.layoutSubtreeIfNeeded()
        let windowPoint = contentView.convert(NSPoint(x: contentView.bounds.midX, y: contentView.bounds.midY), to: nil)

        panel.sendEvent(try makeMouseButtonEvent(type: .leftMouseDown, point: windowPoint, panel: panel))
        panel.sendEvent(try makeMouseButtonEvent(type: .leftMouseUp, point: windowPoint, panel: panel))

        XCTAssertEqual(previewCallCount, 1)
    }

    func testClickingRecordingPreviewOutsidePlayOverlayDoesNotOpenPreview() throws {
        _ = NSApplication.shared
        let windowsBeforeShow = Set(NSApp.windows.map(ObjectIdentifier.init))
        let recording = CapturedRecording(
            id: UUID(),
            fileURL: URL(fileURLWithPath: "/tmp/test.mp4"),
            format: .mp4,
            rect: CGRect(x: 0, y: 0, width: 1282, height: 504),
            pixelSize: CGSize(width: 1282, height: 504),
            byteSize: 10,
            duration: 24
        )
        let controller = QuickAccessPanelController()
        retainedPreviewControllers.append(controller)
        var previewCallCount = 0

        controller.show(
            for: recording,
            preferredAnchor: CGRect(x: 0, y: 0, width: 100, height: 100),
            strings: AppStrings(language: .en),
            download: { true },
            copy: { true },
            preview: {
                previewCallCount += 1
                return true
            },
            close: {}
        )

        let panel = try XCTUnwrap(NSApp.windows.first { !windowsBeforeShow.contains(ObjectIdentifier($0)) } as? NSPanel)
        defer {
            panel.close()
        }
        let contentView = try XCTUnwrap(panel.contentView)
        contentView.layoutSubtreeIfNeeded()
        let windowPoint = contentView.convert(NSPoint(x: 24, y: contentView.bounds.midY), to: nil)

        panel.sendEvent(try makeMouseButtonEvent(type: .leftMouseDown, point: windowPoint, panel: panel))
        panel.sendEvent(try makeMouseButtonEvent(type: .leftMouseUp, point: windowPoint, panel: panel))

        XCTAssertEqual(previewCallCount, 0)
    }

    func testQuickAccessStacksScreenshotsAndRecordingsTogether() throws {
        _ = NSApplication.shared
        let windowsBeforeShow = Set(NSApp.windows.map(ObjectIdentifier.init))
        let controller = QuickAccessPanelController()
        retainedPreviewControllers.append(controller)
        let screenshot = CapturedScreenshot(
            pngData: try makePNGData(),
            image: NSImage(size: NSSize(width: 1600, height: 900)),
            rect: CGRect(x: 0, y: 0, width: 1600, height: 900)
        )
        let recording = CapturedRecording(
            id: UUID(),
            fileURL: URL(fileURLWithPath: "/tmp/test.mp4"),
            format: .mp4,
            rect: CGRect(x: 0, y: 0, width: 1282, height: 504),
            pixelSize: CGSize(width: 1282, height: 504),
            byteSize: 10,
            duration: 24
        )

        controller.show(
            for: screenshot,
            preferredAnchor: nil,
            strings: AppStrings(language: .en),
            copy: { true },
            save: { true },
            recognizeText: { true },
            openWorkspace: { true },
            pin: { true },
            close: {}
        )
        controller.show(
            for: recording,
            preferredAnchor: nil,
            strings: AppStrings(language: .en),
            download: { true },
            copy: { true },
            preview: { true },
            close: {}
        )

        let panels = NSApp.windows.compactMap { window -> NSPanel? in
            windowsBeforeShow.contains(ObjectIdentifier(window)) ? nil : window as? NSPanel
        }
        defer {
            panels.forEach { $0.close() }
        }
        XCTAssertEqual(panels.count, 2)
        let sortedPanels = panels.sorted { $0.frame.minY < $1.frame.minY }
        XCTAssertEqual(sortedPanels.first?.frame.size, CapturePreviewMetrics.previewSize(forDesktopSize: NSScreen.main?.frame.size))
        XCTAssertEqual(sortedPanels.last?.frame.size, QuickAccessPanelController.recordingPreviewSize(forSourceSize: recording.pixelSize))
        XCTAssertGreaterThan(sortedPanels[1].frame.minY, sortedPanels[0].frame.maxY)
    }

    func testShowingRecordingRestoresTemporarilyHiddenScreenshotPreviews() throws {
        _ = NSApplication.shared
        let windowsBeforeShow = Set(NSApp.windows.map(ObjectIdentifier.init))
        let controller = QuickAccessPanelController()
        retainedPreviewControllers.append(controller)
        let screenshot = CapturedScreenshot(
            pngData: try makePNGData(),
            image: NSImage(size: NSSize(width: 1600, height: 900)),
            rect: CGRect(x: 0, y: 0, width: 1600, height: 900)
        )
        let recording = CapturedRecording(
            id: UUID(),
            fileURL: URL(fileURLWithPath: "/tmp/test.mp4"),
            format: .mp4,
            rect: CGRect(x: 0, y: 0, width: 1282, height: 504),
            pixelSize: CGSize(width: 1282, height: 504),
            byteSize: 10,
            duration: 7
        )

        controller.show(
            for: screenshot,
            preferredAnchor: nil,
            strings: AppStrings(language: .en),
            copy: { true },
            save: { true },
            recognizeText: { true },
            openWorkspace: { true },
            pin: { true },
            close: {}
        )
        controller.temporarilyHidePreviews()
        let hiddenPanels = newPreviewPanels(excluding: windowsBeforeShow)
        XCTAssertEqual(hiddenPanels.filter(\.isVisible).count, 0)
        XCTAssertTrue(hiddenPanels.allSatisfy { $0.alphaValue == 0 })
        XCTAssertTrue(hiddenPanels.allSatisfy(\.ignoresMouseEvents))

        controller.show(
            for: recording,
            preferredAnchor: nil,
            strings: AppStrings(language: .en),
            download: { true },
            copy: { true },
            preview: { true },
            close: {}
        )

        let panels = newPreviewPanels(excluding: windowsBeforeShow)
        defer {
            panels.forEach { $0.close() }
        }
        XCTAssertEqual(panels.filter(\.isVisible).count, 2)
        XCTAssertTrue(panels.allSatisfy { $0.alphaValue == 1 })
        XCTAssertTrue(panels.allSatisfy { !$0.ignoresMouseEvents })
    }

    private func makeOneFrameGIF(at url: URL) throws {
        let colorSpace = CGColorSpaceCreateDeviceRGB()
        let pixels: [UInt8] = [
            255, 0, 0, 255,
            0, 255, 0, 255,
            0, 0, 255, 255,
            255, 255, 255, 255,
        ]
        let data = Data(pixels)
        guard let provider = CGDataProvider(data: data as CFData),
              let image = CGImage(
                width: 2,
                height: 2,
                bitsPerComponent: 8,
                bitsPerPixel: 32,
                bytesPerRow: 8,
                space: colorSpace,
                bitmapInfo: CGBitmapInfo(rawValue: CGImageAlphaInfo.last.rawValue),
                provider: provider,
                decode: nil,
                shouldInterpolate: false,
                intent: .defaultIntent
              ),
              let destination = CGImageDestinationCreateWithURL(
                url as CFURL,
                UTType.gif.identifier as CFString,
                1,
                nil
              ) else {
            XCTFail("Failed to create GIF test image")
            return
        }

        CGImageDestinationAddImage(destination, image, nil)
        XCTAssertTrue(CGImageDestinationFinalize(destination))
    }

    private func makePNGData() throws -> Data {
        let bitmap = NSBitmapImageRep(
            bitmapDataPlanes: nil,
            pixelsWide: 2,
            pixelsHigh: 2,
            bitsPerSample: 8,
            samplesPerPixel: 4,
            hasAlpha: true,
            isPlanar: false,
            colorSpaceName: .deviceRGB,
            bytesPerRow: 0,
            bitsPerPixel: 0
        )

        return try XCTUnwrap(bitmap?.representation(using: .png, properties: [:]))
    }

    private func findButton(in view: NSView, accessibilityLabel: String) -> NSButton? {
        if let button = view as? NSButton,
           button.accessibilityLabel() == accessibilityLabel {
            return button
        }

        for subview in view.subviews {
            if let button = findButton(in: subview, accessibilityLabel: accessibilityLabel) {
                return button
            }
        }

        return nil
    }

    private func findPreviewSurface(in view: NSView) -> NSView? {
        view.subviews.first
    }

    private func makeMouseButtonEvent(type: NSEvent.EventType, point: NSPoint, panel: NSPanel) throws -> NSEvent {
        try XCTUnwrap(NSEvent.mouseEvent(
            with: type,
            location: point,
            modifierFlags: [],
            timestamp: 0,
            windowNumber: panel.windowNumber,
            context: nil,
            eventNumber: 0,
            clickCount: 1,
            pressure: type == .leftMouseDown ? 1 : 0
        ))
    }

    private func newPreviewPanels(excluding windowsBeforeShow: Set<ObjectIdentifier>) -> [NSPanel] {
        NSApp.windows.compactMap { window -> NSPanel? in
            windowsBeforeShow.contains(ObjectIdentifier(window)) ? nil : window as? NSPanel
        }
    }
}

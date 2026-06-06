import AppKit
import ImageIO
import UniformTypeIdentifiers
import XCTest
@testable import FrameApp
@testable import FrameCore

@MainActor
final class VideoQuickAccessPanelControllerTests: XCTestCase {
    func testVideoQuickAccessExposesDownloadCopyPreviewAndDisabledEdit() throws {
        let recording = CapturedRecording(
            id: UUID(),
            fileURL: URL(fileURLWithPath: "/tmp/test.mp4"),
            format: .mp4,
            rect: CGRect(x: 0, y: 0, width: 1282, height: 504),
            pixelSize: CGSize(width: 1282, height: 504),
            byteSize: 10,
            duration: 24
        )
        let controller = VideoQuickAccessPanelController()
        let expectedPreviewSize = VideoQuickAccessPanelController.previewSize(forSourceSize: recording.pixelSize)

        controller.show(
            for: recording,
            preferredAnchor: CGRect(x: 0, y: 0, width: 100, height: 100),
            strings: AppStrings(language: .en),
            download: { true },
            copy: { true },
            preview: { true },
            close: {}
        )

        XCTAssertEqual(
            controller.actionLabelsForTesting(recordingID: recording.id),
            ["Download", "Copy", "Preview", "Edit", "Close"]
        )
        XCTAssertFalse(controller.isEditEnabledForTesting(recordingID: recording.id))
        XCTAssertEqual(
            controller.panelSizeForTesting(recordingID: recording.id),
            expectedPreviewSize
        )
        XCTAssertEqual(
            controller.contentFrameForTesting(recordingID: recording.id)?.size,
            expectedPreviewSize
        )
        XCTAssertTrue(controller.isPanelVisibleForTesting(recordingID: recording.id))
        let styleMask = try XCTUnwrap(controller.panelStyleMaskForTesting(recordingID: recording.id))
        XCTAssertTrue(styleMask.contains(.borderless))

        RunLoop.main.run(until: Date().addingTimeInterval(0.1))
        XCTAssertEqual(
            controller.panelSizeForTesting(recordingID: recording.id),
            expectedPreviewSize
        )
        XCTAssertEqual(
            controller.contentFrameForTesting(recordingID: recording.id)?.size,
            expectedPreviewSize
        )
        XCTAssertEqual(
            controller.previewSurfaceFrameForTesting(recordingID: recording.id)?.size,
            expectedPreviewSize
        )
    }

    func testVideoQuickAccessScalesPreviewToRecordingAspectRatio() {
        XCTAssertEqual(
            VideoQuickAccessPanelController.previewSize(forSourceSize: CGSize(width: 1282, height: 504)),
            CGSize(width: 240, height: 94)
        )
        XCTAssertEqual(
            VideoQuickAccessPanelController.previewSize(forSourceSize: CGSize(width: 998, height: 734)),
            CGSize(width: 217, height: 160)
        )
    }

    func testVideoQuickAccessUsesFirstFrameThumbnailWhenAvailable() throws {
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
        let controller = VideoQuickAccessPanelController()

        controller.show(
            for: recording,
            preferredAnchor: CGRect(x: 0, y: 0, width: 100, height: 100),
            strings: AppStrings(language: .en),
            download: { true },
            copy: { true },
            preview: { true },
            close: {}
        )

        XCTAssertTrue(controller.hasThumbnailForTesting(recordingID: recording.id))
        XCTAssertEqual(RecordingThumbnailProvider().thumbnail(for: gifURL)?.size, CGSize(width: 2, height: 2))
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
}

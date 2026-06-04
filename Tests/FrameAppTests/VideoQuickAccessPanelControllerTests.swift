import AppKit
import ImageIO
import UniformTypeIdentifiers
import XCTest
@testable import FrameApp
@testable import FrameCore

@MainActor
final class VideoQuickAccessPanelControllerTests: XCTestCase {
    func testVideoQuickAccessExposesDownloadCopyPreviewAndDisabledEdit() {
        let recording = CapturedRecording(
            id: UUID(),
            fileURL: URL(fileURLWithPath: "/tmp/test.mp4"),
            format: .mp4,
            rect: CGRect(x: 0, y: 0, width: 320, height: 240),
            pixelSize: CGSize(width: 320, height: 240),
            byteSize: 10,
            duration: 24
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

        XCTAssertEqual(
            controller.actionLabelsForTesting(recordingID: recording.id),
            ["Download", "Copy", "Preview", "Edit", "Close"]
        )
        XCTAssertFalse(controller.isEditEnabledForTesting(recordingID: recording.id))
        XCTAssertEqual(
            controller.panelSizeForTesting(recordingID: recording.id),
            CapturePreviewMetrics.previewSize(forDesktopSize: NSScreen.main?.frame.size)
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

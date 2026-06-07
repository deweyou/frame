import XCTest
import AVKit
@testable import FrameApp
@testable import FrameCore

@MainActor
final class VideoPreviewWindowControllerTests: XCTestCase {
    func testPreviewWindowKeepsEditControlsDisabled() {
        let recording = CapturedRecording(
            id: UUID(),
            fileURL: URL(fileURLWithPath: "/tmp/test.mp4"),
            format: .mp4,
            rect: .zero,
            pixelSize: CGSize(width: 320, height: 240),
            byteSize: 10,
            duration: 24
        )
        let controller = VideoPreviewWindowController()

        controller.show(
            recording: recording,
            strings: AppStrings(language: .en),
            copy: { true },
            download: { true }
        )

        XCTAssertFalse(controller.isEditingEnabledForTesting(recordingID: recording.id))
    }

    func testGIFPreviewUsesAnimatedImageViewInsteadOfVideoPlayer() throws {
        let recording = CapturedRecording(
            id: UUID(),
            fileURL: URL(fileURLWithPath: "/tmp/test.gif"),
            format: .gif,
            rect: .zero,
            pixelSize: CGSize(width: 320, height: 240),
            byteSize: 10,
            duration: 24
        )
        let controller = VideoPreviewWindowController()

        controller.show(
            recording: recording,
            strings: AppStrings(language: .en),
            copy: { true },
            download: { true }
        )

        let window = try XCTUnwrap(controller.windowForTesting(recordingID: recording.id))
        let contentView = try XCTUnwrap(window.contentView)
        XCTAssertNil(findSubview(of: AVPlayerView.self, in: contentView))
        let imageView = try XCTUnwrap(findSubview(of: NSImageView.self, in: contentView))
        XCTAssertTrue(imageView.animates)
    }

    private func findSubview<T: NSView>(of type: T.Type, in view: NSView) -> T? {
        if let matchingView = view as? T {
            return matchingView
        }

        for subview in view.subviews {
            if let matchingView = findSubview(of: type, in: subview) {
                return matchingView
            }
        }

        return nil
    }
}

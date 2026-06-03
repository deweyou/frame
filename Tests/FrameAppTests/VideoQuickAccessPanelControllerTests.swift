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
    }
}

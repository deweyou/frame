import AppKit

enum CapturePreviewMetrics {
    static let previewWidth: CGFloat = 200
    static let fallbackAspectRatio: CGFloat = 132 / 200

    @MainActor
    static func desktopAspectRatio() -> CGFloat {
        aspectRatio(forDesktopSize: (NSScreen.main ?? NSScreen.screens.first)?.frame.size)
    }

    nonisolated static func aspectRatio(forDesktopSize desktopSize: CGSize?) -> CGFloat {
        guard let desktopSize,
              desktopSize.width > 0,
              desktopSize.height > 0 else {
            return fallbackAspectRatio
        }

        return desktopSize.height / desktopSize.width
    }

    nonisolated static func previewSize(
        forDesktopSize desktopSize: CGSize?,
        width: CGFloat = previewWidth
    ) -> CGSize {
        CGSize(width: width, height: floor(width * aspectRatio(forDesktopSize: desktopSize)))
    }

    nonisolated static func aspectFillDrawRect(imageSize: CGSize, in bounds: CGRect) -> CGRect {
        guard imageSize.width > 0,
              imageSize.height > 0,
              bounds.width > 0,
              bounds.height > 0 else {
            return .zero
        }

        let scale = max(bounds.width / imageSize.width, bounds.height / imageSize.height)
        let drawSize = CGSize(width: imageSize.width * scale, height: imageSize.height * scale)
        return CGRect(
            x: bounds.midX - drawSize.width / 2,
            y: bounds.midY - drawSize.height / 2,
            width: drawSize.width,
            height: drawSize.height
        )
    }
}

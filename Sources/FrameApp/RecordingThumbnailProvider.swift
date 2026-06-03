import AppKit
import AVFoundation
import ImageIO

struct RecordingThumbnailProvider {
    func thumbnail(for fileURL: URL) -> NSImage? {
        switch fileURL.pathExtension.lowercased() {
        case "gif":
            return thumbnailFromImageSource(fileURL)
        default:
            return thumbnailFromMovie(fileURL)
        }
    }

    private func thumbnailFromMovie(_ fileURL: URL) -> NSImage? {
        let asset = AVAsset(url: fileURL)
        let generator = AVAssetImageGenerator(asset: asset)
        generator.appliesPreferredTrackTransform = true
        generator.maximumSize = CGSize(width: 640, height: 640)

        do {
            let image = try generator.copyCGImage(at: CMTime(value: 0, timescale: 600), actualTime: nil)
            return NSImage(cgImage: image, size: .zero)
        } catch {
            return nil
        }
    }

    private func thumbnailFromImageSource(_ fileURL: URL) -> NSImage? {
        guard let source = CGImageSourceCreateWithURL(fileURL as CFURL, nil),
              let image = CGImageSourceCreateImageAtIndex(source, 0, nil) else {
            return nil
        }

        return NSImage(cgImage: image, size: .zero)
    }
}

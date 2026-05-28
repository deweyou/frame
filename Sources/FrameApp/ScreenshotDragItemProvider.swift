import AppKit
import UniformTypeIdentifiers

@MainActor
final class ScreenshotDragItemProvider {
    private var temporaryDirectoryURLs: [URL] = []
    private let maximumTemporaryDirectoryCount = 8

    func draggingItem(for screenshot: CapturedScreenshot, sourceBounds: NSRect) -> NSDraggingItem {
        let pasteboardItem = NSPasteboardItem()
        pasteboardItem.setData(screenshot.pngData, forType: .png)
        pasteboardItem.setString("Frame Screenshot.png", forType: .string)
        if let fileURL = makeTemporaryPNGFile(with: screenshot.pngData) {
            pasteboardItem.setString(fileURL.absoluteString, forType: .fileURL)
        }

        let draggingItem = NSDraggingItem(pasteboardWriter: pasteboardItem)
        draggingItem.setDraggingFrame(sourceBounds, contents: screenshot.image)
        return draggingItem
    }

    private func makeTemporaryPNGFile(with pngData: Data) -> URL? {
        let directoryURL = FileManager.default.temporaryDirectory
            .appendingPathComponent("FrameDrag-\(UUID().uuidString)", isDirectory: true)
        let fileURL = directoryURL.appendingPathComponent("Frame Screenshot.png", isDirectory: false)

        do {
            try FileManager.default.createDirectory(
                at: directoryURL,
                withIntermediateDirectories: true
            )
            try pngData.write(to: fileURL, options: .atomic)
            rememberTemporaryDirectory(directoryURL)
            return fileURL
        } catch {
            NSLog("Failed to create temporary drag PNG file: \(error.localizedDescription)")
            return nil
        }
    }

    private func rememberTemporaryDirectory(_ directoryURL: URL) {
        temporaryDirectoryURLs.append(directoryURL)
        while temporaryDirectoryURLs.count > maximumTemporaryDirectoryCount {
            let expiredDirectoryURL = temporaryDirectoryURLs.removeFirst()
            try? FileManager.default.removeItem(at: expiredDirectoryURL)
        }
    }
}

import Foundation
import FrameCore

final class ScreenshotFileWriter {
    private let fileManager: FileManager
    private let naming: ScreenshotNaming

    init(fileManager: FileManager = .default, naming: ScreenshotNaming = ScreenshotNaming()) {
        self.fileManager = fileManager
        self.naming = naming
    }

    func write(pngData: Data, date: Date = Date()) throws -> URL {
        let desktopDirectory = try ScreenshotNaming.desktopDirectory(fileManager: fileManager)
        let filename = naming.filename(for: date)
        let saveURL = ScreenshotNaming.saveURL(
            desktopDirectory: desktopDirectory,
            filename: filename
        )

        do {
            try pngData.write(to: saveURL, options: .atomic)
            return saveURL
        } catch {
            throw ScreenshotFileWriterError.writeFailed(url: saveURL, underlyingError: error)
        }
    }
}

private enum ScreenshotFileWriterError: Error, LocalizedError {
    case writeFailed(url: URL, underlyingError: Error)

    var errorDescription: String? {
        switch self {
        case let .writeFailed(url, underlyingError):
            "无法保存截图到 \(url.path)：\(underlyingError.localizedDescription)"
        }
    }
}

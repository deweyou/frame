import Foundation
import FrameCore

final class ScreenshotFileWriter {
    private let fileManager: FileManager
    private let naming: ScreenshotNaming
    private let saveDirectory: () throws -> URL
    private let strings: AppStrings

    init(
        fileManager: FileManager = .default,
        naming: ScreenshotNaming = ScreenshotNaming(),
        saveDirectory: @escaping () throws -> URL = { try SettingsStore.screenshotDirectory() },
        strings: AppStrings = AppStrings.current()
    ) {
        self.fileManager = fileManager
        self.naming = naming
        self.saveDirectory = saveDirectory
        self.strings = strings
    }

    func write(pngData: Data, date: Date = Date()) throws -> URL {
        let directory = try saveDirectory()
        let filename = naming.filename(for: date)
        let saveURL = ScreenshotNaming.saveURL(
            desktopDirectory: directory,
            filename: filename
        )

        do {
            try pngData.write(to: saveURL, options: .atomic)
            return saveURL
        } catch {
            throw ScreenshotFileWriterError.writeFailed(
                message: strings.saveFailedMessage(
                    path: saveURL.path,
                    errorDescription: error.localizedDescription
                )
            )
        }
    }
}

private enum ScreenshotFileWriterError: Error, LocalizedError {
    case writeFailed(message: String)

    var errorDescription: String? {
        switch self {
        case let .writeFailed(message):
            message
        }
    }
}

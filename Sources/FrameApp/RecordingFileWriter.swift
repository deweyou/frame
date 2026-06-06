import Foundation
import FrameCore

final class RecordingFileWriter {
    private let fileManager: FileManager
    private let naming: RecordingNaming
    private let saveDirectory: () throws -> URL

    init(
        fileManager: FileManager = .default,
        naming: RecordingNaming = RecordingNaming(),
        saveDirectory: @escaping () throws -> URL = { try SettingsStore.screenshotDirectory() }
    ) {
        self.fileManager = fileManager
        self.naming = naming
        self.saveDirectory = saveDirectory
    }

    func copyRecording(from sourceURL: URL, format: RecordingFormat, date: Date = Date()) throws -> URL {
        let directory = try saveDirectory()
        let destination = directory.appendingPathComponent(
            naming.filename(for: date, format: format),
            isDirectory: false
        )

        if fileManager.fileExists(atPath: destination.path) {
            try fileManager.removeItem(at: destination)
        }

        try fileManager.copyItem(at: sourceURL, to: destination)
        return destination
    }
}

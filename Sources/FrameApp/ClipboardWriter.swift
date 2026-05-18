import AppKit

@MainActor
final class ClipboardWriter {
    func write(image: NSImage) throws {
        let pasteboard = NSPasteboard.general
        pasteboard.clearContents()

        guard pasteboard.writeObjects([image]) else {
            throw ClipboardWriterError.writeFailed
        }
    }
}

private enum ClipboardWriterError: Error, LocalizedError {
    case writeFailed

    var errorDescription: String? {
        switch self {
        case .writeFailed:
            "无法将截图写入系统剪贴板。"
        }
    }
}

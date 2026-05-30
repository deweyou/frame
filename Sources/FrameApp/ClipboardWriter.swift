import AppKit

struct ClipboardWriter {
    private let pasteboard: NSPasteboard

    init(pasteboard: NSPasteboard = .general) {
        self.pasteboard = pasteboard
    }

    func write(image: NSImage) throws {
        pasteboard.clearContents()
        guard pasteboard.writeObjects([image]) else {
            throw ClipboardWriterError.writeFailed
        }
    }

    func write(text: String) throws {
        pasteboard.clearContents()
        guard pasteboard.setString(text, forType: .string) else {
            throw ClipboardWriterError.writeFailed
        }
    }
}

enum ClipboardWriterError: LocalizedError {
    case writeFailed

    var errorDescription: String? {
        "Failed to write to the clipboard."
    }
}

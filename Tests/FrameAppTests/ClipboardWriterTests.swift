import AppKit
import XCTest
@testable import FrameApp

final class ClipboardWriterTests: XCTestCase {
    func testWriteTextPlacesStringOnPasteboard() throws {
        let pasteboard = NSPasteboard(name: NSPasteboard.Name("FrameTests.\(UUID().uuidString)"))
        let writer = ClipboardWriter(pasteboard: pasteboard)

        try writer.write(text: "recognized text")

        XCTAssertEqual(pasteboard.string(forType: .string), "recognized text")
    }

    func testWriteFileURLPlacesFileOnPasteboard() throws {
        let pasteboard = NSPasteboard(name: NSPasteboard.Name("FrameTests.\(UUID().uuidString)"))
        let writer = ClipboardWriter(pasteboard: pasteboard)
        let url = URL(fileURLWithPath: "/tmp/FrameTestRecording.mp4")

        try writer.write(fileURL: url)

        let objects = pasteboard.readObjects(forClasses: [NSURL.self], options: nil) as? [URL]
        XCTAssertEqual(objects, [url])
    }
}

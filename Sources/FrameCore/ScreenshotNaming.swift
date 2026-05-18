import Foundation

public struct ScreenshotNaming: Sendable {
    private let calendar: Calendar
    private let timeZone: TimeZone

    public init(calendar: Calendar = .current, timeZone: TimeZone = .current) {
        var calendar = calendar
        calendar.timeZone = timeZone

        self.calendar = calendar
        self.timeZone = timeZone
    }

    public func filename(for date: Date = Date()) -> String {
        let components = calendar.dateComponents(
            in: timeZone,
            from: date
        )

        return String(
            format: "Frame %04d-%02d-%02d %02d.%02d.%02d.png",
            components.year ?? 0,
            components.month ?? 0,
            components.day ?? 0,
            components.hour ?? 0,
            components.minute ?? 0,
            components.second ?? 0
        )
    }

    public static func desktopDirectory(fileManager: FileManager = .default) throws -> URL {
        guard let desktopDirectory = fileManager.urls(
            for: .desktopDirectory,
            in: .userDomainMask
        ).first else {
            throw CocoaError(.fileNoSuchFile)
        }

        return desktopDirectory
    }

    public static func saveURL(desktopDirectory: URL, filename: String) -> URL {
        desktopDirectory.appendingPathComponent(filename, isDirectory: false)
    }
}

import Foundation

public struct RecordingNaming: Sendable {
    private let calendar: Calendar
    private let timeZone: TimeZone

    public init(calendar: Calendar = .current, timeZone: TimeZone = .current) {
        var calendar = calendar
        calendar.timeZone = timeZone
        self.calendar = calendar
        self.timeZone = timeZone
    }

    public func filename(for date: Date = Date(), format: RecordingFormat) -> String {
        let components = calendar.dateComponents(in: timeZone, from: date)
        return String(
            format: "Frame %04d-%02d-%02d %02d.%02d.%02d.%@",
            components.year ?? 0,
            components.month ?? 0,
            components.day ?? 0,
            components.hour ?? 0,
            components.minute ?? 0,
            components.second ?? 0,
            format.fileExtension
        )
    }
}

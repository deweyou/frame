public struct KeyboardShortcut: Equatable, Sendable {
    public let key: String
    public let displayName: String
    public let isReservedOnly: Bool

    public init(key: String, displayName: String, isReservedOnly: Bool = false) {
        self.key = key
        self.displayName = displayName
        self.isReservedOnly = isReservedOnly
    }

    public static let defaultScreenshot = KeyboardShortcut(
        key: "a",
        displayName: "Command+Shift+A"
    )

    public static let defaultRecording = KeyboardShortcut(
        key: "r",
        displayName: "Command+Shift+R",
        isReservedOnly: true
    )
}

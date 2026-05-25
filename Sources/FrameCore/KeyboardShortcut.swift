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

public enum ScreenshotShortcut: String, CaseIterable, Identifiable, Sendable {
    case commandShiftA
    case commandShiftS
    case commandShiftD
    case commandShiftF

    public var id: String {
        rawValue
    }

    public var keyboardShortcut: KeyboardShortcut {
        switch self {
        case .commandShiftA:
            KeyboardShortcut(key: "a", displayName: "Command+Shift+A")
        case .commandShiftS:
            KeyboardShortcut(key: "s", displayName: "Command+Shift+S")
        case .commandShiftD:
            KeyboardShortcut(key: "d", displayName: "Command+Shift+D")
        case .commandShiftF:
            KeyboardShortcut(key: "f", displayName: "Command+Shift+F")
        }
    }

    public static let `default`: ScreenshotShortcut = .commandShiftA

    public static func persistedValue(for rawValue: String?) -> ScreenshotShortcut {
        guard let rawValue,
              let shortcut = ScreenshotShortcut(rawValue: rawValue) else {
            return .default
        }

        return shortcut
    }
}

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

public enum ScreenshotShortcutModifier: String, CaseIterable, Hashable, Sendable {
    case command = "cmd"
    case option
    case control
    case shift

    public var symbol: String {
        switch self {
        case .command:
            "⌘"
        case .option:
            "⌥"
        case .control:
            "⌃"
        case .shift:
            "⇧"
        }
    }

    public var displayName: String {
        switch self {
        case .command:
            "Command"
        case .option:
            "Option"
        case .control:
            "Control"
        case .shift:
            "Shift"
        }
    }
}

public enum ScreenshotShortcutKey: Equatable, Hashable, Sendable {
    case letter(String)
    case number(String)
    case unsupported

    public var displayName: String {
        switch self {
        case let .letter(value), let .number(value):
            value.uppercased()
        case .unsupported:
            ""
        }
    }

    var storageValue: String? {
        switch self {
        case let .letter(value), let .number(value):
            value.lowercased()
        case .unsupported:
            nil
        }
    }

    var normalized: ScreenshotShortcutKey {
        switch self {
        case let .letter(value):
            .letter(String(value.prefix(1)).uppercased())
        case let .number(value):
            .number(String(value.prefix(1)))
        case .unsupported:
            .unsupported
        }
    }
}

public enum ScreenshotShortcutValidationFailure: Equatable, Sendable {
    case unsupportedKey
    case insufficientModifiers
    case reservedShortcut
    case duplicateShortcut
}

public enum ScreenshotShortcutValidationResult: Equatable, Sendable {
    case valid(ScreenshotShortcut)
    case invalid(ScreenshotShortcutValidationFailure)
}

public struct ScreenshotShortcut: Equatable, Hashable, Identifiable, Sendable {
    public let key: ScreenshotShortcutKey
    public let modifiers: Set<ScreenshotShortcutModifier>

    public init(key: ScreenshotShortcutKey, modifiers: Set<ScreenshotShortcutModifier>) {
        self.key = key.normalized
        self.modifiers = modifiers
    }

    public var id: String {
        storageValue
    }

    public var rawValue: String {
        legacyRawValue ?? storageValue
    }

    public var displayName: String {
        orderedModifiers.map(\.symbol).joined() + key.displayName
    }

    public var storageValue: String {
        (orderedModifiers.map(\.rawValue) + [key.storageValue ?? ""]).joined(separator: "+")
    }

    public var keyboardShortcut: KeyboardShortcut {
        KeyboardShortcut(
            key: key.storageValue ?? "",
            displayName: (orderedModifiers.map(\.displayName) + [key.displayName]).joined(separator: "+")
        )
    }

    public static let `default` = ScreenshotShortcut(key: .letter("A"), modifiers: [.command, .shift])
    public static let defaultRecording = ScreenshotShortcut(key: .letter("R"), modifiers: [.command, .shift])
    public static let commandShiftA = ScreenshotShortcut(key: .letter("A"), modifiers: [.command, .shift])
    public static let commandShiftS = ScreenshotShortcut(key: .letter("S"), modifiers: [.command, .shift])
    public static let commandShiftD = ScreenshotShortcut(key: .letter("D"), modifiers: [.command, .shift])
    public static let commandShiftF = ScreenshotShortcut(key: .letter("F"), modifiers: [.command, .shift])
    public static let allCases: [ScreenshotShortcut] = [
        .commandShiftA,
        .commandShiftS,
        .commandShiftD,
        .commandShiftF,
    ]

    public static func persistedValue(
        for rawValue: String?,
        defaultShortcut: ScreenshotShortcut = .default,
        reservedShortcuts: Set<ScreenshotShortcut> = [.defaultRecording]
    ) -> ScreenshotShortcut {
        guard let rawValue else {
            return defaultShortcut
        }

        if let legacyShortcut = legacyPresetStorage[rawValue] {
            return legacyShortcut
        }

        return shortcut(storageValue: rawValue, reservedShortcuts: reservedShortcuts) ?? defaultShortcut
    }

    public static func validate(
        key: ScreenshotShortcutKey,
        modifiers: Set<ScreenshotShortcutModifier>,
        reservedShortcuts: Set<ScreenshotShortcut> = [.defaultRecording],
        duplicateShortcut: ScreenshotShortcut? = nil
    ) -> ScreenshotShortcutValidationResult {
        let shortcut = ScreenshotShortcut(key: key, modifiers: modifiers)
        guard shortcut.key.isSupported else {
            return .invalid(.unsupportedKey)
        }

        guard shortcut.hasEnoughModifiers else {
            return .invalid(.insufficientModifiers)
        }

        if shortcut == duplicateShortcut {
            return .invalid(.duplicateShortcut)
        }

        guard !reservedShortcuts.contains(shortcut) else {
            return .invalid(.reservedShortcut)
        }

        return .valid(shortcut)
    }

    private static func shortcut(
        storageValue: String,
        reservedShortcuts: Set<ScreenshotShortcut>
    ) -> ScreenshotShortcut? {
        let components = storageValue
            .split(separator: "+")
            .map { String($0).lowercased() }

        guard components.count >= 3,
              let keyComponent = components.last,
              let key = ScreenshotShortcutKey(storageValue: keyComponent) else {
            return nil
        }

        var modifiers = Set<ScreenshotShortcutModifier>()
        for component in components.dropLast() {
            guard let modifier = ScreenshotShortcutModifier(storageValue: component) else {
                return nil
            }
            modifiers.insert(modifier)
        }

        switch validate(key: key, modifiers: modifiers, reservedShortcuts: reservedShortcuts) {
        case let .valid(shortcut):
            return shortcut
        case .invalid:
            return nil
        }
    }

    private var orderedModifiers: [ScreenshotShortcutModifier] {
        ScreenshotShortcutModifier.displayOrder.filter { modifiers.contains($0) }
    }

    private var hasEnoughModifiers: Bool {
        modifiers.count >= 2 && !modifiers.isDisjoint(with: [.command, .option, .control])
    }

    private var legacyRawValue: String? {
        switch self {
        case .commandShiftA:
            "commandShiftA"
        case .commandShiftS:
            "commandShiftS"
        case .commandShiftD:
            "commandShiftD"
        case .commandShiftF:
            "commandShiftF"
        default:
            nil
        }
    }
}

private let legacyPresetStorage: [String: ScreenshotShortcut] = [
    "commandShiftA": ScreenshotShortcut(key: .letter("A"), modifiers: [.command, .shift]),
    "commandShiftS": ScreenshotShortcut(key: .letter("S"), modifiers: [.command, .shift]),
    "commandShiftD": ScreenshotShortcut(key: .letter("D"), modifiers: [.command, .shift]),
    "commandShiftF": ScreenshotShortcut(key: .letter("F"), modifiers: [.command, .shift]),
]

private extension ScreenshotShortcutModifier {
    static let displayOrder: [ScreenshotShortcutModifier] = [.command, .option, .control, .shift]

    init?(storageValue: String) {
        switch storageValue {
        case "cmd", "command":
            self = .command
        case "option":
            self = .option
        case "control":
            self = .control
        case "shift":
            self = .shift
        default:
            return nil
        }
    }
}

private extension ScreenshotShortcutKey {
    init?(storageValue: String) {
        guard storageValue.count == 1,
              let scalar = storageValue.unicodeScalars.first else {
            return nil
        }

        switch scalar.value {
        case CharacterScalar.a...CharacterScalar.z:
            self = .letter(storageValue.uppercased())
        case CharacterScalar.zero...CharacterScalar.nine:
            self = .number(storageValue)
        default:
            return nil
        }
    }

    var isSupported: Bool {
        switch self {
        case let .letter(value):
            guard value.count == 1,
                  let scalar = value.uppercased().unicodeScalars.first else {
                return false
            }
            return (CharacterScalar.a...CharacterScalar.z).contains(scalar.value)
                || (CharacterScalar.capitalA...CharacterScalar.capitalZ).contains(scalar.value)
        case let .number(value):
            guard value.count == 1,
                  let scalar = value.unicodeScalars.first else {
                return false
            }
            return (CharacterScalar.zero...CharacterScalar.nine).contains(scalar.value)
        case .unsupported:
            return false
        }
    }
}

private enum CharacterScalar {
    static let zero = UnicodeScalar("0").value
    static let nine = UnicodeScalar("9").value
    static let capitalA = UnicodeScalar("A").value
    static let capitalZ = UnicodeScalar("Z").value
    static let a = UnicodeScalar("a").value
    static let z = UnicodeScalar("z").value
}

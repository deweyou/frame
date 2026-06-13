import Carbon
import FrameCore

@MainActor
final class HotKeyController {
    struct RegistrationParameters: Equatable {
        let keyCode: Int
        let modifierFlags: UInt32
    }

    var onScreenshot: (@MainActor () -> Void)?

    private(set) var shortcut: ScreenshotShortcut
    private var hotKeyRef: EventHotKeyRef?
    private var eventHandlerRef: EventHandlerRef?

    init(shortcut: ScreenshotShortcut = .default) {
        self.shortcut = shortcut
    }

    func register(shortcut: ScreenshotShortcut? = nil) throws {
        unregister()
        let shortcut = shortcut ?? self.shortcut

        var eventType = EventTypeSpec(
            eventClass: OSType(kEventClassKeyboard),
            eventKind: UInt32(kEventHotKeyPressed)
        )

        let installStatus = InstallEventHandler(
            GetApplicationEventTarget(),
            hotKeyHandler,
            1,
            &eventType,
            Unmanaged.passUnretained(self).toOpaque(),
            &eventHandlerRef
        )

        guard installStatus == noErr else {
            throw HotKeyRegistrationError.installEventHandlerFailed(installStatus)
        }

        let hotKeyID = EventHotKeyID(
            signature: screenshotHotKeySignature,
            id: screenshotHotKeyID
        )
        let parameters = Self.registrationParameters(for: shortcut)

        let registerStatus = RegisterEventHotKey(
            UInt32(parameters.keyCode),
            parameters.modifierFlags,
            hotKeyID,
            GetApplicationEventTarget(),
            0,
            &hotKeyRef
        )

        guard registerStatus == noErr else {
            unregister()
            throw HotKeyRegistrationError.registerHotKeyFailed(registerStatus, shortcut)
        }

        self.shortcut = shortcut
    }

    static func registrationParameters(for shortcut: ScreenshotShortcut) -> RegistrationParameters {
        RegistrationParameters(
            keyCode: shortcut.carbonKeyCode,
            modifierFlags: shortcut.carbonModifierFlags
        )
    }

    func unregister() {
        if let hotKeyRef {
            UnregisterEventHotKey(hotKeyRef)
            self.hotKeyRef = nil
        }

        if let eventHandlerRef {
            RemoveEventHandler(eventHandlerRef)
            self.eventHandlerRef = nil
        }
    }

}

private extension ScreenshotShortcut {
    var carbonKeyCode: Int {
        switch key {
        case .letter("A"):
            kVK_ANSI_A
        case .letter("B"):
            kVK_ANSI_B
        case .letter("C"):
            kVK_ANSI_C
        case .letter("D"):
            kVK_ANSI_D
        case .letter("E"):
            kVK_ANSI_E
        case .letter("F"):
            kVK_ANSI_F
        case .letter("G"):
            kVK_ANSI_G
        case .letter("H"):
            kVK_ANSI_H
        case .letter("I"):
            kVK_ANSI_I
        case .letter("J"):
            kVK_ANSI_J
        case .letter("K"):
            kVK_ANSI_K
        case .letter("L"):
            kVK_ANSI_L
        case .letter("M"):
            kVK_ANSI_M
        case .letter("N"):
            kVK_ANSI_N
        case .letter("O"):
            kVK_ANSI_O
        case .letter("P"):
            kVK_ANSI_P
        case .letter("Q"):
            kVK_ANSI_Q
        case .letter("R"):
            kVK_ANSI_R
        case .letter("S"):
            kVK_ANSI_S
        case .letter("T"):
            kVK_ANSI_T
        case .letter("U"):
            kVK_ANSI_U
        case .letter("V"):
            kVK_ANSI_V
        case .letter("W"):
            kVK_ANSI_W
        case .letter("X"):
            kVK_ANSI_X
        case .letter("Y"):
            kVK_ANSI_Y
        case .letter("Z"):
            kVK_ANSI_Z
        case .number("0"):
            kVK_ANSI_0
        case .number("1"):
            kVK_ANSI_1
        case .number("2"):
            kVK_ANSI_2
        case .number("3"):
            kVK_ANSI_3
        case .number("4"):
            kVK_ANSI_4
        case .number("5"):
            kVK_ANSI_5
        case .number("6"):
            kVK_ANSI_6
        case .number("7"):
            kVK_ANSI_7
        case .number("8"):
            kVK_ANSI_8
        case .number("9"):
            kVK_ANSI_9
        default:
            kVK_ANSI_A
        }
    }

    var carbonModifierFlags: UInt32 {
        var flags = 0
        if modifiers.contains(.command) {
            flags |= cmdKey
        }
        if modifiers.contains(.option) {
            flags |= optionKey
        }
        if modifiers.contains(.control) {
            flags |= controlKey
        }
        if modifiers.contains(.shift) {
            flags |= shiftKey
        }
        return UInt32(flags)
    }
}

enum HotKeyRegistrationError: Error, LocalizedError {
    case installEventHandlerFailed(OSStatus)
    case registerHotKeyFailed(OSStatus, ScreenshotShortcut)

    var errorDescription: String? {
        switch self {
        case let .installEventHandlerFailed(status):
            "安装全局快捷键监听失败（OSStatus: \(status)）"
        case let .registerHotKeyFailed(status, shortcut):
            "注册截图快捷键 \(shortcut.keyboardShortcut.displayName) 失败（OSStatus: \(status)）"
        }
    }
}

private let screenshotHotKeySignature = OSType(0x46524D41)
private let screenshotHotKeyID: UInt32 = 1

private let hotKeyHandler: EventHandlerUPP = { _, event, userData in
    guard let userData else {
        return noErr
    }

    var hotKeyID = EventHotKeyID()
    let parameterStatus = GetEventParameter(
        event,
        EventParamName(kEventParamDirectObject),
        EventParamType(typeEventHotKeyID),
        nil,
        MemoryLayout<EventHotKeyID>.size,
        nil,
        &hotKeyID
    )

    guard parameterStatus == noErr,
          hotKeyID.signature == screenshotHotKeySignature,
          hotKeyID.id == screenshotHotKeyID else {
        return noErr
    }

    let controllerPointer = UInt(bitPattern: userData)
    Task { @MainActor in
        let userData = UnsafeMutableRawPointer(bitPattern: controllerPointer)!
        let controller = Unmanaged<HotKeyController>.fromOpaque(userData).takeUnretainedValue()
        controller.onScreenshot?()
    }

    return noErr
}

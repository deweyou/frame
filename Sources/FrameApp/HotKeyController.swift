import Carbon

@MainActor
final class HotKeyController {
    var onScreenshot: (@MainActor () -> Void)?

    private var hotKeyRef: EventHotKeyRef?
    private var eventHandlerRef: EventHandlerRef?

    func register() throws {
        unregister()

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

        let registerStatus = RegisterEventHotKey(
            UInt32(kVK_ANSI_A),
            UInt32(cmdKey | shiftKey),
            hotKeyID,
            GetApplicationEventTarget(),
            0,
            &hotKeyRef
        )

        guard registerStatus == noErr else {
            unregister()
            throw HotKeyRegistrationError.registerHotKeyFailed(registerStatus)
        }
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

enum HotKeyRegistrationError: Error, LocalizedError {
    case installEventHandlerFailed(OSStatus)
    case registerHotKeyFailed(OSStatus)

    var errorDescription: String? {
        switch self {
        case let .installEventHandlerFailed(status):
            "安装全局快捷键监听失败（OSStatus: \(status)）"
        case let .registerHotKeyFailed(status):
            "注册截图快捷键 Command+Shift+A 失败（OSStatus: \(status)）"
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

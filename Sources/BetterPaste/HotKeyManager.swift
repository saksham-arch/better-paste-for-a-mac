import AppKit
import Carbon

@MainActor
final class HotKeyManager {
    private var hotKeyRef: EventHotKeyRef?
    private var handlerRef: EventHandlerRef?
    private let action: () -> Void
    private let carbonKeyCode: UInt32
    private let carbonModifiers: UInt32

    private let pointer: UnsafeMutablePointer<HotKeyManager>

    init(config: AppConfig, action: @escaping () -> Void) {
        self.action = action
        self.carbonKeyCode = Self.carbonKeyCode(for: config.pasteShortcut.key)
        self.carbonModifiers = Self.carbonModifiers(for: config.pasteShortcut.modifiers)
        self.pointer = .allocate(capacity: 1)
        self.pointer.initialize(to: self)
    }

    deinit {
        if let hotKeyRef {
            UnregisterEventHotKey(hotKeyRef)
        }
        if let handlerRef {
            RemoveEventHandler(handlerRef)
        }
        pointer.deinitialize(count: 1)
        pointer.deallocate()
    }

    func register() -> OSStatus {
        unregister()

        var eventType = EventTypeSpec(
            eventClass: OSType(kEventClassKeyboard),
            eventKind: UInt32(kEventHotKeyPressed)
        )

        let handlerStatus = InstallEventHandler(
            GetApplicationEventTarget(),
            hotKeyHandler,
            1,
            &eventType,
            pointer,
            &handlerRef
        )
        guard handlerStatus == noErr else { return handlerStatus }

        let hotKeyID = EventHotKeyID(
            signature: fourCharCode("BPST"),
            id: 1
        )

        let registerStatus = RegisterEventHotKey(
            carbonKeyCode,
            carbonModifiers,
            hotKeyID,
            GetApplicationEventTarget(),
            0,
            &hotKeyRef
        )

        if registerStatus != noErr {
            if let handlerRef {
                RemoveEventHandler(handlerRef)
                self.handlerRef = nil
            }
        }

        return registerStatus
    }

    func unregister() {
        if let hotKeyRef {
            UnregisterEventHotKey(hotKeyRef)
            self.hotKeyRef = nil
        }
        if let handlerRef {
            RemoveEventHandler(handlerRef)
            self.handlerRef = nil
        }
    }

    fileprivate func handleHotKey() {
        action()
    }

    private static func carbonKeyCode(for key: String) -> UInt32 {
        let mapping: [String: Int] = [
            "a": kVK_ANSI_A, "b": kVK_ANSI_B, "c": kVK_ANSI_C,
            "d": kVK_ANSI_D, "e": kVK_ANSI_E, "f": kVK_ANSI_F,
            "g": kVK_ANSI_G, "h": kVK_ANSI_H, "i": kVK_ANSI_I,
            "j": kVK_ANSI_J, "k": kVK_ANSI_K, "l": kVK_ANSI_L,
            "m": kVK_ANSI_M, "n": kVK_ANSI_N, "o": kVK_ANSI_O,
            "p": kVK_ANSI_P, "q": kVK_ANSI_Q, "r": kVK_ANSI_R,
            "s": kVK_ANSI_S, "t": kVK_ANSI_T, "u": kVK_ANSI_U,
            "v": kVK_ANSI_V, "w": kVK_ANSI_W, "x": kVK_ANSI_X,
            "y": kVK_ANSI_Y, "z": kVK_ANSI_Z,
            "0": kVK_ANSI_0, "1": kVK_ANSI_1, "2": kVK_ANSI_2,
            "3": kVK_ANSI_3, "4": kVK_ANSI_4, "5": kVK_ANSI_5,
            "6": kVK_ANSI_6, "7": kVK_ANSI_7, "8": kVK_ANSI_8,
            "9": kVK_ANSI_9,
            "space": kVK_Space, "return": kVK_Return, "tab": kVK_Tab,
            "escape": kVK_Escape, "delete": kVK_Delete,
            "f1": kVK_F1, "f2": kVK_F2, "f3": kVK_F3, "f4": kVK_F4,
            "f5": kVK_F5, "f6": kVK_F6, "f7": kVK_F7, "f8": kVK_F8,
            "f9": kVK_F9, "f10": kVK_F10, "f11": kVK_F11, "f12": kVK_F12,
        ]
        return UInt32(mapping[key.lowercased()] ?? kVK_ANSI_V)
    }

    private static func carbonModifiers(for modifiers: [String]) -> UInt32 {
        var flags: UInt32 = 0
        for mod in modifiers {
            switch mod.lowercased() {
            case "command", "cmd":   flags |= UInt32(cmdKey)
            case "control", "ctrl":  flags |= UInt32(controlKey)
            case "option", "alt":    flags |= UInt32(optionKey)
            case "shift":            flags |= UInt32(shiftKey)
            default: break
            }
        }
        return flags
    }

    private func fourCharCode(_ string: String) -> OSType {
        var result: OSType = 0
        for char in string.utf8.prefix(4) {
            result = (result << 8) | OSType(char)
        }
        return result
    }
}

private func hotKeyHandler(
    nextHandler: EventHandlerCallRef?,
    event: EventRef?,
    userData: UnsafeMutableRawPointer?
) -> OSStatus {
    guard let userData else { return OSStatus(eventNotHandledErr) }
    let manager = userData.assumingMemoryBound(to: HotKeyManager.self).pointee
    DispatchQueue.main.async {
        manager.handleHotKey()
    }
    return noErr
}

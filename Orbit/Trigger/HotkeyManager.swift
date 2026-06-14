import Carbon
import AppKit

// Global C-compatible callback — Carbon requires a plain function pointer.
private func hotkeyEventProc(
    _ nextHandler: EventHandlerCallRef?,
    _ event: EventRef?,
    _ userData: UnsafeMutableRawPointer?
) -> OSStatus {
    DispatchQueue.main.async { HotkeyManager.shared.onActivate?() }
    return noErr
}

/// Registers a global hotkey (⌘⇧D by default) via Carbon.
final class HotkeyManager {
    static let shared = HotkeyManager()
    var onActivate: (() -> Void)?

    private var hotKeyRef: EventHotKeyRef?
    private var handlerRef: EventHandlerRef?

    private init() {}

    func register() {
        var eventType = EventTypeSpec(
            eventClass: OSType(kEventClassKeyboard),
            eventKind: UInt32(kEventHotKeyPressed)
        )
        InstallEventHandler(
            GetApplicationEventTarget(),
            hotkeyEventProc,
            1, &eventType,
            nil,
            &handlerRef
        )
        // Signature 'ORBT' = 0x4F524254, id = 1, key D (keyCode 2), ⌘⇧
        let hotKeyID = EventHotKeyID(signature: 0x4F524254, id: 1)
        RegisterEventHotKey(
            2, // D
            UInt32(cmdKey | shiftKey),
            hotKeyID,
            GetApplicationEventTarget(),
            0,
            &hotKeyRef
        )
    }

    func unregister() {
        if let r = hotKeyRef { UnregisterEventHotKey(r); hotKeyRef = nil }
        if let r = handlerRef { RemoveEventHandler(r); handlerRef = nil }
    }
}

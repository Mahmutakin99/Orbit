import Carbon
import AppKit

// Global C-compatible callback — reads the hot key ID to dispatch to the right handler.
private func hotkeyEventProc(
    _ nextHandler: EventHandlerCallRef?,
    _ event: EventRef?,
    _ userData: UnsafeMutableRawPointer?
) -> OSStatus {
    var hkID = EventHotKeyID()
    GetEventParameter(event, EventParamName(kEventParamDirectObject),
                      EventParamType(typeEventHotKeyID), nil,
                      MemoryLayout<EventHotKeyID>.size, nil, &hkID)
    let id = hkID.id
    DispatchQueue.main.async {
        if id == 1 { HotkeyManager.shared.onActivate?() }
        else if id == 2 { HotkeyManager.shared.onActivateWindows?() }
    }
    return noErr
}

/// Registers two global hotkeys via Carbon:
///   id=1  ⌘⇧D — toggle radial menu
///   id=2  ⌘⇧W — toggle windows panel
final class HotkeyManager {
    static let shared = HotkeyManager()
    var onActivate: (() -> Void)?
    var onActivateWindows: (() -> Void)?

    private var hotKeyRef1: EventHotKeyRef?
    private var hotKeyRef2: EventHotKeyRef?
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
        // id=1: ⌘⇧D (keyCode 2) — radial menu
        RegisterEventHotKey(2, UInt32(cmdKey | shiftKey),
                            EventHotKeyID(signature: 0x4F524254, id: 1),
                            GetApplicationEventTarget(), 0, &hotKeyRef1)
        // id=2: ⌘⇧W (keyCode 13) — windows panel
        RegisterEventHotKey(13, UInt32(cmdKey | shiftKey),
                            EventHotKeyID(signature: 0x4F524254, id: 2),
                            GetApplicationEventTarget(), 0, &hotKeyRef2)
    }

    func unregister() {
        if let r = hotKeyRef1 { UnregisterEventHotKey(r); hotKeyRef1 = nil }
        if let r = hotKeyRef2 { UnregisterEventHotKey(r); hotKeyRef2 = nil }
        if let r = handlerRef { RemoveEventHandler(r); handlerRef = nil }
    }
}

//
//  HotKeyManager.swift
//  MicDrop
//
//  Same Carbon Hot Key Manager pattern proven out in Lint — a true
//  system-level global hotkey (Cmd+Option+D) that intercepts the key
//  combo before any other app sees it. No Accessibility permission
//  needed just to register/receive this; that's only required later,
//  for actually inserting text at the cursor.
//

import Carbon.HIToolbox
import AppKit

final class HotKeyManager {
    static let shared = HotKeyManager()

    /// Called on the main thread whenever the hotkey fires.
    var onHotKey: (() -> Void)?

    private var hotKeyRef: EventHotKeyRef?
    private var eventHandler: EventHandlerRef?

    private init() {}

    func register() {
        let signature: FourCharCode = 0x42424C31 // "BBL1"
        let hotKeyID = EventHotKeyID(signature: signature, id: 1)

        var eventType = EventTypeSpec(
            eventClass: OSType(kEventClassKeyboard),
            eventKind: UInt32(kEventHotKeyPressed)
        )

        let handlerStatus = InstallEventHandler(
            GetApplicationEventTarget(),
            { _, _, userData in
                debugLog("⌨️ hotkey event received")
                guard let userData else { return noErr }
                let manager = Unmanaged<HotKeyManager>.fromOpaque(userData).takeUnretainedValue()
                DispatchQueue.main.async {
                    manager.onHotKey?()
                }
                return noErr
            },
            1,
            &eventType,
            Unmanaged.passUnretained(self).toOpaque(),
            &eventHandler
        )
        debugLog("⌨️ InstallEventHandler status = \(handlerStatus)")

        let modifiers: UInt32 = UInt32(cmdKey | optionKey)
        let keyCode: UInt32 = UInt32(kVK_ANSI_D)

        let registerStatus = RegisterEventHotKey(
            keyCode,
            modifiers,
            hotKeyID,
            GetApplicationEventTarget(),
            0,
            &hotKeyRef
        )
        debugLog("⌨️ RegisterEventHotKey status = \(registerStatus) (0 = success)")
    }

    func unregister() {
        if let hotKeyRef {
            UnregisterEventHotKey(hotKeyRef)
            self.hotKeyRef = nil
        }
        if let eventHandler {
            RemoveEventHandler(eventHandler)
            self.eventHandler = nil
        }
    }
}

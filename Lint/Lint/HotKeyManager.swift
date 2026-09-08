//
//  HotKeyManager.swift
//  Lint
//
//  Registers a true system-level global hotkey (Cmd+Shift+V) using Carbon's
//  Hot Key Manager. This is the same mechanism apps like Alfred/Raycast use —
//  it intercepts the key combo at the OS level before any app sees it, so it
//  won't also trigger "Paste and Match Style" in whatever app is focused.
//
//  No Accessibility permission needed for this — that's only required for
//  apps that inject/consume arbitrary events or read other apps' UI, which
//  we're not doing here.
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
        // A unique 4-byte signature identifying our hotkey to the system.
        let signature: FourCharCode = 0x4C4E5431 // "LNT1"
        let hotKeyID = EventHotKeyID(signature: signature, id: 1)

        var eventType = EventTypeSpec(
            eventClass: OSType(kEventClassKeyboard),
            eventKind: UInt32(kEventHotKeyPressed)
        )

        // Install a handler that fires whenever ANY registered hotkey is pressed.
        // We only register one, so we know it's ours.
        let handlerStatus = InstallEventHandler(
            GetApplicationEventTarget(),
            { _, _, userData in
                print("🪄 Lint: hotkey event received")
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
        print("🪄 Lint: InstallEventHandler status = \(handlerStatus)")

        let modifiers: UInt32 = UInt32(cmdKey | shiftKey)
        let keyCode: UInt32 = UInt32(kVK_ANSI_V)

        let registerStatus = RegisterEventHotKey(
            keyCode,
            modifiers,
            hotKeyID,
            GetApplicationEventTarget(),
            0,
            &hotKeyRef
        )
        print("🪄 Lint: RegisterEventHotKey status = \(registerStatus) (0 = success)")
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

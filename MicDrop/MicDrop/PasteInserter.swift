//
//  PasteInserter.swift
//  MicDrop
//
//  Inserts text at the cursor the same way most dictation/snippet-expander
//  tools do: swap the clipboard, simulate Cmd+V, then restore whatever was
//  on the clipboard before. This needs Accessibility permission — posting
//  a synthetic keystroke system-wide is exactly the kind of thing macOS
//  gates behind that permission, unlike the hotkey registration itself.
//

import AppKit

struct PasteInserter {
    static var hasAccessibilityPermission: Bool {
        AXIsProcessTrusted()
    }

    /// Prompts the system permission dialog if not already granted. Returns
    /// immediately — the user has to actually grant it in System Settings,
    /// there's no synchronous "wait for grant" here.
    static func requestAccessibilityPermission() {
        let options: [String: Bool] = [kAXTrustedCheckOptionPrompt.takeRetainedValue() as String: true]
        AXIsProcessTrustedWithOptions(options as CFDictionary)
    }

    static func insertText(_ text: String) {
        let pasteboard = NSPasteboard.general
        let previousContents = pasteboard.string(forType: .string)

        pasteboard.clearContents()
        pasteboard.setString(text, forType: .string)

        simulatePaste()

        // Restore whatever was on the clipboard before, shortly after —
        // long enough for the paste to land, short enough that it doesn't
        // look like we silently clobbered the user's own clipboard.
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.6) {
            pasteboard.clearContents()
            if let previousContents {
                pasteboard.setString(previousContents, forType: .string)
            }
        }
    }

    private static func simulatePaste() {
        guard let source = CGEventSource(stateID: .hidSystemState) else { return }
        let vKeyCode: CGKeyCode = 0x09 // kVK_ANSI_V

        let keyDown = CGEvent(keyboardEventSource: source, virtualKey: vKeyCode, keyDown: true)
        keyDown?.flags = .maskCommand
        let keyUp = CGEvent(keyboardEventSource: source, virtualKey: vKeyCode, keyDown: false)
        keyUp?.flags = .maskCommand

        keyDown?.post(tap: .cghidEventTap)
        keyUp?.post(tap: .cghidEventTap)
    }
}

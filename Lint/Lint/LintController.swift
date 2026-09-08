//
//  LintController.swift
//  Lint
//
//  Owns the actual "clean the clipboard" action, shared by the hotkey and
//  the menu button.
//

import AppKit
import UserNotifications

@MainActor
final class LintController: ObservableObject {
    static let shared = LintController()

    @Published private(set) var isCleaning = false
    @Published private(set) var lastResult: String?

    private init() {}

    func cleanClipboard() async {
        guard !isCleaning else { return }

        guard let text = NSPasteboard.general.string(forType: .string),
              !text.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else {
            print("🪄 Lint: clipboard empty or not text — aborting")
            notify(title: "Lint", body: "Clipboard is empty or isn't text.")
            return
        }

        print("🪄 Lint: cleaning \(text.count) characters…")
        isCleaning = true
        defer { isCleaning = false }

        do {
            let cleaned = try await OllamaClient.cleanText(text)
            print("🪄 Lint: success — \(cleaned.count) characters back")
            NSPasteboard.general.clearContents()
            NSPasteboard.general.setString(cleaned, forType: .string)
            lastResult = cleaned
            // Playing this directly (instead of relying on the notification's
            // sound field) sidesteps a known quirk where macOS silently drops
            // sound for notifications a background/accessory app posts about
            // itself. This always plays.
            NSSound(named: "Glass")?.play()
            notify(title: "Lint ✨", body: "Clipboard cleaned — paste away.")
        } catch {
            print("🪄 Lint: FAILED — \(error)")
            lastResult = nil
            notify(title: "Lint — failed", body: error.localizedDescription)
        }
    }

    func requestNotificationPermission() {
        UNUserNotificationCenter.current().requestAuthorization(options: [.alert, .sound]) { _, _ in }
    }

    private func notify(title: String, body: String) {
        let content = UNMutableNotificationContent()
        content.title = title
        content.body = body
        content.sound = .default
        let request = UNNotificationRequest(
            identifier: UUID().uuidString,
            content: content,
            trigger: nil
        )
        UNUserNotificationCenter.current().add(request)
    }
}

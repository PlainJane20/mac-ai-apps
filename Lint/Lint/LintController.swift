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
            notify(title: "Lint", body: "Clipboard is empty or isn't text.")
            return
        }

        isCleaning = true
        defer { isCleaning = false }

        do {
            let cleaned = try await OllamaClient.cleanText(text)
            NSPasteboard.general.clearContents()
            NSPasteboard.general.setString(cleaned, forType: .string)
            lastResult = cleaned
            notify(title: "Lint ✨", body: "Clipboard cleaned — paste away.")
        } catch {
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
        content.sound = nil
        let request = UNNotificationRequest(
            identifier: UUID().uuidString,
            content: content,
            trigger: nil
        )
        UNUserNotificationCenter.current().add(request)
    }
}

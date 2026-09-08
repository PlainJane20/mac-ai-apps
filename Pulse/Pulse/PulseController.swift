//
//  PulseController.swift
//  Pulse
//
//  Owns the actual "fetch my tickets, summarize them" flow.
//

import AppKit
import UserNotifications

@MainActor
final class PulseController: ObservableObject {
    static let shared = PulseController()

    @Published private(set) var isConfigured: Bool = JiraCredentials.current != nil
    @Published private(set) var isLoading = false
    @Published private(set) var issues: [JiraIssue] = []
    @Published private(set) var brief: String?
    @Published private(set) var lastError: String?
    @Published private(set) var lastRefreshed: Date?

    private init() {}

    func refreshIfStale() {
        guard isConfigured else { return }
        let staleAfter: TimeInterval = 15 * 60
        if lastRefreshed == nil || Date().timeIntervalSince(lastRefreshed!) > staleAfter {
            Task { await refresh() }
        }
    }

    func refresh() async {
        guard isConfigured else { return }
        guard !isLoading else { return }

        isLoading = true
        defer { isLoading = false }
        lastError = nil

        do {
            let fetched = try await JiraClient.fetchMyActiveSprintIssues()
            issues = fetched
            let summary = try await OllamaClient.summarize(fetched)
            brief = summary
            lastRefreshed = Date()
            NSSound(named: "Glass")?.play()
            notify(
                title: "Pulse ✨",
                body: fetched.isEmpty ? "Nothing on your plate right now." : "\(fetched.count) ticket(s) — brief updated."
            )
        } catch {
            lastError = error.localizedDescription
            notify(title: "Pulse — failed", body: error.localizedDescription)
        }
    }

    func saveCredentials(baseURL: String, email: String, apiToken: String) {
        let creds = JiraCredentials(
            baseURL: baseURL.trimmingCharacters(in: .whitespacesAndNewlines),
            email: email.trimmingCharacters(in: .whitespacesAndNewlines),
            apiToken: apiToken.trimmingCharacters(in: .whitespacesAndNewlines)
        )
        creds.save()
        isConfigured = true
        Task { await refresh() }
    }

    func resetCredentials() {
        JiraCredentials.clear()
        isConfigured = false
        issues = []
        brief = nil
        lastRefreshed = nil
        lastError = nil
    }

    func requestNotificationPermission() {
        UNUserNotificationCenter.current().requestAuthorization(options: [.alert, .sound]) { _, _ in }
    }

    private func notify(title: String, body: String) {
        let content = UNMutableNotificationContent()
        content.title = title
        content.body = body
        content.sound = .default
        UNUserNotificationCenter.current().add(
            UNNotificationRequest(identifier: UUID().uuidString, content: content, trigger: nil)
        )
    }
}

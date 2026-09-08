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

    /// Local hour (24h) the daily digest fires at, once per day.
    private let digestHour = 9
    private var digestTimer: Timer?

    private init() {}

    /// For building "open this ticket" links — nil if not configured yet.
    var jiraBaseURL: String? {
        JiraCredentials.current?.normalizedBaseURL
    }

    var breakdown: StatusBreakdown {
        StatusBreakdown(issues)
    }

    /// Ticket count per assignee, highest first — deterministic, computed
    /// directly from the fetched issues. Mostly meaningful once
    /// watchedProjectKey pulls in teammates' tickets too; with just your
    /// own tickets, this trivially shows one name.
    var assigneeCounts: [(name: String, count: Int)] {
        var counts: [String: Int] = [:]
        for issue in issues {
            counts[issue.assigneeName ?? "Unassigned", default: 0] += 1
        }
        return counts.sorted { lhs, rhs in
            lhs.value != rhs.value ? lhs.value > rhs.value : lhs.key < rhs.key
        }.map { (name: $0.key, count: $0.value) }
    }

    /// Issues grouped by project, each group's tickets sorted overdue-first,
    /// then stale, then by priority — so whatever actually needs attention
    /// surfaces at the top instead of staying in raw API order. Each group
    /// carries the actual Jira sprint name/end date when Jira exposes one.
    var issuesByProject: [(projectKey: String, projectName: String, sprintName: String?, sprintEndDate: Date?, issues: [JiraIssue])] {
        var order: [String] = []
        var grouped: [String: [JiraIssue]] = [:]
        for issue in issues {
            if grouped[issue.projectKey] == nil {
                order.append(issue.projectKey)
                grouped[issue.projectKey] = []
            }
            grouped[issue.projectKey]?.append(issue)
        }
        return order.map { key in
            let groupIssues = (grouped[key] ?? []).sorted { a, b in
                if a.isOverdue != b.isOverdue { return a.isOverdue }
                if a.isStale != b.isStale { return a.isStale }
                return a.priorityRank < b.priorityRank
            }
            return (
                projectKey: key,
                projectName: groupIssues.first?.projectName ?? key,
                sprintName: groupIssues.first?.sprintName,
                sprintEndDate: groupIssues.first?.sprintEndDate,
                issues: groupIssues
            )
        }
    }

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
            let breakdownForBrief = StatusBreakdown(fetched)
            let deterministicBrief = Self.deterministicBrief(breakdownForBrief)

            // The LLM narrative gets used ONLY if it passes sanity checks
            // against ground truth. Confirmed across two different local
            // models, four separate ways, that this task is not reliable at
            // real-world scale (21 tickets): hallucinating "is blocked" on
            // every item, dumping a bare list with no synthesis, flatly
            // denying tickets exist despite receiving them in the prompt,
            // and — even when otherwise coherent — enumerating individual
            // ticket keys that just duplicate the ticket list already shown
            // elsewhere in the UI. A deterministic sentence is always
            // correct and never redundant; the LLM narrative only earns its
            // place when it adds real value instead of noise.
            let llmSummaryText = try? await OllamaClient.summarize(fetched)
            let looksLikeTicketDump = llmSummaryText.map { text in
                fetched.contains { text.contains($0.key) }
            } ?? false

            if let llmSummary = llmSummaryText,
               llmSummary.contains(String(breakdownForBrief.total)),
               !looksLikeTicketDump {
                brief = llmSummary
            } else {
                brief = deterministicBrief
            }
            lastRefreshed = Date()
            NSSound(named: "Glass")?.play()
            let breakdown = StatusBreakdown(fetched)
            let flags = [
                breakdown.overdue > 0 ? "\(breakdown.overdue) overdue" : nil,
                breakdown.stale > 0 ? "\(breakdown.stale) stale" : nil,
            ].compactMap { $0 }.joined(separator: ", ")
            notify(
                title: "Pulse ✨",
                body: fetched.isEmpty
                    ? "Nothing on your plate right now."
                    : "\(fetched.count) ticket(s)\(flags.isEmpty ? "" : " — \(flags)") — brief updated."
            )
        } catch {
            lastError = error.localizedDescription
            notify(title: "Pulse — failed", body: error.localizedDescription)
        }
    }

    func saveCredentials(baseURL: String, email: String, apiToken: String, watchedProjectKey: String) {
        let trimmedProject = watchedProjectKey.trimmingCharacters(in: .whitespacesAndNewlines)
        let creds = JiraCredentials(
            baseURL: baseURL.trimmingCharacters(in: .whitespacesAndNewlines),
            email: email.trimmingCharacters(in: .whitespacesAndNewlines),
            apiToken: apiToken.trimmingCharacters(in: .whitespacesAndNewlines),
            watchedProjectKey: trimmedProject.isEmpty ? nil : trimmedProject
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

    /// A ready-to-paste standup update: What I did (recently updated/done),
    /// Today (in progress), Blockers (overdue/stale). Deterministic text
    /// formatting, not LLM-generated — the brief already covers narrative
    /// summary; this is a structured export of the same data.
    var standupText: String {
        guard !issues.isEmpty else { return "Nothing currently assigned in an active sprint." }

        let done = issues.filter { $0.statusCategory == "Done" }
        let inProgress = issues.filter { $0.statusCategory == "In Progress" }
        let blockers = issues.filter { $0.isOverdue || $0.isStale }

        var lines: [String] = ["Standup — \(Date().formatted(date: .abbreviated, time: .omitted))", ""]

        if !done.isEmpty {
            lines.append("What I did:")
            lines.append(contentsOf: done.map { "- \($0.key): \($0.summary)" })
            lines.append("")
        }
        lines.append("Today:")
        lines.append(contentsOf: inProgress.isEmpty
            ? ["- (nothing in progress)"]
            : inProgress.map { "- \($0.key): \($0.summary)" })

        if !blockers.isEmpty {
            lines.append("")
            lines.append("Blockers:")
            lines.append(contentsOf: blockers.map { issue in
                let tag = issue.isOverdue ? "overdue" : "stale \(issue.daysSinceUpdate ?? 0)d"
                return "- \(issue.key): \(issue.summary) (\(tag))"
            })
        }

        return lines.joined(separator: "\n")
    }

    func copyStandupToClipboard() {
        NSPasteboard.general.clearContents()
        NSPasteboard.general.setString(standupText, forType: .string)
        NSSound(named: "Pop")?.play()
    }

    /// Always correct by construction — this is what refresh() falls back
    /// to when the LLM's narrative fails the sanity check against these
    /// same numbers. Deliberately does NOT restate the raw to-do/in-progress
    /// /done counts — those are already big and visible in the stat row
    /// right below this text, so repeating them here is pure noise. This
    /// says only the "so what" the stat row can't: whether it's worth a
    /// second look today.
    static func deterministicBrief(_ breakdown: StatusBreakdown) -> String {
        guard breakdown.total > 0 else {
            return "Nothing currently assigned in an active sprint."
        }
        guard breakdown.overdue > 0 || breakdown.stale > 0 else {
            return "Nothing overdue or stale — steady state."
        }
        var parts: [String] = []
        if breakdown.overdue > 0 { parts.append("\(breakdown.overdue) ticket(s) overdue") }
        if breakdown.stale > 0 { parts.append("\(breakdown.stale) gone 3+ days without an update") }
        return parts.joined(separator: ", ") + " — worth a check-in."
    }

    // MARK: - Daily digest

    /// Runs as a background app the whole day (Login Item), so a simple
    /// in-process timer is enough — no need for launchd/cron. Checks every
    /// 5 minutes whether it's the target hour and today's digest hasn't
    /// already fired; UserDefaults tracks the last-fired date so it only
    /// notifies once per day even though the check runs repeatedly.
    func startDailyDigestTimer() {
        digestTimer?.invalidate()
        digestTimer = Timer.scheduledTimer(withTimeInterval: 300, repeats: true) { [weak self] _ in
            Task { @MainActor in self?.checkDailyDigest() }
        }
    }

    private func checkDailyDigest() {
        guard isConfigured else { return }
        let now = Date()
        guard Calendar.current.component(.hour, from: now) == digestHour else { return }

        let key = "lastDigestDate"
        let today = Calendar.current.startOfDay(for: now)
        if let last = UserDefaults.standard.object(forKey: key) as? Date,
           Calendar.current.isDate(last, inSameDayAs: today) {
            return
        }
        UserDefaults.standard.set(today, forKey: key)
        Task { await refresh() }
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

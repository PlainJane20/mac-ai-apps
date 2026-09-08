//
//  ContentView.swift
//  Pulse
//
//  The popover shown when you click the menu bar icon — either the
//  first-run Jira setup form, or the actual brief.
//

import SwiftUI
import AppKit

struct ContentView: View {
    @ObservedObject private var controller = PulseController.shared

    var body: some View {
        Group {
            if controller.isConfigured {
                BriefView()
            } else {
                SetupView()
            }
        }
        .onAppear {
            controller.refreshIfStale()
        }
    }
}

struct SetupView: View {
    @ObservedObject private var controller = PulseController.shared
    @State private var baseURL = ""
    @State private var email = ""
    @State private var apiToken = ""
    @State private var watchedProjectKey = ""

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            HStack {
                Image(systemName: "waveform.path.ecg")
                Text("Pulse").font(.headline)
            }

            Text("Connect your Jira account. Stored locally on this Mac — never in a file that's committed anywhere.")
                .font(.caption)
                .foregroundStyle(.secondary)

            Divider()

            TextField("Jira URL — e.g. https://yourcompany.atlassian.net", text: $baseURL)
                .textFieldStyle(.roundedBorder)
            TextField("Email", text: $email)
                .textFieldStyle(.roundedBorder)
            SecureField("API Token", text: $apiToken)
                .textFieldStyle(.roundedBorder)

            Text("Generate a token at id.atlassian.com → Manage account → Security → API tokens")
                .font(.caption2)
                .foregroundStyle(.secondary)

            Divider()

            TextField("Also watch this project's sprint (optional) — e.g. PROJ", text: $watchedProjectKey)
                .textFieldStyle(.roundedBorder)
            Text("Shows every ticket in that project's active sprint, not just yours. Leave blank to see only your own tickets.")
                .font(.caption2)
                .foregroundStyle(.secondary)

            Button("Save & Connect") {
                controller.saveCredentials(
                    baseURL: baseURL,
                    email: email,
                    apiToken: apiToken,
                    watchedProjectKey: watchedProjectKey
                )
            }
            .disabled(baseURL.isEmpty || email.isEmpty || apiToken.isEmpty)

            Divider()

            Button("Quit Pulse") {
                NSApp.terminate(nil)
            }
        }
        .padding(12)
        .frame(width: 320)
    }
}

struct BriefView: View {
    @ObservedObject private var controller = PulseController.shared
    @State private var justCopied = false

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            HStack {
                Image(systemName: "waveform.path.ecg")
                Text("Pulse").font(.headline)
                Spacer()
                if controller.isLoading {
                    ProgressView().controlSize(.small)
                } else {
                    Button {
                        Task { await controller.refresh() }
                    } label: {
                        Image(systemName: "arrow.clockwise")
                    }
                    .buttonStyle(.plain)
                }
            }

            if let lastRefreshed = controller.lastRefreshed {
                Text("Updated \(lastRefreshed.formatted(date: .omitted, time: .shortened))")
                    .font(.caption2)
                    .foregroundStyle(.secondary)
            }

            Divider()

            if let error = controller.lastError {
                Text(error)
                    .font(.callout)
                    .foregroundStyle(.red)
            } else if let brief = controller.brief {
                // No ScrollView here on purpose — inside a self-sizing
                // MenuBarExtra popover, a ScrollView has no intrinsic size
                // and silently collapses to zero height without an explicit
                // minHeight. Briefs are short (2-4 sentences); a plain Text
                // just grows naturally with its content.
                Text(brief)
                    .font(.callout)
                    .fixedSize(horizontal: false, vertical: true)
                    .frame(maxWidth: .infinity, alignment: .leading)
            } else {
                Text("No brief yet — click refresh.")
                    .font(.callout)
                    .foregroundStyle(.secondary)
            }

            if !controller.issues.isEmpty {
                Divider()
                BreakdownRow(breakdown: controller.breakdown)
                if controller.assigneeCounts.count > 1 {
                    Divider()
                    AssigneeBreakdownView(counts: controller.assigneeCounts)
                }
                Divider()
                TicketListView(
                    groups: controller.issuesByProject,
                    baseURL: controller.jiraBaseURL
                )
                Divider()
                Button(justCopied ? "Copied ✓" : "Copy for Standup") {
                    controller.copyStandupToClipboard()
                    justCopied = true
                    DispatchQueue.main.asyncAfter(deadline: .now() + 1.5) {
                        justCopied = false
                    }
                }
            }

            Divider()

            Button("Reset Jira Credentials") {
                controller.resetCredentials()
            }
            Button("Quit Pulse") {
                NSApp.terminate(nil)
            }
        }
        .padding(12)
        .frame(width: 320)
    }
}

/// Deterministic counts, computed from the fetched issues — not something
/// asked of the LLM. Small local models are unreliable with exact numbers.
struct BreakdownRow: View {
    let breakdown: StatusBreakdown

    var body: some View {
        VStack(spacing: 6) {
            HStack(spacing: 14) {
                stat("Total", breakdown.total)
                stat("To Do", breakdown.toDo)
                stat("In Prog.", breakdown.inProgress)
                stat("Done", breakdown.done)
            }
            if breakdown.overdue > 0 || breakdown.stale > 0 {
                HStack(spacing: 14) {
                    if breakdown.overdue > 0 {
                        Label("\(breakdown.overdue) overdue", systemImage: "exclamationmark.triangle.fill")
                            .font(.caption2)
                            .foregroundStyle(.red)
                    }
                    if breakdown.stale > 0 {
                        Label("\(breakdown.stale) stale", systemImage: "clock.fill")
                            .font(.caption2)
                            .foregroundStyle(.orange)
                    }
                    Spacer()
                }
            }
        }
    }

    private func stat(_ label: String, _ value: Int) -> some View {
        VStack(spacing: 2) {
            Text("\(value)").font(.caption.bold())
            Text(label).font(.caption2).foregroundStyle(.secondary)
        }
        .frame(maxWidth: .infinity)
    }
}

/// Deterministic ticket count per assignee — capped at 10 rows, same
/// "cap instead of ScrollView" pattern used everywhere else in this view.
struct AssigneeBreakdownView: View {
    let counts: [(name: String, count: Int)]

    private let maxRows = 10

    var body: some View {
        VStack(alignment: .leading, spacing: 4) {
            Text("By assignee")
                .font(.caption.bold())
                .foregroundStyle(.secondary)
            ForEach(counts.prefix(maxRows), id: \.name) { entry in
                HStack {
                    Text(entry.name)
                        .font(.caption)
                        .lineLimit(1)
                    Spacer()
                    Text("\(entry.count)")
                        .font(.caption.monospacedDigit())
                        .foregroundStyle(.secondary)
                }
            }
            if counts.count > maxRows {
                Text("+ \(counts.count - maxRows) more")
                    .font(.caption2)
                    .foregroundStyle(.secondary)
            }
        }
    }
}

/// Grouped by project, each header showing the actual Jira sprint name and
/// a countdown to its end date (e.g. "PROJ — Sprint PROJ-2026-18 (ends in 3d) (5)")
/// when Jira exposes one for that project's board.
///
/// No ScrollView on purpose, same lesson as the brief text above: a
/// ScrollView inside this self-sizing popover has no intrinsic height and
/// silently collapses. Capping the row count and letting the VStack grow
/// naturally sidesteps that entirely.
struct TicketListView: View {
    let groups: [(projectKey: String, projectName: String, sprintName: String?, sprintEndDate: Date?, issues: [JiraIssue])]
    let baseURL: String?

    private let maxRows = 20

    private enum Row: Identifiable {
        case header(name: String, sprintName: String?, sprintEndDate: Date?, count: Int)
        case ticket(JiraIssue)

        var id: String {
            switch self {
            case .header(let name, _, _, _): return "header-\(name)"
            case .ticket(let issue): return issue.id
            }
        }
    }

    // Precomputed as a plain flat array rather than mutating state inside
    // the view builder — mutating a captured var from within a ForEach
    // closure isn't guaranteed to evaluate in a predictable order under
    // SwiftUI's diffing, so the count-so-far it produces can't be trusted.
    private var rows: [Row] {
        var result: [Row] = []
        var shown = 0
        for group in groups {
            if shown >= maxRows { break }
            result.append(.header(
                name: group.projectName,
                sprintName: group.sprintName,
                sprintEndDate: group.sprintEndDate,
                count: group.issues.count
            ))
            for issue in group.issues {
                if shown >= maxRows { break }
                result.append(.ticket(issue))
                shown += 1
            }
        }
        return result
    }

    private func countdownText(_ endDate: Date?) -> String? {
        guard let endDate else { return nil }
        let days = Calendar.current.dateComponents(
            [.day], from: Calendar.current.startOfDay(for: Date()), to: Calendar.current.startOfDay(for: endDate)
        ).day ?? 0
        if days < 0 { return "ended \(-days)d ago" }
        if days == 0 { return "ends today" }
        if days == 1 { return "ends tomorrow" }
        return "ends in \(days)d"
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            ForEach(rows) { row in
                switch row {
                case .header(let name, let sprintName, let sprintEndDate, let count):
                    // Two lines on purpose — long project names were eating
                    // the horizontal space the sprint countdown needed,
                    // truncating it off-screen entirely in one combined line.
                    VStack(alignment: .leading, spacing: 1) {
                        Text("\(name) (\(count))")
                            .font(.caption.bold())
                            .foregroundStyle(.secondary)
                            .lineLimit(1)
                            .truncationMode(.tail)
                        if let sprintName {
                            Text(countdownText(sprintEndDate).map { "\(sprintName) — \($0)" } ?? sprintName)
                                .font(.caption2)
                                .foregroundStyle(.secondary)
                        }
                    }
                case .ticket(let issue):
                    TicketRow(issue: issue, baseURL: baseURL)
                }
            }

            let totalCount = groups.reduce(0) { $0 + $1.issues.count }
            if totalCount > maxRows {
                Text("+ \(totalCount - maxRows) more — open Jira to see all")
                    .font(.caption2)
                    .foregroundStyle(.secondary)
            }
        }
    }
}

struct TicketRow: View {
    let issue: JiraIssue
    let baseURL: String?

    var body: some View {
        Button {
            openInBrowser()
        } label: {
            HStack(alignment: .top, spacing: 6) {
                if issue.isOverdue {
                    Image(systemName: "exclamationmark.triangle.fill")
                        .font(.caption2)
                        .foregroundStyle(.red)
                } else if issue.isStale {
                    Image(systemName: "clock.fill")
                        .font(.caption2)
                        .foregroundStyle(.orange)
                } else if issue.isDueSoon {
                    Image(systemName: "calendar")
                        .font(.caption2)
                        .foregroundStyle(.yellow)
                }
                Text(issue.key)
                    .font(.caption.monospaced())
                    .foregroundStyle(.secondary)
                Text(issue.summary)
                    .font(.caption)
                    .lineLimit(1)
                    .truncationMode(.tail)
                Spacer(minLength: 4)
                Text(issue.status)
                    .font(.caption2)
                    .foregroundStyle(.secondary)
            }
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .help(helpText)
    }

    private var helpText: String {
        var parts = ["Open \(issue.key) in Jira"]
        if issue.isOverdue { parts.append("overdue") }
        if issue.isStale { parts.append("stale \(issue.daysSinceUpdate ?? 0)d") }
        return parts.joined(separator: " — ")
    }

    private func openInBrowser() {
        guard let baseURL, let url = URL(string: "\(baseURL)/browse/\(issue.key)") else { return }
        NSWorkspace.shared.open(url)
    }
}

#Preview {
    ContentView()
}

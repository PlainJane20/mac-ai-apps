//
//  JiraClient.swift
//  Pulse
//
//  Pulls YOUR tickets in any currently-active sprint, across every board and
//  project you have access to — no hardcoded board ID or project key. That's
//  the whole point: this works against any Jira Cloud instance, and there's
//  nothing company-specific baked into the source.
//

import Foundation

enum JiraError: Error, LocalizedError {
    case notConfigured
    case invalidBaseURL(String)
    case badResponse(Int)

    var errorDescription: String? {
        switch self {
        case .notConfigured:
            return "Jira isn't set up yet — add your credentials first."
        case .invalidBaseURL(let url):
            return "\"\(url)\" isn't a valid URL — check for typos (e.g. https://yourcompany.atlassian.net)."
        case .badResponse(let code):
            return "Jira returned HTTP \(code)."
        }
    }
}

struct JiraIssue: Identifiable, Hashable {
    var id: String { key }
    let key: String
    let summary: String
    let status: String
    /// Jira's own bucket for the status ("new" / "indeterminate" / "done"),
    /// independent of whatever custom status names a project's workflow
    /// uses. This is what makes a reliable To Do/In Progress/Done count
    /// possible without hardcoding status name strings.
    let statusCategory: String
    let issueType: String
    let projectKey: String
    let projectName: String
    let priority: String?
    /// The actual active sprint name (e.g. "PROJ-2026-18"), if Jira exposes
    /// one for this issue. nil for boards/projects with no sprint concept.
    let sprintName: String?
    let sprintEndDate: Date?
    /// nil means unassigned. Only meaningful once watchedProjectKey pulls in
    /// tickets beyond just your own — otherwise everything is trivially you.
    let assigneeName: String?
    let updated: Date?
    let dueDate: Date?

    /// Common Jira priority names ranked for sorting; unrecognized/custom
    /// priority names fall back to a middle rank rather than erroring.
    var priorityRank: Int {
        switch priority?.lowercased() {
        case "highest": return 0
        case "high": return 1
        case "medium": return 2
        case "low": return 3
        case "lowest": return 4
        default: return 2
        }
    }

    var daysSinceUpdate: Int? {
        guard let updated else { return nil }
        return Calendar.current.dateComponents(
            [.day], from: Calendar.current.startOfDay(for: updated), to: Calendar.current.startOfDay(for: Date())
        ).day
    }

    /// In Progress but untouched for a while — the kind of quiet stall a
    /// TPM actually needs to know about, not just raw status.
    var isStale: Bool {
        statusCategory == "In Progress" && (daysSinceUpdate ?? 0) >= 3
    }

    var isOverdue: Bool {
        guard let dueDate, statusCategory != "Done" else { return false }
        return dueDate < Calendar.current.startOfDay(for: Date())
    }

    var isDueSoon: Bool {
        guard let dueDate, !isOverdue, statusCategory != "Done" else { return false }
        let days = Calendar.current.dateComponents(
            [.day], from: Calendar.current.startOfDay(for: Date()), to: Calendar.current.startOfDay(for: dueDate)
        ).day ?? 999
        return days <= 3
    }
}

/// Deterministic counts — computed directly from the fetched issues, not
/// left to the LLM to tally (small models are unreliable with exact
/// numbers, as the earlier prompt debugging showed).
struct StatusBreakdown {
    let total: Int
    let toDo: Int
    let inProgress: Int
    let done: Int
    let overdue: Int
    let stale: Int

    init(_ issues: [JiraIssue]) {
        total = issues.count
        toDo = issues.filter { $0.statusCategory == "To Do" }.count
        inProgress = issues.filter { $0.statusCategory == "In Progress" }.count
        done = issues.filter { $0.statusCategory == "Done" }.count
        overdue = issues.filter { $0.isOverdue }.count
        stale = issues.filter { $0.isStale }.count
    }
}

struct JiraClient {
    /// The base query is just "your tickets, any active sprint, any
    /// project" — no board ID or project key baked in, so this works
    /// against any Jira instance. If the user has configured a
    /// watchedProjectKey locally (e.g. "PROJ"), we broaden it to also
    /// include every ticket in that project's active sprint, not just
    /// their own — useful for seeing full team/sprint context, not just
    /// personal assignments.
    private static func jql(for creds: JiraCredentials) -> String {
        guard let project = creds.watchedProjectKey?.trimmingCharacters(in: .whitespacesAndNewlines),
              !project.isEmpty else {
            return "assignee = currentUser() AND sprint in openSprints() ORDER BY project ASC, updated DESC"
        }
        // Strip quotes defensively — project keys are short alphanumeric
        // identifiers, but never trust free-text input inside a query string.
        let safeProject = project.replacingOccurrences(of: "\"", with: "")
        return "(assignee = currentUser() OR project = \"\(safeProject)\") AND sprint in openSprints() ORDER BY project ASC, updated DESC"
    }

    // The Sprint field lives at a dynamically-numbered custom field
    // (customfield_XXXXX) that varies per Jira instance — there's no fixed
    // key to decode. Discovered once per app run via /rest/api/3/field and
    // cached, rather than hardcoded for any one company's instance.
    private static var cachedSprintFieldID: String?

    private static func sprintFieldID(creds: JiraCredentials) async -> String? {
        if let cached = cachedSprintFieldID { return cached }
        guard let url = URL(string: creds.normalizedBaseURL + "/rest/api/3/field") else { return nil }
        var request = URLRequest(url: url)
        request.setValue(creds.authHeader, forHTTPHeaderField: "Authorization")
        request.setValue("application/json", forHTTPHeaderField: "Accept")
        guard let (data, response) = try? await URLSession.shared.data(for: request),
              let http = response as? HTTPURLResponse, (200..<300).contains(http.statusCode) else {
            return nil
        }
        struct FieldInfo: Decodable { let id: String; let name: String }
        guard let fields = try? JSONDecoder().decode([FieldInfo].self, from: data) else { return nil }
        let match = fields.first { $0.name.caseInsensitiveCompare("Sprint") == .orderedSame }
        cachedSprintFieldID = match?.id
        return match?.id
    }

    static func fetchMyActiveSprintIssues() async throws -> [JiraIssue] {
        guard let creds = JiraCredentials.current else {
            throw JiraError.notConfigured
        }

        let sprintField = await sprintFieldID(creds: creds)

        var allIssues: [JiraIssue] = []
        var startAt = 0
        let pageSize = 100

        // sprint_summary.py's pagination relies on a `total` field, but this
        // endpoint's actual response — confirmed by logging the raw body —
        // is {"issues":[...],"isLast":true/false}, no `total` at all. Page
        // until Jira itself says isLast, not until some byte count matches.
        while true {
            let (issues, isLast) = try await fetchPage(
                creds: creds,
                sprintField: sprintField,
                startAt: startAt,
                maxResults: pageSize
            )
            allIssues.append(contentsOf: issues)
            startAt += issues.count
            if isLast || issues.isEmpty { break }
        }

        return allIssues
    }

    private static func fetchPage(
        creds: JiraCredentials,
        sprintField: String?,
        startAt: Int,
        maxResults: Int
    ) async throws -> (issues: [JiraIssue], isLast: Bool) {
        let base = creds.normalizedBaseURL
        guard var components = URLComponents(string: base + "/rest/api/3/search/jql") else {
            throw JiraError.invalidBaseURL(base)
        }
        var fieldsList = "summary,status,issuetype,project,priority,updated,duedate,assignee"
        if let sprintField {
            fieldsList += ",\(sprintField)"
        }
        components.queryItems = [
            URLQueryItem(name: "jql", value: jql(for: creds)),
            URLQueryItem(name: "fields", value: fieldsList),
            URLQueryItem(name: "maxResults", value: String(maxResults)),
            URLQueryItem(name: "startAt", value: String(startAt)),
        ]

        guard let finalURL = components.url else {
            throw JiraError.invalidBaseURL(base)
        }
        var request = URLRequest(url: finalURL)
        request.setValue(creds.authHeader, forHTTPHeaderField: "Authorization")
        request.setValue("application/json", forHTTPHeaderField: "Accept")

        debugLog("📡 Pulse: requesting \(finalURL.absoluteString)")
        let (data, response) = try await URLSession.shared.data(for: request)
        let statusCode = (response as? HTTPURLResponse)?.statusCode ?? -1
        debugLog("📡 Pulse: Jira responded HTTP \(statusCode), \(data.count) bytes")
        if let bodyPreview = String(data: data.prefix(500), encoding: .utf8) {
            debugLog("📡 Pulse: body preview — \(bodyPreview)")
        }
        guard (200..<300).contains(statusCode) else {
            throw JiraError.badResponse(statusCode)
        }

        let decoded = try JSONDecoder().decode(SearchResponse.self, from: data)

        // The sprint field's key is only known at runtime (see sprintFieldID
        // above), so Codable's static keys can't reach it — fall back to
        // JSONSerialization just for this one dynamic lookup, keyed by
        // issue key so it lines up with the Codable-decoded issues below.
        var sprintNameByKey: [String: String] = [:]
        var sprintEndByKey: [String: Date] = [:]
        if let sprintField,
           let root = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
           let rawIssues = root["issues"] as? [[String: Any]] {
            for rawIssue in rawIssues {
                guard let key = rawIssue["key"] as? String,
                      let fields = rawIssue["fields"] as? [String: Any],
                      let sprints = fields[sprintField] as? [[String: Any]],
                      let activeSprint = sprints.first(where: { ($0["state"] as? String) == "active" }) ?? sprints.last
                else { continue }
                if let name = activeSprint["name"] as? String {
                    sprintNameByKey[key] = name
                }
                if let endDateString = activeSprint["endDate"] as? String,
                   let endDate = parseISO8601(endDateString) {
                    sprintEndByKey[key] = endDate
                }
            }
        }

        let issues = decoded.issues.map { raw in
            JiraIssue(
                key: raw.key,
                summary: raw.fields.summary,
                status: raw.fields.status.name,
                statusCategory: raw.fields.status.statusCategory.name,
                issueType: raw.fields.issuetype.name,
                projectKey: raw.fields.project.key,
                projectName: raw.fields.project.name,
                priority: raw.fields.priority?.name,
                sprintName: sprintNameByKey[raw.key],
                sprintEndDate: sprintEndByKey[raw.key],
                assigneeName: raw.fields.assignee?.displayName,
                updated: raw.fields.updated.flatMap(parseISO8601),
                dueDate: raw.fields.duedate.flatMap(parseSimpleDate)
            )
        }
        return (issues, decoded.isLast ?? true)
    }
}

// Jira sends two different date shapes: full ISO8601 timestamps with
// fractional seconds + offset for things like `updated` and sprint
// endDate ("2026-09-15T00:00:00.000-0700"), and bare "yyyy-MM-dd" for
// `duedate` (it has no time component at all).
private func parseISO8601(_ string: String) -> Date? {
    let formatter = ISO8601DateFormatter()
    formatter.formatOptions = [.withInternetDateTime, .withFractionalSeconds]
    if let date = formatter.date(from: string) { return date }
    formatter.formatOptions = [.withInternetDateTime]
    return formatter.date(from: string)
}

private func parseSimpleDate(_ string: String) -> Date? {
    let formatter = DateFormatter()
    formatter.dateFormat = "yyyy-MM-dd"
    formatter.timeZone = .current
    return formatter.date(from: string)
}

// Raw shapes matching Jira's actual JSON response — kept private, mapped to
// the cleaner JiraIssue above so nothing downstream depends on Jira's API
// shape directly.
private struct SearchResponse: Decodable {
    let issues: [RawIssue]
    let isLast: Bool?
}

private struct RawIssue: Decodable {
    let key: String
    let fields: RawFields
}

private struct RawFields: Decodable {
    let summary: String
    let status: RawStatus
    let issuetype: NamedField
    let project: RawProject
    let priority: NamedField?
    let updated: String?
    let duedate: String?
    let assignee: RawAssignee?
}

private struct RawAssignee: Decodable {
    let displayName: String
}

private struct NamedField: Decodable {
    let name: String
}

private struct RawStatus: Decodable {
    let name: String
    let statusCategory: NamedField
}

private struct RawProject: Decodable {
    let key: String
    let name: String
}

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
    let issueType: String
    let projectKey: String
    let projectName: String
    let priority: String?
}

struct JiraClient {
    /// The whole design fits in this one query: your tickets, any active
    /// sprint, any project. Change Jira instances and this still works.
    private static let jql = "assignee = currentUser() AND sprint in openSprints() ORDER BY project ASC, updated DESC"

    static func fetchMyActiveSprintIssues() async throws -> [JiraIssue] {
        guard let creds = JiraCredentials.current else {
            throw JiraError.notConfigured
        }

        var allIssues: [JiraIssue] = []
        var startAt = 0
        let pageSize = 100

        // sprint_summary.py's pagination relies on a `total` field, but this
        // endpoint's actual response — confirmed by logging the raw body —
        // is {"issues":[...],"isLast":true/false}, no `total` at all. Page
        // until Jira itself says isLast, not until some byte count matches.
        while true {
            let (issues, isLast) = try await fetchPage(creds: creds, startAt: startAt, maxResults: pageSize)
            allIssues.append(contentsOf: issues)
            startAt += issues.count
            if isLast || issues.isEmpty { break }
        }

        return allIssues
    }

    private static func fetchPage(
        creds: JiraCredentials,
        startAt: Int,
        maxResults: Int
    ) async throws -> (issues: [JiraIssue], isLast: Bool) {
        let base = creds.normalizedBaseURL
        guard var components = URLComponents(string: base + "/rest/api/3/search/jql") else {
            throw JiraError.invalidBaseURL(base)
        }
        components.queryItems = [
            URLQueryItem(name: "jql", value: jql),
            URLQueryItem(name: "fields", value: "summary,status,issuetype,project,priority"),
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
        let issues = decoded.issues.map { raw in
            JiraIssue(
                key: raw.key,
                summary: raw.fields.summary,
                status: raw.fields.status.name,
                issueType: raw.fields.issuetype.name,
                projectKey: raw.fields.project.key,
                projectName: raw.fields.project.name,
                priority: raw.fields.priority?.name
            )
        }
        return (issues, decoded.isLast ?? true)
    }
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
    let status: NamedField
    let issuetype: NamedField
    let project: RawProject
    let priority: NamedField?
}

private struct NamedField: Decodable {
    let name: String
}

private struct RawProject: Decodable {
    let key: String
    let name: String
}

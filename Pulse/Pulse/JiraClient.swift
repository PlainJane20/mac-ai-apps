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

        // Same pagination pattern as sprint_summary.py's jql_search: keep
        // paging with startAt until we've collected everything the search
        // reports as `total`.
        while true {
            let (issues, total) = try await fetchPage(creds: creds, startAt: startAt, maxResults: pageSize)
            allIssues.append(contentsOf: issues)
            startAt += issues.count
            if startAt >= total || issues.isEmpty { break }
        }

        return allIssues
    }

    private static func fetchPage(
        creds: JiraCredentials,
        startAt: Int,
        maxResults: Int
    ) async throws -> (issues: [JiraIssue], total: Int) {
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

        let (data, response) = try await URLSession.shared.data(for: request)
        guard let http = response as? HTTPURLResponse, (200..<300).contains(http.statusCode) else {
            throw JiraError.badResponse((response as? HTTPURLResponse)?.statusCode ?? -1)
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
        return (issues, decoded.total)
    }
}

// Raw shapes matching Jira's actual JSON response — kept private, mapped to
// the cleaner JiraIssue above so nothing downstream depends on Jira's API
// shape directly.
private struct SearchResponse: Decodable {
    let total: Int
    let issues: [RawIssue]
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

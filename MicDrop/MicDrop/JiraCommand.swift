//
//  JiraCommand.swift
//  MicDrop
//
//  "What's my sprint look like" — reuses the exact query design proven
//  out in Pulse (assignee = currentUser() AND sprint in openSprints(),
//  no hardcoded board/project), and reads Pulse's already-configured
//  local credentials file directly rather than asking you to set up
//  Jira access a second time. Same file, same machine, same user.
//

import Foundation

private struct PulseCredentials: Codable {
    var baseURL: String
    var email: String
    var apiToken: String
    var watchedProjectKey: String?

    var normalizedBaseURL: String {
        var url = baseURL.trimmingCharacters(in: .whitespacesAndNewlines)
        if !url.lowercased().hasPrefix("http://") && !url.lowercased().hasPrefix("https://") {
            url = "https://" + url
        }
        while url.hasSuffix("/") { url = String(url.dropLast()) }
        return url
    }

    var authHeader: String {
        Data("\(email):\(apiToken)".utf8).base64EncodedString()
    }
}

struct JiraCommand {
    private static var pulseCredentials: PulseCredentials? {
        let path = FileManager.default
            .urls(for: .applicationSupportDirectory, in: .userDomainMask)[0]
            .appendingPathComponent("Pulse/jira-credentials.json")
        guard let data = try? Data(contentsOf: path),
              let creds = try? JSONDecoder().decode(PulseCredentials.self, from: data) else {
            return nil
        }
        return creds
    }

    static func run() async -> CommandResult {
        guard let creds = pulseCredentials else {
            return CommandResult(spokenText: "Jira isn't set up in Pulse yet — set that up first.", isQuery: true)
        }

        let jql = "assignee = currentUser() AND sprint in openSprints()"
        guard var components = URLComponents(string: creds.normalizedBaseURL + "/rest/api/3/search/jql") else {
            return CommandResult(spokenText: "Couldn't reach Jira.", isQuery: true)
        }
        components.queryItems = [
            URLQueryItem(name: "jql", value: jql),
            URLQueryItem(name: "fields", value: "status"),
            URLQueryItem(name: "maxResults", value: "100"),
        ]
        guard let url = components.url else {
            return CommandResult(spokenText: "Couldn't reach Jira.", isQuery: true)
        }

        var request = URLRequest(url: url)
        request.setValue("Basic \(creds.authHeader)", forHTTPHeaderField: "Authorization")
        request.setValue("application/json", forHTTPHeaderField: "Accept")

        struct StatusCategory: Decodable { let name: String }
        struct Status: Decodable { let statusCategory: StatusCategory }
        struct Fields: Decodable { let status: Status }
        struct Issue: Decodable { let fields: Fields }
        struct SearchResponse: Decodable { let issues: [Issue] }

        guard let (data, response) = try? await URLSession.shared.data(for: request),
              let http = response as? HTTPURLResponse, (200..<300).contains(http.statusCode),
              let decoded = try? JSONDecoder().decode(SearchResponse.self, from: data) else {
            return CommandResult(spokenText: "Couldn't reach Jira right now.", isQuery: true)
        }

        guard !decoded.issues.isEmpty else {
            return CommandResult(spokenText: "Nothing assigned in an active sprint.", isQuery: true)
        }

        let total = decoded.issues.count
        let toDo = decoded.issues.filter { $0.fields.status.statusCategory.name == "To Do" }.count
        let inProgress = decoded.issues.filter { $0.fields.status.statusCategory.name == "In Progress" }.count
        let done = decoded.issues.filter { $0.fields.status.statusCategory.name == "Done" }.count

        let summary = "\(total) tickets in your active sprint: \(toDo) to do, \(inProgress) in progress, \(done) done."
        return CommandResult(spokenText: summary, isQuery: true)
    }
}

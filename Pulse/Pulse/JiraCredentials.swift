//
//  JiraCredentials.swift
//  Pulse
//
//  Your personal Jira connection details, stored in the macOS Keychain —
//  never in a file, never hardcoded in source. Nothing here is specific
//  to any one company; this works against any Jira Cloud instance you
//  point it at.
//

import Foundation

struct JiraCredentials: Codable {
    private static let service = "com.navisohi.Pulse.jira"
    private static let account = "credentials"

    var baseURL: String   // e.g. "https://yourcompany.atlassian.net" — no trailing slash needed
    var email: String
    var apiToken: String  // generate at id.atlassian.com/manage-profile/security/api-tokens

    // Stored as ONE Keychain item (JSON-encoded) rather than three separate
    // ones — each distinct Keychain item can trigger its own "Pulse wants to
    // access..." permission prompt, so three items meant up to three prompts
    // per read. One item, one prompt.
    static var current: JiraCredentials? {
        guard
            let json = KeychainStore.read(service: service, account: account),
            let data = json.data(using: .utf8),
            let creds = try? JSONDecoder().decode(JiraCredentials.self, from: data),
            !creds.baseURL.isEmpty, !creds.email.isEmpty, !creds.apiToken.isEmpty
        else { return nil }
        return creds
    }

    func save() {
        guard let data = try? JSONEncoder().encode(self),
              let json = String(data: data, encoding: .utf8) else { return }
        KeychainStore.save(service: Self.service, account: Self.account, value: json)
    }

    static func clear() {
        KeychainStore.delete(service: service, account: account)
    }

    var authHeader: String {
        let raw = "\(email):\(apiToken)"
        let encoded = Data(raw.utf8).base64EncodedString()
        return "Basic \(encoded)"
    }

    var normalizedBaseURL: String {
        var url = baseURL.trimmingCharacters(in: .whitespacesAndNewlines)
        // A missing scheme is an easy typo (e.g. pasting just
        // "yourcompany.atlassian.net") — default to https rather than fail.
        if !url.lowercased().hasPrefix("http://") && !url.lowercased().hasPrefix("https://") {
            url = "https://" + url
        }
        while url.hasSuffix("/") {
            url = String(url.dropLast())
        }
        return url
    }
}

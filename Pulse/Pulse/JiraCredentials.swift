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

struct JiraCredentials {
    private static let service = "com.navisohi.Pulse.jira"

    var baseURL: String   // e.g. "https://yourcompany.atlassian.net" — no trailing slash needed
    var email: String
    var apiToken: String  // generate at id.atlassian.com/manage-profile/security/api-tokens

    static var current: JiraCredentials? {
        guard
            let baseURL = KeychainStore.read(service: service, account: "baseURL"),
            let email = KeychainStore.read(service: service, account: "email"),
            let apiToken = KeychainStore.read(service: service, account: "apiToken"),
            !baseURL.isEmpty, !email.isEmpty, !apiToken.isEmpty
        else { return nil }
        return JiraCredentials(baseURL: baseURL, email: email, apiToken: apiToken)
    }

    func save() {
        KeychainStore.save(service: Self.service, account: "baseURL", value: baseURL)
        KeychainStore.save(service: Self.service, account: "email", value: email)
        KeychainStore.save(service: Self.service, account: "apiToken", value: apiToken)
    }

    static func clear() {
        KeychainStore.delete(service: service, account: "baseURL")
        KeychainStore.delete(service: service, account: "email")
        KeychainStore.delete(service: service, account: "apiToken")
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

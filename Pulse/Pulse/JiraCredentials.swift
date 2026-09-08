//
//  JiraCredentials.swift
//  Pulse
//
//  Your personal Jira connection details. Nothing here is specific to any
//  one company; this works against any Jira Cloud instance you point it at.
//
//  Stored in a local file under Application Support rather than the
//  Keychain: with "Sign to Run Locally" (no paid Developer Team), every
//  rebuild produces a new ad-hoc code signature, and macOS Keychain ACLs
//  are tied to that signature — so during active development, "Always
//  Allow" never actually sticks across rebuilds, prompting constantly.
//  This file never touches git (it's outside the repo entirely, same
//  spirit as a local .env file) and is chmod 600. Worth revisiting
//  Keychain once the app has a stable signing identity and isn't being
//  rebuilt every few minutes.
//

import Foundation

struct JiraCredentials: Codable {
    var baseURL: String   // e.g. "https://yourcompany.atlassian.net" — no trailing slash needed
    var email: String
    var apiToken: String  // generate at id.atlassian.com/manage-profile/security/api-tokens

    private static var fileURL: URL {
        let dir = FileManager.default
            .urls(for: .applicationSupportDirectory, in: .userDomainMask)[0]
            .appendingPathComponent("Pulse", isDirectory: true)
        return dir.appendingPathComponent("jira-credentials.json")
    }

    static var current: JiraCredentials? {
        guard
            let data = try? Data(contentsOf: fileURL),
            let creds = try? JSONDecoder().decode(JiraCredentials.self, from: data),
            !creds.baseURL.isEmpty, !creds.email.isEmpty, !creds.apiToken.isEmpty
        else { return nil }
        return creds
    }

    func save() {
        guard let data = try? JSONEncoder().encode(self) else { return }
        let dir = Self.fileURL.deletingLastPathComponent()
        try? FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
        try? data.write(to: Self.fileURL, options: .atomic)
        try? FileManager.default.setAttributes([.posixPermissions: 0o600], ofItemAtPath: Self.fileURL.path)
    }

    static func clear() {
        try? FileManager.default.removeItem(at: fileURL)
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

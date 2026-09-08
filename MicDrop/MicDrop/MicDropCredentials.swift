//
//  MicDropCredentials.swift
//  MicDrop
//
//  Local file storage for third-party tokens (Slack now, Gmail OAuth
//  later) — same reasoning as Pulse's JiraCredentials: no paid Developer
//  Team means ad-hoc code signing changes every rebuild, and Keychain
//  ACLs tied to that signature cause constant re-prompting. Lives outside
//  the git repo entirely, chmod 600, never committed.
//

import Foundation

struct MicDropCredentials: Codable {
    var slackUserToken: String?
    var gmailClientID: String?
    var gmailClientSecret: String?
    var gmailRefreshToken: String?

    private static var fileURL: URL {
        let dir = FileManager.default
            .urls(for: .applicationSupportDirectory, in: .userDomainMask)[0]
            .appendingPathComponent("MicDrop", isDirectory: true)
        return dir.appendingPathComponent("config.json")
    }

    static var current: MicDropCredentials {
        guard
            let data = try? Data(contentsOf: fileURL),
            let creds = try? JSONDecoder().decode(MicDropCredentials.self, from: data)
        else { return MicDropCredentials() }
        return creds
    }

    func save() {
        guard let data = try? JSONEncoder().encode(self) else { return }
        let dir = Self.fileURL.deletingLastPathComponent()
        try? FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
        try? data.write(to: Self.fileURL, options: .atomic)
        try? FileManager.default.setAttributes([.posixPermissions: 0o600], ofItemAtPath: Self.fileURL.path)
    }
}

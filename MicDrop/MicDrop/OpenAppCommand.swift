//
//  OpenAppCommand.swift
//  MicDrop
//
//  "Open Safari" — shells out to `open -a`, the same resolution logic
//  Finder/Spotlight use to turn an app name into the right bundle,
//  rather than reimplementing app lookup ourselves.
//
//  Falls back to a known website for services that are web-only and have
//  no native Mac app at all — "open Gmail" was failing outright since
//  there's no app literally named Gmail to find, confirmed by testing
//  `open -a "Gmail"` directly (exit 1, "Unable to find application").
//

import AppKit
import Foundation

struct OpenAppCommand {
    /// Common services people ask for by name that are web-only — no
    /// native Mac app exists to find, so `open -a` would always fail.
    private static let webFallbacks: [String: String] = [
        "gmail": "https://mail.google.com",
        "google drive": "https://drive.google.com",
        "drive": "https://drive.google.com",
        "google docs": "https://docs.google.com",
        "google calendar": "https://calendar.google.com",
        "outlook": "https://outlook.com",
        "youtube": "https://youtube.com",
    ]

    static func run(argument: String?) -> CommandResult {
        guard let appName = argument, !appName.isEmpty else {
            return CommandResult(spokenText: "Didn't catch which app to open.", isQuery: true)
        }

        let normalized = appName.lowercased().trimmingCharacters(in: .whitespaces)
        if let urlString = webFallbacks[normalized], let url = URL(string: urlString) {
            debugLog("🖥️ OpenAppCommand: \(appName) is web-only, opening \(urlString)")
            NSWorkspace.shared.open(url)
            return CommandResult(spokenText: "Opening \(appName) in your browser.", isQuery: false)
        }

        let process = Process()
        process.executableURL = URL(fileURLWithPath: "/usr/bin/open")
        process.arguments = ["-a", appName]

        do {
            try process.run()
            process.waitUntilExit()
            debugLog("🖥️ OpenAppCommand: open -a \"\(appName)\" exited \(process.terminationStatus)")
            if process.terminationStatus == 0 {
                return CommandResult(spokenText: "Opening \(appName).", isQuery: false)
            } else {
                return CommandResult(spokenText: "Couldn't find an app called \(appName).", isQuery: true)
            }
        } catch {
            debugLog("🖥️ OpenAppCommand: Process failed to launch — \(error)")
            return CommandResult(spokenText: "Couldn't open \(appName) — \(error.localizedDescription)", isQuery: true)
        }
    }
}

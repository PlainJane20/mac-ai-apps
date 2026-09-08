//
//  OpenAppCommand.swift
//  MicDrop
//
//  "Open Safari" — shells out to `open -a`, the same resolution logic
//  Finder/Spotlight use to turn an app name into the right bundle,
//  rather than reimplementing app lookup ourselves.
//

import Foundation

struct OpenAppCommand {
    static func run(argument: String?) -> CommandResult {
        guard let appName = argument, !appName.isEmpty else {
            return CommandResult(spokenText: "Didn't catch which app to open.", isQuery: true)
        }

        let process = Process()
        process.executableURL = URL(fileURLWithPath: "/usr/bin/open")
        process.arguments = ["-a", appName]

        do {
            try process.run()
            process.waitUntilExit()
            if process.terminationStatus == 0 {
                return CommandResult(spokenText: "Opening \(appName).", isQuery: false)
            } else {
                return CommandResult(spokenText: "Couldn't find an app called \(appName).", isQuery: true)
            }
        } catch {
            return CommandResult(spokenText: "Couldn't open \(appName) — \(error.localizedDescription)", isQuery: true)
        }
    }
}

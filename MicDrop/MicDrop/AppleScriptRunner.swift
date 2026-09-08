//
//  AppleScriptRunner.swift
//  MicDrop
//
//  Small shared helper for the handful of commands (Notes, Music, volume)
//  that are simplest via AppleScript rather than a native framework.
//

import Foundation

struct AppleScriptRunner {
    static func run(_ script: String) -> String? {
        guard let appleScript = NSAppleScript(source: script) else { return nil }
        var errorInfo: NSDictionary?
        let result = appleScript.executeAndReturnError(&errorInfo)
        if let errorInfo {
            debugLog("📡 MicDrop: AppleScript error — \(errorInfo)")
            return nil
        }
        return result.stringValue
    }
}

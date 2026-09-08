//
//  NoteCommand.swift
//  MicDrop
//
//  "Note that we need more sensors" — appends a new note to Notes.app.
//  Creates a fresh note each time rather than trying to find/append to an
//  existing one — simpler, and avoids accidentally editing the wrong note.
//

import Foundation

struct NoteCommand {
    static func run(argument: String?) -> CommandResult {
        guard let text = argument, !text.isEmpty else {
            return CommandResult(spokenText: "Didn't catch what to note down.", isQuery: true)
        }

        let escaped = text.replacingOccurrences(of: "\"", with: "\\\"")
        let script = """
        tell application "Notes"
            activate
            make new note at folder "Notes" with properties {body:"\(escaped)"}
        end tell
        """
        _ = AppleScriptRunner.run(script)
        return CommandResult(spokenText: "Noted.", isQuery: false)
    }
}

//
//  MusicCommand.swift
//  MicDrop
//
//  "Pause music" / "what's playing" — AppleScript against Music.app.
//  Doesn't attempt Spotify — Apple's Music.app AppleScript dictionary is
//  stable and built-in; Spotify's requires it to be running and isn't
//  worth the added complexity for v1.
//

import Foundation

struct MusicCommand {
    static func run(argument: String?) -> CommandResult {
        let arg = (argument ?? "").lowercased()

        if arg.contains("pause") || arg.contains("stop") {
            _ = AppleScriptRunner.run("tell application \"Music\" to pause")
            return CommandResult(spokenText: "Paused.", isQuery: false)
        }
        if arg.contains("play") || arg.contains("resume") {
            _ = AppleScriptRunner.run("tell application \"Music\" to play")
            return CommandResult(spokenText: "Playing.", isQuery: false)
        }
        if arg.contains("next") || arg.contains("skip") {
            _ = AppleScriptRunner.run("tell application \"Music\" to next track")
            return CommandResult(spokenText: "Skipped.", isQuery: false)
        }
        if arg.contains("previous") || arg.contains("back") {
            _ = AppleScriptRunner.run("tell application \"Music\" to previous track")
            return CommandResult(spokenText: "Went back a track.", isQuery: false)
        }

        // Default: "what's playing"
        let script = """
        tell application "Music"
            if player state is playing then
                get name of current track & " by " & artist of current track
            else
                get "Nothing is playing"
            end if
        end tell
        """
        let result = AppleScriptRunner.run(script) ?? "Couldn't check what's playing."
        return CommandResult(spokenText: result, isQuery: true)
    }
}

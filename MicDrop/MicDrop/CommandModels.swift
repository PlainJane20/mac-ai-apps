//
//  CommandModels.swift
//  MicDrop
//
//  The shared vocabulary between the intent classifier and the command
//  router: what kinds of things MicDrop can do, and what a completed
//  command looks like once it's run.
//

import Foundation

enum CommandIntent: String, Codable {
    case dictate      // default — just clean the transcript and paste it
    case calendar     // "what's on my calendar today"
    case reminder     // "remind me to X tomorrow"
    case note         // "note that X"
    case battery      // "what's my battery at"
    case volume       // "set volume to X" / "mute"
    case webSearch    // "search for X"
    case openApp      // "open X"
    case music        // "play/pause music", "what's playing"
    case timer        // "set a timer for X minutes"
    case slack        // "check my slack" / "send a slack message to X saying Y"
    case jira         // "what's my sprint look like"
}

struct ParsedCommand: Codable {
    var intent: CommandIntent
    /// Free-form payload the handler interprets — e.g. the search query,
    /// the app name, the reminder text, the Slack recipient + message.
    var argument: String?
}

/// What running a command produced — used to decide how to present the
/// result: query-type commands get spoken aloud + shown in the popover,
/// action-type commands just get a quiet confirmation notification.
struct CommandResult {
    let spokenText: String
    let isQuery: Bool
}

/// An action that reaches outside your own machine (currently: Slack
/// sends) — prepared (channel resolved, message extracted) but not yet
/// executed. Nothing here fires until the user explicitly confirms in
/// the popover. This is the one sensitive-action boundary MicDrop
/// enforces so far; anything that posts/sends/deletes on your behalf in
/// the future should go through the same pattern.
struct PendingAction {
    let description: String
    let execute: () async -> CommandResult
}

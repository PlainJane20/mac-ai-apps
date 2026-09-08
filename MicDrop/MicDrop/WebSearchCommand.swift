//
//  WebSearchCommand.swift
//  MicDrop
//
//  "Search the web for best pizza near me" — opens the default browser
//  with a search results page. Uses the system default search engine's
//  URL scheme isn't easily discoverable, so this goes straight to Google
//  rather than trying to detect/respect a different default engine.
//

import AppKit

struct WebSearchCommand {
    static func run(argument: String?) -> CommandResult {
        guard let query = argument, !query.isEmpty else {
            return CommandResult(spokenText: "Didn't catch what to search for.", isQuery: true)
        }
        guard let encoded = query.addingPercentEncoding(withAllowedCharacters: .urlQueryAllowed),
              let url = URL(string: "https://www.google.com/search?q=\(encoded)") else {
            return CommandResult(spokenText: "Couldn't build a search URL for that.", isQuery: true)
        }
        NSWorkspace.shared.open(url)
        return CommandResult(spokenText: "Searching for \(query).", isQuery: false)
    }
}

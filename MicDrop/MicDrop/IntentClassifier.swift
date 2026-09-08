//
//  IntentClassifier.swift
//  MicDrop
//
//  Classifies a raw transcript into a command intent + argument, via a
//  local LLM asked to output strict JSON.
//
//  The safety rule this whole file exists to enforce: if classification
//  fails, is malformed, or is even slightly ambiguous, ALWAYS fall back
//  to .dictate. Given everything Pulse's AI-brief debugging taught about
//  small local models being unreliable, a wrong classification here isn't
//  cosmetic like a bad brief sentence — it could silently swallow text
//  the user meant to paste, or worse, fire the wrong action (e.g. sending
//  a Slack message instead of just cleaning dictation). Wrongly guessing
//  "dictate" when they meant a command just means they try the command
//  again; wrongly guessing a command when they meant dictation could take
//  an unwanted action. Bias hard toward the safe default.
//

import Foundation

struct IntentClassifier {
    private static let systemPrompt = """
    You classify a voice transcript into exactly one of these intents: \
    dictate, calendar, reminder, note, battery, volume, webSearch, openApp, \
    music, timer, slack, jira.

    Respond with ONLY a JSON object, no other text: \
    {"intent": "<one of the above>", "argument": "<relevant text or null>"}

    Rules:
    - "dictate" means the transcript is just text to clean up and paste —
      this is the default. Only pick another intent if the transcript is
      CLEARLY a command directed at the assistant itself.
    - calendar: asking what's on the calendar/schedule. argument: null.
    - reminder: asking to be reminded of something. argument: the reminder text.
    - note: asking to note/write something down. argument: the note text.
    - battery: asking about battery level. argument: null.
    - volume: asking to change volume or mute. argument: e.g. "50", "mute", "up", "down".
    - webSearch: asking to search the web for something. argument: the search query.
    - openApp: asking to open an application. argument: the app name.
    - music: asking to play/pause/skip music or what's playing. argument: e.g. "play", "pause", "next", "current".
    - timer: asking to set a timer. argument: e.g. "10 minutes".
    - slack: asking about Slack messages, or to send one. argument: the relevant text.
    - jira: asking about sprint/tickets/Jira status. argument: null.

    If you are not confident it's a command, or it could reasonably be \
    read as just dictation, respond with intent "dictate". When in doubt, \
    choose "dictate".

    Examples:
    "so basically we need to fix the login bug" -> {"intent": "dictate", "argument": null}
    "what's on my calendar today" -> {"intent": "calendar", "argument": null}
    "remind me to call the dentist tomorrow" -> {"intent": "reminder", "argument": "call the dentist tomorrow"}
    "search the web for best pizza near me" -> {"intent": "webSearch", "argument": "best pizza near me"}
    "open safari" -> {"intent": "openApp", "argument": "Safari"}
    "set a timer for 10 minutes" -> {"intent": "timer", "argument": "10 minutes"}
    "what's my battery at" -> {"intent": "battery", "argument": null}
    """

    private struct ChatMessage: Encodable {
        let role: String
        let content: String
    }
    private struct ChatRequest: Encodable {
        let model: String
        let messages: [ChatMessage]
        let stream: Bool
        let format: String
    }
    private struct ChatResponse: Decodable {
        struct Message: Decodable { let content: String }
        let message: Message
    }

    static func classify(_ transcript: String) async -> ParsedCommand {
        let fallback = ParsedCommand(intent: .dictate, argument: nil)

        guard let url = URL(string: "http://localhost:11434/api/chat") else { return fallback }
        var request = URLRequest(url: url)
        request.httpMethod = "POST"
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")

        guard let body = try? JSONEncoder().encode(
            ChatRequest(
                model: OllamaClient.defaultModel,
                messages: [
                    ChatMessage(role: "system", content: systemPrompt),
                    ChatMessage(role: "user", content: transcript),
                ],
                stream: false,
                format: "json"
            )
        ) else { return fallback }
        request.httpBody = body

        guard let (data, response) = try? await URLSession.shared.data(for: request),
              let http = response as? HTTPURLResponse, (200..<300).contains(http.statusCode) else {
            return fallback
        }

        guard let decoded = try? JSONDecoder().decode(ChatResponse.self, from: data),
              let contentData = decoded.message.content.data(using: .utf8),
              let parsed = try? JSONDecoder().decode(ParsedCommand.self, from: contentData) else {
            return fallback
        }

        return parsed
    }
}

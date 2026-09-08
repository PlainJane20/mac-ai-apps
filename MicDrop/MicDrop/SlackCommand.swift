//
//  SlackCommand.swift
//  MicDrop
//
//  Reuses the existing SLACK_USER_TOKEN from slack-daily-agent rather than
//  setting up a new Slack app. Checked its actual granted scopes before
//  writing any code: identify, channels:history, groups:history,
//  channels:read, groups:read, users:read, chat:write — notably NO im:*
//  scopes, so this token can read/post to channels and private groups,
//  but cannot see or send direct messages. Scoped accordingly rather than
//  guessing and having it silently fail.
//

import Foundation

enum SlackError: Error, LocalizedError {
    case notConfigured
    case channelNotFound(String)
    case couldNotParseRequest

    var errorDescription: String? {
        switch self {
        case .notConfigured:
            return "Slack isn't set up — no token found."
        case .channelNotFound(let name):
            return "Couldn't find a Slack channel called \(name)."
        case .couldNotParseRequest:
            return "Couldn't tell which channel or what message to send."
        }
    }
}

/// What SlackCommand.run produces — either a direct result (reading
/// activity, or an error), or a send that needs explicit confirmation
/// before it actually reaches Slack.
enum SlackOutcome {
    case result(CommandResult)
    case pendingSend(PendingAction)
}

struct SlackCommand {
    private static let baseURL = "https://slack.com/api"

    static func run(argument: String?) async -> SlackOutcome {
        guard let token = MicDropCredentials.current.slackUserToken else {
            return .result(CommandResult(spokenText: SlackError.notConfigured.localizedDescription, isQuery: true))
        }
        guard let text = argument, !text.isEmpty else {
            return .result(CommandResult(spokenText: "Didn't catch what you wanted to do in Slack.", isQuery: true))
        }

        // Ask the LLM to split "tell #general the deploy is done" into a
        // channel + message, same "structured extraction, safe fallback"
        // pattern as the main intent classifier. If it can't confidently
        // extract both, we do NOT guess and send to the wrong place —
        // we just report that we couldn't parse it.
        guard let (channel, message) = await extractChannelAndMessage(from: text) else {
            return .result(await checkRecentActivity(token: token))
        }

        do {
            let channelID = try await lookupChannelID(name: channel, token: token)
            // Resolved and ready, but NOT sent yet — sending reaches another
            // person, so it waits for an explicit confirm click, same
            // principle Codex's review flagged: sensitive actions get a
            // confirmation step, not immediate execution.
            let action = PendingAction(description: "Send to #\(channel): \"\(message)\"") {
                do {
                    try await postMessage(channelID: channelID, text: message, token: token)
                    return CommandResult(spokenText: "Sent to #\(channel).", isQuery: false)
                } catch {
                    return CommandResult(spokenText: error.localizedDescription, isQuery: true)
                }
            }
            return .pendingSend(action)
        } catch {
            return .result(CommandResult(spokenText: error.localizedDescription, isQuery: true))
        }
    }

    // MARK: - Send

    private struct ExtractedMessage: Codable {
        let channel: String?
        let message: String?
    }

    private static func extractChannelAndMessage(from text: String) async -> (channel: String, message: String)? {
        let systemPrompt = """
        Extract a Slack channel name and message from the text. Respond with \
        ONLY JSON: {"channel": "<name without # or null>", "message": "<text or null>"}. \
        If either isn't clearly present, use null for that field.
        """
        guard let url = URL(string: "http://localhost:11434/api/chat") else { return nil }
        var request = URLRequest(url: url)
        request.httpMethod = "POST"
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")

        struct ChatMessage: Encodable { let role: String; let content: String }
        struct ChatRequest: Encodable { let model: String; let messages: [ChatMessage]; let stream: Bool; let format: String }
        struct ChatResponse: Decodable { struct Message: Decodable { let content: String }; let message: Message }

        guard let body = try? JSONEncoder().encode(ChatRequest(
            model: OllamaClient.defaultModel,
            messages: [ChatMessage(role: "system", content: systemPrompt), ChatMessage(role: "user", content: text)],
            stream: false,
            format: "json"
        )) else { return nil }
        request.httpBody = body

        guard let (data, _) = try? await URLSession.shared.data(for: request),
              let decoded = try? JSONDecoder().decode(ChatResponse.self, from: data),
              let contentData = decoded.message.content.data(using: .utf8),
              let extracted = try? JSONDecoder().decode(ExtractedMessage.self, from: contentData),
              let channel = extracted.channel, let message = extracted.message
        else { return nil }

        return (channel, message)
    }

    private static func lookupChannelID(name: String, token: String) async throws -> String {
        var url = URL(string: "\(baseURL)/conversations.list")!
        url.append(queryItems: [
            URLQueryItem(name: "types", value: "public_channel,private_channel"),
            URLQueryItem(name: "limit", value: "200"),
        ])
        var request = URLRequest(url: url)
        request.setValue("Bearer \(token)", forHTTPHeaderField: "Authorization")

        let (data, _) = try await URLSession.shared.data(for: request)
        struct Channel: Decodable { let id: String; let name: String }
        struct ListResponse: Decodable { let ok: Bool; let channels: [Channel]? }

        let decoded = try JSONDecoder().decode(ListResponse.self, from: data)
        let target = name.lowercased().trimmingCharacters(in: CharacterSet(charactersIn: "#"))
        guard let match = decoded.channels?.first(where: { $0.name.lowercased() == target }) else {
            throw SlackError.channelNotFound(name)
        }
        return match.id
    }

    private static func postMessage(channelID: String, text: String, token: String) async throws {
        let url = URL(string: "\(baseURL)/chat.postMessage")!
        var request = URLRequest(url: url)
        request.httpMethod = "POST"
        request.setValue("Bearer \(token)", forHTTPHeaderField: "Authorization")
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        request.httpBody = try JSONEncoder().encode(["channel": channelID, "text": text])
        _ = try await URLSession.shared.data(for: request)
    }

    // MARK: - Read (best effort — channels/groups only, no DM visibility)

    private static func checkRecentActivity(token: String) async -> CommandResult {
        guard let url = URL(string: "\(baseURL)/conversations.list?types=public_channel,private_channel&limit=20") else {
            return CommandResult(spokenText: "Couldn't check Slack.", isQuery: true)
        }
        var request = URLRequest(url: url)
        request.setValue("Bearer \(token)", forHTTPHeaderField: "Authorization")

        struct Channel: Decodable { let id: String; let name: String; let is_member: Bool? }
        struct ListResponse: Decodable { let ok: Bool; let channels: [Channel]? }

        guard let (data, _) = try? await URLSession.shared.data(for: request),
              let decoded = try? JSONDecoder().decode(ListResponse.self, from: data) else {
            return CommandResult(spokenText: "Couldn't check Slack.", isQuery: true)
        }

        let memberCount = decoded.channels?.filter { $0.is_member == true }.count ?? 0
        return CommandResult(
            spokenText: "You're in \(memberCount) channels. Note: this token can't see direct messages, only channels.",
            isQuery: true
        )
    }
}

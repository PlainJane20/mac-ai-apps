//
//  OllamaClient.swift
//  Pulse
//
//  Turns your raw ticket list into a short natural-language brief using a
//  local LLM (Ollama). Same reasoning as Lint: this touches real work data,
//  so it stays entirely on-device — no cloud API call, ever.
//

import Foundation

enum OllamaError: Error, LocalizedError {
    case emptyResponse
    case serverUnreachable

    var errorDescription: String? {
        switch self {
        case .emptyResponse:
            return "Ollama returned an empty response."
        case .serverUnreachable:
            return "Couldn't reach Ollama at localhost:11434 — is it running?"
        }
    }
}

struct OllamaClient {
    static let defaultModel = "llama3.2:latest"

    private static let systemPrompt = """
    You are a concise status-summary assistant for a technical program manager. \
    You'll receive a list of Jira tickets currently assigned to the user, across \
    whatever active sprints they're in, one per line. Write a short daily brief: \
    2-4 plain-English sentences, plus bullet points ONLY for tickets that are \
    blocked, high priority, or otherwise worth flagging first — omit bullet points \
    entirely if there's nothing that needs flagging, never emit empty bullets. If \
    there's more than one project represented, group by project. Never invent \
    ticket details, counts, or names beyond what's given — if the list is empty, \
    respond with a single plain sentence saying there's nothing currently assigned \
    in an active sprint, with no bullet points at all. Respond with ONLY the brief \
    itself — no preamble, no restating these instructions.
    """

    private struct ChatMessage: Encodable {
        let role: String
        let content: String
    }

    private struct ChatRequest: Encodable {
        let model: String
        let messages: [ChatMessage]
        let stream: Bool
    }

    private struct ChatResponse: Decodable {
        struct Message: Decodable { let content: String }
        let message: Message
    }

    static func summarize(_ issues: [JiraIssue], model: String = defaultModel) async throws -> String {
        let url = URL(string: "http://localhost:11434/api/chat")!

        let listing = issues.map { issue -> String in
            var line = "\(issue.key) [\(issue.projectKey)] \(issue.issueType) — \(issue.status)"
            if let priority = issue.priority {
                line += " — priority: \(priority)"
            }
            line += " — \(issue.summary)"
            return line
        }.joined(separator: "\n")

        let userContent = issues.isEmpty
            ? "No tickets are currently assigned in an active sprint."
            : "You have \(issues.count) ticket(s) assigned in active sprints:\n\n\(listing)"

        var request = URLRequest(url: url)
        request.httpMethod = "POST"
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        request.httpBody = try JSONEncoder().encode(
            ChatRequest(
                model: model,
                messages: [
                    ChatMessage(role: "system", content: systemPrompt),
                    ChatMessage(role: "user", content: userContent),
                ],
                stream: false
            )
        )

        debugLog("📡 Pulse: requesting Ollama /api/chat with \(issues.count) issue(s)")
        let data: Data
        do {
            (data, _) = try await URLSession.shared.data(for: request)
        } catch {
            debugLog("📡 Pulse: Ollama request failed — \(error)")
            throw OllamaError.serverUnreachable
        }
        debugLog("📡 Pulse: Ollama responded, \(data.count) bytes")
        if let bodyPreview = String(data: data.prefix(500), encoding: .utf8) {
            debugLog("📡 Pulse: body preview — \(bodyPreview)")
        }

        let decoded = try JSONDecoder().decode(ChatResponse.self, from: data)
        let brief = decoded.message.content.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !brief.isEmpty else { throw OllamaError.emptyResponse }
        return brief
    }
}

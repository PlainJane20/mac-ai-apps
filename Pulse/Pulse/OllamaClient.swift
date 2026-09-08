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
    // llama3.2:latest (3B) proved unreliable at this task's real scale —
    // confirmed hallucinating a claim on every ticket in one run, then
    // degenerating to a bare list with no synthesis at all on another,
    // both against the same 21-ticket real request. qwen2.5-coder:7b
    // handled equivalent synthetic 20-ticket tests correctly both when
    // nothing needed flagging and when exactly 2 of 20 did — accurate
    // count, no hallucination, correct selective flagging both times.
    static let defaultModel = "qwen2.5-coder:7b"

    private static let systemPrompt = """
    You are a concise status-summary assistant for a technical program manager. \
    You'll receive a list of Jira tickets currently assigned to the user, across \
    whatever active sprints they're in, one per line. Write ONLY a short narrative \
    brief: 2-3 plain-English sentences, no more. Do NOT list, enumerate, or bullet \
    individual ticket keys or titles under any circumstance — the user already sees \
    the full ticket list elsewhere in the app, so repeating it here is pure noise. \
    Speak only in aggregate: counts, categories, and anything genuinely blocked or \
    high priority described in prose, never as a per-ticket list. Never invent \
    ticket details, counts, or names beyond what's given — if the list is empty, \
    respond with a single plain sentence saying there's nothing currently assigned \
    in an active sprint. Respond with ONLY the brief itself — no preamble, no \
    restating these instructions, no markdown formatting.
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

        // A small local model summarizing a very long list tends to get
        // overwhelmed and fall back to a generic response instead of
        // actually reading it (confirmed while testing against a
        // deliberately broadened query that returned 97 tickets — real
        // day-to-day active-sprint counts are nowhere near this, but capping
        // defensively costs nothing).
        let maxTicketsForSummary = 30
        let truncated = issues.count > maxTicketsForSummary
        let ticketsToList = truncated ? Array(issues.prefix(maxTicketsForSummary)) : issues

        let listing = ticketsToList.map { issue -> String in
            var line = "\(issue.key) [\(issue.projectKey)] \(issue.issueType) — \(issue.status)"
            if let priority = issue.priority {
                line += " — priority: \(priority)"
            }
            line += " — \(issue.summary)"
            return line
        }.joined(separator: "\n")

        let truncationNote = truncated
            ? "\n\n(showing the first \(maxTicketsForSummary) of \(issues.count) — mention the total count is higher)"
            : ""

        let userContent = issues.isEmpty
            ? "No tickets are currently assigned in an active sprint."
            : "You have \(issues.count) ticket(s) assigned in active sprints:\n\n\(listing)\(truncationNote)"

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

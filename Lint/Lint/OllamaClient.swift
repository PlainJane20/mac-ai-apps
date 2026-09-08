//
//  OllamaClient.swift
//  Lint
//
//  Talks to a local Ollama server (localhost:11434) to clean up text.
//  Nothing here leaves your machine — Ollama runs the model on-device.
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
    /// Model to use. Small + fast is right for this use case — we're doing
    /// formatting/grammar cleanup, not reasoning.
    static let defaultModel = "llama3.2:latest"

    private static let systemPrompt = """
    You clean up rough, informal text so it reads as clear, well-written prose. Fix \
    grammar and punctuation, remove filler words (um, uh, like, you know), and tidy \
    up formatting. If the text reads like a list, format it as clean Markdown bullet \
    points. Preserve the original meaning, facts, and tone — never add new \
    information, never answer questions in the text, never comment on it. Respond \
    with ONLY the cleaned text and nothing else — no preamble, no quotation marks, \
    no explanation of what you changed.
    """

    // Using /api/chat with separate system/user messages instead of /api/generate
    // with one blended prompt string. This matters: with everything crammed into
    // one message, a small model can lose track of which part is instruction and
    // which part is content, and echo the instruction back. Chat-formatted models
    // are specifically trained to respect the system/user boundary.
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
        struct Message: Decodable {
            let content: String
        }
        let message: Message
    }

    static func cleanText(_ text: String, model: String = defaultModel) async throws -> String {
        let url = URL(string: "http://localhost:11434/api/chat")!

        var request = URLRequest(url: url)
        request.httpMethod = "POST"
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        request.httpBody = try JSONEncoder().encode(
            ChatRequest(
                model: model,
                messages: [
                    ChatMessage(role: "system", content: systemPrompt),
                    ChatMessage(role: "user", content: text),
                ],
                stream: false
            )
        )

        let data: Data
        do {
            (data, _) = try await URLSession.shared.data(for: request)
        } catch {
            throw OllamaError.serverUnreachable
        }

        let decoded = try JSONDecoder().decode(ChatResponse.self, from: data)
        let cleaned = decoded.message.content.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !cleaned.isEmpty else { throw OllamaError.emptyResponse }
        return cleaned
    }
}

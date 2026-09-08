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

    private struct GenerateRequest: Encodable {
        let model: String
        let prompt: String
        let stream: Bool
    }

    private struct GenerateResponse: Decodable {
        let response: String
    }

    static func cleanText(_ text: String, model: String = defaultModel) async throws -> String {
        let url = URL(string: "http://localhost:11434/api/generate")!

        let prompt = """
        Clean up the following text. Fix grammar and punctuation, remove filler words \
        (um, uh, like, you know), and tidy up formatting. If it reads like a list, format \
        it as clean Markdown bullet points. Preserve the original meaning, facts, and tone \
        — don't add anything new. Return ONLY the cleaned text with no preamble, no \
        quotation marks, and no commentary.

        TEXT:
        \(text)
        """

        var request = URLRequest(url: url)
        request.httpMethod = "POST"
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        request.httpBody = try JSONEncoder().encode(
            GenerateRequest(model: model, prompt: prompt, stream: false)
        )

        let data: Data
        do {
            (data, _) = try await URLSession.shared.data(for: request)
        } catch {
            throw OllamaError.serverUnreachable
        }

        let decoded = try JSONDecoder().decode(GenerateResponse.self, from: data)
        let cleaned = decoded.response.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !cleaned.isEmpty else { throw OllamaError.emptyResponse }
        return cleaned
    }
}

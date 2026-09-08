//
//  WhisperKitRecorder.swift
//  MicDrop
//
//  Replaces Apple's Speech framework as the transcription engine — same
//  reasoning Scribe (the reference app that prompted this) uses WhisperKit
//  for: it runs its own self-contained Whisper model via Core ML,
//  completely independent of Siri/Dictation. That directly eliminates the
//  exact bug this session hit (transcription silently failing because the
//  system Dictation toggle was off) — WhisperKit never touches that
//  subsystem at all.
//
//  Simpler design than the streaming Apple Speech version: records to a
//  temp WAV file, transcribes the whole thing once recording stops,
//  rather than streaming partial results. We only ever used the final
//  transcript anyway (for intent classification), so there's nothing
//  lost, and it's a more robust first pass.
//

import AVFoundation
import Foundation
import WhisperKit

enum DictationError: Error, LocalizedError {
    case permissionDenied
    case emptyTranscript

    var errorDescription: String? {
        switch self {
        case .permissionDenied:
            return "Microphone access was denied. Check System Settings → Privacy & Security."
        case .emptyTranscript:
            return "Didn't catch any speech."
        }
    }
}

@MainActor
final class WhisperKitRecorder {
    static let shared = WhisperKitRecorder()

    private(set) var isRecording = false

    private var whisperKit: WhisperKit?
    private let audioEngine = AVAudioEngine()
    private var audioFile: AVAudioFile?
    private var recordingURL: URL?

    private init() {}

    private func ensureModelLoaded() async throws {
        guard whisperKit == nil else { return }
        debugLog("🤖 WhisperKit: loading model (first run downloads it — needs internet)…")
        whisperKit = try await WhisperKit(model: "base.en")
        debugLog("🤖 WhisperKit: model loaded")
    }

    func start() async throws {
        try await ensureModelLoaded()

        let url = FileManager.default.temporaryDirectory.appendingPathComponent("micdrop-\(UUID().uuidString).wav")
        recordingURL = url

        let inputNode = audioEngine.inputNode
        let format = inputNode.outputFormat(forBus: 0)
        debugLog("🤖 WhisperKit: recording format \(format)")

        let file = try AVAudioFile(forWriting: url, settings: format.settings)
        audioFile = file

        inputNode.installTap(onBus: 0, bufferSize: 1024, format: format) { [weak self] buffer, _ in
            try? self?.audioFile?.write(from: buffer)
        }

        audioEngine.prepare()
        try audioEngine.start()
        isRecording = true
    }

    func stop() async -> String {
        audioEngine.stop()
        audioEngine.inputNode.removeTap(onBus: 0)
        audioFile = nil
        isRecording = false

        guard let url = recordingURL, let whisperKit else { return "" }
        defer { try? FileManager.default.removeItem(at: url) }

        do {
            let results = try await whisperKit.transcribe(audioPath: url.path())
            let text = results.map(\.text).joined(separator: " ")
            debugLog("🤖 WhisperKit: transcript \"\(text)\"")
            return text.trimmingCharacters(in: .whitespacesAndNewlines)
        } catch {
            debugLog("🤖 WhisperKit: transcribe error — \(error)")
            return ""
        }
    }
}

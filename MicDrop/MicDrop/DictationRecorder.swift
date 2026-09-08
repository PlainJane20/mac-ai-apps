//
//  DictationRecorder.swift
//  MicDrop
//
//  Captures microphone audio and transcribes it on-device via Apple's
//  Speech framework — requiresOnDeviceRecognition is set explicitly so
//  audio never leaves the machine, same "local only" stance as every
//  other app in this series.
//

import AVFoundation
import Speech

enum DictationError: Error, LocalizedError {
    case permissionDenied
    case recognizerUnavailable
    case emptyTranscript

    var errorDescription: String? {
        switch self {
        case .permissionDenied:
            return "Microphone or Speech Recognition access was denied. Check System Settings → Privacy & Security."
        case .recognizerUnavailable:
            return "On-device speech recognition isn't available right now."
        case .emptyTranscript:
            return "Didn't catch any speech."
        }
    }
}

@MainActor
final class DictationRecorder {
    static let shared = DictationRecorder()

    private(set) var isRecording = false

    private let audioEngine = AVAudioEngine()
    private let recognizer = SFSpeechRecognizer(locale: Locale(identifier: "en-US"))
    private var request: SFSpeechAudioBufferRecognitionRequest?
    private var task: SFSpeechRecognitionTask?
    private var latestTranscript = ""

    private init() {}

    static func requestPermissions(completion: @escaping (Bool) -> Void) {
        SFSpeechRecognizer.requestAuthorization { speechStatus in
            guard speechStatus == .authorized else {
                DispatchQueue.main.async { completion(false) }
                return
            }
            AVCaptureDevice.requestAccess(for: .audio) { granted in
                DispatchQueue.main.async { completion(granted) }
            }
        }
    }

    func start() throws {
        guard let recognizer, recognizer.isAvailable else {
            throw DictationError.recognizerUnavailable
        }
        debugLog("🗣️ supportsOnDeviceRecognition = \(recognizer.supportsOnDeviceRecognition)")

        latestTranscript = ""
        let request = SFSpeechAudioBufferRecognitionRequest()
        request.shouldReportPartialResults = true
        // Keep this entirely on-device — the whole point of this app is
        // that dictation never leaves the machine. If the OS doesn't
        // actually support on-device recognition for this locale/hardware,
        // this would otherwise fail silently — we log it above instead of
        // guessing.
        request.requiresOnDeviceRecognition = true
        self.request = request

        let inputNode = audioEngine.inputNode
        let format = inputNode.outputFormat(forBus: 0)
        debugLog("🗣️ input format: \(format)")
        inputNode.installTap(onBus: 0, bufferSize: 1024, format: format) { [weak self] buffer, _ in
            self?.request?.append(buffer)
        }

        audioEngine.prepare()
        try audioEngine.start()
        isRecording = true

        task = recognizer.recognitionTask(with: request) { [weak self] result, error in
            guard let self else { return }
            if let error {
                debugLog("🗣️ recognition task error: \(error)")
            }
            if let result {
                self.latestTranscript = result.bestTranscription.formattedString
                debugLog("🗣️ partial result: \"\(self.latestTranscript)\" isFinal=\(result.isFinal)")
            }
        }
    }

    /// Stops recording and returns the transcript. Waits briefly after
    /// endAudio() before cancelling — the recognizer's final result
    /// arrives asynchronously, and cancelling right away risks truncating
    /// the last word or two.
    func stop() async -> String {
        audioEngine.stop()
        audioEngine.inputNode.removeTap(onBus: 0)
        request?.endAudio()
        try? await Task.sleep(nanoseconds: 400_000_000)
        task?.cancel()
        request = nil
        task = nil
        isRecording = false
        return latestTranscript.trimmingCharacters(in: .whitespacesAndNewlines)
    }
}

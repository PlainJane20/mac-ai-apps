//
//  MicDropController.swift
//  MicDrop
//
//  Owns the record → transcribe → clean → insert flow.
//

import AppKit
import UserNotifications

@MainActor
final class MicDropController: ObservableObject {
    static let shared = MicDropController()

    @Published private(set) var isRecording = false
    @Published private(set) var isProcessing = false
    @Published private(set) var lastError: String?
    @Published private(set) var lastResult: String?
    /// Set when a sensitive action (currently: Slack sends) is resolved
    /// and ready, but waiting on an explicit confirm/cancel in the
    /// popover — nothing here has actually happened yet.
    @Published private(set) var pendingAction: PendingAction?

    private init() {}

    func toggleRecording() {
        if isRecording {
            Task { await stopAndProcess() }
        } else {
            startRecording()
        }
    }

    private func startRecording() {
        guard PasteInserter.hasAccessibilityPermission else {
            lastError = "Grant Accessibility access first — see the menu."
            PasteInserter.requestAccessibilityPermission()
            return
        }

        DictationRecorder.requestPermissions { [weak self] granted in
            guard let self else { return }
            guard granted else {
                self.lastError = DictationError.permissionDenied.localizedDescription
                return
            }
            do {
                try DictationRecorder.shared.start()
                self.isRecording = true
                self.lastError = nil
            } catch {
                self.lastError = error.localizedDescription
            }
        }
    }

    private func stopAndProcess() async {
        isRecording = false
        let transcript = await DictationRecorder.shared.stop()

        guard !transcript.isEmpty else {
            lastError = DictationError.emptyTranscript.localizedDescription
            notify(title: "Mic Drop", body: "Didn't catch any speech.")
            return
        }

        isProcessing = true
        defer { isProcessing = false }
        lastError = nil

        let command = await IntentClassifier.classify(transcript)
        debugLog("📡 MicDrop: classified as \(command.intent.rawValue), argument: \(command.argument ?? "nil")")

        if command.intent == .dictate {
            await runDictation(transcript)
        } else {
            await runCommand(command)
        }
    }

    private func runDictation(_ transcript: String) async {
        do {
            let cleaned = try await OllamaClient.cleanText(transcript)
            PasteInserter.insertText(cleaned)
            lastResult = cleaned
            NSSound(named: "Glass")?.play()
            notify(title: "Mic Drop ✨", body: "Inserted — \(cleaned.count) characters.")
        } catch {
            lastError = error.localizedDescription
            lastResult = nil
            notify(title: "Mic Drop — failed", body: error.localizedDescription)
        }
    }

    private func runCommand(_ command: ParsedCommand) async {
        switch await CommandRouter.run(command) {
        case .needsConfirmation(let action):
            pendingAction = action
            notify(title: "Mic Drop — confirm?", body: action.description)
        case .completed(let result):
            present(result)
        }
    }

    private func present(_ result: CommandResult) {
        lastResult = result.spokenText

        if result.isQuery {
            // Query results get spoken AND shown as a notification — you
            // might be looking at your screen or not.
            SpeechOutput.speak(result.spokenText)
            notify(title: "Mic Drop", body: result.spokenText)
        } else {
            NSSound(named: "Glass")?.play()
            notify(title: "Mic Drop ✅", body: result.spokenText)
        }
    }

    func confirmPendingAction() {
        guard let action = pendingAction else { return }
        pendingAction = nil
        Task {
            let result = await action.execute()
            present(result)
        }
    }

    func cancelPendingAction() {
        pendingAction = nil
        notify(title: "Mic Drop", body: "Cancelled.")
    }

    func requestNotificationPermission() {
        UNUserNotificationCenter.current().requestAuthorization(options: [.alert, .sound]) { _, _ in }
    }

    private func notify(title: String, body: String) {
        let content = UNMutableNotificationContent()
        content.title = title
        content.body = body
        content.sound = .default
        UNUserNotificationCenter.current().add(
            UNNotificationRequest(identifier: UUID().uuidString, content: content, trigger: nil)
        )
    }
}

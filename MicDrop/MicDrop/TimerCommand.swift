//
//  TimerCommand.swift
//  MicDrop
//
//  "Set a timer for 10 minutes" — a plain in-process timer that fires a
//  notification + sound when it's up. No need for a system-level timer
//  API; MicDrop already runs continuously as a background app.
//

import Foundation
import UserNotifications

struct TimerCommand {
    static func run(argument: String?) -> CommandResult {
        guard let text = argument, let seconds = parseDuration(text) else {
            return CommandResult(spokenText: "Didn't catch how long to set the timer for.", isQuery: true)
        }

        DispatchQueue.main.asyncAfter(deadline: .now() + seconds) {
            let content = UNMutableNotificationContent()
            content.title = "Miko ⏰"
            content.body = "Timer's up — \(text)."
            content.sound = .default
            UNUserNotificationCenter.current().add(
                UNNotificationRequest(identifier: UUID().uuidString, content: content, trigger: nil)
            )
        }

        return CommandResult(spokenText: "Timer set for \(text).", isQuery: false)
    }

    /// Parses simple durations like "10 minutes", "1 hour", "30 seconds".
    /// Doesn't attempt anything more elaborate — good enough for voice.
    private static func parseDuration(_ text: String) -> Double? {
        let lower = text.lowercased()
        guard let numberString = lower.split(separator: " ").first(where: { $0.contains(where: \.isNumber) }),
              let value = Double(numberString.filter { $0.isNumber || $0 == "." }) else {
            return nil
        }

        if lower.contains("hour") { return value * 3600 }
        if lower.contains("min") { return value * 60 }
        if lower.contains("sec") { return value }
        // No unit spoken — assume minutes, the common case for "set a timer for 10".
        return value * 60
    }
}

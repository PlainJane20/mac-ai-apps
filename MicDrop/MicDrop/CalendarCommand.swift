//
//  CalendarCommand.swift
//  MicDrop
//
//  "What's on my calendar today" — native EventKit, read-only, no
//  external auth needed.
//

import EventKit

struct CalendarCommand {
    static func run() async -> CommandResult {
        let store = EKEventStore()

        let granted: Bool = await withCheckedContinuation { continuation in
            store.requestFullAccessToEvents { granted, _ in
                continuation.resume(returning: granted)
            }
        }
        guard granted else {
            return CommandResult(spokenText: "Calendar access isn't granted yet.", isQuery: true)
        }

        let calendar = Calendar.current
        let startOfDay = calendar.startOfDay(for: Date())
        guard let endOfDay = calendar.date(byAdding: .day, value: 1, to: startOfDay) else {
            return CommandResult(spokenText: "Couldn't compute today's date range.", isQuery: true)
        }

        let predicate = store.predicateForEvents(withStart: startOfDay, end: endOfDay, calendars: nil)
        let events = store.events(matching: predicate).sorted { $0.startDate < $1.startDate }

        guard !events.isEmpty else {
            return CommandResult(spokenText: "Nothing on your calendar today.", isQuery: true)
        }

        let formatter = DateFormatter()
        formatter.timeStyle = .short
        let lines = events.map { event -> String in
            let time = event.isAllDay ? "all day" : formatter.string(from: event.startDate)
            return "\(time): \(event.title ?? "Untitled event")"
        }

        let summary = "You have \(events.count) event\(events.count == 1 ? "" : "s") today. " + lines.joined(separator: ". ")
        return CommandResult(spokenText: summary, isQuery: true)
    }
}

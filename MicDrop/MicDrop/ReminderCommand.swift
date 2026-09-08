//
//  ReminderCommand.swift
//  MicDrop
//
//  "Remind me to call the dentist tomorrow" — native EventKit reminders.
//  v1 doesn't parse a specific due date/time out of the argument; it just
//  creates the reminder with the spoken text as the title, due date left
//  unset. Good enough to capture the thought; refining "tomorrow at 3pm"
//  into an actual due date is a reasonable follow-up, not a blocker.
//

import EventKit

struct ReminderCommand {
    static func run(argument: String?) async -> CommandResult {
        guard let text = argument, !text.isEmpty else {
            return CommandResult(spokenText: "Didn't catch what to remind you about.", isQuery: true)
        }

        let store = EKEventStore()
        let granted: Bool = await withCheckedContinuation { continuation in
            store.requestFullAccessToReminders { granted, _ in
                continuation.resume(returning: granted)
            }
        }
        guard granted else {
            return CommandResult(spokenText: "Reminders access isn't granted yet.", isQuery: true)
        }

        let reminder = EKReminder(eventStore: store)
        reminder.title = text
        reminder.calendar = store.defaultCalendarForNewReminders()

        do {
            try store.save(reminder, commit: true)
            return CommandResult(spokenText: "Added a reminder: \(text).", isQuery: false)
        } catch {
            return CommandResult(spokenText: "Couldn't save that reminder — \(error.localizedDescription)", isQuery: true)
        }
    }
}

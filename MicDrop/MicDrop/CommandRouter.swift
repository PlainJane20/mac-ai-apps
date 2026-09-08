//
//  CommandRouter.swift
//  MicDrop
//
//  Dispatches a classified command to its handler. Every branch returns a
//  CommandResult; the caller decides whether to speak it, notify, or (for
//  .dictate) hand off to the existing clean+paste pipeline instead.
//

import Foundation
import UserNotifications

/// What the router produced — most commands complete immediately;
/// .slack alone can come back as something that still needs your
/// explicit confirmation before it actually fires.
enum RouterOutcome {
    case completed(CommandResult)
    case needsConfirmation(PendingAction)
}

struct CommandRouter {
    static func run(_ command: ParsedCommand) async -> RouterOutcome {
        switch command.intent {
        case .dictate:
            // Handled separately by MicDropController — this branch
            // shouldn't normally be reached via the router.
            return .completed(CommandResult(spokenText: "", isQuery: false))
        case .calendar:
            return .completed(await CalendarCommand.run())
        case .reminder:
            return .completed(await ReminderCommand.run(argument: command.argument))
        case .note:
            return .completed(NoteCommand.run(argument: command.argument))
        case .battery:
            return .completed(SystemCommand.battery())
        case .volume:
            return .completed(SystemCommand.volume(argument: command.argument))
        case .webSearch:
            return .completed(WebSearchCommand.run(argument: command.argument))
        case .openApp:
            return .completed(OpenAppCommand.run(argument: command.argument))
        case .music:
            return .completed(MusicCommand.run(argument: command.argument))
        case .timer:
            return .completed(TimerCommand.run(argument: command.argument))
        case .slack:
            switch await SlackCommand.run(argument: command.argument) {
            case .result(let result): return .completed(result)
            case .pendingSend(let action): return .needsConfirmation(action)
            }
        case .jira:
            return .completed(await JiraCommand.run())
        }
    }
}

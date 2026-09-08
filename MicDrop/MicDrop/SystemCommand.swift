//
//  SystemCommand.swift
//  MicDrop
//
//  Battery level (native IOKit power source API) and volume (AppleScript
//  — no simple public API for this one). Deliberately NOT attempting
//  Focus/Do Not Disturb toggling: Apple removed third-party programmatic
//  access to Focus modes in recent macOS versions for privacy reasons —
//  there's no supported public API for it anymore, so it's out of scope
//  rather than built on something fragile/unsupported.
//

import Foundation
import IOKit.ps

struct SystemCommand {
    static func battery() -> CommandResult {
        guard let snapshot = IOPSCopyPowerSourcesInfo()?.takeRetainedValue(),
              let sources = IOPSCopyPowerSourcesList(snapshot)?.takeRetainedValue() as? [CFTypeRef],
              let source = sources.first,
              let description = IOPSGetPowerSourceDescription(snapshot, source)?.takeUnretainedValue() as? [String: Any],
              let percentage = description[kIOPSCurrentCapacityKey] as? Int
        else {
            return CommandResult(spokenText: "Couldn't read the battery level.", isQuery: true)
        }

        let charging = (description[kIOPSPowerSourceStateKey] as? String) == kIOPSACPowerValue
        let suffix = charging ? ", and it's charging" : ""
        return CommandResult(spokenText: "Battery is at \(percentage) percent\(suffix).", isQuery: true)
    }

    static func volume(argument: String?) -> CommandResult {
        let arg = (argument ?? "").lowercased()

        if arg.contains("mute") {
            _ = AppleScriptRunner.run("set volume with output muted")
            return CommandResult(spokenText: "Muted.", isQuery: false)
        }
        if arg.contains("unmute") {
            _ = AppleScriptRunner.run("set volume without output muted")
            return CommandResult(spokenText: "Unmuted.", isQuery: false)
        }
        if let level = Int(arg.filter(\.isNumber)) {
            let clamped = max(0, min(100, level))
            _ = AppleScriptRunner.run("set volume output volume \(clamped)")
            return CommandResult(spokenText: "Volume set to \(clamped) percent.", isQuery: false)
        }
        if arg.contains("up") {
            _ = AppleScriptRunner.run("set volume output volume ((output volume of (get volume settings)) + 15)")
            return CommandResult(spokenText: "Turned it up.", isQuery: false)
        }
        if arg.contains("down") {
            _ = AppleScriptRunner.run("set volume output volume ((output volume of (get volume settings)) - 15)")
            return CommandResult(spokenText: "Turned it down.", isQuery: false)
        }
        return CommandResult(spokenText: "Didn't catch what to do with the volume.", isQuery: true)
    }
}

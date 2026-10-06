# MicDrop

### A native menu bar voice assistant: dictate or give a command, with local models

Press a global hotkey, talk, and pause. MicDrop transcribes on-device with
WhisperKit, then uses a local Ollama model to decide whether you were dictating
text (clean it and paste it at the cursor) or giving a command (run it).

[![Swift 5](https://img.shields.io/badge/swift-5-F05138?logo=swift&logoColor=white)](https://swift.org/)
[![SwiftUI](https://img.shields.io/badge/UI-SwiftUI-0A84FF)]()
[![Ollama Local LLM](https://img.shields.io/badge/LLM-Ollama_%28local%29-8b5cf6)](https://ollama.com)
[![WhisperKit](https://img.shields.io/badge/STT-WhisperKit-14b8a6)](https://github.com/argmaxinc/WhisperKit)
[![Platform macOS](https://img.shields.io/badge/platform-macOS_15.5+-000000?logo=apple&logoColor=white)]()

Status: work in progress. There is no automated test suite; behavior described
here is read from the source in this directory.

## How it works

1. **Hotkey** (`HotKeyManager.swift`): `Cmd+Option+D`, registered with Carbon
   `RegisterEventHotKey`. It toggles recording. The popover button does the same.
2. **Record and transcribe** (`WhisperKitRecorder.swift`): records to a temporary
   WAV with `AVAudioEngine`, then transcribes the whole file once with WhisperKit
   (`base.en`). Recording auto-stops after about 1.5 seconds of silence that
   follows detected speech (a fixed RMS threshold). The model is downloaded on
   first run, which needs internet.
3. **Classify** (`IntentClassifier.swift`): the transcript goes to Ollama
   (`/api/chat`, `llama3.2:latest`, JSON output) with a system prompt listing the
   allowed intents. Any failure, malformed JSON, or doubt falls back to plain
   dictation, on purpose, so a misfire cannot trigger an unwanted action.
4. **Dictation path** (`MicDropController.swift`, `OllamaClient.swift`,
   `PasteInserter.swift`): the transcript is cleaned by the local model (filler
   words, grammar, bullet lists), written to the clipboard, pasted with a
   simulated `Cmd+V`, and the previous clipboard text is restored about 0.6 s
   later. This needs Accessibility permission.
5. **Command path** (`CommandRouter.swift`): dispatches to one handler per intent.
   Query-style results are spoken (`AVSpeechSynthesizer`) and shown as a
   notification; action-style results get a notification and a sound.

## Commands the code implements

| Intent | What it does | Implementation |
|---|---|---|
| calendar | Reads today's events | EventKit, read-only |
| reminder | Creates a reminder titled with the spoken text (no due-date parsing) | EventKit |
| note | Creates a new note | AppleScript, Notes.app |
| battery | Reports percentage and whether on AC power | IOKit power sources |
| volume | Set a level, mute, up/down by 15 (the unmute branch is unreachable: "unmute" matches the mute check first) | AppleScript |
| webSearch | Opens a Google search in the default browser | `NSWorkspace` |
| openApp | Opens an app by name; a few web-only services (Gmail, Drive, Docs, Calendar, Outlook, YouTube) open in the browser; "Chrome" is aliased | `open -a`, `NSWorkspace` |
| music | Play, pause, next, previous, what's playing | AppleScript, Music.app only |
| timer | In-process timer ("10 minutes", "1 hour", "30 seconds") that fires a notification | `DispatchQueue`; lost if the app quits |
| slack | Without a parsed channel and message: reports how many channels the token is in. With one: resolves the channel and waits for an explicit Confirm click before posting | Slack Web API, user token from a local config file |
| jira | Counts your tickets in open sprints by status category (to do / in progress / done) | Jira REST, reads Pulse's local credentials file |

Slack sends are the only sensitive-action boundary: they go through a
`PendingAction` that does nothing until you click Confirm in the popover.
The Slack token cannot see or send direct messages, only channels.

## What is not built

- Gmail. `MicDropCredentials.swift` has fields for a Gmail OAuth client, but no
  Gmail command exists.
- Reminder due dates, Spotify support, Focus / Do Not Disturb control.
- Streaming transcription; the whole recording is transcribed after it stops.
- Tests or CI.
- Cleanup of leftover "Miko" strings in notification titles from an earlier
  working name.

## Credentials and privacy

- No secrets are in this repo. Slack token (and the unused Gmail fields) are read
  from `~/Library/Application Support/MicDrop/config.json`, written with
  permissions `0600`. The Jira command reads
  `~/Library/Application Support/Pulse/jira-credentials.json`, which Pulse writes.
- Transcription and the Ollama calls stay on your machine. Network calls the code
  makes: Slack and Jira (only when you use those commands), and the one-time
  WhisperKit model download.
- The app is not sandboxed (`com.apple.security.app-sandbox` is false), which it
  needs for AppleScript, simulated keystrokes, and shelling out to `open`.
- `DebugLog.swift` appends debug lines, including transcripts, to
  `/tmp/micdrop-debug.log`. Delete or disable it before sharing a build.

## Setup

```bash
brew install ollama
ollama pull llama3.2
```

Open `MicDrop.xcodeproj` in Xcode (macOS 15.5 deployment target; Swift Package
Manager fetches WhisperKit) and run. Grant microphone, notifications,
Accessibility, and (for those commands) Calendar and Reminders access when
prompted.

To enable Slack, create `config.json` at the path above with a
`slackUserToken` value (this is a manual step; there is no setup UI for it).

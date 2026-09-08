# mac-ai-apps

Personal native macOS apps, each solving a problem I actually have, built to learn
the native-app + local-AI development process end to end.

## Apps (in build order)

1. **Lint** — menu-bar clipboard cleaner. `Cmd+Shift+V` sends clipboard text through
   a local LLM (Ollama) to reformat/clean it up, then replaces the clipboard contents.
2. **Pulse** — menu-bar Jira sprint brief, summarized via a local LLM. Queries
   `assignee = currentUser() AND sprint in openSprints()` — no board ID, project key,
   or company domain hardcoded anywhere in source, so it works against any Jira
   instance, not just one company's. Credentials live in macOS Keychain, entered
   once at first launch, never in a file. **Hard rule: no real employer ticket data,
   screenshots, or API responses ever get committed** — README/sample output use only
   fabricated examples (fake ticket IDs like `PROJ-123`, fake names). The tool is
   generic; the *usage* isn't shareable, and those stay separate.
3. **Dictation tool** — global hotkey → on-device speech-to-text (Whisper) → local LLM
   cleanup pass → inserts text at cursor.

This repo is private for now but intended to eventually go public — these three are
resume-shareable personal projects, not tied to sensitive data.

## Shared patterns

No shared package — each app is small enough that copying the pattern is simpler than
extracting a library. What's reused by hand across apps: the `MenuBarExtra` scaffold,
the Ollama HTTP client shape, and the `UNUserNotificationCenterDelegate` fix for
foreground-notification sound. The global hotkey (where used) is a direct Carbon
`RegisterEventHotKey` call, no third-party dependency.

## Local AI stack

- **Ollama** (`localhost:11434`) running `llama3.2:latest` for general text tasks

# mac-ai-apps

Personal native macOS apps, each solving a problem I actually have, built to learn
the native-app + local-AI development process end to end.

## Apps (in build order)

1. **Lint** — menu-bar clipboard cleaner. `Cmd+Shift+V` sends clipboard text through
   a local LLM (Ollama) to reformat/clean it up, then replaces the clipboard contents.
2. **TPM Daily Brief** — menu-bar app that pulls Jira sprint data (reusing the fetch
   logic from `an earlier private script`) and summarizes it via a local LLM.
   Local-only by design — this touches internal work data. Company-specific config
   (board ID, project key, domain) stays in a gitignored config file, never hardcoded
   in source, so this repo can go public later without exposing employer internals.
3. **Dictation tool** — global hotkey → on-device speech-to-text (Whisper) → local LLM
   cleanup pass → inserts text at cursor.

This repo is private for now but intended to eventually go public — these three are
resume-shareable personal projects, not tied to sensitive data (once TPM Daily Brief's
config is properly externalized).

## Shared code

Common pieces (global hotkey registration, Ollama HTTP client, clipboard/notification
helpers) live in a local Swift package so each app reuses the same foundation instead
of re-implementing it.

## Local AI stack

- **Ollama** (`localhost:11434`) running `llama3.2:latest` for general text tasks
- **KeyboardShortcuts** (SPM) for global hotkeys

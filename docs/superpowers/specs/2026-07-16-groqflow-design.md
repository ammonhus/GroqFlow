# GroqFlow — Design Spec

Date: 2026-07-16
Status: Approved by user (build straight through to working .app)

## What it is

Native macOS menu-bar dictation app cloning Wispr Flow's desktop experience, backed by Groq APIs.
Hold Right Option to dictate; release to transcribe, format, and paste at the cursor in whatever app
is frontmost. Double-tap Right Option for hands-free mode. Esc cancels.

## Locked decisions

- macOS only (user is on macOS 26.2, Apple Silicon, Swift 6.2.3 toolchain).
- Native Swift. AppKit shell + SwiftUI views. SwiftPM executable, hand-assembled `.app` bundle,
  ad-hoc codesign, no sandbox, `LSUIElement = true` (menu bar only, no Dock icon).
- Hotkey: Right Option (keyCode 61). Hold >= 0.25 s = push-to-talk. Double-tap within 350 ms =
  hands-free toggle. Esc = cancel. Rebindable in Settings (choices: Right Option, Right Command,
  fn, F5).
- STT: Groq `whisper-large-v3-turbo` via `POST https://api.groq.com/openai/v1/audio/transcriptions`.
  16 kHz mono 16-bit WAV built in memory. `language` param when user picked one; `prompt` param
  (<= 224 tokens) seeded from personal dictionary + context.
- Formatting: Groq `llama-3.1-8b-instant` via chat completions. Single pass, JSON response
  `{"text": ...}`. Falls back to raw transcript on any error.
- API key: user pastes into Settings; stored in macOS Keychain. Never in files.
- Package dependency: `sindresorhus/KeyboardShortcuts` NOT used — hotkey needs raw flagsChanged
  handling for modifier-only hold/double-tap; hand-rolled CGEventTap. Zero external dependencies
  target; SQLite via system `libsqlite3`.
- Swift language mode: v5 in Package.swift (avoid strict-concurrency churn), main-actor UI.

## Architecture

Single process. Modules communicate through `AppState` (ObservableObject on MainActor) and a
`DictationController` state machine. Every module below is one directory owned by one build agent.

```
Sources/GroqFlow/
  App/         main.swift, AppDelegate, AppState, DictationController (state machine)
  Hotkey/      HotkeyManager — CGEventTap listen-only, health-check loop
  Audio/       AudioRecorder (AVAudioEngine tap -> AVAudioConverter -> 16k mono Int16),
               WAVEncoder, SoundPlayer (start/stop/cancel pings), level meter publisher
  Groq/        GroqAPI (HTTP), TranscriptionService, FormattingService, FormattingPrompt builder
  Insertion/   TextInserter — clipboard save/write/Cmd-V synth/restore, concealed pasteboard type,
               "type instead of paste" fallback via CGEventKeyboardSetUnicodeString
  Context/     ContextService — NSWorkspace frontmost app, bundle-id -> StyleCategory,
               AX read of focused element text (toggleable)
  FlowBar/     FlowBarPanel (NSPanel nonactivating, floating, all Spaces + fullscreen aux),
               FlowBarView (SwiftUI): idle pill / listening waveform / processing spinner,
               check = stop, x = cancel
  History/     HistoryStore (SQLite3 C API), TranscriptRecord, stats (words, WPM, streak)
  Vocab/       DictionaryStore + SnippetStore (JSON files in Application Support)
  SettingsKit/ SettingsStore (UserDefaults-backed ObservableObject), KeychainHelper
  MenuBar/     StatusItemController (NSStatusItem, state-aware icon, menu)
  MainWindow/  MainWindowController + SwiftUI: HomeView (history+stats+search),
               DictionaryView, SnippetsView, StyleView, SettingsView, OnboardingView
  Support/     Permissions (mic / input monitoring / accessibility check+prompt),
               LaunchAtLogin (SMAppService), Log
```

### DictationController state machine

States: `idle -> recording(pushToTalk | handsFree) -> processing -> inserting -> idle`,
plus `cancelled` from any active state (Esc, X button, or hotkey while processing does nothing).
Command Mode runs the same pipeline with `mode = .command(selectedText)`.

Flow, push-to-talk:
1. Right Option down held 0.25 s -> `recording`: play start ping, show FlowBar waveform,
   AudioRecorder.start(). Capture frontmost app snapshot (bundle id, name, AX context) NOW —
   focus must be read before we do anything else.
2. Right Option up -> `processing`: stop recorder, get WAV. If < 0.4 s of audio, discard silently.
3. TranscriptionService -> raw text. Empty -> flash "didn't catch that" on FlowBar, back to idle.
4. FormattingService(raw, context, style, dictionary, snippets) -> formatted text.
5. TextInserter.paste(formatted) -> `inserting` -> save HistoryRecord(raw, formatted, app,
   duration, wpm) -> idle. Play completion tick.

Hands-free: double-tap arms it; FlowBar shows persistent waveform with check/x; second double-tap,
check click, or Esc ends and processes. Session hard cap 10 min (25 MB API limit ~= 13 min WAV).

Errors: network/API failure -> FlowBar shows brief error, audio WAV written to
`Application Support/GroqFlow/recovery/`, History shows a "Retry" row that re-runs the pipeline.
Silence >= 5 s with near-zero levels while recording -> "Microphone not working?" hint on bar.

### HotkeyManager details

- CGEventTap `.listenOnly` on `flagsChanged` + `keyDown` (Esc). Needs Input Monitoring permission;
  synthesis in TextInserter needs Accessibility. Both requested in onboarding.
- Right Option identified by keyCode 61 with `.maskAlternate`. Hold vs tap: timestamp on down,
  0.25 s timer promotes to push-to-talk; up before promote checks double-tap window (350 ms).
- Health check: every 5 s verify `CGEvent.tapIsEnabled`, re-enable, reinstall if dead
  (handles kCGEventTapDisabledByTimeout and the TCC/codesign race).
- While recording in push-to-talk, a mouse click does NOT cancel (Wispr discards on click; we keep
  it simpler and only Esc/X cancels — documented divergence).

### Command Mode

Secondary hotkey: hold Right Option + Control (rebindable). On press: capture current selection by
snapshotting the clipboard, synthesizing Cmd-C, waiting 150 ms, reading the pasteboard, restoring
the snapshot. Record instruction while held; on release run STT, then FormattingService in command
mode (selectedText + instruction -> replacement). Paste replaces the selection. No selection ->
result is inserted at cursor (inline answer). Selection cap 1,000 words. FlowBar shows a distinct
accent color while in Command Mode.

### Formatting engine (the Wispr behavior, replicated in one LLM pass)

System prompt (built by FormattingPrompt) instructs the model to output JSON `{"text": ...}` and:
- Remove filler words (um, uh, like, you know) and false starts.
- Backtrack: apply self-corrections signalled by "actually", "scratch that", "wait", "no",
  "I mean", or restatement. Preserve genuine uses ("I actually enjoyed it").
- Punctuate from phrasing; honor spoken punctuation ("comma", "period", "question mark",
  "new line", "new paragraph", full Wispr set). Never auto-insert em dashes.
- Spoken enumerations ("one ... two ..." / "first ... second ...") -> numbered list.
- Numbers to digits. Emails/URLs joined ("john dot smith at gmail dot com" -> john.smith@gmail.com).
- Capitalization: sentence case; if `context.precedingText` ends mid-sentence, start lowercase.
- Style category adjusts ONLY capitalization/punctuation/spacing (Wispr rule), not wording:
  veryCasual (no caps, minimal punctuation), casual (caps, light punctuation, no trailing period),
  excited (caps + !), formal (full punctuation). Category from bundle id map:
  personal messaging (iMessage/WhatsApp/Telegram/Signal), work messaging (Slack/Teams/Discord),
  email (Mail/Outlook/Superhuman), code (Xcode/Terminal/iTerm/VS Code/Cursor/Windsurf/Warp),
  other (default).
- Code category: no auto-capitalization, technical terms as identifiers ("user ID" -> userId when
  clearly an identifier), no smart quotes.
- Dictionary words: exact spellings enforced; starred words win conflicts. Snippets: if the whole
  utterance matches a snippet trigger phrase (fuzzy), output the snippet body verbatim.
- Command Mode variant prompt: given selectedText + spoken instruction, return replacement only.
- Temperature 0.2, max ~2x input tokens. On malformed JSON, retry once, then use raw transcript.

Raw transcript ALWAYS stored alongside formatted; History row action "Undo AI edit" copies raw.

### TextInserter

1. Snapshot `NSPasteboard.general` (string/RTF items only; skip files — documented).
2. `setString` with `org.nspasteboard.ConcealedType` marker.
3. CGEvent Cmd-down, V-down, V-up, Cmd-up to `.cghidEventTap`.
4. Restore snapshot after 300 ms.
Fallback setting "Type instead of paste": CGEventKeyboardSetUnicodeString in 20-char chunks.
Secure-input detection (`IsSecureEventInputEnabled`): show FlowBar warning, copy to clipboard
instead of pasting.

### FlowBar

NSPanel: `[.borderless, .nonactivatingPanel]`, `.floating` level, `.canJoinAllSpaces` +
`.fullScreenAuxiliary`, never becomes key, positioned bottom-center (remembers screen). SwiftUI
content, three states: idle (small dim pill, hidden entirely if "Show Flow Bar" off), listening
(expanded pill, live 24-bar waveform from level meter, check + x buttons, mouse events enabled),
processing (indeterminate shimmer). Click idle pill = start hands-free. Right-click = mini menu
(mic picker, language, snooze 1 h, open app).

### Main window

SwiftUI, sidebar navigation: Home, Dictionary, Snippets, Style, Settings. Opens from menu bar or
on first launch (onboarding replaces content until complete).
- Home: header (total words, streak, avg WPM, current shortcut), search field, transcript list
  grouped Today/Yesterday/date; row hover: copy, undo-AI-edit, retry (failed rows), delete.
- Dictionary: add field (60 char cap), list with star toggle + delete; "misspelling fix" entries
  (wrong -> right pairs). Auto-learn is OUT of v1 (needs typed-correction observation).
- Snippets: trigger phrase -> body editor.
- Style: four category cards with preset picker (veryCasual/casual/excited/formal) + live preview.
- Settings: General (API key field w/ validate button, mic picker, languages multi-select +
  auto-detect toggle, shortcut rebind), System (launch at login, show Flow Bar, sounds, show in
  history), Formatting (smart formatting on/off, context awareness on/off), About.
- Onboarding: welcome -> API key entry + validation -> permissions checklist (Microphone, Input
  Monitoring, Accessibility; live green/red status, Grant buttons, re-check on app activation) ->
  mic test with level meter -> practice dictation into a text field -> done.

### Menu bar

NSStatusItem, template icon; swaps to filled/red while recording, spinner overlay while
processing. Menu: Open GroqFlow, Paste Last Transcript, Copy Last Transcript, separator,
Start Hands-Free Dictation, separator, Settings…, Quit.

### Storage

- History: SQLite at `~/Library/Application Support/GroqFlow/history.db` (id, ts, raw, formatted,
  bundle_id, app_name, duration_ms, char_count, mode, status).
- Dictionary/snippets/settings: JSON + UserDefaults in same dir; Keychain for API key.

## Packaging

`scripts/build_app.sh`: `swift build -c release` -> assemble `dist/GroqFlow.app/Contents/`
(MacOS/GroqFlow binary, Info.plist with NSMicrophoneUsageDescription + LSUIElement + bundle id
`com.ammon.groqflow`, icon), `codesign -s - --force --deep`. Stable ad-hoc identity; script warns
that re-signing resets TCC grants. README documents: first run, key entry, the three permission
grants, and disabling conflicts if user later picks fn.

## Testing

- Unit: WAVEncoder output header/bytes; FormattingPrompt assembly; style category mapping;
  double-tap/hold state machine logic (extracted pure `HotkeyClassifier` for testability);
  HistoryStore CRUD; snippet trigger matching.
- Integration (manual + scripted): `swift build` clean; launch smoke test; scripted Groq round-trip
  with a bundled test WAV (skipped without key). End-to-end verified live by orchestrator with
  the user's key at hand-off.

## Divergences from Wispr Flow (v1)

No cloud sync/accounts, no auto-learn dictionary, no Scratchpad, no meeting recorder, no Transforms
slots, no mouse-button hotkeys, no per-word language switching UI beyond language list + auto-detect,
click-outside doesn't cancel recording. Everything else above mimics documented Wispr behavior.

# GroqFlow

A native macOS menu-bar dictation app. Hold a key, speak, and your words are
transcribed and pasted at your cursor in any app. Speech-to-text runs on Groq
Whisper; formatting and command mode run on Groq Llama. It is a local menu-bar
utility (no dock icon) modeled on Wispr Flow.

## Requirements

- macOS 14.0 or later (Apple Silicon)
- A Groq API key from https://console.groq.com
- Swift 6.2 toolchain (Xcode command line tools) to build

## One-time setup

1. Build the app bundle:

   ```
   bash scripts/build_app.sh
   ```

   This compiles a release binary and assembles `dist/GroqFlow.app`, then
   ad-hoc signs it.

2. Optional: move the app to Applications so it survives rebuilds and shows up
   in Spotlight:

   ```
   mv dist/GroqFlow.app /Applications/
   ```

3. Launch it (double-click `GroqFlow.app`, or `open dist/GroqFlow.app`). There
   is no dock icon; look for the microphone icon in the menu bar. On first
   launch an onboarding window opens.

4. Paste your Groq API key. Get one at https://console.groq.com, then paste it
   into the onboarding key field and click Validate. Onboarding continues once
   the key checks out. The key is stored in the macOS Keychain, never on disk
   in plain text.

5. Grant the three permissions when onboarding asks (or later in System
   Settings > Privacy & Security):

   - Microphone — to record your voice.
   - Input Monitoring — so the app can see the dictation key being held.
   - Accessibility — so the app can paste (Cmd-V) and read the current
     selection for command mode.

   The onboarding checklist shows a live status dot for each and a Grant button
   that opens the right settings pane.

## Usage

- Hold Right Option and speak. Release to transcribe and paste at the cursor.
- Double-tap Right Option to start hands-free (toggle) dictation. Tap the key
  again, or click the stop button on the Flow Bar, to end. Hands-free has a
  10-minute cap.
- Press Esc to cancel an in-progress recording, transcription, or paste.
- Hold Right Option + Control for command mode: your current selection is sent
  along with a spoken instruction (for example, "make this more formal") and
  the result replaces the selection. With nothing selected, the spoken
  instruction is answered inline.

The Flow Bar (small capsule near the bottom of the screen) shows recording
state and a live waveform, with stop and cancel buttons. You can hide it in
Settings.

The menu-bar icon menu gives you: open the main window, paste or copy the last
transcript, start hands-free, open Settings, and quit.

## Features

- Groq Whisper speech-to-text with optional language selection or auto-detect.
- Smart formatting on Groq Llama: removes fillers, applies spoken punctuation
  ("new line", "new paragraph"), handles backtracking ("actually", "scratch
  that"), numbered lists, and per-app style presets (casual/formal caps and
  punctuation).
- Context awareness: adapts formatting to the frontmost app category (personal
  messaging, work messaging, email, code, or other).
- Custom dictionary: enforce spellings of names and terms, with starred
  priority words and misspelling corrections.
- Snippets: spoken triggers expand to canned text without an LLM call.
- History window: searchable, day-grouped list of past transcripts with copy,
  undo-AI-edit (copy the raw transcript), retry, and delete.
- Command mode for editing the current selection by voice.
- Hands-free toggle dictation with a 10-minute cap.
- Optional launch at login, subtle start/stop/cancel sounds, and type-instead-
  of-paste for fields that reject pastes.

## Troubleshooting

- Permissions reset after a rebuild. `scripts/build_app.sh` ad-hoc signs the
  app, so every rebuild produces a new signature that macOS treats as a
  different app. After rebuilding you must re-grant Microphone, Input
  Monitoring, and Accessibility. To avoid this, move the app to `/Applications`
  and rebuild less often, or sign with a stable Developer ID certificate.

- Nothing pastes in a password field. macOS "secure input" is active in
  password and other secure fields. GroqFlow will not synthesize keystrokes
  there. It copies the transcript to the clipboard and flashes a notice
  instead, so you can paste manually where it is safe.

- The paste lands in the wrong window. Cmd-V goes to whatever app is frontmost.
  If the GroqFlow main window is open and focused, the paste can land there.
  Click into your target app first, then dictate.

- "Microphone not working?" hint or a flat waveform. If the input level stays
  near zero for a few seconds the app shows a hint. Check that the right input
  device is selected in Settings, that Microphone permission is granted, and
  that the mic is not muted or in use elsewhere.

- Key held but nothing records. Confirm Input Monitoring is granted. If it was
  granted before a rebuild, re-grant it (see the permissions-reset note above).

- Launch at login does nothing from `swift run`. Launch at login only works
  from the signed `.app` bundle, not from a raw `swift run` binary.

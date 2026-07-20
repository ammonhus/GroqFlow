import Foundation
import AppKit
import Combine

// The dictation state machine. Owns the pipeline that turns a hotkey gesture
// into pasted text: capture context -> record -> transcribe -> format -> paste
// -> history. Only writer of AppState. Runs entirely on the main actor; network
// work suspends off-main inside GroqAPI/FormattingService.
@MainActor
final class DictationController {
    private let appState: AppState
    private let settings: SettingsStore
    private let recorder: AudioRecorder
    private let history: HistoryStore
    private let dictionary: DictionaryStore
    private let snippets: SnippetStore
    private let flowBar: FlowBarController
    private let recoveryDir: URL

    // Invoked after history rows change (retry / new record) so the main window
    // can refresh its list. Set by the integration layer.
    var onHistoryChanged: (() -> Void)?

    private var cancellables = Set<AnyCancellable>()

    private var currentMode: DictationMode?
    private var capturedContext: AppContext = .empty
    private var commandSelectedText: String?
    private var recordingDurationSec: TimeInterval = 0

    private var processingTask: Task<Void, Never>?
    private var handsFreeCapTimer: DispatchWorkItem?
    private var silenceMonitorTask: Task<Void, Never>?

    // Bumped on cancel so any in-flight pipeline abandons its remaining work.
    private var pipelineGeneration = 0

    // Session hard cap for hands-free (matches the recorder's 10-minute sample cap).
    private let handsFreeCapSeconds: TimeInterval = 600
    private let selectionWordCap = 1000

    init(appState: AppState, settings: SettingsStore, recorder: AudioRecorder,
         history: HistoryStore, dictionary: DictionaryStore, snippets: SnippetStore,
         flowBar: FlowBarController, recoveryDir: URL) {
        self.appState = appState
        self.settings = settings
        self.recorder = recorder
        self.history = history
        self.dictionary = dictionary
        self.snippets = snippets
        self.flowBar = flowBar
        self.recoveryDir = recoveryDir

        // Bridge the recorder's smoothed level into AppState for the waveform.
        recorder.$level
            .sink { [weak self] level in self?.appState.audioLevel = level }
            .store(in: &cancellables)
    }

    // MARK: - Hotkey routing

    func handle(_ action: HotkeyAction) {
        switch action {
        case .beginPushToTalk: beginRecording(mode: .pushToTalk)
        case .endPushToTalk: stopAndProcess()
        case .toggleHandsFree: toggleHandsFree()
        case .beginCommand: beginCommand()
        case .endCommand: stopAndProcess()
        case .cancel: cancel()
        }
    }

    // MARK: - UI entry points

    // FlowBar check button, or a menu/status action to stop a hands-free session.
    func stopFromUI() {
        if case .recording = appState.dictationState { stopAndProcess() }
    }

    func toggleHandsFree() {
        switch appState.dictationState {
        case .idle:
            beginRecording(mode: .handsFree)
        case .recording(.handsFree):
            stopAndProcess()
        default:
            break // ignore during push-to-talk / command / processing
        }
    }

    func pasteLast() {
        guard let text = lastFormatted(), !text.isEmpty else { return }
        TextInserter.paste(text, typeInstead: settings.typeInsteadOfPaste)
    }

    func copyLast() {
        guard let text = lastFormatted(), !text.isEmpty else { return }
        let pb = NSPasteboard.general
        pb.clearContents()
        pb.setString(text, forType: .string)
    }

    // MARK: - Recording start

    private func beginRecording(mode: DictationMode) {
        guard startCapture(mode: mode) else { return }
        if mode == .handsFree { scheduleHandsFreeCap() }
    }

    private func beginCommand() {
        guard startCapture(mode: .command) else { return }
        // Grab the current selection via Cmd-C while the instruction is spoken.
        // The target app is still frontmost (we never activate).
        Task { @MainActor [weak self] in
            guard let self else { return }
            let selection = await TextInserter.copySelection()
            if let selection {
                self.commandSelectedText = Self.capWords(selection, maxWords: self.selectionWordCap)
            }
        }
    }

    // Shared start: context snapshot FIRST, then ping + waveform + recorder.
    private func startCapture(mode: DictationMode) -> Bool {
        guard case .idle = appState.dictationState else {
            // A hotkey during processing used to be swallowed silently, so the user
            // spoke into dead air and lost the dictation. Tell them instead.
            switch appState.dictationState {
            case .processing, .inserting:
                flowBar.show()
                flowBar.flash(message: "Still finishing the last one — try again in a moment")
                SoundPlayer.playError()
            default:
                break // already recording: waveform is on screen, nothing to add
            }
            return false
        }

        guard let key = settings.apiKey, !key.isEmpty else {
            flowBar.show()
            flowBar.flash(message: "Add your Groq API key in Settings")
            SoundPlayer.playError()
            return false
        }

        // Read the destination focus before doing anything else.
        capturedContext = ContextService.snapshot(axEnabled: settings.contextAwareness)

        do {
            recorder.setPreferredDevice(uid: settings.micDeviceUID)
            try recorder.start()
        } catch {
            Log.audio.error("recorder start failed: \(String(describing: error), privacy: .public)")
            flowBar.show()
            flowBar.flash(message: "Microphone unavailable")
            SoundPlayer.playError()
            return false
        }

        currentMode = mode
        commandSelectedText = nil
        appState.dictationState = .recording(mode)
        SoundPlayer.playStart()
        flowBar.show()
        startSilenceMonitor()
        return true
    }

    // MARK: - Recording stop -> pipeline

    private func stopAndProcess() {
        guard case .recording(let mode) = appState.dictationState else { return }
        cancelHandsFreeCap()
        stopSilenceMonitor()

        recordingDurationSec = recorder.currentDuration
        let wav = recorder.stop()
        appState.dictationState = .processing(mode)

        guard let wav else {
            // Under the 0.4 s minimum: nothing usable was captured.
            flowBar.flash(message: "Too short — hold the key while you speak")
            finishToIdle()
            return
        }

        let context = capturedContext
        let selected = commandSelectedText
        let duration = recordingDurationSec
        let gen = pipelineGeneration
        processingTask = Task { @MainActor [weak self] in
            await self?.process(wav: wav, durationSec: duration, mode: mode,
                                context: context, selected: selected, gen: gen)
        }
    }

    private func process(wav: Data, durationSec: TimeInterval, mode: DictationMode,
                         context: AppContext, selected: String?, gen: Int) async {
        guard let key = settings.apiKey, !key.isEmpty else {
            handleFailure(wav: wav, raw: "", mode: mode, context: context,
                          durationSec: durationSec, message: "Add your Groq API key in Settings")
            return
        }
        let api = GroqAPI(apiKey: key)
        let language = resolvedLanguage()
        let sttPrompt = FormattingPrompt.sttPrompt(dictionary: dictionary.entries, context: context)

        // 1. Transcribe (auto-retries once bare on empty/error — see transcribeRetrying).
        let trimmed: String
        do {
            trimmed = try await transcribeRetrying(api: api, wav: wav, language: language, prompt: sttPrompt)
        } catch {
            guard gen == pipelineGeneration else { return }
            Log.groq.error("transcription failed: \(String(describing: error), privacy: .public)")
            handleFailure(wav: wav, raw: "", mode: mode, context: context,
                          durationSec: durationSec, message: "Transcription failed")
            return
        }
        guard gen == pipelineGeneration else { return }

        if trimmed.isEmpty {
            // Keep the audio: an empty transcript on real speech is recoverable
            // via Retry from the history list, which re-transcribes the saved WAV.
            handleFailure(wav: wav, raw: "", mode: mode, context: context,
                          durationSec: durationSec, message: "Didn't catch that — saved for retry")
            return
        }

        // 2. Format (command mode uses the instruction pipeline).
        let service = FormattingService(api: api)
        let formatted: String
        if mode == .command {
            let result = await service.command(selected: selected, instruction: trimmed)
            guard gen == pipelineGeneration else { return }
            guard let result else {
                handleFailure(wav: wav, raw: trimmed, mode: mode, context: context,
                              durationSec: durationSec, message: "Command failed")
                return
            }
            formatted = result
        } else {
            let result = await service.format(raw: trimmed, context: context,
                                              preset: preset(for: context.category),
                                              dictionary: dictionary.entries,
                                              snippets: snippets.snippets,
                                              smartFormatting: settings.smartFormatting)
            guard gen == pipelineGeneration else { return }
            formatted = result
        }

        // 3. Paste + record.
        appState.dictationState = .inserting
        performInsert(formatted)
        recordHistory(raw: trimmed, formatted: formatted, mode: mode,
                      context: context, durationSec: durationSec, status: "ok")
        SoundPlayer.playStop()
        onHistoryChanged?()
        finishToIdle()
    }

    // MARK: - Transcription retry

    // Groq Whisper intermittently returns an empty transcript (HTTP 200,
    // text: "") for valid speech — non-deterministic and server-side, and a
    // plain retry recovers effectively all of them. Try once with the prompt,
    // then once bare (no prompt/language) if the first is empty or throws.
    // Returns the trimmed transcript ("" if still empty); rethrows only if the
    // bare attempt also errors.
    private func transcribeRetrying(api: GroqAPI, wav: Data,
                                    language: String?, prompt: String?) async throws -> String {
        do {
            let first = try await api.transcribe(wav: wav, language: language, prompt: prompt)
            let t = first.trimmingCharacters(in: .whitespacesAndNewlines)
            if !t.isEmpty { return t }
            Log.groq.error("empty transcript, retrying bare")
        } catch {
            Log.groq.error("transcription attempt failed, retrying bare: \(String(describing: error), privacy: .public)")
        }
        let second = try await api.transcribe(wav: wav, language: nil, prompt: nil)
        return second.trimmingCharacters(in: .whitespacesAndNewlines)
    }

    // MARK: - Insertion

    private func performInsert(_ text: String) {
        guard !text.isEmpty else { return }
        // TextInserter copies to the clipboard instead of pasting when secure
        // input is active; surface that to the user.
        if TextInserter.isSecureInputActive {
            flowBar.flash(message: "Secure field: copied to clipboard")
        }
        TextInserter.paste(text, typeInstead: settings.typeInsteadOfPaste)
    }

    // MARK: - Cancel

    private func cancel() {
        switch appState.dictationState {
        case .idle:
            return // Esc while idle does nothing
        case .recording:
            cancelHandsFreeCap()
            stopSilenceMonitor()
            recorder.cancel()
            pipelineGeneration += 1
            SoundPlayer.playCancel()
            finishToIdle()
        case .processing, .inserting:
            pipelineGeneration += 1
            processingTask?.cancel()
            processingTask = nil
            SoundPlayer.playCancel()
            finishToIdle()
        }
    }

    // MARK: - Retry (from Home)

    // Re-runs the pipeline from a stored recovery WAV when available, else
    // re-formats the stored raw transcript. Updates the history row in place.
    func retry(id: Int64) {
        Task { @MainActor [weak self] in
            guard let self else { return }
            guard let record = try? self.history.record(id: id) else { return }
            guard let key = self.settings.apiKey, !key.isEmpty else {
                self.flowBar.show()
                self.flowBar.flash(message: "Add your Groq API key in Settings")
                return
            }
            let api = GroqAPI(apiKey: key)
            let service = FormattingService(api: api)
            let category = ContextService.category(forBundleID: record.bundleID)
            let context = AppContext(bundleID: record.bundleID, appName: record.appName,
                                     precedingText: nil, category: category)

            var raw = record.raw.trimmingCharacters(in: .whitespacesAndNewlines)
            let wavURL = self.recoveryDir.appendingPathComponent("\(id).wav")
            if let wav = try? Data(contentsOf: wavURL) {
                let prompt = FormattingPrompt.sttPrompt(dictionary: self.dictionary.entries, context: context)
                if let newRaw = try? await api.transcribe(wav: wav, language: self.resolvedLanguage(), prompt: prompt) {
                    let t = newRaw.trimmingCharacters(in: .whitespacesAndNewlines)
                    if !t.isEmpty { raw = t }
                }
            }

            guard !raw.isEmpty else {
                self.flowBar.show()
                self.flowBar.flash(message: "Retry failed")
                return
            }

            let formatted: String
            if record.mode == "command" {
                formatted = await service.command(selected: nil, instruction: raw) ?? raw
            } else {
                formatted = await service.format(raw: raw, context: context,
                                                 preset: self.preset(for: category),
                                                 dictionary: self.dictionary.entries,
                                                 snippets: self.snippets.snippets,
                                                 smartFormatting: self.settings.smartFormatting)
            }

            try? self.history.markRetried(id: id, formatted: formatted)
            try? FileManager.default.removeItem(at: wavURL)
            self.onHistoryChanged?()
        }
    }

    // MARK: - Failure handling

    private func handleFailure(wav: Data?, raw: String, mode: DictationMode,
                              context: AppContext, durationSec: TimeInterval, message: String) {
        flowBar.flash(message: message)
        SoundPlayer.playError()
        let id = recordHistory(raw: raw, formatted: "", mode: mode,
                               context: context, durationSec: durationSec, status: "failed")
        if let wav, let id { saveRecovery(wav: wav, id: id) }
        onHistoryChanged?()
        finishToIdle()
    }

    private func saveRecovery(wav: Data, id: Int64) {
        try? FileManager.default.createDirectory(at: recoveryDir, withIntermediateDirectories: true)
        try? wav.write(to: recoveryDir.appendingPathComponent("\(id).wav"))
    }

    // MARK: - History

    @discardableResult
    private func recordHistory(raw: String, formatted: String, mode: DictationMode,
                              context: AppContext, durationSec: TimeInterval, status: String) -> Int64? {
        var record = TranscriptRecord(
            raw: raw,
            formatted: formatted,
            bundleID: context.bundleID,
            appName: context.appName,
            durationMs: Int(durationSec * 1000),
            mode: modeString(mode),
            status: status)
        do {
            let id = try history.insert(record)
            if status == "ok" {
                record.id = id
                appState.lastTranscript = record
            }
            return id
        } catch {
            Log.app.error("history insert failed: \(String(describing: error), privacy: .public)")
            return nil
        }
    }

    private func lastFormatted() -> String? {
        if let t = appState.lastTranscript { return t.formatted }
        return (try? history.all(matching: nil))?.first(where: { $0.status == "ok" })?.formatted
    }

    // MARK: - Session helpers

    private func finishToIdle() {
        currentMode = nil
        commandSelectedText = nil
        cancelHandsFreeCap()
        stopSilenceMonitor()
        processingTask = nil
        appState.audioLevel = 0
        appState.dictationState = .idle
        if settings.showFlowBar { flowBar.show() } else { flowBar.hide() }
    }

    private func scheduleHandsFreeCap() {
        cancelHandsFreeCap()
        let work = DispatchWorkItem { [weak self] in
            guard let self, case .recording(.handsFree) = self.appState.dictationState else { return }
            self.flowBar.flash(message: "10 minute limit reached")
            self.stopAndProcess()
        }
        handsFreeCapTimer = work
        DispatchQueue.main.asyncAfter(deadline: .now() + handsFreeCapSeconds, execute: work)
    }

    private func cancelHandsFreeCap() {
        handsFreeCapTimer?.cancel()
        handsFreeCapTimer = nil
    }

    // Flags a possible dead mic: near-zero level for 5 s while recording.
    private func startSilenceMonitor() {
        silenceMonitorTask?.cancel()
        silenceMonitorTask = Task { @MainActor [weak self] in
            var silentFor = 0.0
            var warned = false
            while !Task.isCancelled {
                try? await Task.sleep(nanoseconds: 500_000_000)
                guard let self, case .recording = self.appState.dictationState else { return }
                if self.recorder.level < 0.01 {
                    silentFor += 0.5
                    if silentFor >= 5.0, !warned {
                        warned = true
                        self.flowBar.flash(message: "Microphone not working?")
                    }
                } else {
                    silentFor = 0
                    warned = false
                }
            }
        }
    }

    private func stopSilenceMonitor() {
        silenceMonitorTask?.cancel()
        silenceMonitorTask = nil
    }

    // MARK: - Derived values

    private func resolvedLanguage() -> String? {
        guard !settings.autoDetectLanguage, settings.languages.count == 1 else { return nil }
        return settings.languages.first
    }

    private func preset(for category: StyleCategory) -> StylePreset {
        settings.stylePresets[category] ?? .formal
    }

    private func modeString(_ mode: DictationMode) -> String {
        switch mode {
        case .pushToTalk: return "pushToTalk"
        case .handsFree: return "handsFree"
        case .command: return "command"
        }
    }

    private static func capWords(_ text: String, maxWords: Int) -> String {
        let words = text.split(whereSeparator: { $0.isWhitespace })
        if words.count <= maxWords { return text }
        return words.prefix(maxWords).joined(separator: " ")
    }
}

import AppKit
import Combine

// Builds the object graph, wires every module's callbacks, and either launches
// onboarding or starts the hotkey listener + flow bar depending on settings.
@MainActor
public final class AppDelegate: NSObject, NSApplicationDelegate {
    private let appState = AppState()

    private var settings: SettingsStore!
    private var dictionary: DictionaryStore!
    private var snippets: SnippetStore!
    private var history: HistoryStore!
    private var recorder: AudioRecorder!

    private var hotkey: HotkeyManager!
    private var flowBar: FlowBarController!
    private var statusItem: StatusItemController!
    private var mainWindow: MainWindowController!
    private var dictation: DictationController!

    private var cancellables = Set<AnyCancellable>()
    private var hasStartedDictation = false

    public override init() {
        super.init()
    }

    public func applicationDidFinishLaunching(_ notification: Notification) {
        let support = Self.appSupportDir()
        try? FileManager.default.createDirectory(at: support, withIntermediateDirectories: true)

        // Stores.
        settings = SettingsStore()
        dictionary = DictionaryStore(fileURL: support.appendingPathComponent("dictionary.json"))
        snippets = SnippetStore(fileURL: support.appendingPathComponent("snippets.json"))
        history = Self.openHistory(in: support)
        recorder = AudioRecorder()

        SoundPlayer.enabled = settings.soundsEnabled

        // UI + services.
        flowBar = FlowBarController(appState: appState)
        statusItem = StatusItemController(appState: appState)
        mainWindow = MainWindowController(appState: appState, settings: settings, history: history,
                                          dictionary: dictionary, snippets: snippets)
        hotkey = HotkeyManager(settings: settings)
        dictation = DictationController(appState: appState, settings: settings, recorder: recorder,
                                        history: history, dictionary: dictionary, snippets: snippets,
                                        flowBar: flowBar,
                                        recoveryDir: support.appendingPathComponent("recovery", isDirectory: true))

        wireCallbacks()
        observeSettings()

        if settings.onboardingComplete {
            startDictation(showPermissionAlert: true)
        } else {
            mainWindow.showOnboarding()
            // Start the engine during onboarding so the practice step works
            // live. No blocking alert here: the onboarding permissions step
            // owns that UX, and the hotkey health loop installs the tap as soon
            // as Input Monitoring is granted mid-onboarding.
            startDictation(showPermissionAlert: false)
        }
    }

    // MARK: - Wiring

    private func wireCallbacks() {
        hotkey.onAction = { [weak self] action in self?.dictation.handle(action) }
        hotkey.isHandsFreeActive = { [weak self] in
            if case .recording(.handsFree) = self?.appState.dictationState { return true }
            return false
        }

        flowBar.onStopTapped = { [weak self] in self?.dictation.stopFromUI() }
        flowBar.onCancelTapped = { [weak self] in self?.dictation.handle(.cancel) }
        flowBar.onIdleTapped = { [weak self] in self?.dictation.toggleHandsFree() }

        statusItem.onOpen = { [weak self] in self?.mainWindow.show() }
        statusItem.onPasteLast = { [weak self] in self?.dictation.pasteLast() }
        statusItem.onCopyLast = { [weak self] in self?.dictation.copyLast() }
        statusItem.onStartHandsFree = { [weak self] in self?.dictation.toggleHandsFree() }
        statusItem.onSettings = { [weak self] in self?.mainWindow.show() }
        statusItem.onQuit = { NSApp.terminate(nil) }

        mainWindow.onValidateKey = { key in await GroqAPI(apiKey: key).validateKey() }
        mainWindow.onRetryRecord = { [weak self] id in self?.dictation.retry(id: id) }

        dictation.onHistoryChanged = { [weak self] in self?.mainWindow.refresh() }
    }

    private func observeSettings() {
        settings.$soundsEnabled
            .sink { SoundPlayer.enabled = $0 }
            .store(in: &cancellables)

        // Ensure the engine is running once onboarding completes (it is usually
        // already started; this is a no-op guard for the completed case).
        settings.$onboardingComplete
            .removeDuplicates()
            .sink { [weak self] complete in
                if complete { self?.startDictation(showPermissionAlert: true) }
            }
            .store(in: &cancellables)

        // Reflect flow-bar visibility changes while idle.
        settings.$showFlowBar
            .removeDuplicates()
            .sink { [weak self] show in
                guard let self, self.hasStartedDictation else { return }
                if case .idle = self.appState.dictationState {
                    if show { self.flowBar.show() } else { self.flowBar.hide() }
                }
            }
            .store(in: &cancellables)
    }

    // MARK: - Start

    private func startDictation(showPermissionAlert: Bool) {
        guard !hasStartedDictation else { return }
        hasStartedDictation = true

        recorder.setPreferredDevice(uid: settings.micDeviceUID)

        if !hotkey.start() && showPermissionAlert {
            presentPermissionAlert()
        }
        if settings.showFlowBar {
            flowBar.show()
        }
    }

    private func presentPermissionAlert() {
        var missing: [String] = []
        if !Permissions.inputMonitoringGranted { missing.append("Input Monitoring") }
        if !Permissions.accessibilityGranted { missing.append("Accessibility") }
        if !Permissions.micGranted { missing.append("Microphone") }
        if missing.isEmpty { missing.append("Input Monitoring") }

        let alert = NSAlert()
        alert.messageText = "GroqFlow needs permission to run"
        alert.informativeText = "The global shortcut could not start. Grant these in System Settings, then reopen GroqFlow:\n\n"
            + missing.joined(separator: "\n")
        alert.addButton(withTitle: "Open System Settings")
        alert.addButton(withTitle: "Later")
        if alert.runModal() == .alertFirstButtonReturn {
            Permissions.openSettingsPane(.inputMonitoring)
        }
    }

    // MARK: - Paths

    private static func appSupportDir() -> URL {
        let base = FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask).first
            ?? URL(fileURLWithPath: NSTemporaryDirectory())
        return base.appendingPathComponent("GroqFlow", isDirectory: true)
    }

    private static func openHistory(in support: URL) -> HistoryStore {
        let path = support.appendingPathComponent("history.db").path
        if let store = try? HistoryStore(dbPath: path) {
            return store
        }
        Log.app.error("history open failed at \(path, privacy: .public); falling back to temp")
        let fallback = NSTemporaryDirectory() + "groqflow-history.db"
        // Force-unwrap only if even the temp path fails, which would be catastrophic.
        return try! HistoryStore(dbPath: fallback)
    }
}

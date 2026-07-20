import AppKit
import Combine

// Menu-bar status item: state-aware icon plus the app menu.
// Subclasses NSObject so menu items can target its @objc handlers.
@MainActor
public final class StatusItemController: NSObject {
    private let appState: AppState
    private let statusItem: NSStatusItem
    private var cancellables = Set<AnyCancellable>()

    public var onOpen: (() -> Void)?
    public var onPasteLast: (() -> Void)?
    public var onCopyLast: (() -> Void)?
    public var onStartHandsFree: (() -> Void)?
    public var onSettings: (() -> Void)?
    public var onQuit: (() -> Void)?

    public init(appState: AppState) {
        self.appState = appState
        self.statusItem = NSStatusBar.system.statusItem(withLength: NSStatusItem.variableLength)
        super.init()
        configureButton()
        buildMenu()
        observeState()
    }

    // MARK: - Icon

    private func configureButton() {
        updateIcon(for: appState.dictationState)
    }

    private func observeState() {
        appState.$dictationState
            .removeDuplicates()
            .sink { [weak self] state in
                self?.updateIcon(for: state)
            }
            .store(in: &cancellables)
    }

    private func updateIcon(for state: DictationState) {
        guard let button = statusItem.button else { return }
        switch state {
        case .idle:
            button.image = Self.symbol("mic")
            button.contentTintColor = nil
        case .recording:
            button.image = Self.symbol("mic.fill")
            button.contentTintColor = .systemRed
        case .processing:
            button.image = Self.symbol("waveform")
            button.contentTintColor = .secondaryLabelColor
        case .inserting:
            button.image = Self.symbol("mic.fill")
            button.contentTintColor = .secondaryLabelColor
        }
    }

    private static func symbol(_ name: String) -> NSImage? {
        let image = NSImage(systemSymbolName: name, accessibilityDescription: "GroqFlow")
        image?.isTemplate = true
        return image
    }

    // MARK: - Menu

    private func buildMenu() {
        let menu = NSMenu()
        menu.autoenablesItems = false
        menu.addItem(makeItem("Open GroqFlow", #selector(handleOpen)))
        menu.addItem(makeItem("Paste Last Transcript", #selector(handlePasteLast)))
        menu.addItem(makeItem("Copy Last Transcript", #selector(handleCopyLast)))
        menu.addItem(.separator())
        menu.addItem(makeItem("Start Hands-Free Dictation", #selector(handleStartHandsFree)))
        menu.addItem(.separator())
        menu.addItem(makeItem("Settings...", #selector(handleSettings)))
        menu.addItem(makeItem("Quit", #selector(handleQuit)))
        statusItem.menu = menu
    }

    private func makeItem(_ title: String, _ action: Selector) -> NSMenuItem {
        let item = NSMenuItem(title: title, action: action, keyEquivalent: "")
        item.target = self
        return item
    }

    // MARK: - Actions

    @objc private func handleOpen() { onOpen?() }
    @objc private func handlePasteLast() { onPasteLast?() }
    @objc private func handleCopyLast() { onCopyLast?() }
    @objc private func handleStartHandsFree() { onStartHandsFree?() }
    @objc private func handleSettings() { onSettings?() }
    @objc private func handleQuit() { onQuit?() }
}

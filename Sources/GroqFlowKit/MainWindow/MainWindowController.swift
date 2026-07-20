import AppKit
import SwiftUI
import Combine

// Owns the single main window and swaps its content between the onboarding
// wizard and the sidebar app. Integration sets the two callbacks and calls
// show() or showOnboarding().
@MainActor
public final class MainWindowController {
    private let model: MainWindowModel
    private var window: NSWindow?

    public var onValidateKey: ((String) async -> Bool)? {
        didSet { model.onValidateKey = onValidateKey }
    }
    public var onRetryRecord: ((Int64) -> Void)? {
        didSet { model.onRetryRecord = onRetryRecord }
    }

    public init(appState: AppState, settings: SettingsStore, history: HistoryStore,
                dictionary: DictionaryStore, snippets: SnippetStore) {
        self.model = MainWindowModel(appState: appState, settings: settings, history: history,
                                     dictionary: dictionary, snippets: snippets)
    }

    public func show() {
        model.historyVM.reload()
        let root = MainRootView(model: model)
        present(NSHostingController(rootView: root), title: "GroqFlow")
    }

    // Reloads the Home list in place without activating or reordering the
    // window. Safe to call after a background dictation completes.
    public func refresh() {
        guard let window, window.isVisible else { return }
        model.historyVM.reload()
    }

    public func showOnboarding() {
        let root = OnboardingView(model: model) { [weak self] in
            self?.model.settings.onboardingComplete = true
            self?.show()
        }
        present(NSHostingController(rootView: root), title: "Welcome to GroqFlow")
    }

    // MARK: - Window plumbing

    private func present(_ controller: NSViewController, title: String) {
        let isNew = (window == nil)
        let window = ensureWindow()
        window.title = title
        window.contentViewController = controller
        // Assigning contentViewController can shrink the window to the hosting
        // view's fitting size; restore the intended size on first presentation.
        if isNew {
            window.setContentSize(NSSize(width: 900, height: 600))
            window.center()
        }
        NSApp.activate(ignoringOtherApps: true)
        window.makeKeyAndOrderFront(nil)
    }

    private func ensureWindow() -> NSWindow {
        if let window { return window }
        let window = NSWindow(
            contentRect: NSRect(x: 0, y: 0, width: 900, height: 600),
            styleMask: [.titled, .closable, .miniaturizable, .resizable],
            backing: .buffered,
            defer: false)
        window.isReleasedWhenClosed = false
        window.minSize = NSSize(width: 820, height: 520)
        self.window = window
        return window
    }
}

// Shared reference the SwiftUI tree reads. Stores are injected directly into
// views where observation is needed; the closures are read at call time so
// integration can set them after construction.
@MainActor
final class MainWindowModel: ObservableObject {
    let appState: AppState
    let settings: SettingsStore
    let history: HistoryStore
    let dictionary: DictionaryStore
    let snippets: SnippetStore
    let historyVM: HistoryViewModel

    var onValidateKey: ((String) async -> Bool)?
    var onRetryRecord: ((Int64) -> Void)?

    init(appState: AppState, settings: SettingsStore, history: HistoryStore,
         dictionary: DictionaryStore, snippets: SnippetStore) {
        self.appState = appState
        self.settings = settings
        self.history = history
        self.dictionary = dictionary
        self.snippets = snippets
        self.historyVM = HistoryViewModel(history: history)
    }
}

enum MainSidebarItem: String, CaseIterable, Identifiable, Hashable {
    case home, dictionary, snippets, style, settings

    var id: String { rawValue }

    var title: String {
        switch self {
        case .home: return "Home"
        case .dictionary: return "Dictionary"
        case .snippets: return "Snippets"
        case .style: return "Style"
        case .settings: return "Settings"
        }
    }

    var systemImage: String {
        switch self {
        case .home: return "house"
        case .dictionary: return "character.book.closed"
        case .snippets: return "text.badge.plus"
        case .style: return "paintbrush"
        case .settings: return "gearshape"
        }
    }
}

struct MainRootView: View {
    let model: MainWindowModel
    @State private var selection: MainSidebarItem? = .home

    var body: some View {
        NavigationSplitView {
            List(selection: $selection) {
                ForEach(MainSidebarItem.allCases) { item in
                    Label(item.title, systemImage: item.systemImage)
                        .tag(item)
                }
            }
            .listStyle(.sidebar)
            .navigationSplitViewColumnWidth(min: 180, ideal: 200, max: 240)
        } detail: {
            detailView(for: selection ?? .home)
        }
        .frame(minWidth: 820, minHeight: 520)
    }

    @ViewBuilder
    private func detailView(for item: MainSidebarItem) -> some View {
        switch item {
        case .home:
            HomeView(model: model)
        case .dictionary:
            DictionaryView(store: model.dictionary)
        case .snippets:
            SnippetsView(store: model.snippets)
        case .style:
            StyleView(settings: model.settings)
        case .settings:
            SettingsView(model: model)
        }
    }
}

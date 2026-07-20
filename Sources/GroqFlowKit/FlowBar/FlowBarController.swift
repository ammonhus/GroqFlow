import AppKit
import Combine
import QuartzCore
import SwiftUI

// Observable bridge between the AppKit controller and its SwiftUI content.
// The controller owns it; the view reads flashMessage and invokes the callbacks.
@MainActor
final class FlowBarModel: ObservableObject {
    @Published var flashMessage: String?
    var onStop: (() -> Void)?
    var onCancel: (() -> Void)?
    var onIdle: (() -> Void)?
}

// Floating, non-activating status bar that shows dictation state at the
// bottom-center of the main screen. Visible across all Spaces and over
// fullscreen apps. The DictationController drives show/hide/flash.
@MainActor
public final class FlowBarController {
    private let appState: AppState
    private let model = FlowBarModel()
    private let panel: NSPanel
    private var cancellables = Set<AnyCancellable>()
    private var flashWorkItem: DispatchWorkItem?

    private let bottomMargin: CGFloat = 28

    public init(appState: AppState) {
        self.appState = appState

        panel = NSPanel(
            contentRect: NSRect(x: 0, y: 0, width: 116, height: 30),
            styleMask: [.borderless, .nonactivatingPanel],
            backing: .buffered,
            defer: false
        )
        panel.level = .statusBar
        panel.collectionBehavior = [.canJoinAllSpaces, .fullScreenAuxiliary]
        panel.hidesOnDeactivate = false
        panel.becomesKeyOnlyIfNeeded = true
        panel.isOpaque = false
        panel.backgroundColor = .clear
        panel.hasShadow = false
        panel.isMovableByWindowBackground = false
        panel.ignoresMouseEvents = false

        let hosting = NSHostingView(rootView: FlowBarView(appState: appState, model: model))
        panel.contentView = hosting

        subscribe()
    }

    // MARK: - Public callbacks (forwarded to the view model)

    public var onStopTapped: (() -> Void)? {
        get { model.onStop }
        set { model.onStop = newValue }
    }

    public var onCancelTapped: (() -> Void)? {
        get { model.onCancel }
        set { model.onCancel = newValue }
    }

    public var onIdleTapped: (() -> Void)? {
        get { model.onIdle }
        set { model.onIdle = newValue }
    }

    // MARK: - Visibility

    public func show() {
        updatePanelFrame(animated: false)
        panel.orderFrontRegardless()
    }

    public func hide() {
        panel.orderOut(nil)
    }

    // Brief transient message (errors/hints). Auto-clears after 2.5 s.
    // Assumes the bar is already visible for the operation that produced it.
    public func flash(message: String) {
        flashWorkItem?.cancel()
        model.flashMessage = message
        let work = DispatchWorkItem { [weak self] in
            self?.model.flashMessage = nil
        }
        flashWorkItem = work
        DispatchQueue.main.asyncAfter(deadline: .now() + 2.5, execute: work)
    }

    // MARK: - Layout

    private func subscribe() {
        // @Published emits in willSet (before the property updates), and
        // updatePanelFrame re-reads the current state/flash. Deliver on the next
        // main-runloop tick so the read sees the updated values; otherwise the
        // panel sizes one transition behind and renders off-center.
        appState.$dictationState
            .receive(on: DispatchQueue.main)
            .sink { [weak self] _ in self?.updatePanelFrame(animated: true) }
            .store(in: &cancellables)
        model.$flashMessage
            .receive(on: DispatchQueue.main)
            .sink { [weak self] _ in self?.updatePanelFrame(animated: true) }
            .store(in: &cancellables)
        NotificationCenter.default
            .publisher(for: NSApplication.didChangeScreenParametersNotification)
            .sink { [weak self] _ in self?.updatePanelFrame(animated: false) }
            .store(in: &cancellables)
    }

    private func targetSize() -> NSSize {
        if model.flashMessage != nil {
            return NSSize(width: 210, height: 30)
        }
        switch appState.dictationState {
        case .idle:
            return NSSize(width: 22, height: 8)
        case .recording:
            return NSSize(width: 120, height: 30)
        case .processing, .inserting:
            return NSSize(width: 78, height: 28)
        }
    }

    private func updatePanelFrame(animated: Bool) {
        let size = targetSize()
        let screen = panel.screen ?? NSScreen.main
        // Center on the full screen width so a side-docked Dock (which insets
        // visibleFrame) does not push the bar off-center. Y still rides above
        // the Dock via visibleFrame.
        guard let full = screen?.frame, let visible = screen?.visibleFrame else { return }
        let origin = NSPoint(
            x: (full.midX - size.width / 2).rounded(),
            y: (visible.minY + bottomMargin).rounded()
        )
        let frame = NSRect(origin: origin, size: size)

        // Use AppKit's native frame animation: it animates origin AND size
        // together. animator().setFrame animates size but drops the new origin,
        // which left the bar anchored to its previous (idle) left edge and
        // growing off-center.
        panel.setFrame(frame, display: true, animate: animated && panel.isVisible)
    }
}

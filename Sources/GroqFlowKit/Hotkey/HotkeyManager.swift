import Foundation
import CoreGraphics

// Well-known keyCodes not covered by HotkeyChoice.
enum HotkeyKeyCode {
    static let escape: Int64 = 53
}

// Latches whether a push-to-talk gesture began as a command chord (dictation
// key + Control) so the matching release is reported as a command, not plain
// push-to-talk. Pure and testable.
struct CommandChordRouter {
    private(set) var inCommand = false

    mutating func route(_ action: HotkeyAction, controlHeld: Bool) -> HotkeyAction {
        switch action {
        case .beginPushToTalk:
            inCommand = controlHeld
            return controlHeld ? .beginCommand : .beginPushToTalk
        case .endPushToTalk:
            if inCommand {
                inCommand = false
                return .endCommand
            }
            return .endPushToTalk
        default:
            return action
        }
    }
}

// Listen-only CGEventTap over flagsChanged + key events. Classifies the
// configured dictation key into push-to-talk / hands-free / command actions and
// emits cancel on Esc. Never consumes events. Runs a health loop that
// re-enables or reinstalls the tap if the system disables it.
@MainActor
public final class HotkeyManager {
    private let settings: SettingsStore

    public var onAction: ((HotkeyAction) -> Void)?

    // Set by the integration layer: returns true while a hands-free session is
    // recording. When true, the next press of the dictation key ends the
    // session immediately (no need to click the checkmark).
    public var isHandsFreeActive: (() -> Bool)?

    private var classifier = HotkeyClassifier()
    private var chordRouter = CommandChordRouter()
    private var controlHeld = false

    private var eventTap: CFMachPort?
    private var runLoopSource: CFRunLoopSource?
    private var holdTimer: DispatchWorkItem?
    private var healthTask: Task<Void, Never>?

    private static let eventMask: CGEventMask =
        CGEventMask(1 << CGEventType.flagsChanged.rawValue) |
        CGEventMask(1 << CGEventType.keyDown.rawValue) |
        CGEventMask(1 << CGEventType.keyUp.rawValue)

    public init(settings: SettingsStore) {
        self.settings = settings
    }

    // MARK: - Lifecycle

    public func start() -> Bool {
        if eventTap != nil { return true }
        guard installTap() else {
            Log.hotkey.error("Failed to create event tap; Input Monitoring likely denied")
            return false
        }
        startHealthLoop()
        Log.hotkey.info("Hotkey event tap installed")
        return true
    }

    public func stop() {
        healthTask?.cancel()
        healthTask = nil
        cancelHoldTimer()
        teardownTap()
    }

    // MARK: - Tap install / teardown

    private func installTap() -> Bool {
        guard let tap = CGEvent.tapCreate(
            tap: .cgSessionEventTap,
            place: .headInsertEventTap,
            options: .listenOnly,
            eventsOfInterest: Self.eventMask,
            callback: hotkeyTapCallback,
            userInfo: Unmanaged.passUnretained(self).toOpaque()
        ) else {
            return false
        }
        let source = CFMachPortCreateRunLoopSource(kCFAllocatorDefault, tap, 0)
        CFRunLoopAddSource(CFRunLoopGetMain(), source, .commonModes)
        CGEvent.tapEnable(tap: tap, enable: true)
        eventTap = tap
        runLoopSource = source
        return true
    }

    private func teardownTap() {
        if let tap = eventTap {
            CGEvent.tapEnable(tap: tap, enable: false)
        }
        if let source = runLoopSource {
            CFRunLoopRemoveSource(CFRunLoopGetMain(), source, .commonModes)
        }
        eventTap = nil
        runLoopSource = nil
    }

    // MARK: - Health loop

    private func startHealthLoop() {
        healthTask?.cancel()
        healthTask = Task { @MainActor [weak self] in
            while !Task.isCancelled {
                try? await Task.sleep(nanoseconds: 5_000_000_000)
                guard !Task.isCancelled, let self else { return }
                self.checkTapHealth()
            }
        }
    }

    private func checkTapHealth() {
        guard let tap = eventTap else {
            _ = installTap()
            return
        }
        if !CGEvent.tapIsEnabled(tap: tap) {
            Log.hotkey.warning("Event tap disabled; re-enabling")
            CGEvent.tapEnable(tap: tap, enable: true)
            if !CGEvent.tapIsEnabled(tap: tap) {
                Log.hotkey.warning("Re-enable failed; reinstalling event tap")
                teardownTap()
                _ = installTap()
            }
        }
    }

    // MARK: - Event handling

    fileprivate func handleEvent(type: CGEventType, event: CGEvent) {
        let t = CFAbsoluteTimeGetCurrent()
        switch type {
        case .tapDisabledByTimeout, .tapDisabledByUserInput:
            if let tap = eventTap { CGEvent.tapEnable(tap: tap, enable: true) }
        case .flagsChanged:
            handleFlagsChanged(event, at: t)
        case .keyDown:
            handleKeyDown(event, at: t)
        case .keyUp:
            handleKeyUp(event, at: t)
        default:
            break
        }
    }

    private func handleFlagsChanged(_ event: CGEvent, at t: TimeInterval) {
        let flags = event.flags
        controlHeld = flags.contains(.maskControl)
        let choice = settings.hotkey
        guard choice.isModifier else { return }
        let keyCode = event.getIntegerValueField(.keyboardEventKeycode)
        guard keyCode == choice.keyCode else { return }
        if flags.contains(modifierMask(for: choice)) {
            keyPressed(at: t)
        } else {
            keyReleased(at: t)
        }
    }

    private func handleKeyDown(_ event: CGEvent, at t: TimeInterval) {
        let keyCode = event.getIntegerValueField(.keyboardEventKeycode)
        if keyCode == HotkeyKeyCode.escape {
            // Always emitted; the controller ignores cancel when idle.
            deliver(.cancel)
            return
        }
        let choice = settings.hotkey
        guard !choice.isModifier, keyCode == choice.keyCode else { return }
        // Ignore auto-repeat while a non-modifier key (e.g. F5) is held.
        if event.getIntegerValueField(.keyboardEventAutorepeat) != 0 { return }
        keyPressed(at: t)
    }

    private func handleKeyUp(_ event: CGEvent, at t: TimeInterval) {
        let choice = settings.hotkey
        guard !choice.isModifier else { return }
        let keyCode = event.getIntegerValueField(.keyboardEventKeycode)
        guard keyCode == choice.keyCode else { return }
        keyReleased(at: t)
    }

    private func modifierMask(for choice: HotkeyChoice) -> CGEventFlags {
        switch choice {
        case .rightOption: return .maskAlternate
        case .rightCommand: return .maskCommand
        case .fn: return .maskSecondaryFn
        case .f5: return []
        }
    }

    // MARK: - Classifier driving

    private func keyPressed(at t: TimeInterval) {
        // While hands-free is recording, any press of the dictation key ends the
        // session right away. Discard the gesture so the matching release/timer
        // do not also fire.
        if isHandsFreeActive?() == true {
            cancelHoldTimer()
            classifier.reset()
            deliver(.toggleHandsFree)
            return
        }
        _ = classifier.keyDown(at: t)
        scheduleHoldTimer()
    }

    private func keyReleased(at t: TimeInterval) {
        cancelHoldTimer()
        if let action = classifier.keyUp(at: t) { deliver(action) }
    }

    private func scheduleHoldTimer() {
        cancelHoldTimer()
        guard let deadline = classifier.pendingTimerDeadline else { return }
        let delay = max(0, deadline - CFAbsoluteTimeGetCurrent())
        let work = DispatchWorkItem { [weak self] in
            MainActor.assumeIsolated {
                guard let self else { return }
                if let action = self.classifier.timerFired(at: CFAbsoluteTimeGetCurrent()) {
                    self.deliver(action)
                }
            }
        }
        holdTimer = work
        DispatchQueue.main.asyncAfter(deadline: .now() + delay, execute: work)
    }

    private func cancelHoldTimer() {
        holdTimer?.cancel()
        holdTimer = nil
    }

    private func deliver(_ action: HotkeyAction) {
        let routed = chordRouter.route(action, controlHeld: controlHeld)
        onAction?(routed)
    }
}

// Listen-only tap callback. Reconstructs the manager from the refcon, hops to
// the main actor (the source lives on the main run loop), and passes the event
// through unchanged.
private func hotkeyTapCallback(
    proxy: CGEventTapProxy,
    type: CGEventType,
    event: CGEvent,
    refcon: UnsafeMutableRawPointer?
) -> Unmanaged<CGEvent>? {
    if let refcon {
        let manager = Unmanaged<HotkeyManager>.fromOpaque(refcon).takeUnretainedValue()
        MainActor.assumeIsolated {
            manager.handleEvent(type: type, event: event)
        }
    }
    return Unmanaged.passUnretained(event)
}

import Foundation

// Actions the hotkey layer emits. beginCommand/endCommand are produced by
// HotkeyManager when the command chord (dictation key + Control) is held;
// cancel is produced on Esc. The pure classifier only yields the
// push-to-talk / hands-free actions.
public enum HotkeyAction: Equatable {
    case beginPushToTalk, endPushToTalk, toggleHandsFree
    case beginCommand, endCommand, cancel
}

// Pure hold vs double-tap logic for the dictation key. No AppKit, no timers of
// its own: the owner feeds it keyDown/keyUp/timerFired with monotonic-ish
// timestamps and schedules the hold timer using `pendingTimerDeadline`.
//
// Semantics:
//   keyDown            -> starts a press; arms the hold timer (never returns an action)
//   timerFired(hold)   -> promotes an unreleased press to .beginPushToTalk
//   keyUp after begin  -> .endPushToTalk
//   keyUp before hold  -> a tap (single tap alone does nothing)
//   two taps in window -> .toggleHandsFree
public struct HotkeyClassifier {
    private let holdThreshold: TimeInterval
    private let doubleTapWindow: TimeInterval

    private enum Phase {
        case idle
        case pressed          // first press, awaiting promote or release
        case pressedAfterTap  // press that may complete a double-tap
        case holding          // promoted to push-to-talk
    }

    private var phase: Phase = .idle
    private var keyDownTime: TimeInterval = 0
    private var lastTapDownTime: TimeInterval?   // keyDown time of the prior completed tap

    // Tolerance so a timer firing exactly at the deadline still promotes.
    private static let timerEpsilon: TimeInterval = 0.001

    public init(holdThreshold: TimeInterval = 0.25, doubleTapWindow: TimeInterval = 0.35) {
        self.holdThreshold = holdThreshold
        self.doubleTapWindow = doubleTapWindow
    }

    public mutating func keyDown(at t: TimeInterval) -> HotkeyAction? {
        // Ignore a keyDown while a press is already being tracked.
        switch phase {
        case .pressed, .pressedAfterTap, .holding:
            return nil
        case .idle:
            break
        }
        keyDownTime = t
        if let last = lastTapDownTime, t - last <= doubleTapWindow {
            phase = .pressedAfterTap
        } else {
            phase = .pressed
            lastTapDownTime = nil
        }
        return nil
    }

    public mutating func keyUp(at t: TimeInterval) -> HotkeyAction? {
        switch phase {
        case .idle:
            return nil
        case .holding:
            phase = .idle
            lastTapDownTime = nil
            return .endPushToTalk
        case .pressed:
            // First tap: nothing happens now, but it arms a double-tap.
            lastTapDownTime = keyDownTime
            phase = .idle
            return nil
        case .pressedAfterTap:
            // Second tap within the window completes a double-tap.
            lastTapDownTime = nil
            phase = .idle
            return .toggleHandsFree
        }
    }

    public mutating func timerFired(at t: TimeInterval) -> HotkeyAction? {
        // Promote only if a press is still pending and the hold threshold has
        // genuinely elapsed for the current press (guards a stale timer).
        switch phase {
        case .pressed, .pressedAfterTap:
            guard t - keyDownTime >= holdThreshold - Self.timerEpsilon else { return nil }
            phase = .holding
            lastTapDownTime = nil
            return .beginPushToTalk
        case .idle, .holding:
            return nil
        }
    }

    public var pendingTimerDeadline: TimeInterval? {
        switch phase {
        case .pressed, .pressedAfterTap:
            return keyDownTime + holdThreshold
        case .idle, .holding:
            return nil
        }
    }

    // Discards any in-progress gesture. Used when the owner consumes a press
    // out-of-band (e.g. ending a hands-free session) so the pending keyUp/timer
    // produce no further action.
    public mutating func reset() {
        phase = .idle
        lastTapDownTime = nil
    }
}

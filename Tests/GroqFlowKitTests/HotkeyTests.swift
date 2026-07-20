import XCTest
@testable import GroqFlowKit

final class HotkeyTests: XCTestCase {

    // MARK: - HotkeyClassifier

    func testHoldPromotesToPushToTalk() {
        var c = HotkeyClassifier(holdThreshold: 0.25, doubleTapWindow: 0.35)
        XCTAssertNil(c.keyDown(at: 0))
        XCTAssertEqual(c.pendingTimerDeadline, 0.25)
        XCTAssertEqual(c.timerFired(at: 0.25), .beginPushToTalk)
        // Once holding, no timer is pending.
        XCTAssertNil(c.pendingTimerDeadline)
        XCTAssertEqual(c.keyUp(at: 0.6), .endPushToTalk)
    }

    func testQuickReleaseIsNoOp() {
        var c = HotkeyClassifier(holdThreshold: 0.25, doubleTapWindow: 0.35)
        XCTAssertNil(c.keyDown(at: 0))
        // Released well before the hold threshold and no second tap: nothing.
        XCTAssertNil(c.keyUp(at: 0.1))
        XCTAssertNil(c.pendingTimerDeadline)
    }

    func testDoubleTapToggles() {
        var c = HotkeyClassifier(holdThreshold: 0.25, doubleTapWindow: 0.35)
        XCTAssertNil(c.keyDown(at: 0))
        XCTAssertNil(c.keyUp(at: 0.05))            // first tap
        XCTAssertNil(c.keyDown(at: 0.2))           // second press inside window
        XCTAssertEqual(c.keyUp(at: 0.25), .toggleHandsFree)
    }

    func testDoubleTapOutsideWindowIsTwoSingleTaps() {
        var c = HotkeyClassifier(holdThreshold: 0.25, doubleTapWindow: 0.35)
        XCTAssertNil(c.keyDown(at: 0))
        XCTAssertNil(c.keyUp(at: 0.05))            // first tap arms window
        // Second press begins after the window closes -> treated as fresh tap.
        XCTAssertNil(c.keyDown(at: 0.5))
        XCTAssertNil(c.keyUp(at: 0.55))
    }

    func testTapThenHoldStartsPushToTalk() {
        var c = HotkeyClassifier(holdThreshold: 0.25, doubleTapWindow: 0.35)
        XCTAssertNil(c.keyDown(at: 0))
        XCTAssertNil(c.keyUp(at: 0.05))            // tap
        XCTAssertNil(c.keyDown(at: 0.2))           // second press inside window
        // Held past threshold instead of tapped -> push-to-talk, not a toggle.
        XCTAssertEqual(c.timerFired(at: 0.45), .beginPushToTalk)
        XCTAssertEqual(c.keyUp(at: 1.0), .endPushToTalk)
    }

    func testPendingTimerDeadlineExposedCorrectly() {
        var c = HotkeyClassifier(holdThreshold: 0.25, doubleTapWindow: 0.35)
        XCTAssertNil(c.pendingTimerDeadline)       // idle
        XCTAssertNil(c.keyDown(at: 1.0))
        XCTAssertEqual(c.pendingTimerDeadline, 1.25)
        XCTAssertNil(c.keyUp(at: 1.1))
        XCTAssertNil(c.pendingTimerDeadline)       // back to idle
    }

    func testEarlyTimerDoesNotPromote() {
        var c = HotkeyClassifier(holdThreshold: 0.25, doubleTapWindow: 0.35)
        XCTAssertNil(c.keyDown(at: 0))
        // A timer that fires before the threshold (e.g. a stale prior timer)
        // must not promote the press.
        XCTAssertNil(c.timerFired(at: 0.15))
        XCTAssertEqual(c.pendingTimerDeadline, 0.25)
        // The correct timer still promotes.
        XCTAssertEqual(c.timerFired(at: 0.25), .beginPushToTalk)
    }

    func testHoldDoesNotArmDoubleTap() {
        var c = HotkeyClassifier(holdThreshold: 0.25, doubleTapWindow: 0.35)
        XCTAssertNil(c.keyDown(at: 0))
        XCTAssertEqual(c.timerFired(at: 0.25), .beginPushToTalk)
        XCTAssertEqual(c.keyUp(at: 0.3), .endPushToTalk)
        // A quick tap right after a hold is a plain first tap, not a toggle.
        XCTAssertNil(c.keyDown(at: 0.35))
        XCTAssertNil(c.keyUp(at: 0.4))
    }

    func testStaleKeyDownWhilePressedIgnored() {
        var c = HotkeyClassifier(holdThreshold: 0.25, doubleTapWindow: 0.35)
        XCTAssertNil(c.keyDown(at: 0))
        // A duplicate keyDown must not reset the press timing.
        XCTAssertNil(c.keyDown(at: 0.1))
        XCTAssertEqual(c.pendingTimerDeadline, 0.25)
    }

    func testSpuriousKeyUpWhenIdle() {
        var c = HotkeyClassifier(holdThreshold: 0.25, doubleTapWindow: 0.35)
        XCTAssertNil(c.keyUp(at: 0))
    }

    // MARK: - CommandChordRouter (cancel + command path)

    func testCommandChordRoutesToCommandWhenControlHeld() {
        var r = CommandChordRouter()
        XCTAssertEqual(r.route(.beginPushToTalk, controlHeld: true), .beginCommand)
        // Release is reported as command even if Control was let go first.
        XCTAssertEqual(r.route(.endPushToTalk, controlHeld: false), .endCommand)
    }

    func testCommandChordPassesThroughWithoutControl() {
        var r = CommandChordRouter()
        XCTAssertEqual(r.route(.beginPushToTalk, controlHeld: false), .beginPushToTalk)
        XCTAssertEqual(r.route(.endPushToTalk, controlHeld: false), .endPushToTalk)
    }

    func testCommandLatchResetsBetweenGestures() {
        var r = CommandChordRouter()
        _ = r.route(.beginPushToTalk, controlHeld: true)   // command begins
        _ = r.route(.endPushToTalk, controlHeld: true)     // command ends, latch clears
        // Next gesture without Control is plain push-to-talk.
        XCTAssertEqual(r.route(.beginPushToTalk, controlHeld: false), .beginPushToTalk)
        XCTAssertEqual(r.route(.endPushToTalk, controlHeld: false), .endPushToTalk)
    }

    func testRouterPassesCancelAndToggleUnchanged() {
        var r = CommandChordRouter()
        XCTAssertEqual(r.route(.cancel, controlHeld: true), .cancel)
        XCTAssertEqual(r.route(.toggleHandsFree, controlHeld: true), .toggleHandsFree)
    }

    func testEscapeKeyCode() {
        XCTAssertEqual(HotkeyKeyCode.escape, 53)
    }

    func testCancelActionEquatable() {
        XCTAssertEqual(HotkeyAction.cancel, .cancel)
        XCTAssertNotEqual(HotkeyAction.cancel, .endPushToTalk)
    }
}

final class HotkeyClassifierResetTests: XCTestCase {
    // After reset, a pending press produces no action on keyUp or timer, and
    // double-tap tracking is cleared. Backs the hands-free single-press stop.
    func testResetDiscardsPendingPress() {
        var c = HotkeyClassifier()
        _ = c.keyDown(at: 0)
        c.reset()
        XCTAssertNil(c.pendingTimerDeadline)
        XCTAssertNil(c.keyUp(at: 0.1))
        XCTAssertNil(c.timerFired(at: 0.3))
    }

    func testResetClearsDoubleTapArming() {
        var c = HotkeyClassifier()
        _ = c.keyDown(at: 0)
        _ = c.keyUp(at: 0.05)   // first tap arms double-tap
        c.reset()
        // A press+release right after reset must be treated as a fresh first
        // tap, not the second half of a double-tap.
        _ = c.keyDown(at: 0.1)
        XCTAssertNil(c.keyUp(at: 0.15))
    }
}

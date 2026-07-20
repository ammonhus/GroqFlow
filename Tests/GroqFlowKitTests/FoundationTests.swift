import XCTest
@testable import GroqFlowKit

final class FoundationTests: XCTestCase {
    func testHotkeyKeyCodes() {
        XCTAssertEqual(HotkeyChoice.rightOption.keyCode, 61)
        XCTAssertEqual(HotkeyChoice.rightCommand.keyCode, 54)
        XCTAssertEqual(HotkeyChoice.fn.keyCode, 63)
        XCTAssertEqual(HotkeyChoice.f5.keyCode, 96)
        XCTAssertFalse(HotkeyChoice.f5.isModifier)
    }

    func testTranscriptRecordDefaults() {
        let r = TranscriptRecord(raw: "a", formatted: "A", bundleID: nil, appName: nil,
                                 durationMs: 1000, mode: "pushToTalk", status: "ok")
        XCTAssertEqual(r.id, 0)
    }
}

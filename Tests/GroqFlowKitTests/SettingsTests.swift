import XCTest
@testable import GroqFlowKit

@MainActor
final class SettingsTests: XCTestCase {
    private var suiteName: String!
    private var defaults: UserDefaults!

    override func setUp() {
        super.setUp()
        suiteName = "test.groqflow.\(UUID().uuidString)"
        defaults = UserDefaults(suiteName: suiteName)
    }

    override func tearDown() {
        defaults.removePersistentDomain(forName: suiteName)
        defaults = nil
        suiteName = nil
        super.tearDown()
    }

    func testDefaultValues() {
        let store = SettingsStore(defaults: defaults)
        XCTAssertEqual(store.hotkey, .rightOption)
        XCTAssertEqual(store.languages, [])
        XCTAssertTrue(store.autoDetectLanguage)
        XCTAssertNil(store.micDeviceUID)
        XCTAssertFalse(store.launchAtLogin)
        XCTAssertTrue(store.showFlowBar)
        XCTAssertTrue(store.soundsEnabled)
        XCTAssertTrue(store.smartFormatting)
        XCTAssertTrue(store.contextAwareness)
        XCTAssertFalse(store.typeInsteadOfPaste)
        XCTAssertFalse(store.onboardingComplete)
    }

    func testDefaultPresets() {
        let store = SettingsStore(defaults: defaults)
        XCTAssertEqual(store.stylePresets[.personalMessaging], .casual)
        XCTAssertEqual(store.stylePresets[.workMessaging], .casual)
        XCTAssertEqual(store.stylePresets[.email], .formal)
        XCTAssertEqual(store.stylePresets[.code], .casual)
        XCTAssertEqual(store.stylePresets[.other], .formal)
    }

    func testRoundTripPersistence() {
        let store = SettingsStore(defaults: defaults)
        store.hotkey = .fn
        store.languages = ["en", "es"]
        store.autoDetectLanguage = false
        store.micDeviceUID = "device-123"
        store.showFlowBar = false
        store.soundsEnabled = false
        store.smartFormatting = false
        store.contextAwareness = false
        store.typeInsteadOfPaste = true
        store.onboardingComplete = true
        store.stylePresets[.email] = .excited

        let reloaded = SettingsStore(defaults: defaults)
        XCTAssertEqual(reloaded.hotkey, .fn)
        XCTAssertEqual(reloaded.languages, ["en", "es"])
        XCTAssertFalse(reloaded.autoDetectLanguage)
        XCTAssertEqual(reloaded.micDeviceUID, "device-123")
        XCTAssertFalse(reloaded.showFlowBar)
        XCTAssertFalse(reloaded.soundsEnabled)
        XCTAssertFalse(reloaded.smartFormatting)
        XCTAssertFalse(reloaded.contextAwareness)
        XCTAssertTrue(reloaded.typeInsteadOfPaste)
        XCTAssertTrue(reloaded.onboardingComplete)
        XCTAssertEqual(reloaded.stylePresets[.email], .excited)
        // Unmutated presets keep their defaults.
        XCTAssertEqual(reloaded.stylePresets[.personalMessaging], .casual)
        XCTAssertEqual(reloaded.stylePresets[.code], .casual)
    }

    func testMicDeviceUIDClears() {
        let store = SettingsStore(defaults: defaults)
        store.micDeviceUID = "abc"
        XCTAssertEqual(SettingsStore(defaults: defaults).micDeviceUID, "abc")

        store.micDeviceUID = nil
        XCTAssertNil(SettingsStore(defaults: defaults).micDeviceUID)
    }

    func testHotkeyRawValueMapping() {
        XCTAssertEqual(HotkeyChoice.rightOption.rawValue, "rightOption")
        XCTAssertEqual(HotkeyChoice(rawValue: "rightOption"), .rightOption)
        XCTAssertEqual(HotkeyChoice(rawValue: "fn"), .fn)
        XCTAssertNil(HotkeyChoice(rawValue: "bogus"))

        XCTAssertEqual(HotkeyChoice.rightOption.keyCode, 61)
        XCTAssertEqual(HotkeyChoice.rightCommand.keyCode, 54)
        XCTAssertEqual(HotkeyChoice.fn.keyCode, 63)
        XCTAssertEqual(HotkeyChoice.f5.keyCode, 96)
    }

    func testHotkeyPersistsAcrossAllChoices() {
        for choice in HotkeyChoice.allCases {
            let store = SettingsStore(defaults: defaults)
            store.hotkey = choice
            XCTAssertEqual(SettingsStore(defaults: defaults).hotkey, choice)
        }
    }
}

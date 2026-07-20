import XCTest
@testable import GroqFlowKit

@MainActor
final class ContextTests: XCTestCase {

    // MARK: category mapping

    func testPersonalMessagingBundleIDs() {
        XCTAssertEqual(ContextService.category(forBundleID: "com.apple.MobileSMS"), .personalMessaging)
        XCTAssertEqual(ContextService.category(forBundleID: "net.whatsapp.WhatsApp"), .personalMessaging)
        XCTAssertEqual(ContextService.category(forBundleID: "ru.keepcoder.Telegram"), .personalMessaging)
        XCTAssertEqual(ContextService.category(forBundleID: "org.whispersystems.signal-desktop"), .personalMessaging)
    }

    func testWorkMessagingBundleIDs() {
        XCTAssertEqual(ContextService.category(forBundleID: "com.tinyspeck.slackmacgap"), .workMessaging)
        XCTAssertEqual(ContextService.category(forBundleID: "com.microsoft.teams2"), .workMessaging)
        XCTAssertEqual(ContextService.category(forBundleID: "com.hnc.Discord"), .workMessaging)
    }

    func testEmailBundleIDs() {
        XCTAssertEqual(ContextService.category(forBundleID: "com.apple.mail"), .email)
        XCTAssertEqual(ContextService.category(forBundleID: "com.microsoft.Outlook"), .email)
        XCTAssertEqual(ContextService.category(forBundleID: "com.superhuman.electron"), .email)
        XCTAssertEqual(ContextService.category(forBundleID: "com.missiveapp.mac"), .email)
    }

    func testCodeBundleIDs() {
        XCTAssertEqual(ContextService.category(forBundleID: "com.apple.dt.Xcode"), .code)
        XCTAssertEqual(ContextService.category(forBundleID: "com.apple.Terminal"), .code)
        XCTAssertEqual(ContextService.category(forBundleID: "com.googlecode.iterm2"), .code)
        XCTAssertEqual(ContextService.category(forBundleID: "com.microsoft.VSCode"), .code)
        XCTAssertEqual(ContextService.category(forBundleID: "com.microsoft.VSCodeInsiders"), .code)
        XCTAssertEqual(ContextService.category(forBundleID: "com.todesktop.230313mzl4w4u92"), .code) // Cursor
        XCTAssertEqual(ContextService.category(forBundleID: "com.exafunction.windsurf"), .code)
        XCTAssertEqual(ContextService.category(forBundleID: "dev.warp.Warp-Stable"), .code)
    }

    func testUnknownAndNilFallBackToOther() {
        XCTAssertEqual(ContextService.category(forBundleID: "com.google.Chrome"), .other)
        XCTAssertEqual(ContextService.category(forBundleID: "com.apple.Safari"), .other)
        XCTAssertEqual(ContextService.category(forBundleID: ""), .other)
        XCTAssertEqual(ContextService.category(forBundleID: nil), .other)
    }

    func testCategoryIsCaseInsensitive() {
        XCTAssertEqual(ContextService.category(forBundleID: "COM.TINYSPECK.SLACKMACGAP"), .workMessaging)
    }

    // MARK: precedingText truncation

    func testTruncateNilAndEmpty() {
        XCTAssertNil(ContextService.truncatePreceding(nil))
        XCTAssertNil(ContextService.truncatePreceding(""))
    }

    func testTruncateShortStringUnchanged() {
        let short = "Hello there, this is short."
        XCTAssertEqual(ContextService.truncatePreceding(short), short)
    }

    func testTruncateExactly300Unchanged() {
        let exact = String(repeating: "a", count: 300)
        let result = ContextService.truncatePreceding(exact)
        XCTAssertEqual(result?.count, 300)
        XCTAssertEqual(result, exact)
    }

    func testTruncateLongKeepsLast300() {
        let input = String(repeating: "a", count: 50) + String(repeating: "b", count: 300)
        let result = ContextService.truncatePreceding(input)
        XCTAssertEqual(result?.count, 300)
        XCTAssertEqual(result, String(repeating: "b", count: 300))
    }

    func testTruncateDropsLeadingOverflow() {
        let input = "X" + String(repeating: "y", count: 300)
        let result = ContextService.truncatePreceding(input)
        XCTAssertEqual(result?.count, 300)
        XCTAssertEqual(result?.first, "y")
    }
}

import XCTest
@testable import GroqFlowKit

@MainActor
final class StoreTests: XCTestCase {

    // MARK: - Helpers

    private func tempPath(_ ext: String) -> String {
        let dir = FileManager.default.temporaryDirectory
        return dir.appendingPathComponent("groqflow-\(UUID().uuidString).\(ext)").path
    }

    private func tempURL(_ ext: String) -> URL {
        FileManager.default.temporaryDirectory
            .appendingPathComponent("groqflow-\(UUID().uuidString).\(ext)")
    }

    private func makeRecord(raw: String = "raw",
                            formatted: String,
                            date: Date = Date(),
                            durationMs: Int = 60000,
                            mode: String = "pushToTalk",
                            status: String = "ok") -> TranscriptRecord {
        TranscriptRecord(date: date, raw: raw, formatted: formatted, bundleID: "com.test.app",
                         appName: "Test", durationMs: durationMs, mode: mode, status: status)
    }

    // MARK: - HistoryStore CRUD

    func testHistoryInsertAndFetch() throws {
        let store = try HistoryStore(dbPath: tempPath("db"))
        let id = try store.insert(makeRecord(raw: "hello world", formatted: "Hello world."))
        XCTAssertGreaterThan(id, 0)

        let all = try store.all(matching: nil)
        XCTAssertEqual(all.count, 1)
        let row = try XCTUnwrap(all.first)
        XCTAssertEqual(row.id, id)
        XCTAssertEqual(row.raw, "hello world")
        XCTAssertEqual(row.formatted, "Hello world.")
        XCTAssertEqual(row.bundleID, "com.test.app")
        XCTAssertEqual(row.appName, "Test")
        XCTAssertEqual(row.durationMs, 60000)
        XCTAssertEqual(row.mode, "pushToTalk")
        XCTAssertEqual(row.status, "ok")
    }

    func testHistoryRecordByID() throws {
        let store = try HistoryStore(dbPath: tempPath("db"))
        let id = try store.insert(makeRecord(formatted: "one"))
        let fetched = try XCTUnwrap(store.record(id: id))
        XCTAssertEqual(fetched.id, id)
        XCTAssertEqual(fetched.formatted, "one")
        XCTAssertNil(try store.record(id: 99999))
    }

    func testHistoryDelete() throws {
        let store = try HistoryStore(dbPath: tempPath("db"))
        let id = try store.insert(makeRecord(formatted: "gone soon"))
        try store.delete(id: id)
        XCTAssertNil(try store.record(id: id))
        XCTAssertEqual(try store.all(matching: nil).count, 0)
    }

    func testHistoryNilOptionalColumns() throws {
        let store = try HistoryStore(dbPath: tempPath("db"))
        let rec = TranscriptRecord(raw: "r", formatted: "f", bundleID: nil, appName: nil,
                                   durationMs: 1000, mode: "pushToTalk", status: "ok")
        let id = try store.insert(rec)
        let fetched = try XCTUnwrap(store.record(id: id))
        XCTAssertNil(fetched.bundleID)
        XCTAssertNil(fetched.appName)
    }

    func testHistoryNewestFirst() throws {
        let store = try HistoryStore(dbPath: tempPath("db"))
        let now = Date()
        _ = try store.insert(makeRecord(formatted: "older", date: now.addingTimeInterval(-100)))
        _ = try store.insert(makeRecord(formatted: "newer", date: now))
        let all = try store.all(matching: nil)
        XCTAssertEqual(all.map(\.formatted), ["newer", "older"])
    }

    // MARK: - Search

    func testHistorySearchMatchesRawAndFormatted() throws {
        let store = try HistoryStore(dbPath: tempPath("db"))
        _ = try store.insert(makeRecord(raw: "call the plumber", formatted: "Call the plumber."))
        _ = try store.insert(makeRecord(raw: "buy groceries", formatted: "Buy groceries."))

        let plumber = try store.all(matching: "plumber")
        XCTAssertEqual(plumber.count, 1)
        XCTAssertEqual(plumber.first?.formatted, "Call the plumber.")

        // matches on formatted text (capitalized) too
        let grocery = try store.all(matching: "Groceries")
        XCTAssertEqual(grocery.count, 1)

        // empty/whitespace query returns everything
        XCTAssertEqual(try store.all(matching: "   ").count, 2)
        XCTAssertEqual(try store.all(matching: nil).count, 2)

        XCTAssertEqual(try store.all(matching: "nonexistent").count, 0)
    }

    // MARK: - Stats

    func testStatsWordsAndWPMExcludeFailed() throws {
        let store = try HistoryStore(dbPath: tempPath("db"))
        // 5 words, 1 minute -> 5 wpm
        _ = try store.insert(makeRecord(formatted: "one two three four five", durationMs: 60000))
        // 10 words, 1 minute -> 10 wpm
        _ = try store.insert(makeRecord(formatted: "a b c d e f g h i j", durationMs: 60000))
        // failed row: counts toward total words, excluded from wpm
        _ = try store.insert(makeRecord(formatted: "fail words here", durationMs: 60000, status: "failed"))

        let stats = try store.stats()
        XCTAssertEqual(stats.totalWords, 18)              // 5 + 10 + 3
        XCTAssertEqual(stats.avgWPM, 7.5, accuracy: 0.0001) // (5 + 10) / 2
    }

    func testStatsAvgWPMSkipsZeroDuration() throws {
        let store = try HistoryStore(dbPath: tempPath("db"))
        _ = try store.insert(makeRecord(formatted: "one two three four", durationMs: 30000)) // 8 wpm
        _ = try store.insert(makeRecord(formatted: "junk", durationMs: 0))                    // skipped
        let stats = try store.stats()
        XCTAssertEqual(stats.avgWPM, 8.0, accuracy: 0.0001)
    }

    func testStatsEmpty() throws {
        let store = try HistoryStore(dbPath: tempPath("db"))
        let stats = try store.stats()
        XCTAssertEqual(stats.totalWords, 0)
        XCTAssertEqual(stats.streakDays, 0)
        XCTAssertEqual(stats.avgWPM, 0)
    }

    func testStatsStreakWithGap() throws {
        let store = try HistoryStore(dbPath: tempPath("db"))
        let cal = Calendar.current
        let startOfToday = cal.startOfDay(for: Date())
        func day(_ offset: Int) -> Date {
            // noon of the offset day, avoids midnight/DST edges
            let d = cal.date(byAdding: .day, value: offset, to: startOfToday)!
            return cal.date(byAdding: .hour, value: 12, to: d)!
        }
        // today and yesterday present, gap at -2, another record at -3
        _ = try store.insert(makeRecord(formatted: "today one", date: day(0)))
        _ = try store.insert(makeRecord(formatted: "today two", date: day(0)))
        _ = try store.insert(makeRecord(formatted: "yesterday", date: day(-1)))
        _ = try store.insert(makeRecord(formatted: "three days ago", date: day(-3)))

        let stats = try store.stats()
        XCTAssertEqual(stats.streakDays, 2) // today + yesterday, stops at the gap
    }

    func testStatsStreakZeroWhenTodayMissing() throws {
        let store = try HistoryStore(dbPath: tempPath("db"))
        let cal = Calendar.current
        let startOfToday = cal.startOfDay(for: Date())
        let yesterdayNoon = cal.date(byAdding: .hour, value: 12,
                                     to: cal.date(byAdding: .day, value: -1, to: startOfToday)!)!
        _ = try store.insert(makeRecord(formatted: "yesterday only", date: yesterdayNoon))
        // streak is defined as consecutive days ending today; no record today -> 0
        XCTAssertEqual(try store.stats().streakDays, 0)
    }

    // MARK: - markRetried

    func testMarkRetriedUpdatesFormattedAndStatus() throws {
        let store = try HistoryStore(dbPath: tempPath("db"))
        let id = try store.insert(makeRecord(raw: "raw text", formatted: "raw text", status: "failed"))
        try store.markRetried(id: id, formatted: "Formatted result.")
        let fetched = try XCTUnwrap(store.record(id: id))
        XCTAssertEqual(fetched.formatted, "Formatted result.")
        XCTAssertEqual(fetched.status, "ok")
        XCTAssertEqual(fetched.raw, "raw text") // raw is preserved
    }

    // MARK: - Persistence across instances

    func testHistoryPersistsAcrossInstances() throws {
        let path = tempPath("db")
        let id: Int64
        do {
            let store = try HistoryStore(dbPath: path)
            id = try store.insert(makeRecord(formatted: "persisted"))
        }
        let reopened = try HistoryStore(dbPath: path)
        let fetched = try XCTUnwrap(reopened.record(id: id))
        XCTAssertEqual(fetched.formatted, "persisted")
    }

    // MARK: - DictionaryStore

    func testDictionaryAddAndRoundTrip() throws {
        let url = tempURL("json")
        let store = DictionaryStore(fileURL: url)
        store.add(text: "GroqFlow", misspelling: nil)
        store.add(text: "definitely", misspelling: "definately")
        XCTAssertEqual(store.entries.count, 2)

        // reload from same file
        let reloaded = DictionaryStore(fileURL: url)
        XCTAssertEqual(reloaded.entries.count, 2)
        XCTAssertEqual(reloaded.entries[0].text, "GroqFlow")
        XCTAssertEqual(reloaded.entries[1].misspelling, "definately")
    }

    func testDictionary60CharCap() throws {
        let store = DictionaryStore(fileURL: tempURL("json"))
        let long = String(repeating: "a", count: 100)
        store.add(text: long, misspelling: nil)
        XCTAssertEqual(store.entries.first?.text.count, 60)
    }

    func testDictionaryUpdateCapsText() throws {
        let store = DictionaryStore(fileURL: tempURL("json"))
        store.add(text: "short", misspelling: nil)
        var entry = try XCTUnwrap(store.entries.first)
        entry.text = String(repeating: "z", count: 90)
        store.update(entry)
        XCTAssertEqual(store.entries.first?.text.count, 60)
    }

    func testDictionaryToggleStarAndRemove() throws {
        let store = DictionaryStore(fileURL: tempURL("json"))
        store.add(text: "starred", misspelling: nil)
        let id = try XCTUnwrap(store.entries.first?.id)
        store.toggleStar(id: id)
        XCTAssertTrue(store.entries.first?.starred ?? false)
        store.toggleStar(id: id)
        XCTAssertFalse(store.entries.first?.starred ?? true)
        store.remove(id: id)
        XCTAssertTrue(store.entries.isEmpty)
    }

    func testDictionaryEmptyMisspellingBecomesNil() throws {
        let store = DictionaryStore(fileURL: tempURL("json"))
        store.add(text: "word", misspelling: "")
        XCTAssertNil(store.entries.first?.misspelling)
    }

    // MARK: - SnippetStore

    func testSnippetAddAndRoundTrip() throws {
        let url = tempURL("json")
        let store = SnippetStore(fileURL: url)
        store.add(trigger: "my address", body: "123 Main St, Springfield")
        store.add(trigger: "sig", body: "Best,\nAmmon")
        XCTAssertEqual(store.snippets.count, 2)

        let reloaded = SnippetStore(fileURL: url)
        XCTAssertEqual(reloaded.snippets.count, 2)
        XCTAssertEqual(reloaded.snippets[0].trigger, "my address")
        XCTAssertEqual(reloaded.snippets[1].body, "Best,\nAmmon")
    }

    func testSnippetUpdateAndRemove() throws {
        let store = SnippetStore(fileURL: tempURL("json"))
        store.add(trigger: "a", body: "alpha")
        var snip = try XCTUnwrap(store.snippets.first)
        snip.body = "alphabet"
        store.update(snip)
        XCTAssertEqual(store.snippets.first?.body, "alphabet")
        store.remove(id: snip.id)
        XCTAssertTrue(store.snippets.isEmpty)
    }

    func testStoresLoadEmptyWhenFileMissing() throws {
        let dict = DictionaryStore(fileURL: tempURL("json"))
        XCTAssertTrue(dict.entries.isEmpty)
        let snips = SnippetStore(fileURL: tempURL("json"))
        XCTAssertTrue(snips.snippets.isEmpty)
    }
}

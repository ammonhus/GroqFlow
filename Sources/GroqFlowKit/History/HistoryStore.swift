import Foundation
import SQLite3

// SQLite tells us to copy bound text/blob data rather than reference it.
private let sqliteTransient = unsafeBitCast(-1, to: sqlite3_destructor_type.self)

public enum HistoryStoreError: Error {
    case open(String)
    case sqlite(String)
}

// Transcript history backed by SQLite via the C API (WAL mode).
// @unchecked Sendable: access to the raw db handle is serialized with a lock.
public final class HistoryStore: @unchecked Sendable {

    public struct Stats {
        public let totalWords: Int
        public let streakDays: Int
        public let avgWPM: Double
    }

    private var db: OpaquePointer?
    private let lock = NSLock()

    public init(dbPath: String) throws {
        var handle: OpaquePointer?
        guard sqlite3_open(dbPath, &handle) == SQLITE_OK, let handle else {
            let message = handle.map { String(cString: sqlite3_errmsg($0)) } ?? "unable to open database"
            if let handle { sqlite3_close(handle) }
            throw HistoryStoreError.open(message)
        }
        self.db = handle
        try exec("PRAGMA journal_mode=WAL;")
        try exec("PRAGMA synchronous=NORMAL;")
        try createSchema()
    }

    deinit {
        if let db { sqlite3_close(db) }
    }

    // MARK: - Writes

    @discardableResult
    public func insert(_ r: TranscriptRecord) throws -> Int64 {
        lock.lock(); defer { lock.unlock() }
        let sql = """
        INSERT INTO history (ts, raw, formatted, bundle_id, app_name, duration_ms, char_count, mode, status)
        VALUES (?, ?, ?, ?, ?, ?, ?, ?, ?);
        """
        let stmt = try prepare(sql)
        defer { sqlite3_finalize(stmt) }
        sqlite3_bind_double(stmt, 1, r.date.timeIntervalSince1970)
        sqlite3_bind_text(stmt, 2, r.raw, -1, sqliteTransient)
        sqlite3_bind_text(stmt, 3, r.formatted, -1, sqliteTransient)
        bindOptionalText(stmt, 4, r.bundleID)
        bindOptionalText(stmt, 5, r.appName)
        sqlite3_bind_int64(stmt, 6, Int64(r.durationMs))
        sqlite3_bind_int64(stmt, 7, Int64(r.formatted.count))
        sqlite3_bind_text(stmt, 8, r.mode, -1, sqliteTransient)
        sqlite3_bind_text(stmt, 9, r.status, -1, sqliteTransient)
        guard sqlite3_step(stmt) == SQLITE_DONE else { throw sqliteError() }
        return sqlite3_last_insert_rowid(db)
    }

    public func delete(id: Int64) throws {
        lock.lock(); defer { lock.unlock() }
        let stmt = try prepare("DELETE FROM history WHERE id = ?;")
        defer { sqlite3_finalize(stmt) }
        sqlite3_bind_int64(stmt, 1, id)
        guard sqlite3_step(stmt) == SQLITE_DONE else { throw sqliteError() }
    }

    // Retry re-ran the pipeline successfully: replace formatted text and mark ok.
    public func markRetried(id: Int64, formatted: String) throws {
        lock.lock(); defer { lock.unlock() }
        let stmt = try prepare("UPDATE history SET formatted = ?, char_count = ?, status = 'ok' WHERE id = ?;")
        defer { sqlite3_finalize(stmt) }
        sqlite3_bind_text(stmt, 1, formatted, -1, sqliteTransient)
        sqlite3_bind_int64(stmt, 2, Int64(formatted.count))
        sqlite3_bind_int64(stmt, 3, id)
        guard sqlite3_step(stmt) == SQLITE_DONE else { throw sqliteError() }
    }

    // MARK: - Reads

    public func all(matching query: String?) throws -> [TranscriptRecord] {
        lock.lock(); defer { lock.unlock() }
        return try fetch(matching: query)
    }

    public func record(id: Int64) throws -> TranscriptRecord? {
        lock.lock(); defer { lock.unlock() }
        let stmt = try prepare("\(selectColumns) WHERE id = ?;")
        defer { sqlite3_finalize(stmt) }
        sqlite3_bind_int64(stmt, 1, id)
        if sqlite3_step(stmt) == SQLITE_ROW {
            return readRow(stmt)
        }
        return nil
    }

    public func stats() throws -> Stats {
        lock.lock(); defer { lock.unlock() }
        let records = try fetch(matching: nil)

        let totalWords = records.reduce(0) { $0 + wordCount($1.formatted) }
        let streakDays = computeStreak(records)

        let successful = records.filter { $0.status == "ok" && $0.durationMs > 0 }
        var wpmSum = 0.0
        for r in successful {
            let minutes = Double(r.durationMs) / 60000.0
            wpmSum += Double(wordCount(r.formatted)) / minutes
        }
        let avgWPM = successful.isEmpty ? 0 : wpmSum / Double(successful.count)

        return Stats(totalWords: totalWords, streakDays: streakDays, avgWPM: avgWPM)
    }

    // MARK: - Internal helpers (no locking)

    private let selectColumns =
        "SELECT id, ts, raw, formatted, bundle_id, app_name, duration_ms, mode, status FROM history"

    private func fetch(matching query: String?) throws -> [TranscriptRecord] {
        var sql = selectColumns
        let trimmed = query?.trimmingCharacters(in: .whitespacesAndNewlines)
        let hasQuery = !(trimmed ?? "").isEmpty
        if hasQuery {
            sql += " WHERE raw LIKE ?1 OR formatted LIKE ?1"
        }
        sql += " ORDER BY ts DESC, id DESC;"

        let stmt = try prepare(sql)
        defer { sqlite3_finalize(stmt) }
        if hasQuery, let trimmed {
            sqlite3_bind_text(stmt, 1, "%\(trimmed)%", -1, sqliteTransient)
        }
        var results: [TranscriptRecord] = []
        while sqlite3_step(stmt) == SQLITE_ROW {
            results.append(readRow(stmt))
        }
        return results
    }

    private func readRow(_ stmt: OpaquePointer?) -> TranscriptRecord {
        TranscriptRecord(
            id: sqlite3_column_int64(stmt, 0),
            date: Date(timeIntervalSince1970: sqlite3_column_double(stmt, 1)),
            raw: columnText(stmt, 2),
            formatted: columnText(stmt, 3),
            bundleID: columnOptionalText(stmt, 4),
            appName: columnOptionalText(stmt, 5),
            durationMs: Int(sqlite3_column_int64(stmt, 6)),
            mode: columnText(stmt, 7),
            status: columnText(stmt, 8)
        )
    }

    private func computeStreak(_ records: [TranscriptRecord]) -> Int {
        guard !records.isEmpty else { return 0 }
        let cal = Calendar.current
        let days = Set(records.map { cal.startOfDay(for: $0.date) })
        var streak = 0
        var day = cal.startOfDay(for: Date())
        while days.contains(day) {
            streak += 1
            guard let prev = cal.date(byAdding: .day, value: -1, to: day) else { break }
            day = prev
        }
        return streak
    }

    private func wordCount(_ s: String) -> Int {
        s.split(whereSeparator: { $0.isWhitespace }).count
    }

    // MARK: - SQLite plumbing

    private func createSchema() throws {
        try exec("""
        CREATE TABLE IF NOT EXISTS history (
            id INTEGER PRIMARY KEY AUTOINCREMENT,
            ts REAL NOT NULL,
            raw TEXT NOT NULL,
            formatted TEXT NOT NULL,
            bundle_id TEXT,
            app_name TEXT,
            duration_ms INTEGER NOT NULL,
            char_count INTEGER NOT NULL,
            mode TEXT NOT NULL,
            status TEXT NOT NULL
        );
        """)
        try exec("CREATE INDEX IF NOT EXISTS idx_history_ts ON history(ts DESC);")
    }

    private func exec(_ sql: String) throws {
        var errmsg: UnsafeMutablePointer<CChar>?
        if sqlite3_exec(db, sql, nil, nil, &errmsg) != SQLITE_OK {
            let message = errmsg.map { String(cString: $0) } ?? "unknown error"
            sqlite3_free(errmsg)
            throw HistoryStoreError.sqlite(message)
        }
    }

    private func prepare(_ sql: String) throws -> OpaquePointer? {
        var stmt: OpaquePointer?
        guard sqlite3_prepare_v2(db, sql, -1, &stmt, nil) == SQLITE_OK else {
            throw sqliteError()
        }
        return stmt
    }

    private func bindOptionalText(_ stmt: OpaquePointer?, _ index: Int32, _ value: String?) {
        if let value {
            sqlite3_bind_text(stmt, index, value, -1, sqliteTransient)
        } else {
            sqlite3_bind_null(stmt, index)
        }
    }

    private func columnText(_ stmt: OpaquePointer?, _ index: Int32) -> String {
        guard let c = sqlite3_column_text(stmt, index) else { return "" }
        return String(cString: c)
    }

    private func columnOptionalText(_ stmt: OpaquePointer?, _ index: Int32) -> String? {
        guard let c = sqlite3_column_text(stmt, index) else { return nil }
        return String(cString: c)
    }

    private func sqliteError() -> HistoryStoreError {
        .sqlite(String(cString: sqlite3_errmsg(db)))
    }
}

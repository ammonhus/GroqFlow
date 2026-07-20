import Foundation
import Combine

// One day's worth of transcripts for the grouped Home list.
struct HistoryDayGroup: Identifiable {
    let id: String
    let title: String
    let records: [TranscriptRecord]
}

// Loads transcripts from HistoryStore, applies the search filter, and groups
// them by day (Today / Yesterday / date) for HomeView. HistoryStore itself is
// not observable, so this view model owns the reactive surface.
@MainActor
final class HistoryViewModel: ObservableObject {
    @Published var searchText: String = "" {
        didSet { reload() }
    }
    @Published private(set) var groups: [HistoryDayGroup] = []
    @Published private(set) var stats: HistoryStore.Stats?

    private let history: HistoryStore

    init(history: HistoryStore) {
        self.history = history
        reload()
    }

    func reload() {
        let trimmed = searchText.trimmingCharacters(in: .whitespacesAndNewlines)
        do {
            let records = try history.all(matching: trimmed.isEmpty ? nil : trimmed)
            groups = Self.makeGroups(from: records)
        } catch {
            Log.app.error("history load failed: \(String(describing: error))")
            groups = []
        }
        do {
            stats = try history.stats()
        } catch {
            stats = nil
        }
    }

    func delete(id: Int64) {
        do {
            try history.delete(id: id)
            reload()
        } catch {
            Log.app.error("history delete failed: \(String(describing: error))")
        }
    }

    // MARK: - Grouping (pure)

    static func makeGroups(from records: [TranscriptRecord],
                           now: Date = Date(),
                           calendar: Calendar = .current) -> [HistoryDayGroup] {
        guard !records.isEmpty else { return [] }

        let todayStart = calendar.startOfDay(for: now)
        let yesterdayStart = calendar.date(byAdding: .day, value: -1, to: todayStart)

        var order: [Date] = []
        var buckets: [Date: [TranscriptRecord]] = [:]
        for record in records {
            let day = calendar.startOfDay(for: record.date)
            if buckets[day] == nil { order.append(day) }
            buckets[day, default: []].append(record)
        }

        let sortedDays = order.sorted(by: >)
        return sortedDays.map { day in
            let title: String
            if day == todayStart {
                title = "Today"
            } else if let yesterdayStart, day == yesterdayStart {
                title = "Yesterday"
            } else {
                title = dayFormatter.string(from: day)
            }
            return HistoryDayGroup(id: keyFormatter.string(from: day),
                                   title: title,
                                   records: buckets[day] ?? [])
        }
    }

    private static let dayFormatter: DateFormatter = {
        let f = DateFormatter()
        f.dateStyle = .medium
        f.timeStyle = .none
        return f
    }()

    private static let keyFormatter: DateFormatter = {
        let f = DateFormatter()
        f.dateFormat = "yyyy-MM-dd"
        return f
    }()
}

import Foundation
import Combine

// Personal dictionary persisted as JSON with atomic writes.
// Loads on init, saves on every mutation.
@MainActor
public final class DictionaryStore: ObservableObject {

    private static let maxTextLength = 60

    @Published public private(set) var entries: [DictionaryEntry] = []

    private let fileURL: URL

    public init(fileURL: URL) {
        self.fileURL = fileURL
        ensureDirectory()
        load()
    }

    public func add(text: String, misspelling: String?) {
        let capped = String(text.prefix(Self.maxTextLength))
        let cleanedMisspelling = misspelling?.isEmpty == true ? nil : misspelling
        entries.append(DictionaryEntry(text: capped, starred: false, misspelling: cleanedMisspelling))
        save()
    }

    public func toggleStar(id: UUID) {
        guard let idx = entries.firstIndex(where: { $0.id == id }) else { return }
        entries[idx].starred.toggle()
        save()
    }

    public func remove(id: UUID) {
        entries.removeAll { $0.id == id }
        save()
    }

    public func update(_ entry: DictionaryEntry) {
        guard let idx = entries.firstIndex(where: { $0.id == entry.id }) else { return }
        var updated = entry
        updated.text = String(entry.text.prefix(Self.maxTextLength))
        entries[idx] = updated
        save()
    }

    // MARK: - Persistence

    private func load() {
        guard let data = try? Data(contentsOf: fileURL),
              let decoded = try? JSONDecoder().decode([DictionaryEntry].self, from: data) else { return }
        entries = decoded
    }

    private func save() {
        guard let data = try? JSONEncoder().encode(entries) else { return }
        try? data.write(to: fileURL, options: [.atomic])
    }

    private func ensureDirectory() {
        let dir = fileURL.deletingLastPathComponent()
        try? FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
    }
}

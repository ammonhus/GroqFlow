import Foundation
import Combine

// Snippet library persisted as JSON with atomic writes.
// Loads on init, saves on every mutation.
@MainActor
public final class SnippetStore: ObservableObject {

    @Published public private(set) var snippets: [Snippet] = []

    private let fileURL: URL

    public init(fileURL: URL) {
        self.fileURL = fileURL
        ensureDirectory()
        load()
    }

    public func add(trigger: String, body: String) {
        snippets.append(Snippet(trigger: trigger, body: body))
        save()
    }

    public func remove(id: UUID) {
        snippets.removeAll { $0.id == id }
        save()
    }

    public func update(_ snippet: Snippet) {
        guard let idx = snippets.firstIndex(where: { $0.id == snippet.id }) else { return }
        snippets[idx] = snippet
        save()
    }

    // MARK: - Persistence

    private func load() {
        guard let data = try? Data(contentsOf: fileURL),
              let decoded = try? JSONDecoder().decode([Snippet].self, from: data) else { return }
        snippets = decoded
    }

    private func save() {
        guard let data = try? JSONEncoder().encode(snippets) else { return }
        try? data.write(to: fileURL, options: [.atomic])
    }

    private func ensureDirectory() {
        let dir = fileURL.deletingLastPathComponent()
        try? FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
    }
}

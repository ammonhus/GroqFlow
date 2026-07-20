import SwiftUI

struct DictionaryView: View {
    @ObservedObject var store: DictionaryStore

    @State private var newWord = ""
    @State private var newMisspelling = ""

    private let maxLength = 60

    var body: some View {
        VStack(alignment: .leading, spacing: 16) {
            Text("Teach GroqFlow names, jargon, and exact spellings. Add an optional misspelling to fix a word the model gets wrong.")
                .font(.subheadline)
                .foregroundStyle(.secondary)

            addRow

            if store.entries.isEmpty {
                emptyState
            } else {
                list
            }
        }
        .padding(20)
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
        .navigationTitle("Dictionary")
    }

    private var addRow: some View {
        HStack(spacing: 8) {
            TextField("Word or phrase", text: $newWord)
                .textFieldStyle(.roundedBorder)
                .onChange(of: newWord) { _, value in
                    if value.count > maxLength { newWord = String(value.prefix(maxLength)) }
                }
            TextField("Heard as (optional)", text: $newMisspelling)
                .textFieldStyle(.roundedBorder)
                .frame(maxWidth: 200)
            Button("Add", action: add)
                .disabled(trimmedWord.isEmpty)
        }
    }

    private var list: some View {
        List {
            ForEach(store.entries) { entry in
                HStack(spacing: 10) {
                    Button {
                        store.toggleStar(id: entry.id)
                    } label: {
                        Image(systemName: entry.starred ? "star.fill" : "star")
                            .foregroundStyle(entry.starred ? .yellow : .secondary)
                    }
                    .buttonStyle(.borderless)
                    .help(entry.starred ? "Starred (wins conflicts)" : "Star this word")

                    VStack(alignment: .leading, spacing: 2) {
                        Text(entry.text)
                        if let misspelling = entry.misspelling, !misspelling.isEmpty {
                            Text("fixes \"\(misspelling)\"")
                                .font(.caption2)
                                .foregroundStyle(.secondary)
                        }
                    }
                    Spacer()
                    Button {
                        store.remove(id: entry.id)
                    } label: {
                        Image(systemName: "trash")
                    }
                    .buttonStyle(.borderless)
                    .help("Delete")
                }
                .padding(.vertical, 2)
            }
        }
        .listStyle(.inset(alternatesRowBackgrounds: true))
    }

    private var emptyState: some View {
        VStack(spacing: 8) {
            Image(systemName: "character.book.closed")
                .font(.system(size: 36))
                .foregroundStyle(.tertiary)
            Text("No words yet")
                .font(.headline)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }

    private var trimmedWord: String {
        newWord.trimmingCharacters(in: .whitespacesAndNewlines)
    }

    private func add() {
        let word = trimmedWord
        guard !word.isEmpty else { return }
        let misspelling = newMisspelling.trimmingCharacters(in: .whitespacesAndNewlines)
        store.add(text: word, misspelling: misspelling.isEmpty ? nil : misspelling)
        newWord = ""
        newMisspelling = ""
    }
}

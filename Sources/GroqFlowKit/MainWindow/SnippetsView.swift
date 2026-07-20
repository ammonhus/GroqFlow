import SwiftUI

struct SnippetsView: View {
    @ObservedObject var store: SnippetStore

    @State private var selectedID: UUID?
    @State private var triggerText = ""
    @State private var bodyText = ""

    var body: some View {
        HStack(spacing: 0) {
            snippetList
            Divider()
            editor
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .navigationTitle("Snippets")
        .onChange(of: selectedID) { _, _ in loadSelection() }
    }

    // MARK: - List

    private var snippetList: some View {
        VStack(spacing: 0) {
            List(selection: $selectedID) {
                ForEach(store.snippets) { snippet in
                    VStack(alignment: .leading, spacing: 2) {
                        Text(snippet.trigger.isEmpty ? "Untitled" : snippet.trigger)
                            .lineLimit(1)
                        Text(snippet.body)
                            .font(.caption2)
                            .foregroundStyle(.secondary)
                            .lineLimit(1)
                    }
                    .tag(snippet.id)
                }
            }
            .listStyle(.sidebar)

            HStack(spacing: 4) {
                Button(action: addSnippet) {
                    Image(systemName: "plus")
                }
                .buttonStyle(.borderless)
                .help("Add snippet")

                Button(action: removeSelected) {
                    Image(systemName: "minus")
                }
                .buttonStyle(.borderless)
                .disabled(selectedID == nil)
                .help("Remove snippet")

                Spacer()
            }
            .padding(6)
        }
        .frame(width: 240)
    }

    // MARK: - Editor

    @ViewBuilder
    private var editor: some View {
        if selectedID != nil {
            VStack(alignment: .leading, spacing: 12) {
                Text("Trigger phrase")
                    .font(.caption)
                    .foregroundStyle(.secondary)
                TextField("Say this to expand the snippet", text: $triggerText)
                    .textFieldStyle(.roundedBorder)

                Text("Expands to")
                    .font(.caption)
                    .foregroundStyle(.secondary)
                TextEditor(text: $bodyText)
                    .font(.body)
                    .frame(minHeight: 160)
                    .overlay(RoundedRectangle(cornerRadius: 6).stroke(.quaternary))

                HStack {
                    Spacer()
                    Button("Save", action: save)
                        .keyboardShortcut("s", modifiers: .command)
                        .disabled(triggerText.trimmingCharacters(in: .whitespaces).isEmpty)
                }
                Spacer()
            }
            .padding(20)
        } else {
            VStack(spacing: 8) {
                Image(systemName: "text.badge.plus")
                    .font(.system(size: 36))
                    .foregroundStyle(.tertiary)
                Text("Select or add a snippet")
                    .font(.headline)
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity)
        }
    }

    // MARK: - Actions

    private func loadSelection() {
        guard let id = selectedID, let snippet = store.snippets.first(where: { $0.id == id }) else {
            triggerText = ""
            bodyText = ""
            return
        }
        triggerText = snippet.trigger
        bodyText = snippet.body
    }

    private func addSnippet() {
        store.add(trigger: "New snippet", body: "")
        selectedID = store.snippets.last?.id
    }

    private func removeSelected() {
        guard let id = selectedID else { return }
        store.remove(id: id)
        selectedID = nil
    }

    private func save() {
        guard let id = selectedID else { return }
        store.update(Snippet(id: id, trigger: triggerText, body: bodyText))
    }
}

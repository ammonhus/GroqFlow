import SwiftUI
import AppKit

struct HomeView: View {
    let model: MainWindowModel
    @ObservedObject private var vm: HistoryViewModel
    @ObservedObject private var settings: SettingsStore

    init(model: MainWindowModel) {
        self.model = model
        _vm = ObservedObject(wrappedValue: model.historyVM)
        _settings = ObservedObject(wrappedValue: model.settings)
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 16) {
            statsHeader
            searchField
            historyList
        }
        .padding(20)
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
        .navigationTitle("Home")
    }

    // MARK: - Stats

    private var statsHeader: some View {
        HStack(spacing: 12) {
            HomeStatTile(title: "Total Words",
                         value: "\(vm.stats?.totalWords ?? 0)",
                         systemImage: "textformat.size")
            HomeStatTile(title: "Day Streak",
                         value: "\(vm.stats?.streakDays ?? 0)",
                         systemImage: "flame")
            HomeStatTile(title: "Avg WPM",
                         value: "\(Int((vm.stats?.avgWPM ?? 0).rounded()))",
                         systemImage: "speedometer")
            HomeStatTile(title: "Shortcut",
                         value: settings.hotkey.displayName,
                         systemImage: "keyboard")
        }
    }

    // MARK: - Search

    private var searchField: some View {
        HStack(spacing: 8) {
            Image(systemName: "magnifyingglass")
                .foregroundStyle(.secondary)
            TextField("Search transcripts", text: $vm.searchText)
                .textFieldStyle(.plain)
            if !vm.searchText.isEmpty {
                Button {
                    vm.searchText = ""
                } label: {
                    Image(systemName: "xmark.circle.fill")
                        .foregroundStyle(.secondary)
                }
                .buttonStyle(.plain)
            }
            Button {
                vm.reload()
            } label: {
                Image(systemName: "arrow.clockwise")
            }
            .buttonStyle(.plain)
            .foregroundStyle(.secondary)
            .help("Refresh")
        }
        .padding(8)
        .background(.quaternary.opacity(0.5), in: RoundedRectangle(cornerRadius: 8))
    }

    // MARK: - List

    @ViewBuilder
    private var historyList: some View {
        if vm.groups.isEmpty {
            emptyState
        } else {
            ScrollView {
                LazyVStack(alignment: .leading, spacing: 20, pinnedViews: [.sectionHeaders]) {
                    ForEach(vm.groups) { group in
                        Section {
                            VStack(spacing: 8) {
                                ForEach(group.records) { record in
                                    HomeHistoryRow(
                                        record: record,
                                        onCopy: { copyText(record.formatted) },
                                        onCopyRaw: { copyText(record.raw) },
                                        onRetry: record.status == "failed"
                                            ? { model.onRetryRecord?(record.id) }
                                            : nil,
                                        onDelete: { vm.delete(id: record.id) })
                                }
                            }
                        } header: {
                            Text(group.title)
                                .font(.headline)
                                .foregroundStyle(.secondary)
                                .frame(maxWidth: .infinity, alignment: .leading)
                                .padding(.vertical, 4)
                                .background(Color(nsColor: .windowBackgroundColor))
                        }
                    }
                }
            }
        }
    }

    private var emptyState: some View {
        VStack(spacing: 10) {
            Image(systemName: "waveform")
                .font(.system(size: 40))
                .foregroundStyle(.tertiary)
            Text(vm.searchText.isEmpty ? "No dictations yet" : "No matches")
                .font(.headline)
            Text(vm.searchText.isEmpty
                 ? "Hold \(settings.hotkey.displayName) and speak to get started."
                 : "Try a different search.")
                .font(.subheadline)
                .foregroundStyle(.secondary)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }
}

private func copyText(_ text: String) {
    let pb = NSPasteboard.general
    pb.clearContents()
    pb.setString(text, forType: .string)
}

// MARK: - Stat tile

private struct HomeStatTile: View {
    let title: String
    let value: String
    let systemImage: String

    var body: some View {
        VStack(alignment: .leading, spacing: 6) {
            Label(title, systemImage: systemImage)
                .font(.caption)
                .foregroundStyle(.secondary)
                .labelStyle(.titleAndIcon)
            Text(value)
                .font(.title2.weight(.semibold))
                .lineLimit(1)
                .minimumScaleFactor(0.6)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(12)
        .background(.quaternary.opacity(0.4), in: RoundedRectangle(cornerRadius: 10))
    }
}

// MARK: - History row

private struct HomeHistoryRow: View {
    let record: TranscriptRecord
    let onCopy: () -> Void
    let onCopyRaw: () -> Void
    let onRetry: (() -> Void)?
    let onDelete: () -> Void

    @State private var hovering = false

    var body: some View {
        HStack(alignment: .top, spacing: 12) {
            VStack(alignment: .leading, spacing: 4) {
                Text(record.formatted.isEmpty ? record.raw : record.formatted)
                    .lineLimit(3)
                    .textSelection(.enabled)
                HStack(spacing: 8) {
                    if record.status == "failed" {
                        Label("Failed", systemImage: "exclamationmark.triangle.fill")
                            .font(.caption2)
                            .foregroundStyle(.orange)
                    }
                    if let app = record.appName, !app.isEmpty {
                        Text(app)
                    }
                    Text(Self.timeFormatter.string(from: record.date))
                    if record.mode == "command" {
                        Label("Command", systemImage: "wand.and.stars")
                    }
                }
                .font(.caption2)
                .foregroundStyle(.secondary)
            }
            Spacer(minLength: 8)
            if hovering {
                HStack(spacing: 6) {
                    rowButton("doc.on.doc", "Copy", onCopy)
                    rowButton("arrow.uturn.backward", "Copy original transcript", onCopyRaw)
                    if let onRetry {
                        rowButton("arrow.clockwise", "Retry", onRetry)
                    }
                    rowButton("trash", "Delete", onDelete)
                }
                .transition(.opacity)
            }
        }
        .padding(12)
        .background(.quaternary.opacity(hovering ? 0.5 : 0.25),
                    in: RoundedRectangle(cornerRadius: 8))
        .onHover { hovering = $0 }
        .animation(.easeInOut(duration: 0.12), value: hovering)
    }

    private func rowButton(_ symbol: String, _ help: String, _ action: @escaping () -> Void) -> some View {
        Button(action: action) {
            Image(systemName: symbol)
        }
        .buttonStyle(.borderless)
        .help(help)
    }

    private static let timeFormatter: DateFormatter = {
        let f = DateFormatter()
        f.dateStyle = .none
        f.timeStyle = .short
        return f
    }()
}

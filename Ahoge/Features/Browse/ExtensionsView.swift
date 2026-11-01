import SwiftUI

struct ExtensionsView: View {
    @EnvironmentObject private var store: ExtensionStore
    @EnvironmentObject private var sources: SourceManager
    @State private var showRepos = false
    @State private var busy: Set<String> = []
    @State private var actionError: String?

    var body: some View {
        let rows = store.rows()
        List {
            if store.repos.isEmpty {
                Section {
                    VStack(alignment: .leading, spacing: 8) {
                        Text("No repositories yet").font(.headline)
                        Text("Sources come from extension repositories. Add the Ahoge Extensions repository to get started.")
                            .font(.callout)
                            .foregroundStyle(.secondary)
                        Button("Add Ahoge Extensions") { Task { await addDefault() } }
                            .buttonStyle(.borderedProminent)
                    }
                    .padding(.vertical, 4)
                }
            }
            if let error = store.lastError {
                Section { Label(error, systemImage: "exclamationmark.triangle").foregroundStyle(.orange) }
            }
            section("Updates", rows.filter { $0.state == .updateAvailable })
            section("Installed", rows.filter { $0.state == .installed })
            section("Available", rows.filter { $0.state == .available })
            section("Requires app update", rows.filter { $0.state == .requiresAppUpdate })
        }
        .overlay { if store.isRefreshing && rows.isEmpty { ProgressView() } }
        .refreshable { await store.refresh() }
        .task { if store.indexes.isEmpty && !store.repos.isEmpty { await store.refresh() } }
        .toolbar {
            ToolbarItem(placement: .topBarTrailing) {
                Button { showRepos = true } label: { Image(systemName: "tray.full") }
                    .accessibilityLabel("Repositories")
            }
        }
        .sheet(isPresented: $showRepos) { NavigationStack { RepositoriesView() } }
        .alert("Extension error", isPresented: Binding(get: { actionError != nil }, set: { if !$0 { actionError = nil } })) {
            Button("OK", role: .cancel) {}
        } message: {
            Text(actionError ?? "")
        }
    }

    @ViewBuilder
    private func section(_ title: String, _ rows: [ExtensionRow]) -> some View {
        if !rows.isEmpty {
            Section(title) {
                ForEach(rows) { row in
                    ExtensionRowView(row: row, busy: busy.contains(row.id)) { await perform(row) }
                }
            }
        }
    }

    private func perform(_ row: ExtensionRow) async {
        busy.insert(row.id)
        defer { busy.remove(row.id) }
        do {
            switch row.state {
            case .available, .updateAvailable:
                try await store.install(row.source, from: row.repoURL)
            case .installed:
                store.uninstall(row.source.id)
            case .requiresAppUpdate:
                break
            }
            sources.resetSessions()
        } catch {
            actionError = error.localizedDescription
        }
    }

    private func addDefault() async {
        do {
            try await store.addRepo(ExtensionStore.defaultRepoURL)
        } catch {
            actionError = error.localizedDescription
        }
    }
}

private struct ExtensionRowView: View {
    let row: ExtensionRow
    let busy: Bool
    let action: () async -> Void

    var body: some View {
        HStack(spacing: 12) {
            RemoteImage(url: row.iconURL ?? "")
                .frame(width: 40, height: 40)
                .clipShape(RoundedRectangle(cornerRadius: 8))
            VStack(alignment: .leading, spacing: 2) {
                HStack(spacing: 6) {
                    Text(row.source.name)
                    if row.source.nsfw { Text("18+").font(.caption2.bold()).foregroundStyle(.red) }
                    if row.source.isReportedBroken {
                        Image(systemName: "exclamationmark.triangle.fill")
                            .foregroundStyle(.orange)
                            .accessibilityLabel("Reported broken")
                    }
                }
                Text("\(row.source.lang.uppercased()) · \(row.source.version)")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
            Spacer()
            if busy {
                ProgressView()
            } else {
                switch row.state {
                case .available:
                    Button("Install") { Task { await action() } }.buttonStyle(.bordered)
                case .updateAvailable:
                    Button("Update") { Task { await action() } }.buttonStyle(.borderedProminent)
                case .installed:
                    Button("Uninstall", role: .destructive) { Task { await action() } }.buttonStyle(.bordered)
                case .requiresAppUpdate:
                    Text("Needs newer app").font(.caption).foregroundStyle(.secondary)
                }
            }
        }
    }
}

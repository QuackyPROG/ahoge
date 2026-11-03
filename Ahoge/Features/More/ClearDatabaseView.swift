import SwiftUI

/// Mihon's Clear database: forget titles that were only opened, not saved to the library.
struct ClearDatabaseView: View {
    @EnvironmentObject private var repo: LibraryRepository
    @EnvironmentObject private var extensions: ExtensionStore
    @State private var keepRead = true
    @State private var counts: [String: Int] = [:]
    @State private var selected: Set<String> = []
    @State private var confirming = false
    @State private var cleared: Int?

    var body: some View {
        List {
            Section {
                Toggle("Keep titles with read chapters", isOn: $keepRead)
            } footer: {
                Text("Titles in your library and titles with downloads are never removed.")
            }
            .themedRows()

            Section("Sources") {
                if counts.isEmpty {
                    Text("Nothing to clear.").foregroundStyle(.secondary)
                }
                ForEach(counts.keys.sorted(), id: \.self) { id in
                    Button {
                        if selected.contains(id) { selected.remove(id) } else { selected.insert(id) }
                    } label: {
                        HStack {
                            Image(systemName: selected.contains(id) ? "checkmark.circle.fill" : "circle")
                                .foregroundStyle(selected.contains(id) ? Color.accentColor : .secondary)
                            Text(name(of: id)).foregroundStyle(.primary)
                            Spacer()
                            Text("\(counts[id] ?? 0)").foregroundStyle(.secondary)
                        }
                    }
                }
            }
            .themedRows()

            Section {
                Button("Clear \(total) title\(total == 1 ? "" : "s")", role: .destructive) { confirming = true }
                    .disabled(total == 0)
            }
            .themedRows()
        }
        .navigationTitle("Clear database")
        .navigationBarTitleDisplayMode(.inline)
        .themedScreen()
        .onAppear(perform: reload)
        .onChange(of: keepRead) { reload() }
        .confirmationDialog("Remove \(total) title\(total == 1 ? "" : "s")?", isPresented: $confirming, titleVisibility: .visible) {
            Button("Clear", role: .destructive) {
                cleared = repo.clearNonLibrary(sources: selected, keepRead: keepRead)
                reload()
            }
        } message: {
            Text("Their chapters and history go too. This cannot be undone.")
        }
        .alert("Cleared \(cleared ?? 0) title\(cleared == 1 ? "" : "s")", isPresented: Binding(get: { cleared != nil }, set: { if !$0 { cleared = nil } })) {
            Button("OK", role: .cancel) {}
        }
    }

    private var total: Int { selected.reduce(0) { $0 + (counts[$1] ?? 0) } }

    private func reload() {
        counts = repo.nonLibraryCounts(keepRead: keepRead)
        selected = Set(counts.keys)
    }

    private func name(of id: String) -> String {
        extensions.installed.first { $0.id == id }?.name ?? id
    }
}

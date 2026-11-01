import SwiftUI

struct RepositoriesView: View {
    @EnvironmentObject private var store: ExtensionStore
    @EnvironmentObject private var sources: SourceManager
    @Environment(\.dismiss) private var dismiss
    @State private var newURL = ""
    @State private var adding = false
    @State private var error: String?
    @State private var removing: ExtensionRepo?

    var body: some View {
        List {
            Section {
                if store.repos.isEmpty { Text("No repositories").foregroundStyle(.secondary) }
                ForEach(store.repos) { repo in
                    VStack(alignment: .leading, spacing: 2) {
                        Text(repo.name)
                        Text(repo.url).font(.caption).foregroundStyle(.secondary).textSelection(.enabled)
                    }
                    .swipeActions {
                        Button("Remove", role: .destructive) { removing = repo }
                    }
                    .contextMenu {
                        Button { UIPasteboard.general.string = repo.url } label: { Label("Copy URL", systemImage: "doc.on.doc") }
                        Button(role: .destructive) { removing = repo } label: { Label("Remove", systemImage: "trash") }
                    }
                }
                .onDelete { offsets in
                    removing = offsets.first.map { store.repos[$0] }
                }
            } header: {
                Text("Repositories")
            } footer: {
                if !store.repos.isEmpty { Text("Swipe left or long-press a repository to remove it.") }
            }
            Section {
                TextField("https://…/index.json", text: $newURL)
                    .textInputAutocapitalization(.never)
                    .autocorrectionDisabled()
                    .keyboardType(.URL)
                Button(adding ? "Adding…" : "Add repository") { Task { await add(newURL) } }
                    .disabled(adding || newURL.isEmpty)
                if !store.repos.contains(where: { $0.url == ExtensionStore.defaultRepoURL }) {
                    Button("Add Ahoge Extensions") { Task { await add(ExtensionStore.defaultRepoURL) } }
                        .disabled(adding)
                }
            } footer: {
                if let error { Text(error).foregroundStyle(.red) }
            }
        }
        .navigationTitle("Repositories")
        .toolbar {
            ToolbarItem(placement: .topBarLeading) { if !store.repos.isEmpty { EditButton() } }
            ToolbarItem(placement: .confirmationAction) { Button("Done") { dismiss() } }
        }
        .confirmationDialog(
            "Remove \(removing?.name ?? "repository")?",
            isPresented: Binding(get: { removing != nil }, set: { if !$0 { removing = nil } }),
            titleVisibility: .visible,
            presenting: removing
        ) { repo in
            let count = store.installedCount(fromRepo: repo.url)
            Button(count > 0 ? "Remove, keep extensions" : "Remove", role: .destructive) { remove(repo, uninstalling: false) }
            if count > 0 {
                Button("Remove and uninstall \(count) extension\(count == 1 ? "" : "s")", role: .destructive) {
                    remove(repo, uninstalling: true)
                }
            }
            Button("Cancel", role: .cancel) {}
        } message: { repo in
            if store.installedCount(fromRepo: repo.url) > 0 {
                Text("Kept extensions stay usable but won't get updates from this repository.")
            }
        }
    }

    private func remove(_ repo: ExtensionRepo, uninstalling: Bool) {
        store.removeRepo(repo.url, uninstallingSources: uninstalling)
        if uninstalling { sources.resetSessions() }
        removing = nil
    }

    private func add(_ url: String) async {
        adding = true
        error = nil
        do {
            try await store.addRepo(url)
            newURL = ""
        } catch {
            self.error = error.localizedDescription
        }
        adding = false
    }
}

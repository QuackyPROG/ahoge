import SwiftUI

struct RepositoriesView: View {
    @EnvironmentObject private var store: ExtensionStore
    @EnvironmentObject private var sources: SourceManager
    @Environment(\.dismiss) private var dismiss
    @Environment(\.openURL) private var openURL
    @State private var newURL = ""
    @State private var showAdd = false
    @State private var adding = false
    @State private var error: String?
    @State private var removing: ExtensionRepo?
    @State private var copied: String?

    var body: some View {
        List {
            Section {
                ForEach(store.repos) { repo in row(repo) }
                Button {
                    newURL = ""
                    showAdd = true
                } label: {
                    Label(adding ? "Adding…" : "Add repository", systemImage: "plus")
                }
                .disabled(adding)
            } footer: {
                if let error { Text(error).foregroundStyle(.red) }
            }
        }
        .navigationTitle("Repositories")
        .navigationBarTitleDisplayMode(.inline)
        .toolbar { ToolbarItem(placement: .confirmationAction) { Button("Done") { dismiss() } } }
        .alert("Add repository", isPresented: $showAdd) {
            TextField("https://…/index.json", text: $newURL)
                .textInputAutocapitalization(.never)
                .autocorrectionDisabled()
                .keyboardType(.URL)
            Button("Add") { Task { await add(newURL) } }
                .disabled(newURL.trimmingCharacters(in: .whitespaces).isEmpty)
            if !store.repos.contains(where: { $0.url == ExtensionStore.defaultRepoURL }) {
                Button("Add Ahoge Extensions") { Task { await add(ExtensionStore.defaultRepoURL) } }
            }
            Button("Cancel", role: .cancel) {}
        } message: {
            Text("Paste the link to a repository's index.json.")
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

    private func row(_ repo: ExtensionRepo) -> some View {
        HStack(spacing: 18) {
            Text(repo.name).lineLimit(1)
            Spacer(minLength: 0)
            if let page = Self.webPage(for: repo.url) {
                Button { openURL(page) } label: { Image(systemName: "globe") }
                    .accessibilityLabel("Open \(repo.name) in browser")
            }
            Button {
                UIPasteboard.general.string = repo.url
                withAnimation { copied = repo.url }
                Task {
                    try? await Task.sleep(for: .seconds(1.5))
                    withAnimation { if copied == repo.url { copied = nil } }
                }
            } label: {
                Image(systemName: copied == repo.url ? "checkmark" : "doc.on.doc")
                    .contentTransition(.symbolEffect(.replace))
            }
            .accessibilityLabel("Copy \(repo.name) link")
            Button { removing = repo } label: { Image(systemName: "trash") }
                .tint(.red)
                .accessibilityLabel("Remove \(repo.name)")
        }
        .buttonStyle(.borderless)
        .imageScale(.medium)
    }

    /// The page a person would visit for a repository: its GitHub project for raw GitHub links,
    /// otherwise the folder holding the index.
    static func webPage(for indexURL: String) -> URL? {
        guard let url = URL(string: indexURL), let host = url.host() else { return nil }
        let parts = url.pathComponents.filter { $0 != "/" }
        if host == "raw.githubusercontent.com", parts.count >= 2 {
            return URL(string: "https://github.com/\(parts[0])/\(parts[1])")
        }
        return url.deletingLastPathComponent()
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
        } catch {
            self.error = error.localizedDescription
        }
        adding = false
    }
}

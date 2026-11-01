import SwiftUI

struct RepositoriesView: View {
    @EnvironmentObject private var store: ExtensionStore
    @Environment(\.dismiss) private var dismiss
    @State private var newURL = ""
    @State private var adding = false
    @State private var error: String?

    var body: some View {
        List {
            Section("Repositories") {
                if store.repos.isEmpty { Text("No repositories").foregroundStyle(.secondary) }
                ForEach(store.repos) { repo in
                    VStack(alignment: .leading, spacing: 2) {
                        Text(repo.name)
                        Text(repo.url).font(.caption).foregroundStyle(.secondary).textSelection(.enabled)
                    }
                }
                .onDelete { offsets in
                    let urls = offsets.map { store.repos[$0].url }
                    for url in urls { store.removeRepo(url) }
                }
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
            ToolbarItem(placement: .confirmationAction) { Button("Done") { dismiss() } }
        }
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

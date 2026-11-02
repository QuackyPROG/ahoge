import SwiftUI

/// Mihon's category editor: add, rename, reorder and delete Library categories.
struct CategoriesView: View {
    @EnvironmentObject private var repo: LibraryRepository
    @State private var name = ""
    @State private var target: MangaCategory?
    @State private var creating = false
    @State private var renaming = false
    @State private var deleting = false

    var body: some View {
        List {
            Section {
                ForEach(repo.categories) { category in
                    Button {
                        target = category
                        name = category.name
                        renaming = true
                    } label: {
                        HStack {
                            Label(category.name, systemImage: "folder").foregroundStyle(.primary)
                            Spacer()
                            Text("\(repo.library(in: category.id).count)").monospacedDigit().foregroundStyle(.secondary)
                        }
                    }
                    .swipeActions(allowsFullSwipe: false) {
                        Button("Delete", systemImage: "trash", role: .destructive) {
                            target = category
                            deleting = true
                        }
                    }
                }
                .onMove { repo.moveCategories(fromOffsets: $0, toOffset: $1) }
            } footer: {
                if !repo.categories.isEmpty {
                    Text("Tap to rename, swipe to delete, Edit to reorder. Titles in no category show under Default.")
                }
            }
            .themedRows()
        }
        .overlay {
            if repo.categories.isEmpty {
                ContentUnavailableView("No categories", systemImage: "folder", description: Text("Categories split your library into tabs. Tap + to add one."))
            }
        }
        .navigationTitle("Categories")
        .toolbar {
            ToolbarItem(placement: .topBarTrailing) { EditButton().disabled(repo.categories.count < 2) }
            ToolbarItem(placement: .topBarTrailing) {
                Button("Add category", systemImage: "plus") {
                    name = ""
                    creating = true
                }
            }
        }
        .alert("New category", isPresented: $creating) {
            TextField("Name", text: $name)
            Button("Add") { repo.createCategory(named: name) }
                .disabled(!repo.isAvailableCategoryName(name))
            Button("Cancel", role: .cancel) {}
        }
        .alert("Rename category", isPresented: $renaming) {
            TextField("Name", text: $name)
            Button("Rename") { if let target { repo.renameCategory(target.id, to: name) } }
                .disabled(!repo.isAvailableCategoryName(name, except: target?.id))
            Button("Cancel", role: .cancel) {}
        }
        .alert("Delete “\(target?.name ?? "")”?", isPresented: $deleting) {
            Button("Delete", role: .destructive) { if let target { repo.deleteCategory(target.id) } }
            Button("Cancel", role: .cancel) {}
        } message: {
            Text("Its titles stay in your library.")
        }
        .themedScreen()
    }
}

import SwiftUI

/// Mihon's "Set categories" for one or more library titles. With several titles, a category
/// only some have starts as a dash and is left alone unless tapped.
struct SetCategoriesSheet: View {
    let manga: [LibraryManga]
    @EnvironmentObject private var repo: LibraryRepository
    @Environment(\.dismiss) private var dismiss
    @Environment(\.palette) private var palette
    @State private var checks: [Int64: CategoryCheck] = [:]

    var body: some View {
        NavigationStack {
            List {
                Section {
                    ForEach(repo.categories) { category in
                        let check = checks[category.id] ?? .off
                        Button {
                            checks[category.id] = CategoryAssignment.toggled(check)
                        } label: {
                            HStack(spacing: 12) {
                                Image(systemName: Self.symbol(check))
                                    .font(.title3)
                                    .foregroundStyle(check == .off ? Color.secondary : palette.primary.color)
                                Text(category.name).foregroundStyle(.primary)
                                Spacer()
                            }
                            .contentShape(Rectangle())
                        }
                        .buttonStyle(.plain)
                        .sensoryFeedback(.selection, trigger: check)
                    }
                } footer: {
                    Text("Titles in no category show under Default.")
                }
                .themedRows()
            }
            .overlay {
                if repo.categories.isEmpty {
                    ContentUnavailableView("No categories", systemImage: "folder", description: Text("Tap Edit categories to make one."))
                }
            }
            .navigationTitle(manga.count == 1 ? "Set categories" : "Set categories (\(manga.count))")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) { Button("Cancel") { dismiss() } }
                ToolbarItem(placement: .confirmationAction) { Button("Save") { save() }.bold() }
                ToolbarItem(placement: .bottomBar) { NavigationLink("Edit categories") { CategoriesView() } }
            }
            .themedScreen()
            .onAppear {
                // Runs again after Edit categories: keeps the choices made, new categories start off.
                let initial = CategoryAssignment.initial(categoryIds: repo.categories.map(\.id), selections: manga.map { repo.categoryIds(of: $0) })
                checks = initial.merging(checks.filter { initial[$0.key] != nil }) { _, chosen in chosen }
            }
        }
        .presentationDetents([.medium, .large])
        .presentationDragIndicator(.visible)
    }

    private func save() {
        // Categories deleted while the sheet was open are dropped from the choices.
        let live = checks.filter { check in repo.categories.contains { $0.id == check.key } }
        for title in manga {
            repo.setCategories(CategoryAssignment.apply(live, to: repo.categoryIds(of: title)), for: title)
        }
        dismiss()
    }

    private static func symbol(_ check: CategoryCheck) -> String {
        switch check {
        case .on: "checkmark.square.fill"
        case .off: "square"
        case .mixed: "minus.square.fill"
        }
    }
}

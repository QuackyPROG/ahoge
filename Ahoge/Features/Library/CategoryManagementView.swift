// Modified for Ahoge from an Apache-2.0-licensed prior implementation.
// See THIRD_PARTY_NOTICES.md for attribution and license information.

//
//  CategoryManagementView.swift
//  Ahoge
//

import SwiftUI

struct CategoryManagementView: View {
    @EnvironmentObject private var model: AppModel
    @State private var newCategoryName = ""

    var body: some View {
        List {
            Section {
                Label("Organize your shelf", systemImage: "folder").font(.title2.weight(.bold))
                Text("Create a category, then assign titles from the library or a title's menu.")
                    .font(.subheadline).foregroundStyle(.secondary)
                if model.state.securityPreferences.lockLibraryEdits {
                    Label("Library editing is locked", systemImage: "lock.fill")
                        .font(.footnote).foregroundStyle(.secondary)
                }
            }
            Section("Your categories") {
                if model.categories.isEmpty {
                    ContentUnavailableView(
                        "No Categories Yet",
                        systemImage: "folder.badge.plus",
                        description: Text("Use the name editor below to create your first category.")
                    )
                } else {
                    ForEach(model.categories) { category in
                        NavigationLink {
                            CategoryDetailView(category: category)
                        } label: {
                            Label(category.name, systemImage: category.systemImage)
                        }
                    }
                }
            }
            Section("Create Category") {
                TextField("New category name", text: $newCategoryName)
                    .disabled(model.state.securityPreferences.lockLibraryEdits)
                Button("Add Category", systemImage: "folder.badge.plus") {
                    model.addCategory(named: newCategoryName)
                    newCategoryName = ""
                }
                .disabled(model.state.securityPreferences.lockLibraryEdits)
            }
        }
        .frame(maxWidth: 760)
        .frame(maxWidth: .infinity)
        .navigationTitle("Categories")
    }
}

private struct CategoryDetailView: View {
    @EnvironmentObject private var model: AppModel
    let category: Category
    @State private var name: String

    init(category: Category) {
        self.category = category
        _name = State(initialValue: category.name)
    }

    var body: some View {
        Form {
            Section {
                Label(category.name, systemImage: category.systemImage).font(.title2.weight(.bold))
                if model.state.securityPreferences.lockLibraryEdits {
                    Label("Library editing is locked", systemImage: "lock.fill")
                }
            }
            Section("Category name") {
                TextField("Name", text: $name)
                    .accessibilityLabel("Category name")
                    .disabled(model.state.securityPreferences.lockLibraryEdits)
                Button("Save Name", systemImage: "checkmark") {
                    model.renameCategory(category.id, to: name)
                }
                .disabled(model.state.securityPreferences.lockLibraryEdits)
            }
            Section {
                Button("Delete Category", role: .destructive) {
                    model.deleteCategory(category.id)
                }
                .disabled(model.state.securityPreferences.lockLibraryEdits)
            } header: { Text("Remove category") } footer: {
                Text("Delete this category from your library organization.")
            }
        }
        .frame(maxWidth: 760)
        .frame(maxWidth: .infinity)
        .navigationTitle(category.name)
    }
}

struct LibrarySettingsView: View {
    @EnvironmentObject private var model: AppModel

    var body: some View {
        Form {
            Section {
                Label("Your library", systemImage: "books.vertical").font(.title3.weight(.semibold))
                Text("Choose how your shelf appears and where newly added titles belong.")
                    .font(.subheadline).foregroundStyle(.secondary)
            }
            Section("Shelf information") {
                Toggle("Show Continue Reading", isOn: Binding(
                    get: { model.state.libraryPreferences.showContinueReading },
                    set: model.setContinueReadingVisible
                ))
                Toggle("Show Downloaded Badge", isOn: Binding(
                    get: { model.state.libraryPreferences.showDownloadedBadge },
                    set: model.setDownloadedBadgeVisible
                ))
                Toggle("Show Unread Badge", isOn: Binding(
                    get: { model.state.libraryPreferences.showUnreadBadge },
                    set: model.setUnreadBadgeVisible
                ))
            }

            Section("Defaults") {
                Picker("Sort", selection: Binding(
                    get: { model.state.libraryPreferences.sortMode },
                    set: model.setLibrarySortMode
                )) {
                    ForEach(LibrarySortMode.allCases) { mode in
                        Text(mode.title).tag(mode)
                    }
                }

                if model.categories.isEmpty {
                    LabeledContent("Default Category", value: "Uncategorized")
                    Text("Titles added to the library stay uncategorized until you create and assign your own categories.")
                        .font(.subheadline)
                        .foregroundStyle(.secondary)
                } else {
                    Picker("Default Category", selection: Binding(
                        get: { model.state.libraryPreferences.defaultCategoryID },
                        set: model.setDefaultCategoryID
                    )) {
                        ForEach(model.categories) { category in
                            Text(category.name).tag(category.id)
                        }
                    }
                }
            }
        }
        .frame(maxWidth: 760)
        .frame(maxWidth: .infinity)
        .navigationTitle("Library Settings")
    }
}

struct LibraryBatchMigrationView: View {
    @EnvironmentObject private var model: AppModel

    var body: some View {
        let hideSensitiveCovers = model.state.securityPreferences.hideSensitiveCovers

        List {
            Section {
                Label("Review migration candidates", systemImage: "arrow.triangle.swap").font(.title3.weight(.semibold))
                Text("Choose a library title to compare its available sources. Transfer options are configured for each title.")
                    .font(.subheadline).foregroundStyle(.secondary)
            }
            Section("Library titles") {
                let libraryTitles = model.libraryItems(selectedCategoryID: nil)
            if libraryTitles.isEmpty {
                ContentUnavailableView("No library titles", systemImage: "books.vertical", description: Text("Add a title to your Library before comparing editions."))
            }
            ForEach(libraryTitles) { item in
                    if let source = model.migrationSource(for: item.manga) {
                        NavigationLink {
                            MigrationConfirmationView(source: source, target: item.manga)
                        } label: {
                            MangaRow(
                                manga: item.manga,
                                hideSensitiveCover: hideSensitiveCovers,
                                allowsAdultContent: model.source(for: item.manga.sourceID)?.allowsAdultContent ?? false
                            )
                        }
                    } else {
                        VStack(alignment: .leading, spacing: 6) {
                            MangaRow(
                                manga: item.manga,
                                hideSensitiveCover: hideSensitiveCovers,
                                allowsAdultContent: model.source(for: item.manga.sourceID)?.allowsAdultContent ?? false
                            )
                            Text("Migration unavailable because the source could not be resolved.")
                                .font(.caption)
                                .foregroundStyle(.secondary)
                        }
                    }
                }
            }
        }
        .listStyle(.insetGrouped)
        .frame(maxWidth: 760)
        .frame(maxWidth: .infinity)
        .navigationTitle("Batch Migration")
    }
}

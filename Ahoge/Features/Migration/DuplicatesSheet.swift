import SwiftUI

/// Shown when adding a title that looks like one already in the library (Mihon's duplicate warning).
struct DuplicatesSheet: View {
    let duplicates: [LibraryManga]
    /// Migrates the chosen library entry to the title being added.
    let migrate: (LibraryManga) -> Void
    let addAnyway: () -> Void
    @EnvironmentObject private var sources: SourceManager
    @Environment(\.dismiss) private var dismiss

    var body: some View {
        NavigationStack {
            List {
                Section {
                    ForEach(duplicates) { manga in
                        HStack(spacing: 12) {
                            RemoteImage(url: manga.displayCover)
                                .frame(width: 40, height: 60)
                                .clipShape(RoundedRectangle(cornerRadius: 6))
                            VStack(alignment: .leading, spacing: 2) {
                                Text(manga.title).lineLimit(2)
                                Text(sources.installed(manga.sourceId)?.name ?? manga.sourceId)
                                    .font(.caption)
                                    .foregroundStyle(.secondary)
                            }
                            Spacer()
                            Button("Migrate") {
                                dismiss()
                                migrate(manga)
                            }
                            .buttonStyle(.bordered)
                        }
                    }
                } footer: {
                    Text("Migrate moves read chapters, categories and notes from the entry in your library to this one.")
                }
                .themedRows()
                Section {
                    Button("Add anyway") {
                        dismiss()
                        addAnyway()
                    }
                    Button("Cancel", role: .cancel) { dismiss() }
                }
                .themedRows()
            }
            .themedScreen()
            .navigationTitle("Possible duplicates")
            .navigationBarTitleDisplayMode(.inline)
        }
    }
}

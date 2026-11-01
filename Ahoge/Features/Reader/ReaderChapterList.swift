import SwiftUI

/// The manga's chapters inside the reader: current one highlighted and scrolled into view.
struct ReaderChapterList: View {
    let manga: LibraryManga
    let current: ChapterRecord
    let select: (ChapterRecord) -> Void
    @Environment(\.dismiss) private var dismiss
    @StateObject private var visible = VisibleRows()

    var body: some View {
        let chapters = ChapterDisplay.load(for: manga.key).apply(to: manga.chapters)
        NavigationStack {
            ScrollViewReader { proxy in
                List {
                    ForEach(Array(chapters.enumerated()), id: \.element.key) { index, chapter in
                        Button {
                            dismiss()
                            if chapter.key != current.key { select(chapter) }
                        } label: {
                            ChapterRow(chapter: chapter, isCurrent: chapter.key == current.key)
                        }
                        .buttonStyle(.plain)
                        .id(chapter.key)
                        .listRowBackground(chapter.key == current.key ? Color.accentColor.opacity(0.12) : nil)
                        .onAppear { visible.appeared(index) }
                        .onDisappear { visible.disappeared(index) }
                    }
                }
                .listStyle(.plain)
                .overlay(alignment: .trailing) {
                    if chapters.count > 40 {
                        FastScroller(
                            count: chapters.count,
                            topIndex: visible.top,
                            label: { chapters[$0].number >= 0 ? "Ch. \(chapters[$0].number.formatted())" : chapters[$0].name },
                            scrollTo: { proxy.scrollTo(chapters[$0].key, anchor: .top) }
                        )
                    }
                }
                .onAppear { proxy.scrollTo(current.key, anchor: .center) }
            }
            .navigationTitle("\(chapters.count) chapters")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar { ToolbarItem(placement: .confirmationAction) { Button("Done") { dismiss() } } }
        }
        .presentationDetents([.medium, .large])
        .presentationDragIndicator(.visible)
    }
}

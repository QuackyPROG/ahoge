import SwiftData
import SwiftUI

struct MangaDetailView: View {
    let ref: MangaRef
    @EnvironmentObject private var sources: SourceManager
    @Environment(\.modelContext) private var context
    @Query private var matches: [LibraryManga]
    @State private var isLoading = false
    @State private var error: Error?
    @State private var expanded = false
    @State private var reading: ChapterRecord?
    @State private var webTarget: WebTarget?

    init(ref: MangaRef) {
        self.ref = ref
        let key = LibraryManga.makeKey(sourceId: ref.sourceId, url: ref.url)
        _matches = Query(filter: #Predicate<LibraryManga> { $0.key == key })
    }

    private var manga: LibraryManga? { matches.first }
    private var repo: LibraryRepository { LibraryRepository(context: context) }
    private var headers: [String: String] {
        sources.installed(ref.sourceId).map { ["Referer": $0.baseUrl + "/"] } ?? [:]
    }

    var body: some View {
        List {
            Section { header }
                .listRowSeparator(.hidden)
            if let error, manga?.chapters.isEmpty ?? true {
                Section {
                    ErrorStateView(error: error, retry: { Task { await refresh() } }, openWeb: { webTarget = WebTarget(url: $0) })
                }
            }
            if let manga { chapters(manga) }
        }
        .listStyle(.plain)
        .navigationTitle(manga?.title ?? ref.title)
        .navigationBarTitleDisplayMode(.inline)
        .refreshable { await refresh() }
        .task {
            repo.upsert(sourceId: ref.sourceId, url: ref.url, title: ref.title, cover: ref.cover)
            if manga?.lastChapterFetch == nil { await refresh() }
        }
        .toolbar {
            ToolbarItem(placement: .topBarTrailing) {
                if let info = sources.installed(ref.sourceId) {
                    Button { webTarget = WebTarget(url: info.baseUrl + ref.url) } label: { Image(systemName: "globe") }
                        .accessibilityLabel("Open in web view")
                }
            }
        }
        .sheet(item: $webTarget) { WebViewSheet(target: $0) }
        .fullScreenCover(item: $reading) { chapter in
            if let manga { ReaderView(sourceId: ref.sourceId, manga: manga, chapter: chapter) }
        }
    }

    @ViewBuilder
    private var header: some View {
        HStack(alignment: .top, spacing: 14) {
            Color.clear
                .frame(width: 110, height: 165)
                .overlay { RemoteImage(url: manga?.coverUrl.nonEmpty ?? ref.cover, headers: headers) }
                .clipShape(RoundedRectangle(cornerRadius: 8))
            VStack(alignment: .leading, spacing: 6) {
                Text(manga?.title ?? ref.title).font(.title3.bold()).lineLimit(4)
                if let author = manga?.author.nonEmpty { Label(author, systemImage: "person").font(.subheadline) }
                if let status = manga?.status { Label(status.capitalized, systemImage: "clock").font(.subheadline).foregroundStyle(.secondary) }
                Text(sources.installed(ref.sourceId)?.name ?? ref.sourceId).font(.caption).foregroundStyle(.secondary)
            }
        }
        HStack {
            Button { toggleLibrary() } label: {
                Label(manga?.inLibrary == true ? "In library" : "Add to library", systemImage: manga?.inLibrary == true ? "heart.fill" : "heart")
            }
            .buttonStyle(.bordered)
            if let next = nextChapter {
                Button { reading = next } label: {
                    Label(next.lastPageRead > 0 || (manga?.chapters.contains { $0.read } ?? false) ? "Resume" : "Start", systemImage: "play.fill")
                }
                .buttonStyle(.borderedProminent)
            }
        }
        if let summary = manga?.summary.nonEmpty {
            Text(summary)
                .font(.callout)
                .lineLimit(expanded ? nil : 3)
                .onTapGesture { withAnimation { expanded.toggle() } }
        }
        if let genres = manga?.genres, !genres.isEmpty {
            ScrollView(.horizontal, showsIndicators: false) {
                HStack {
                    ForEach(genres, id: \.self) { genre in
                        Text(genre)
                            .font(.caption)
                            .padding(.horizontal, 8)
                            .padding(.vertical, 4)
                            .background(.quaternary, in: Capsule())
                    }
                }
            }
        }
        if isLoading { ProgressView().frame(maxWidth: .infinity) }
    }

    private func chapters(_ manga: LibraryManga) -> some View {
        let list = manga.sortedChapters
        return Section("\(list.count) chapters") {
            ForEach(list) { chapter in
                Button { reading = chapter } label: { ChapterRow(chapter: chapter) }
                    .buttonStyle(.plain)
                    .swipeActions(edge: .leading) {
                        Button(chapter.read ? "Unread" : "Read") { repo.setRead([chapter], !chapter.read) }
                            .tint(.blue)
                    }
                    .contextMenu {
                        Button(chapter.read ? "Mark as unread" : "Mark as read") { repo.setRead([chapter], !chapter.read) }
                        Button("Mark previous as read") { repo.markPreviousRead(chapter, in: manga) }
                    }
            }
        }
    }

    /// The oldest unread chapter (chapters are newest first), else the newest.
    private var nextChapter: ChapterRecord? {
        guard let list = manga?.sortedChapters, !list.isEmpty else { return nil }
        return list.last { !$0.read } ?? list.first
    }

    private func toggleLibrary() {
        let target = manga ?? repo.upsert(sourceId: ref.sourceId, url: ref.url, title: ref.title, cover: ref.cover)
        repo.setInLibrary(target, !target.inLibrary)
    }

    private func refresh() async {
        isLoading = true
        error = nil
        defer { isLoading = false }
        do {
            let source = try sources.source(ref.sourceId)
            let details = try await source.details(url: ref.url)
            let chapterList = try await source.chapters(url: ref.url)
            let saved = repo.upsert(sourceId: ref.sourceId, url: ref.url, details: details)
            repo.applyChapters(chapterList, to: saved)
        } catch {
            self.error = error
        }
    }
}

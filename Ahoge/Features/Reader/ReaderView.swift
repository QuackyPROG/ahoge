import SwiftData
import SwiftUI

struct ReaderView: View {
    @StateObject private var model: ReaderModel
    @EnvironmentObject private var sources: SourceManager
    @Environment(\.modelContext) private var context
    @Environment(\.dismiss) private var dismiss
    @State private var showOverlay = false
    @State private var sliderPage = 0.0
    @State private var showChapters = false
    private let start: ChapterRecord

    init(sourceId: String, manga: LibraryManga, chapter: ChapterRecord) {
        start = chapter
        _model = StateObject(wrappedValue: ReaderModel(sourceId: sourceId, manga: manga, start: chapter))
    }

    var body: some View {
        ScrollViewReader { proxy in
            ScrollView {
                LazyVStack(spacing: 0) {
                    ForEach(model.sections) { section in
                        ForEach(Array(section.pages.enumerated()), id: \.offset) { index, page in
                            ReaderPageView(page: page)
                                .id(pageID(section.id, index))
                                .onAppear {
                                    model.pageAppeared(section, index: index, repo: LibraryRepository(context: context), manager: sources)
                                }
                        }
                        Text("End of \(section.chapter.name)")
                            .font(.footnote)
                            .foregroundStyle(.secondary)
                            .padding(.vertical, 32)
                    }
                    if model.isLoadingNext { ProgressView().tint(.white).padding() }
                    if let error = model.error {
                        ErrorStateView(error: error, retry: { Task { await model.open(model.currentChapter, manager: sources) } })
                            .foregroundStyle(.white)
                    }
                }
            }
            .background(Color.black)
            .contentShape(Rectangle())
            .onTapGesture { withAnimation(.easeInOut(duration: 0.2)) { showOverlay.toggle() } }
            .overlay { if showOverlay { overlay(proxy) } }
            .task {
                guard model.sections.isEmpty else { return }
                await model.open(start, manager: sources)
                if !start.read, start.lastPageRead > 0 {
                    try? await Task.sleep(nanoseconds: 150_000_000)
                    proxy.scrollTo(pageID(start.url, start.lastPageRead), anchor: .top)
                }
            }
        }
        .ignoresSafeArea()
        .statusBarHidden(!showOverlay)
        .sheet(isPresented: $showChapters) {
            ReaderChapterList(manga: model.manga, current: model.currentChapter) { chapter in
                Task { await model.open(chapter, manager: sources) }
            }
        }
    }

    private func pageID(_ chapterURL: String, _ index: Int) -> String { "\(chapterURL)#\(index)" }

    private func overlay(_ proxy: ScrollViewProxy) -> some View {
        let count = model.currentSection?.pages.count ?? 0
        return VStack {
            HStack {
                Button { dismiss() } label: { Image(systemName: "xmark").font(.headline).padding(10) }
                VStack(alignment: .leading) {
                    Text(model.manga.title).font(.caption).foregroundStyle(.secondary).lineLimit(1)
                    Text(model.currentChapter.name).font(.subheadline.bold()).lineLimit(1)
                }
                Spacer()
                Button { showChapters = true } label: { Image(systemName: "list.bullet").font(.headline).padding(10) }
                    .accessibilityLabel("Chapters")
            }
            .padding(.horizontal)
            .padding(.top, 50)
            .background(.ultraThinMaterial)
            Spacer()
            VStack(spacing: 8) {
                if count > 1 {
                    Slider(value: $sliderPage, in: 0...Double(count - 1), step: 1, onEditingChanged: { editing in
                        if !editing { proxy.scrollTo(pageID(model.currentChapter.url, Int(sliderPage)), anchor: .top) }
                    })
                }
                HStack {
                    Button {
                        if let previous = model.chapter(before: model.currentChapter) { Task { await model.open(previous, manager: sources) } }
                    } label: { Image(systemName: "backward.end.fill") }
                    .disabled(model.chapter(before: model.currentChapter) == nil)
                    Spacer()
                    Text(count > 0 ? "\(model.currentPage + 1) / \(count)" : "–").monospacedDigit()
                    Spacer()
                    Button {
                        if let next = model.chapter(after: model.currentChapter) { Task { await model.open(next, manager: sources) } }
                    } label: { Image(systemName: "forward.end.fill") }
                    .disabled(model.chapter(after: model.currentChapter) == nil)
                }
            }
            .padding()
            .padding(.bottom, 24)
            .background(.ultraThinMaterial)
        }
        .onAppear { sliderPage = Double(model.currentPage) }
        .onChange(of: model.currentPage) { _, page in sliderPage = Double(page) }
    }
}

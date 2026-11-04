import SwiftUI

/// Mihon's download queue: what is waiting and downloading, drag to reorder, swipe to cancel.
struct DownloadQueueView: View {
    @EnvironmentObject private var downloads: DownloadManager
    @Environment(\.palette) private var palette

    var body: some View {
        List {
            ForEach(downloads.queue) { item in
                DownloadQueueRow(item: item)
            }
            .onMove { offsets, destination in
                guard let from = offsets.first else { return }
                // `onMove` counts the destination before the item leaves; `move(_:to:)` after.
                downloads.move(downloads.queue[from].chapterKey, to: destination > from ? destination - 1 : destination)
            }
            .onDelete { offsets in
                downloads.cancel(offsets.map { downloads.queue[$0].chapterKey })
            }
            .themedRows(plain: true)
        }
        .listStyle(.plain)
        .overlay {
            if downloads.queue.isEmpty {
                ContentUnavailableView("No downloads", systemImage: "arrow.down.circle", description: Text("Download chapters from a title's page or from Updates."))
            }
        }
        .navigationTitle("Download queue")
        .navigationBarTitleDisplayMode(.inline)
        .themedScreen()
        .toolbar {
            if !downloads.queue.isEmpty {
                ToolbarItem(placement: .topBarTrailing) {
                    Button(downloads.isPaused ? "Resume" : "Pause", systemImage: downloads.isPaused ? "play.fill" : "pause.fill") {
                        if downloads.isPaused { downloads.resume() } else { downloads.pause() }
                    }
                }
                ToolbarItem(placement: .topBarTrailing) {
                    Menu {
                        Button("Cancel all", systemImage: "xmark", role: .destructive) {
                            downloads.cancel(downloads.queue.map(\.chapterKey))
                        }
                    } label: {
                        Image(systemName: "ellipsis.circle")
                    }
                }
            }
        }
        .safeAreaInset(edge: .top) {
            if downloads.isPaused, !downloads.queue.isEmpty {
                Label("Paused", systemImage: "pause.circle.fill")
                    .font(.footnote.weight(.semibold))
                    .foregroundStyle(palette.onPrimary.color)
                    .frame(maxWidth: .infinity)
                    .padding(.vertical, 6)
                    .background(palette.primary.color)
            }
        }
    }
}

private struct DownloadQueueRow: View {
    let item: DownloadItem

    var body: some View {
        HStack(spacing: 12) {
            VStack(alignment: .leading, spacing: 4) {
                Text(item.mangaTitle).font(.subheadline.weight(.semibold)).lineLimit(1)
                Text(item.chapterName).font(.footnote).foregroundStyle(.secondary).lineLimit(1)
                switch item.state {
                case .queued:
                    EmptyView()
                case .downloading:
                    ProgressView(value: item.progress)
                case .error(let message):
                    Text(message).font(.caption).foregroundStyle(.red).lineLimit(2)
                }
            }
            Spacer(minLength: 0)
            if item.pageCount > 0 {
                Text("\(item.pagesDone)/\(item.pageCount)")
                    .font(.caption.monospacedDigit())
                    .foregroundStyle(.secondary)
            }
            DownloadProgressIcon(item: item).font(.title3)
        }
        .padding(.vertical, 2)
    }
}

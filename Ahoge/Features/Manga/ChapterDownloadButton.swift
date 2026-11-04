import SwiftUI

/// A chapter's download state beside its row: download, queued, progress ring, downloaded or failed.
/// Tapping downloads; the other states open a menu to cancel, retry or delete.
struct ChapterDownloadButton: View {
    let chapter: ChapterRecord
    @EnvironmentObject private var downloads: DownloadManager
    @Environment(\.palette) private var palette

    var body: some View {
        Group {
            if downloads.isDownloaded(chapter.key) {
                Menu {
                    Button("Delete download", systemImage: "trash", role: .destructive) { downloads.delete([chapter]) }
                } label: {
                    Image(systemName: "checkmark.circle.fill").foregroundStyle(palette.primary.color)
                }
                .accessibilityLabel("Downloaded")
            } else if let item = downloads.queue.first(where: { $0.chapterKey == chapter.key }) {
                Menu {
                    if item.isError {
                        Button("Retry", systemImage: "arrow.clockwise") { downloads.enqueue([chapter]) }
                    }
                    Button("Cancel download", systemImage: "xmark", role: .destructive) { downloads.cancel([chapter.key]) }
                } label: {
                    DownloadProgressIcon(item: item)
                }
            } else {
                Button { downloads.enqueue([chapter]) } label: {
                    Image(systemName: "arrow.down.circle").foregroundStyle(.secondary)
                }
                .accessibilityLabel("Download")
            }
        }
        .font(.title3)
        .buttonStyle(.plain)
        .frame(width: 34, height: 34)
        .contentShape(Rectangle())
    }
}

/// Queued (dashed ring), downloading (filling ring) or failed (warning), for one queue item.
struct DownloadProgressIcon: View {
    let item: DownloadItem
    @Environment(\.palette) private var palette

    var body: some View {
        switch item.state {
        case .queued:
            Circle()
                .strokeBorder(Color.secondary, style: StrokeStyle(lineWidth: 2, dash: [3, 3]))
                .frame(width: 20, height: 20)
                .accessibilityLabel("Queued")
        case .downloading:
            ZStack {
                Circle().stroke(Color.secondary.opacity(0.3), lineWidth: 2.5)
                Circle()
                    .trim(from: 0, to: max(0.03, item.progress))
                    .stroke(palette.primary.color, style: StrokeStyle(lineWidth: 2.5, lineCap: .round))
                    .rotationEffect(.degrees(-90))
                    .animation(.linear(duration: 0.2), value: item.progress)
            }
            .frame(width: 20, height: 20)
            .accessibilityLabel("Downloading, \(Int(item.progress * 100)) percent")
        case .error:
            Image(systemName: "exclamationmark.circle.fill")
                .foregroundStyle(.red)
                .accessibilityLabel("Download failed")
        }
    }
}

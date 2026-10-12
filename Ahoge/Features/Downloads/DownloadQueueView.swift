// Modified for Ahoge from an Apache-2.0-licensed prior implementation.
// See THIRD_PARTY_NOTICES.md for attribution and license information.

import SwiftUI

struct DownloadQueueView: View {
    @EnvironmentObject private var model: AppModel
    var showsNavigationTitle: Bool = true

    var body: some View {
        ScrollView {
            let jobs = model.jobs()
            if jobs.isEmpty {
                ContentUnavailableView(
                    "Queue is empty",
                    systemImage: "tray",
                    description: Text("Chapters you download will appear here while they are queued or transferring.")
                )
                .frame(maxWidth: .infinity)
                .padding(.top, 70)
            } else {
                LazyVStack(spacing: 12) {
                    ForEach(jobs) { job in
                        downloadCard(job)
                    }
                }
                .padding(.horizontal, AhogeLayout.pagePadding)
                .padding(.vertical, 12)
            }
        }
        .modifier(OptionalNavigationTitleModifier(enabled: showsNavigationTitle, title: "Download Queue"))
    }

    private func downloadCard(_ job: DownloadJob) -> some View {
        VStack(alignment: .leading, spacing: 10) {
            HStack(alignment: .top, spacing: 12) {
                MangaCoverView(
                    manga: job.manga,
                    hideSensitiveCover: model.state.securityPreferences.hideSensitiveCovers,
                    allowsAdultContent: model.source(for: job.manga.sourceID)?.allowsAdultContent ?? false,
                    cornerRadius: 10
                )
                .frame(width: 46, height: 64)

                VStack(alignment: .leading, spacing: 4) {
                    Text(job.manga.title)
                        .font(.subheadline.weight(.semibold))
                        .lineLimit(1)
                    Text(job.chapter.title)
                        .font(.caption)
                        .foregroundStyle(.secondary)
                        .lineLimit(1)
                    Label(job.state.rawValue.capitalized, systemImage: stateSymbol(job.state))
                        .font(.caption2.weight(.semibold))
                        .foregroundStyle(job.state == .failed ? .red : .secondary)
                }
                Spacer()
                actionMenu(job)
            }

            if job.state == .downloading || job.state == .queued || job.state == .paused {
                ProgressView(value: min(max(job.progress, 0), 1))
                    .accessibilityLabel("Download progress")
                    .accessibilityValue("\(Int(job.progress * 100)) percent")
            }

            if let message = job.errorMessage, !message.isEmpty {
                Text(message)
                    .font(.caption)
                    .foregroundStyle(.red)
                    .fixedSize(horizontal: false, vertical: true)
            }
        }
        .padding(14)
        .background(Color.primary.opacity(0.045), in: RoundedRectangle(cornerRadius: 16, style: .continuous))
    }

    @ViewBuilder
    private func actionMenu(_ job: DownloadJob) -> some View {
        Menu {
            switch job.state {
            case .queued, .downloading, .paused:
                Button(role: .destructive) {
                    model.cancelDownload(jobID: job.id)
                } label: {
                    Label("Cancel", systemImage: "xmark.circle")
                }
            case .failed:
                Button {
                    model.retryDownload(jobID: job.id)
                } label: {
                    Label("Retry", systemImage: "arrow.clockwise")
                }
                Button(role: .destructive) {
                    model.cancelDownload(jobID: job.id)
                } label: {
                    Label("Cancel", systemImage: "xmark.circle")
                }
            case .complete:
                Button(role: .destructive) {
                    model.removeDownloaded(manga: job.manga, chapter: job.chapter)
                } label: {
                    Label("Remove", systemImage: "trash")
                }
            }
        } label: {
            Image(systemName: "ellipsis.circle")
                .font(.title3)
                .foregroundStyle(.secondary)
        }
        .accessibilityLabel("Actions for \(job.chapter.title)")
    }

    private func stateSymbol(_ state: DownloadState) -> String {
        switch state {
        case .queued: return "clock"
        case .downloading: return "arrow.down.circle"
        case .paused: return "pause.circle"
        case .failed: return "exclamationmark.triangle"
        case .complete: return "checkmark.circle"
        }
    }
}

private struct OptionalNavigationTitleModifier: ViewModifier {
    let enabled: Bool
    let title: String

    func body(content: Content) -> some View {
        if enabled { content.navigationTitle(title) }
        else { content }
    }
}

// Modified for Ahoge from an Apache-2.0-licensed prior implementation.
// See THIRD_PARTY_NOTICES.md for attribution and license information.

import SwiftUI

enum AhogeLayout {
    static let pagePadding: CGFloat = 18
    static let sectionSpacing: CGFloat = 24
    static let contentSpacing: CGFloat = 14
    static let cardRadius: CGFloat = 18
    static let coverRadius: CGFloat = 14
    static let compactCoverRatio: CGFloat = 0.70
}

struct AhogeSectionHeader<Trailing: View>: View {
    let title: String
    var subtitle: String?
    @ViewBuilder let trailing: Trailing

    init(
        _ title: String,
        subtitle: String? = nil,
        @ViewBuilder trailing: () -> Trailing
    ) {
        self.title = title
        self.subtitle = subtitle
        self.trailing = trailing()
    }

    var body: some View {
        HStack(alignment: .firstTextBaseline, spacing: 12) {
            VStack(alignment: .leading, spacing: 2) {
                Text(title)
                    .font(.title3.weight(.semibold))
                if let subtitle, !subtitle.isEmpty {
                    Text(subtitle)
                        .font(.subheadline)
                        .foregroundStyle(.secondary)
                }
            }
            Spacer(minLength: 8)
            trailing
        }
    }
}

extension AhogeSectionHeader where Trailing == EmptyView {
    init(_ title: String, subtitle: String? = nil) {
        self.init(title, subtitle: subtitle) { EmptyView() }
    }
}

struct AhogeFilterChip: View {
    let title: String
    let systemImage: String?
    let isSelected: Bool
    let action: () -> Void

    init(
        _ title: String,
        systemImage: String? = nil,
        isSelected: Bool,
        action: @escaping () -> Void
    ) {
        self.title = title
        self.systemImage = systemImage
        self.isSelected = isSelected
        self.action = action
    }

    var body: some View {
        Button(action: action) {
            HStack(spacing: 6) {
                if let systemImage {
                    Image(systemName: systemImage)
                }
                Text(title)
                    .lineLimit(1)
            }
            .font(.subheadline.weight(isSelected ? .semibold : .medium))
            .padding(.horizontal, 13)
            .padding(.vertical, 8)
            .foregroundStyle(isSelected ? Color.white : Color.primary)
            .background {
                Capsule(style: .continuous)
                    .fill(isSelected ? AnyShapeStyle(Color.accentColor) : AnyShapeStyle(.quaternary))
            }
            .contentShape(Capsule())
        }
        .buttonStyle(.plain)
        .accessibilityAddTraits(isSelected ? .isSelected : [])
    }
}

struct AhogeMangaGridCard: View {
    let manga: Manga
    var hideSensitiveCover = false
    var allowsAdultContent = false
    var progress: ReadingProgress?
    var badgeText: String?
    var showsDownloadedBadge = false

    var body: some View {
        VStack(alignment: .leading, spacing: 9) {
            ZStack(alignment: .topTrailing) {
                MangaCoverView(
                    manga: manga,
                    hideSensitiveCover: hideSensitiveCover,
                    allowsAdultContent: allowsAdultContent,
                    cornerRadius: AhogeLayout.coverRadius
                )
                .aspectRatio(AhogeLayout.compactCoverRatio, contentMode: .fit)
                .frame(maxWidth: .infinity)
                .shadow(color: .black.opacity(0.10), radius: 10, y: 5)

                VStack(alignment: .trailing, spacing: 6) {
                    if showsDownloadedBadge {
                        Image(systemName: "arrow.down.circle.fill")
                            .font(.caption.weight(.semibold))
                            .foregroundStyle(.white)
                            .padding(7)
                            .background(.black.opacity(0.58), in: Circle())
                            .accessibilityLabel("Downloaded")
                    }
                    if let badgeText, !badgeText.isEmpty {
                        Text(badgeText)
                            .font(.caption2.weight(.semibold))
                            .foregroundStyle(.white)
                            .padding(.horizontal, 8)
                            .padding(.vertical, 5)
                            .background(.black.opacity(0.62), in: Capsule())
                    }
                }
                .padding(8)
            }

            Text(manga.title)
                .font(.subheadline.weight(.semibold))
                .foregroundStyle(.primary)
                .lineLimit(2)
                .multilineTextAlignment(.leading)

            if let progress {
                ProgressView(
                    value: Double(min(max(progress.pageIndex + 1, 0), max(progress.totalPages, 1))),
                    total: Double(max(progress.totalPages, 1))
                )
                .progressViewStyle(.linear)
                .accessibilityLabel("Reading progress")
                .accessibilityValue("Page \(progress.pageIndex + 1) of \(max(progress.totalPages, 1))")
            } else {
                Text(manga.author.isEmpty ? manga.statusText : manga.author)
                    .font(.caption)
                    .foregroundStyle(.secondary)
                    .lineLimit(1)
            }
        }
        .contentShape(Rectangle())
        .accessibilityElement(children: .combine)
    }
}

struct AhogeContinueReadingCard: View {
    let manga: Manga
    let chapter: Chapter
    let progress: ReadingProgress?
    var hideSensitiveCover = false
    var allowsAdultContent = false

    var body: some View {
        HStack(spacing: 16) {
            MangaCoverView(
                manga: manga,
                hideSensitiveCover: hideSensitiveCover,
                allowsAdultContent: allowsAdultContent,
                cornerRadius: 16
            )
            .frame(width: 92, height: 130)
            .shadow(color: .black.opacity(0.12), radius: 10, y: 5)

            VStack(alignment: .leading, spacing: 8) {
                Text("CONTINUE READING")
                    .font(.caption2.weight(.bold))
                    .foregroundStyle(.secondary)
                    .tracking(0.6)

                Text(manga.title)
                    .font(.headline)
                    .lineLimit(2)

                Text(progress?.chapterTitle ?? chapter.title)
                    .font(.subheadline)
                    .foregroundStyle(.secondary)
                    .lineLimit(1)

                if let progress {
                    ProgressView(
                        value: Double(progress.pageIndex + 1),
                        total: Double(max(progress.totalPages, 1))
                    )
                    Text("Page \(progress.pageIndex + 1) of \(max(progress.totalPages, 1))")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }

                Label("Resume", systemImage: "play.fill")
                    .font(.subheadline.weight(.semibold))
                    .foregroundStyle(.tint)
                    .padding(.top, 2)
            }
            Spacer(minLength: 0)
        }
        .padding(14)
        .background(.thinMaterial, in: RoundedRectangle(cornerRadius: AhogeLayout.cardRadius, style: .continuous))
        .overlay {
            RoundedRectangle(cornerRadius: AhogeLayout.cardRadius, style: .continuous)
                .stroke(.quaternary, lineWidth: 0.5)
        }
        .accessibilityElement(children: .combine)
    }
}

struct AhogeSourceCard: View {
    let source: Source

    var body: some View {
        HStack(spacing: 13) {
            Image(systemName: source.systemImage)
                .font(.title3.weight(.semibold))
                .frame(width: 38, height: 38)
                .background(.quaternary, in: RoundedRectangle(cornerRadius: 11, style: .continuous))

            VStack(alignment: .leading, spacing: 3) {
                HStack(spacing: 6) {
                    Text(source.name)
                        .font(.subheadline.weight(.semibold))
                        .lineLimit(1)
                    if source.isPinned {
                        Image(systemName: "pin.fill")
                            .font(.caption2)
                            .foregroundStyle(.secondary)
                    }
                }
                Text("\(source.language.rawValue) · \(source.kind == .local ? "Local" : "Remote")")
                    .font(.caption)
                    .foregroundStyle(.secondary)
                    .lineLimit(1)
            }
            Spacer(minLength: 0)
        }
        .padding(12)
        .background(Color.primary.opacity(0.045), in: RoundedRectangle(cornerRadius: 16, style: .continuous))
        .overlay {
            RoundedRectangle(cornerRadius: 16, style: .continuous)
                .stroke(.quaternary, lineWidth: 0.5)
        }
        .contentShape(Rectangle())
        .accessibilityElement(children: .combine)
    }
}

struct AhogeStatusBadge: View {
    let title: String
    let systemImage: String

    var body: some View {
        Label(title, systemImage: systemImage)
            .font(.caption.weight(.semibold))
            .foregroundStyle(.secondary)
            .padding(.horizontal, 9)
            .padding(.vertical, 5)
            .background(.quaternary, in: Capsule())
    }
}

struct AhogeActionRow: View {
    let title: String
    let subtitle: String?
    let systemImage: String
    var role: ButtonRole?
    var showsChevron = true

    var body: some View {
        HStack(spacing: 13) {
            Image(systemName: systemImage)
                .font(.body.weight(.semibold))
                .frame(width: 30, height: 30)
                .foregroundStyle(role == .destructive ? Color.red : Color.accentColor)
                .background(.quaternary, in: RoundedRectangle(cornerRadius: 9, style: .continuous))
            VStack(alignment: .leading, spacing: 2) {
                Text(title)
                    .font(.body)
                    .foregroundStyle(role == .destructive ? Color.red : Color.primary)
                if let subtitle, !subtitle.isEmpty {
                    Text(subtitle)
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
            }
            Spacer()
            if showsChevron {
                Image(systemName: "chevron.right")
                    .font(.caption.weight(.semibold))
                    .foregroundStyle(.tertiary)
            }
        }
        .contentShape(Rectangle())
    }
}

// Modified for Ahoge from an Apache-2.0-licensed prior implementation.
// See THIRD_PARTY_NOTICES.md for attribution and license information.

import SwiftUI

enum AhogeLayout {
    static let pagePadding: CGFloat = 20
    static let sectionSpacing: CGFloat = 28
    static let contentSpacing: CGFloat = 12
    static let cardRadius: CGFloat = 12
    static let coverRadius: CGFloat = 8
    static let compactCoverRatio: CGFloat = 0.70
}

enum AhogePalette {
    static let canvas = Color(uiColor: .systemBackground)
    static let surface = Color(uiColor: .secondarySystemBackground)
    static let ink = Color.primary
    static let secondaryInk = Color.secondary
    static let divider = Color(uiColor: .separator)
    static let accent = Color.accentColor
    static let status = Color.secondary
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
        ViewThatFits(in: .horizontal) {
            headerRow
            VStack(alignment: .leading, spacing: 12) { heading; trailing }
        }
        .accessibilityAddTraits(.isHeader)
    }

    private var heading: some View {
        VStack(alignment: .leading, spacing: 4) {
            Text(title).font(.title3.weight(.bold))
            if let subtitle, !subtitle.isEmpty {
                Text(subtitle).font(.subheadline).foregroundStyle(.secondary)
            }
        }
    }

    private var headerRow: some View {
        HStack(alignment: .firstTextBaseline, spacing: 12) {
            heading
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
    @Environment(\.colorSchemeContrast) private var contrast
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
                    .fixedSize(horizontal: false, vertical: true)
            }
            .frame(minHeight: 44)
            .font(.subheadline.weight(isSelected ? .semibold : .medium))
            .padding(.horizontal, 13)
            .padding(.vertical, 8)
            .foregroundStyle(isSelected ? Color.accentColor : Color.primary)
            .background {
                Capsule(style: .continuous)
                    .fill(isSelected ? AnyShapeStyle(Color.accentColor.opacity(0.12)) : AnyShapeStyle(AhogePalette.surface))
            }
            .overlay {
                Capsule().stroke(isSelected ? Color.accentColor : AhogePalette.divider,
                                 lineWidth: contrast == .increased ? 2 : 1)
            }
            .contentShape(Capsule())
        }
        .buttonStyle(.plain)
        .accessibilityAddTraits(isSelected ? .isSelected : [])
    }
}

struct AhogeMangaGridCard: View {
    @Environment(\.dynamicTypeSize) private var dynamicTypeSize
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
                .accessibilityHidden(true)
                .aspectRatio(AhogeLayout.compactCoverRatio, contentMode: .fit)
                .frame(maxWidth: dynamicTypeSize.isAccessibilitySize ? 180 : .infinity)

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
                            .font(.caption.weight(.semibold))
                            .foregroundStyle(.white)
                            .padding(.horizontal, 8)
                            .padding(.vertical, 5)
                            .background(.black.opacity(0.62), in: Capsule())
                    }
                }
                .padding(8)
            }

            Text(manga.title)
                .font(.headline)
                .foregroundStyle(.primary)
                .lineLimit(dynamicTypeSize.isAccessibilitySize ? nil : 2)
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
                    .lineLimit(dynamicTypeSize.isAccessibilitySize ? nil : 1)
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

    @Environment(\.dynamicTypeSize) private var dynamicTypeSize

    var body: some View {
        Group {
            if dynamicTypeSize.isAccessibilitySize {
                VStack(alignment: .leading, spacing: 20) { cover; readingDetails }
            } else {
                HStack(alignment: .center, spacing: 24) { cover; readingDetails }
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(.vertical, 16)
        .accessibilityElement(children: .combine)
        .accessibilityHint("Resume reading this chapter")
    }

    private var cover: some View {
        MangaCoverView(
            manga: manga,
            hideSensitiveCover: hideSensitiveCover,
            allowsAdultContent: allowsAdultContent,
            cornerRadius: 12
        )
        .accessibilityHidden(true)
        .aspectRatio(AhogeLayout.compactCoverRatio, contentMode: .fit)
        .frame(width: dynamicTypeSize.isAccessibilitySize ? 140 : 120)
        .shadow(color: .black.opacity(0.12), radius: 8, y: 4)
    }

    private var readingDetails: some View {
        VStack(alignment: .leading, spacing: 12) {
            Text("Continue reading").font(.subheadline).foregroundStyle(.secondary)
            Text(manga.title).font(.title2.weight(.bold)).fixedSize(horizontal: false, vertical: true)
            Text(progress?.chapterTitle ?? chapter.title)
                .font(.subheadline).foregroundStyle(.secondary)
                .fixedSize(horizontal: false, vertical: true)
            if let progress {
                ProgressView(value: Double(progress.pageIndex + 1), total: Double(max(progress.totalPages, 1)))
                    .accessibilityLabel("Reading progress")
                Text("Page \(progress.pageIndex + 1) of \(max(progress.totalPages, 1))")
                    .font(.footnote.monospacedDigit()).foregroundStyle(.secondary)
            }
            Label("Resume", systemImage: "play.fill")
                .font(.headline).foregroundStyle(.tint)
                .frame(minHeight: 44)
        }
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
                        .fixedSize(horizontal: false, vertical: true)
                    if source.isPinned {
                        Image(systemName: "pin.fill")
                            .font(.caption2)
                            .foregroundStyle(.secondary)
                    }
                }
                Text("\(source.language.rawValue) · \(source.kind == .local ? "Local" : "Remote")")
                    .font(.caption)
                    .foregroundStyle(.secondary)
                    .fixedSize(horizontal: false, vertical: true)
            }
            Spacer(minLength: 0)
        }
        .padding(12)
        .background(AhogePalette.surface, in: RoundedRectangle(cornerRadius: 8, style: .continuous))
        .overlay {
            RoundedRectangle(cornerRadius: 8, style: .continuous)
                .stroke(AhogePalette.divider, lineWidth: 0.5)
        }
        .contentShape(Rectangle())
        .accessibilityElement(children: .combine)
    }
}

struct AhogeStatusBadge: View {
    @Environment(\.colorSchemeContrast) private var contrast
    let title: String
    let systemImage: String

    var body: some View {
        Label(title, systemImage: systemImage)
            .font(.caption.weight(.semibold))
            .foregroundStyle(.secondary)
            .padding(.horizontal, 9)
            .padding(.vertical, 5)
            .background(AhogePalette.surface, in: Capsule())
            .overlay { Capsule().stroke(AhogePalette.divider, lineWidth: contrast == .increased ? 2 : 0.5) }
            .fixedSize(horizontal: false, vertical: true)
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
        .frame(minHeight: 44)
        .contentShape(Rectangle())
        .accessibilityElement(children: .combine)
    }
}

import SwiftUI

/// How the Library draws titles (`Pref.libraryDisplayMode`).
enum LibraryDisplayMode: String, CaseIterable, Identifiable {
    case compact, comfortable, coverOnly, list

    var id: String { rawValue }

    var label: String {
        switch self {
        case .compact: "Compact grid"
        case .comfortable: "Comfortable grid"
        case .coverOnly: "Cover-only grid"
        case .list: "List"
        }
    }
}

enum LibraryBadges {
    /// The id of the on-device source (Phase 8's `LocalSource`); its titles get the "Local" badge.
    static let localSourceId = "local"
}

/// A small label on a cover or list row.
struct CardBadge: Hashable {
    enum Kind { case unread, downloaded, info }
    let text: String
    let kind: Kind
}

/// The badges stacked on one corner of a card, in the order given.
struct CardBadges: View {
    let badges: [CardBadge]
    @Environment(\.palette) private var palette

    var body: some View {
        HStack(spacing: 0) {
            ForEach(badges, id: \.self) { badge in
                Text(badge.text)
                    .font(.caption2.weight(.bold).monospacedDigit())
                    .padding(.horizontal, 6)
                    .padding(.vertical, 3)
                    .foregroundStyle(foreground(badge.kind))
                    .background(background(badge.kind))
            }
        }
        .clipShape(RoundedRectangle(cornerRadius: 5, style: .continuous))
    }

    private func foreground(_ kind: CardBadge.Kind) -> Color {
        switch kind {
        case .unread: palette.onPrimary.color
        case .downloaded, .info: palette.onSurface.color
        }
    }

    private func background(_ kind: CardBadge.Kind) -> Color {
        switch kind {
        case .unread: palette.primary.color
        case .downloaded: palette.container.color
        case .info: palette.surface.color
        }
    }
}

/// A library title as a row: cover, title and badges.
struct MangaListRow: View {
    let title: String
    let cover: String
    var headers: [String: String] = [:]
    var badges: [CardBadge] = []
    @Environment(\.palette) private var palette

    var body: some View {
        HStack(spacing: 12) {
            Color.clear
                .frame(width: 44, height: 64)
                .overlay { RemoteImage(url: cover, headers: headers, maxPixelWidth: 160) }
                .clipShape(RoundedRectangle(cornerRadius: 6, style: .continuous))
            Text(title)
                .font(.subheadline.weight(.medium))
                .foregroundStyle(palette.onSurface.color)
                .lineLimit(2)
                .multilineTextAlignment(.leading)
            Spacer(minLength: 8)
            CardBadges(badges: badges)
        }
        .padding(.vertical, 4)
        .frame(maxWidth: .infinity, alignment: .leading)
        .contentShape(Rectangle())
        .accessibilityElement(children: .combine)
    }
}

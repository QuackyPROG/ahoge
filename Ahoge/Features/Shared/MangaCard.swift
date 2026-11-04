import SwiftUI

/// Mihon's compact grid card: the title over the bottom of the cover on a gradient.
struct MangaCard: View {
    let title: String
    let cover: String
    var headers: [String: String] = [:]
    var badge: String?
    /// Library badges: unread and downloaded count top left, language and local marker top right.
    var leadingBadges: [CardBadge] = []
    var trailingBadges: [CardBadge] = []
    /// `.comfortable` puts the title under the cover, `.coverOnly` leaves it out.
    var style = LibraryDisplayMode.compact
    /// A browse result already in the library; shown faded.
    var inLibrary = false
    @Environment(\.palette) private var palette

    /// About three pixels per point of the widest grid card.
    static let coverPixelWidth: CGFloat = 360

    var body: some View {
        if style == .comfortable {
            VStack(alignment: .leading, spacing: 5) {
                coverView
                Text(title)
                    .font(.caption.weight(.semibold))
                    .foregroundStyle(palette.onSurface.color)
                    .lineLimit(2)
                    .multilineTextAlignment(.leading)
                    .frame(maxWidth: .infinity, alignment: .leading)
            }
            .opacity(inLibrary ? 0.4 : 1)
            .accessibilityElement(children: .combine)
            .accessibilityValue(inLibrary ? "In library" : "")
        } else {
            coverView
                .opacity(inLibrary ? 0.4 : 1)
                .accessibilityElement(children: .combine)
                .accessibilityValue(inLibrary ? "In library" : "")
                .accessibilityLabel(title)
        }
    }

    private var coverView: some View {
        Color.clear
            .aspectRatio(2 / 3, contentMode: .fit)
            .overlay { RemoteImage(url: cover, headers: headers, maxPixelWidth: Self.coverPixelWidth) }
            .overlay(alignment: .bottomLeading) {
                if style == .compact {
                    Text(title)
                        .font(.caption.weight(.semibold))
                        .foregroundStyle(.white)
                        .lineLimit(2)
                        .multilineTextAlignment(.leading)
                        .shadow(color: .black.opacity(0.6), radius: 2, y: 1)
                        .padding(.horizontal, 8)
                        .padding(.top, 28)
                        .padding(.bottom, 7)
                        .frame(maxWidth: .infinity, alignment: .leading)
                        .background(LinearGradient(colors: [.clear, .black.opacity(0.78)], startPoint: .top, endPoint: .bottom))
                }
            }
            .overlay(alignment: .topLeading) {
                HStack(spacing: 4) {
                    if let badge {
                        Text(badge)
                            .font(.caption2.weight(.bold).monospacedDigit())
                            .padding(.horizontal, 6)
                            .padding(.vertical, 3)
                            .foregroundStyle(palette.onPrimary.color)
                            .background(palette.primary.color, in: RoundedRectangle(cornerRadius: 5, style: .continuous))
                    }
                    if !leadingBadges.isEmpty { CardBadges(badges: leadingBadges) }
                }
                .padding(6)
            }
            .overlay(alignment: .topTrailing) {
                if !trailingBadges.isEmpty { CardBadges(badges: trailingBadges).padding(6) }
            }
            .clipShape(RoundedRectangle(cornerRadius: 10, style: .continuous))
            .background(RoundedRectangle(cornerRadius: 10, style: .continuous).fill(.black).shadow(color: .black.opacity(0.18), radius: 6, y: 3))
            .overlay(RoundedRectangle(cornerRadius: 10, style: .continuous).strokeBorder(.white.opacity(0.08)))
    }
}

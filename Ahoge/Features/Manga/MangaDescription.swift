import SwiftUI

enum DescriptionFormatter {
    private static let entities = ["&amp;": "&", "&quot;": "\"", "&#39;": "'", "&#039;": "'", "&apos;": "'", "&nbsp;": " ", "&lt;": "<", "&gt;": ">"]

    /// Cleans a source description: HTML entities and tags, Markdown rules and list markers, runs of
    /// blank lines. Inline Markdown (bold, italics, links), which MangaDex uses, is kept for rendering.
    static func clean(_ text: String) -> String {
        var s = text.replacingOccurrences(of: "\r\n", with: "\n")
        s = s.replacingOccurrences(of: "<br\\s*/?>", with: "\n", options: [.regularExpression, .caseInsensitive])
        s = s.replacingOccurrences(of: "</p>\\s*<p[^>]*>", with: "\n\n", options: [.regularExpression, .caseInsensitive])
        s = s.replacingOccurrences(of: "<[^>]+>", with: "", options: .regularExpression)
        for (entity, value) in entities { s = s.replacingOccurrences(of: entity, with: value) }
        let lines = s.components(separatedBy: "\n").map { line -> String in
            let trimmed = line.trimmingCharacters(in: .whitespaces)
            if trimmed.range(of: "^([-*_])(\\s*\\1){2,}$", options: .regularExpression) != nil { return "" }
            if let marker = trimmed.range(of: "^[-*+]\\s+", options: .regularExpression) {
                return "• " + trimmed[marker.upperBound...]
            }
            return trimmed
        }
        s = lines.joined(separator: "\n")
        s = s.replacingOccurrences(of: "\n{3,}", with: "\n\n", options: .regularExpression)
        return s.trimmingCharacters(in: .whitespacesAndNewlines)
    }

    static func attributed(_ text: String) -> AttributedString {
        let cleaned = clean(text)
        let options = AttributedString.MarkdownParsingOptions(interpretedSyntax: .inlineOnlyPreservingWhitespace)
        return (try? AttributedString(markdown: cleaned, options: options)) ?? AttributedString(cleaned)
    }
}

/// Collapsed: three lines fading out with a chevron. Expanded: full selectable text.
struct MangaDescription: View {
    let summary: String
    @Binding var expanded: Bool

    var body: some View {
        let text = DescriptionFormatter.attributed(summary)
        VStack(spacing: 2) {
            Text(text)
                .font(.callout)
                .foregroundStyle(.primary.opacity(0.85))
                .lineLimit(expanded ? nil : 3)
                .frame(maxWidth: .infinity, alignment: .leading)
                .textSelection(.enabled)
                .mask {
                    if expanded {
                        Rectangle()
                    } else {
                        LinearGradient(stops: [.init(color: .black, location: 0.55), .init(color: .black.opacity(0.15), location: 1)], startPoint: .top, endPoint: .bottom)
                    }
                }
            Button {
                withAnimation(.easeInOut(duration: 0.2)) { expanded.toggle() }
            } label: {
                Image(systemName: expanded ? "chevron.up" : "chevron.down")
                    .font(.footnote.weight(.semibold))
                    .foregroundStyle(.secondary)
                    .frame(maxWidth: .infinity, minHeight: 24)
                    .contentShape(Rectangle())
            }
            .buttonStyle(.plain)
            .accessibilityLabel(expanded ? "Show less" : "Show more")
        }
        .contentShape(Rectangle())
        .onTapGesture { if !expanded { withAnimation(.easeInOut(duration: 0.2)) { expanded = true } } }
    }
}

import SwiftUI

struct ChapterRow: View {
    @ObservedObject var chapter: ChapterRecord
    /// The chapter open in the reader, highlighted in the reader's chapter list.
    var isCurrent = false
    /// Shown in place of the chapter's own name ("Chapter N" display).
    var title: String?
    @Environment(\.palette) private var palette
    @AppStorage(Pref.dateFormat.name) private var dateFormat = Pref.dateFormat.defaultValue
    @AppStorage(Pref.relativeTimestamps.name) private var relativeDates = Pref.relativeTimestamps.defaultValue

    var body: some View {
        HStack(spacing: 10) {
            VStack(alignment: .leading, spacing: 3) {
                Text(title ?? chapter.name)
                    .font(.subheadline.weight(isCurrent ? .semibold : .regular))
                    .foregroundStyle(isCurrent ? palette.primary.color : chapter.read ? Color.secondary : Color.primary)
                    .lineLimit(2)
                HStack(spacing: 4) {
                    if let date = chapter.dateUpload { Text(DateFormatting.string(for: date, format: dateFormat, relative: relativeDates, now: Date())) }
                    if let scanlator = chapter.scanlator, !scanlator.isEmpty {
                        if chapter.dateUpload != nil { Text("•") }
                        Text(scanlator).lineLimit(1)
                    }
                    if !chapter.read && chapter.lastPageRead > 0 {
                        Text("•")
                        Text("Page \(chapter.lastPageRead + 1)").foregroundStyle(palette.primary.color)
                    }
                }
                .font(.caption)
                .foregroundStyle(.secondary)
                .opacity(chapter.read && !isCurrent ? 0.7 : 1)
            }
            Spacer(minLength: 0)
            if chapter.bookmark {
                Image(systemName: "bookmark.fill").font(.caption).foregroundStyle(palette.primary.color)
                    .accessibilityLabel("Bookmarked")
            }
            if !chapter.read {
                Circle().fill(palette.primary.color).frame(width: 7, height: 7)
                    .accessibilityLabel("Unread")
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .contentShape(Rectangle())
    }
}

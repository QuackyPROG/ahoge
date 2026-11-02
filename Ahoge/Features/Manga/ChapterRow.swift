import SwiftUI

struct ChapterRow: View {
    @ObservedObject var chapter: ChapterRecord
    /// The chapter open in the reader, highlighted in the reader's chapter list.
    var isCurrent = false

    var body: some View {
        HStack(spacing: 10) {
            VStack(alignment: .leading, spacing: 3) {
                Text(chapter.name)
                    .font(.subheadline.weight(isCurrent ? .semibold : .regular))
                    .foregroundStyle(isCurrent ? Color.accentColor : chapter.read ? Color.secondary : Color.primary)
                    .lineLimit(2)
                HStack(spacing: 4) {
                    if let date = chapter.dateUpload { Text(date, format: .dateTime.year().month(.abbreviated).day()) }
                    if let scanlator = chapter.scanlator, !scanlator.isEmpty {
                        if chapter.dateUpload != nil { Text("•") }
                        Text(scanlator).lineLimit(1)
                    }
                    if !chapter.read && chapter.lastPageRead > 0 {
                        Text("•")
                        Text("Page \(chapter.lastPageRead + 1)").foregroundStyle(Color.accentColor)
                    }
                }
                .font(.caption)
                .foregroundStyle(.secondary)
                .opacity(chapter.read && !isCurrent ? 0.7 : 1)
            }
            Spacer(minLength: 0)
            if !chapter.read {
                Circle().fill(Color.accentColor).frame(width: 7, height: 7)
                    .accessibilityLabel("Unread")
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .contentShape(Rectangle())
    }
}

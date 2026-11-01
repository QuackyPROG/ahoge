import SwiftUI

struct ChapterRow: View {
    let chapter: ChapterRecord

    var body: some View {
        VStack(alignment: .leading, spacing: 3) {
            Text(chapter.name)
                .foregroundStyle(chapter.read ? .secondary : .primary)
                .lineLimit(2)
            HStack(spacing: 6) {
                if let date = chapter.dateUpload { Text(date, format: .dateTime.year().month().day()) }
                if let scanlator = chapter.scanlator, !scanlator.isEmpty { Text("· \(scanlator)") }
                if !chapter.read && chapter.lastPageRead > 0 { Text("· Page \(chapter.lastPageRead + 1)") }
            }
            .font(.caption)
            .foregroundStyle(.secondary)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .contentShape(Rectangle())
    }
}

import SwiftUI

/// "Checking about every 7 days" on a library title's page; tapping picks its own interval.
struct UpdateIntervalRow: View {
    let manga: LibraryManga
    @EnvironmentObject private var repo: LibraryRepository
    @AppStorage(Pref.updateSmart.name) private var smart = Pref.updateSmart.defaultValue

    private static let choices = [1, 2, 3, 5, 7, 14, 28]

    var body: some View {
        Menu {
            Picker("Check for new chapters", selection: Binding(
                get: { manga.updateInterval ?? -1 },
                set: { repo.setUpdateInterval($0 < 0 ? nil : $0, for: manga) }
            )) {
                Text("Automatic").tag(-1)
                Text("Never").tag(0)
                ForEach(Self.choices, id: \.self) { days in
                    Text(days == 1 ? "Every day" : "Every \(days) days").tag(days)
                }
            }
        } label: {
            Label(summary, systemImage: "calendar.badge.clock")
                .font(.footnote)
                .multilineTextAlignment(.leading)
        }
    }

    private func days(_ interval: TimeInterval) -> String {
        let count = max(1, Int((interval / 86_400).rounded()))
        return count == 1 ? "day" : "\(count) days"
    }

    private var summary: String {
        if let own = manga.updateInterval {
            if own == 0 { return "Never checked for new chapters" }
            return "Checking every \(days(Double(own) * 86_400))"
        }
        guard smart else { return "Checked with every library update" }
        if let predicted = ReleasePredictor.interval(for: manga) {
            return "Checking about every \(days(predicted))"
        }
        return "Checking for new chapters automatically"
    }
}

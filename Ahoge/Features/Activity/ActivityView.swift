// Modified for Ahoge from an Apache-2.0-licensed prior implementation.
// See THIRD_PARTY_NOTICES.md for attribution and license information.

import SwiftUI

/// Compatibility destination; Updates and History each have their own root.
struct ActivityView: View {
    var body: some View {
        List {
            NavigationLink("Updates") { UpdatesView() }
            NavigationLink("History") { HistoryView() }
            NavigationLink("Download Queue") { DownloadQueueView() }
        }.navigationTitle("Activity")
    }
}

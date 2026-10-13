// Modified for Ahoge from an Apache-2.0-licensed prior implementation.
// See THIRD_PARTY_NOTICES.md for attribution and license information.

import SwiftUI

struct StatsView: View {
    @EnvironmentObject private var model: AppModel
    @Environment(\.dynamicTypeSize) private var dynamicTypeSize

    var body: some View {
        ScrollView {
            if model.hasMeaningfulStats {
                LazyVStack(alignment: .leading, spacing: AhogeLayout.sectionSpacing) {
                    VStack(alignment: .leading, spacing: 8) {
                        Text("Your reading life").font(.system(.largeTitle, design: .rounded, weight: .bold))
                        Text("A snapshot of your library and reading activity.")
                            .font(.body).foregroundStyle(.secondary)
                    }
                    ForEach(model.statsSections()) { section in
                        VStack(alignment: .leading, spacing: 12) {
                            AhogeSectionHeader(section.title)
                            VStack(spacing: 0) {
                                ForEach(section.items) { item in
                                    metricCard(item)
                                    Divider()
                                }
                            }
                        }
                    }
                }
                .padding(.horizontal, AhogeLayout.pagePadding)
                .padding(.vertical, 24)
                .frame(maxWidth: 760, alignment: .leading)
                .frame(maxWidth: .infinity)
            } else {
                ContentUnavailableView(
                    "No Reading Stats Yet",
                    systemImage: "chart.bar",
                    description: Text("Start adding titles and reading chapters to build your stats.")
                )
                .frame(maxWidth: .infinity)
                .padding(.top, 70)
            }
        }
        .navigationTitle("Stats")
    }

    private func metricCard(_ item: StatsItem) -> some View {
        let layout = dynamicTypeSize.isAccessibilitySize
            ? AnyLayout(VStackLayout(alignment: .leading, spacing: 8))
            : AnyLayout(HStackLayout(alignment: .firstTextBaseline, spacing: 20))
        return layout {
            VStack(alignment: .leading, spacing: 8) {
                Label(item.title, systemImage: item.systemImage)
                    .font(.headline)
                if let detail = item.detail {
                    Text(detail).font(.subheadline).foregroundStyle(.secondary)
                        .fixedSize(horizontal: false, vertical: true)
                }
            }
            .frame(maxWidth: .infinity, alignment: .leading)
            Text(item.value)
                .font(.system(.title, design: .rounded, weight: .semibold))
                .monospacedDigit().foregroundStyle(model.chromeTint)
                .fixedSize(horizontal: false, vertical: true)
        }
        .padding(.vertical, 16)
        .accessibilityElement(children: .combine)
    }
}

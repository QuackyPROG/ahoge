// Modified for Ahoge from an Apache-2.0-licensed prior implementation.
// See THIRD_PARTY_NOTICES.md for attribution and license information.

import SwiftUI

struct StatsView: View {
    @EnvironmentObject private var model: AppModel

    var body: some View {
        ScrollView {
            if model.hasMeaningfulStats {
                LazyVStack(alignment: .leading, spacing: AhogeLayout.sectionSpacing) {
                    ForEach(model.statsSections()) { section in
                        VStack(alignment: .leading, spacing: 12) {
                            AhogeSectionHeader(section.title)
                            LazyVGrid(
                                columns: [GridItem(.adaptive(minimum: 145), spacing: 12)],
                                spacing: 12
                            ) {
                                ForEach(section.items) { item in
                                    metricCard(item)
                                }
                            }
                        }
                    }
                }
                .padding(.horizontal, AhogeLayout.pagePadding)
                .padding(.vertical, 12)
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
        VStack(alignment: .leading, spacing: 8) {
            Image(systemName: item.systemImage)
                .font(.headline)
                .foregroundStyle(model.chromeTint)
            Text(item.value)
                .font(.title2.weight(.semibold))
                .minimumScaleFactor(0.8)
            Text(item.title)
                .font(.subheadline.weight(.medium))
            if let detail = item.detail {
                Text(detail)
                    .font(.caption)
                    .foregroundStyle(.secondary)
                    .fixedSize(horizontal: false, vertical: true)
            }
        }
        .frame(maxWidth: .infinity, minHeight: 116, alignment: .topLeading)
        .padding(14)
        .background(Color.primary.opacity(0.045), in: RoundedRectangle(cornerRadius: AhogeLayout.cardRadius, style: .continuous))
        .accessibilityElement(children: .combine)
    }
}

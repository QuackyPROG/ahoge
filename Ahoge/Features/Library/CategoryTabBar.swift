import SwiftUI

/// One Library tab: a category, or Default (id 0) for titles in no category.
struct LibraryShelf: Identifiable, Hashable {
    let id: Int
    let name: String
}

/// Mihon's scrolling category tabs, as pills that slide to the selected one.
struct CategoryTabBar: View {
    let shelves: [LibraryShelf]
    let counts: [Int: Int]
    @Binding var selection: Int
    @Environment(\.palette) private var palette
    @Namespace private var pill

    var body: some View {
        ScrollViewReader { proxy in
            ScrollView(.horizontal, showsIndicators: false) {
                HStack(spacing: 4) {
                    ForEach(shelves) { shelf in
                        let selected = shelf.id == selection
                        Button {
                            withAnimation(.spring(duration: 0.3)) { selection = shelf.id }
                        } label: {
                            HStack(spacing: 6) {
                                Text(shelf.name)
                                if let count = counts[shelf.id] {
                                    Text("\(count)")
                                        .font(.caption2.weight(.bold).monospacedDigit())
                                        .padding(.horizontal, 6)
                                        .padding(.vertical, 2)
                                        .background(selected ? palette.onPrimary.color.opacity(0.2) : palette.container.color, in: Capsule())
                                }
                            }
                            .font(.subheadline.weight(selected ? .semibold : .medium))
                            .foregroundStyle(selected ? palette.onPrimary.color : palette.onSurfaceVariant.color)
                            .padding(.horizontal, 14)
                            .padding(.vertical, 8)
                            .background {
                                if selected {
                                    Capsule().fill(palette.primary.color).matchedGeometryEffect(id: "pill", in: pill)
                                }
                            }
                        }
                        .buttonStyle(.plain)
                        .id(shelf.id)
                        .accessibilityAddTraits(selected ? .isSelected : [])
                    }
                }
                .padding(.horizontal)
            }
            .onChange(of: selection) { _, id in
                withAnimation { proxy.scrollTo(id, anchor: .center) }
            }
        }
        .padding(.vertical, 6)
        .sensoryFeedback(.selection, trigger: selection)
    }
}

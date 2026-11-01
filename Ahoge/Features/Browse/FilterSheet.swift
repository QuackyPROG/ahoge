import SwiftUI

/// Mihon-style filter sheet: Reset and Filter on top, the source's filters below.
struct FilterSheet: View {
    @Binding var state: FilterState
    let apply: (FilterState) -> Void

    var body: some View {
        NavigationStack {
            List {
                FilterRows(filters: state.filters, values: $state.values)
            }
            .listStyle(.insetGrouped)
            .navigationTitle("Filters")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Reset") { state.reset() }
                        .disabled(state.activeCount == 0)
                }
                ToolbarItem(placement: .confirmationAction) {
                    Button("Filter") { apply(state) }.bold()
                }
            }
        }
    }
}

private struct FilterRows: View {
    let filters: [SourceFilter]
    @Binding var values: [String: FilterValue]

    var body: some View {
        ForEach(Array(filters.enumerated()), id: \.offset) { _, filter in
            row(filter)
        }
    }

    @ViewBuilder
    private func row(_ filter: SourceFilter) -> some View {
        switch filter {
        case .header(let name):
            Text(name)
                .font(.footnote.weight(.semibold))
                .foregroundStyle(.secondary)
                .textCase(.uppercase)
                .listRowBackground(Color.clear)
        case .separator:
            EmptyView()
        case .text(let key, let name):
            TextField(name, text: text(key))
                .textInputAutocapitalization(.never)
                .autocorrectionDisabled()
        case .checkbox(let key, let name, _):
            Toggle(name, isOn: bool(key))
        case .tristate(let key, let name):
            TriStateRow(name: name, state: tristate(key))
        case .select(let key, let name, let options, _):
            Picker(name, selection: option(key)) {
                ForEach(options, id: \.value) { Text($0.label).tag($0.value) }
            }
            .pickerStyle(.menu)
        case .sort(let key, let name, let options, let fallback):
            SortRows(name: name, options: options, value: sort(key, fallback))
        case .group(let key, let name, let children):
            GroupRows(name: name, children: children, values: group(key, children))
        }
    }

    private func text(_ key: String) -> Binding<String> {
        Binding(get: { if case .text(let v) = values[key] { return v }; return "" }, set: { values[key] = .text($0) })
    }

    private func bool(_ key: String) -> Binding<Bool> {
        Binding(get: { if case .bool(let v) = values[key] { return v }; return false }, set: { values[key] = .bool($0) })
    }

    private func tristate(_ key: String) -> Binding<TriState> {
        Binding(get: { if case .state(let v) = values[key] { return v }; return .ignore }, set: { values[key] = .state($0) })
    }

    private func option(_ key: String) -> Binding<String> {
        Binding(get: { if case .option(let v) = values[key] { return v }; return "" }, set: { values[key] = .option($0) })
    }

    private func sort(_ key: String, _ fallback: SortValue) -> Binding<SortValue> {
        Binding(get: { if case .sort(let v) = values[key] { return v }; return fallback }, set: { values[key] = .sort($0) })
    }

    private func group(_ key: String, _ children: [SourceFilter]) -> Binding<[String: FilterValue]> {
        Binding(
            get: { if case .group(let v) = values[key] { return v }; return SourceFilter.defaults(for: children) },
            set: { values[key] = .group($0) }
        )
    }
}

/// Tap cycles: ignored → included (✓) → excluded (✕).
private struct TriStateRow: View {
    let name: String
    @Binding var state: TriState

    var body: some View {
        Button { state = state.next } label: {
            HStack(spacing: 12) {
                Image(systemName: icon)
                    .font(.title3)
                    .foregroundStyle(color)
                    .frame(width: 24)
                Text(name).foregroundStyle(state == .exclude ? .secondary : .primary)
                    .strikethrough(state == .exclude)
                Spacer()
            }
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .accessibilityValue(state == .include ? "Included" : state == .exclude ? "Excluded" : "Off")
    }

    private var icon: String {
        switch state {
        case .ignore: "square"
        case .include: "checkmark.square.fill"
        case .exclude: "xmark.square.fill"
        }
    }

    private var color: Color {
        switch state {
        case .ignore: .secondary
        case .include: .accentColor
        case .exclude: .red
        }
    }
}

/// Tapping the selected option flips its direction, tapping another selects it descending.
private struct SortRows: View {
    let name: String
    let options: [FilterOption]
    @Binding var value: SortValue
    @State private var expanded = false

    var body: some View {
        DisclosureGroup(isExpanded: $expanded) {
            ForEach(options, id: \.value) { option in
                Button {
                    if value.value == option.value { value.ascending.toggle() } else { value = SortValue(value: option.value, ascending: false) }
                } label: {
                    HStack {
                        Image(systemName: value.ascending ? "arrow.up" : "arrow.down")
                            .foregroundStyle(Color.accentColor)
                            .opacity(value.value == option.value ? 1 : 0)
                            .frame(width: 24)
                        Text(option.label)
                        Spacer()
                    }
                    .contentShape(Rectangle())
                }
                .buttonStyle(.plain)
            }
        } label: {
            LabeledContent(name, value: label)
        }
    }

    private var label: String {
        let title = options.first { $0.value == value.value }?.label ?? value.value
        return title + (value.ascending ? " ↑" : " ↓")
    }
}

private struct GroupRows: View {
    let name: String
    let children: [SourceFilter]
    @Binding var values: [String: FilterValue]
    @State private var expanded = false

    var body: some View {
        let count = FilterState(filters: children, values: values).activeCount
        DisclosureGroup(isExpanded: $expanded) {
            FilterRows(filters: children, values: $values)
        } label: {
            HStack {
                Text(name)
                Spacer()
                if count > 0 {
                    Text("\(count)")
                        .font(.caption.bold())
                        .padding(.horizontal, 7)
                        .padding(.vertical, 2)
                        .foregroundStyle(.white)
                        .background(Color.accentColor, in: Capsule())
                }
            }
        }
    }
}

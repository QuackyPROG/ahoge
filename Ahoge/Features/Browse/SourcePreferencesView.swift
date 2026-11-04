import SwiftUI

/// A "Settings" row shown only for a source whose script declares `preferences()` (proposed host API v2).
struct SourcePreferencesLink: View {
    let sourceId: String
    @EnvironmentObject private var sources: SourceManager
    @State private var hasPreferences = false

    var body: some View {
        Group {
            if hasPreferences {
                NavigationLink { SourcePreferencesView(sourceId: sourceId) } label: {
                    Label("Settings", systemImage: "slider.horizontal.3")
                }
            }
        }
        .task { hasPreferences = (try? sources.source(sourceId).hasPreferences) ?? false }
    }
}

/// The form generated from a source's `preferences()` schema: toggles, lists and text fields.
struct SourcePreferencesView: View {
    let sourceId: String
    @EnvironmentObject private var sources: SourceManager
    @State private var schema: [SourcePreference] = []
    @State private var values: [String: SourcePreferenceValue] = [:]
    @State private var error: String?
    @State private var loaded = false

    var body: some View {
        List {
            if let error {
                Label(error, systemImage: "exclamationmark.triangle").foregroundStyle(.orange).themedRows()
            }
            ForEach(schema.filter { $0.kind != .unsupported }) { item in
                Section {
                    row(item)
                } footer: {
                    if let summary = item.summary { Text(summary) }
                }
                .themedRows()
            }
        }
        .overlay { if !loaded { ProgressView() } }
        .navigationTitle(sources.installed(sourceId)?.name ?? "Settings")
        .navigationBarTitleDisplayMode(.inline)
        .themedScreen()
        .task {
            guard !loaded else { return }
            values = SourcePreferenceStore.values(for: sourceId)
            do {
                schema = try await sources.source(sourceId).preferences()
            } catch {
                self.error = error.localizedDescription
            }
            loaded = true
        }
    }

    @ViewBuilder
    private func row(_ item: SourcePreference) -> some View {
        switch item.kind {
        case .toggle:
            Toggle(item.title, isOn: Binding<Bool>(
                get: { if case .bool(let on) = current(item) { return on } else { return false } },
                set: { save(.bool($0), item) }
            ))
        case .list:
            Picker(item.title, selection: Binding<String>(
                get: { if case .string(let value) = current(item) { return value } else { return "" } },
                set: { save(.string($0), item) }
            )) {
                ForEach(item.options, id: \.value) { Text($0.title).tag($0.value) }
            }
        case .text:
            TextField(item.title, text: Binding<String>(
                get: { if case .string(let value) = current(item) { return value } else { return "" } },
                set: { save(.string($0), item) }
            ))
            .autocorrectionDisabled()
            .textInputAutocapitalization(.never)
        case .unsupported:
            EmptyView()
        }
    }

    private func current(_ item: SourcePreference) -> SourcePreferenceValue? {
        values[item.key] ?? item.defaultValue
    }

    private func save(_ value: SourcePreferenceValue, _ item: SourcePreference) {
        values[item.key] = value
        SourcePreferenceStore.set(value, for: item.key, sourceId: sourceId)
        sources.preferencesChanged(sourceId)
    }
}

// Modified for Ahoge from an Apache-2.0-licensed prior implementation.
// See THIRD_PARTY_NOTICES.md for attribution and license information.

import SwiftUI

struct ReaderSettingsView: View {
    @EnvironmentObject private var model: AppModel
    @Environment(\.dismiss) private var dismiss

    var body: some View {
        NavigationStack {
            Form {
                Section {
                    Picker("Reading mode", selection: Binding(
                        get: { model.state.readerPreferences.mode },
                        set: model.setReaderMode
                    )) {
                        ForEach(ReaderMode.allCases) { mode in
                            Text(mode.title).tag(mode)
                        }
                    }

                    Picker("Wide pages", selection: Binding(
                        get: { model.state.readerPreferences.spreadBehavior },
                        set: model.setReaderSpreadBehavior
                    )) {
                        ForEach(ReaderSpreadBehavior.allCases) { behavior in
                            Text(behavior.title).tag(behavior)
                        }
                    }

                    Picker("Orientation", selection: Binding(
                        get: { model.state.readerPreferences.orientation },
                        set: model.setReaderOrientation
                    )) {
                        ForEach(ReaderOrientation.allCases) { orientation in
                            Text(orientation.rawValue.capitalized).tag(orientation)
                        }
                    }
                } header: {
                    Label("Reading", systemImage: "book.pages")
                } footer: {
                    Text("Wide-page handling applies to paged reading modes.")
                }

                Section {
                    Toggle("Show page number", isOn: Binding(
                        get: { model.state.readerPreferences.showPageNumber },
                        set: model.setReaderPageNumberVisible
                    ))
                    Toggle("Keep screen awake", isOn: Binding(
                        get: { model.state.readerPreferences.keepAwake },
                        set: model.setKeepAwake
                    ))
                } header: {
                    Label("Controls", systemImage: "slider.horizontal.3")
                }

                Section {
                    Toggle("Enable color filter", isOn: Binding(
                        get: { model.state.readerPreferences.colorFilter.enabled },
                        set: model.setColorFilterEnabled
                    ))

                    VStack(alignment: .leading, spacing: 8) {
                        LabeledContent("Grayscale", value: model.state.readerPreferences.colorFilter.grayscale.formatted(.percent.precision(.fractionLength(0))))
                        Slider(value: Binding(
                            get: { model.state.readerPreferences.colorFilter.grayscale },
                            set: model.setColorFilterGrayscale
                        ), in: 0...1)
                    }

                    VStack(alignment: .leading, spacing: 8) {
                        LabeledContent("Dimming", value: model.state.readerPreferences.colorFilter.dimming.formatted(.percent.precision(.fractionLength(0))))
                        Slider(value: Binding(
                            get: { model.state.readerPreferences.colorFilter.dimming },
                            set: model.setColorFilterDimming
                        ), in: 0...1)
                    }
                } header: {
                    Label("Page Appearance", systemImage: "circle.lefthalf.filled")
                }
            }
            .navigationTitle("Reader Settings")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .confirmationAction) {
                    Button("Done") { dismiss() }
                }
            }
        }
    }
}

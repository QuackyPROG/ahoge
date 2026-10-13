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
                    VStack(alignment: .leading, spacing: 8) {
                        Text("Make the page yours").font(.title2.weight(.bold))
                        Text("Reading direction, page layout and appearance.")
                            .font(.subheadline).foregroundStyle(.secondary)
                    }.padding(.vertical, 8)
                }
                Section {
                    Picker("Reading mode", selection: Binding(
                        get: { model.state.readerPreferences.mode },
                        set: model.setReaderMode
                    )) {
                        ForEach(ReaderMode.allCases) { mode in
                            Text(mode.title).tag(mode)
                        }
                    }

                } header: {
                    Label("Reading direction", systemImage: "book.pages")
                } footer: {
                    Text("Choose paged reading, vertical scrolling, or continuous webtoon pages.")
                }

                Section {
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
                    Label("Page layout", systemImage: "rectangle.split.1x2")
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
                    Label("While reading", systemImage: "slider.horizontal.3")
                } footer: {
                    Text("Controls can be shown or hidden while the chapter remains on screen.")
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
                        .accessibilityLabel("Grayscale")
                    }

                    VStack(alignment: .leading, spacing: 8) {
                        LabeledContent("Dimming", value: model.state.readerPreferences.colorFilter.dimming.formatted(.percent.precision(.fractionLength(0))))
                        Slider(value: Binding(
                            get: { model.state.readerPreferences.colorFilter.dimming },
                            set: model.setColorFilterDimming
                        ), in: 0...1)
                        .accessibilityLabel("Dimming")
                    }
                } header: {
                    Label("Page Appearance", systemImage: "circle.lefthalf.filled")
                } footer: {
                    Text("The color filter adjusts chapter pages without changing the original images.")
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

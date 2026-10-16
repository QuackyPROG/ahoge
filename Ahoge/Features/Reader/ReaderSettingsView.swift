// Modified for Ahoge from an Apache-2.0-licensed prior implementation.
// See THIRD_PARTY_NOTICES.md for attribution and license information.

import SwiftUI

struct ReaderSettingsView: View {
    @EnvironmentObject private var model: AppModel
    @Environment(\.dismiss) private var dismiss

    private func parityBinding<Value>(_ keyPath: WritableKeyPath<ReaderParityPreferences, Value>) -> Binding<Value> {
        Binding(get: { model.state.readerPreferences.parity[keyPath: keyPath] }, set: { value in
            var preferences = model.state.readerPreferences.parity
            preferences[keyPath: keyPath] = value
            model.setReaderParityPreferences(preferences)
        })
    }

    let focusSetting: String?
    init(focusSetting: String? = nil) { self.focusSetting = focusSetting }

    var body: some View {
        ScrollViewReader { proxy in
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
                    .id("reader.mode")

                } header: {
                    Label("Reading direction", systemImage: "book.pages")
                } footer: {
                    Text("Choose paged reading, vertical scrolling, or continuous webtoon pages.")
                }

                Section {
                    Picker("Dual-page display", selection: parityBinding(\.dualPageDisplay)) {
                        ForEach(ReaderDualPageDisplay.allCases) { Text($0.title).tag($0) }
                    }
                    Toggle("First page alone", isOn: parityBinding(\.firstPageAlone))
                    if !ReaderDualPageDisplay.always.enabled(mode: model.state.readerPreferences.mode, viewport: nil) {
                        Text("Dual-page display is available in horizontal paged reading.")
                            .font(.footnote).foregroundStyle(.secondary)
                    }
                    Picker("Wide pages", selection: Binding(
                        get: { model.state.readerPreferences.spreadBehavior },
                        set: model.setReaderSpreadBehavior
                    )) {
                        ForEach(ReaderSpreadBehavior.allCases) { behavior in
                            Text(behavior.title).tag(behavior)
                        }
                    }
                    .id("reader.spread")

                    Picker("Orientation", selection: Binding(
                        get: { model.state.readerPreferences.orientation },
                        set: model.setReaderOrientation
                    )) {
                        ForEach(ReaderOrientation.allCases) { orientation in
                            Text(orientation.rawValue.capitalized).tag(orientation)
                        }
                    }
                    .id("reader.orientation")
                } header: {
                    Label("Page layout", systemImage: "rectangle.split.1x2")
                } footer: {
                    Text("Split halves and rotation apply to paged and continuous reading. Orientation follows iOS window and multitasking support.")
                }

                Section("Page appearance and navigation") {
                    Picker("Image scale", selection: parityBinding(\.scale)) {
                        ForEach(ReaderScale.allCases) { Text($0.title).tag($0) }
                    }
                    .id("reader.scale")
                    Picker("Zoom start", selection: parityBinding(\.zoomStart)) {
                        ForEach(ReaderZoomStart.allCases) { Text($0.rawValue.capitalized).tag($0) }
                    }
                    .id("reader.zoomStart")
                    Picker("Tap navigation", selection: parityBinding(\.tapNavigation)) {
                        ForEach(ReaderTapNavigation.allCases) { Text($0.title).tag($0) }
                    }
                    .id("reader.tapNavigation")
                    Toggle("Invert horizontal taps", isOn: parityBinding(\.invertHorizontalTaps))
                    .id("reader.invertHorizontalTaps")
                    Toggle("Invert vertical taps", isOn: parityBinding(\.invertVerticalTaps))
                    .id("reader.invertVerticalTaps")
                    Toggle("Animate page transitions", isOn: parityBinding(\.animatePages))
                    .id("reader.animatePages")
                    Picker("Background", selection: parityBinding(\.background)) {
                        ForEach(ReaderBackground.allCases) { Text($0.rawValue.capitalized).tag($0) }
                    }
                    .id("reader.background")
                    Toggle("Crop uniform borders", isOn: parityBinding(\.cropBorders))
                    .id("reader.cropBorders")
                    Toggle("Reverse split halves", isOn: parityBinding(\.invertSplitOrder))
                    .id("reader.invertSplitOrder")
                    Toggle("Rotate unsplit wide pages", isOn: parityBinding(\.rotateWidePages))
                    .id("reader.rotateWidePages")
                    Toggle("Rotate clockwise", isOn: parityBinding(\.rotateClockwise))
                        .disabled(!model.state.readerPreferences.parity.rotateWidePages)
                        .id("reader.rotateClockwise")
                    Toggle("Fullscreen", isOn: parityBinding(\.fullscreen))
                    .id("reader.fullscreen")
                }
                Section("Continuous reading") {
                    LabeledContent("Long strip page gap", value: "\(Int(model.state.readerPreferences.parity.continuousGap)) pt")
                    Slider(value: parityBinding(\.continuousGap), in: 0...64, step: 2)
                    .id("reader.continuousGap")
                    LabeledContent("Webtoon page gap", value: "\(Int(model.state.readerPreferences.parity.webtoonGap)) pt")
                    Slider(value: parityBinding(\.webtoonGap), in: 0...64, step: 2)
                    .id("reader.webtoonGap")
                    LabeledContent("Side padding", value: "\(Int(model.state.readerPreferences.parity.sidePadding))%")
                    Slider(value: parityBinding(\.sidePadding), in: 0...25, step: 1)
                    .id("reader.sidePadding")
                    Toggle("Double tap to zoom", isOn: parityBinding(\.doubleTapZoom))
                    .id("reader.doubleTapZoom")
                    Toggle("Allow zoom below fitted size", isOn: parityBinding(\.allowZoomOut))
                    .id("reader.allowZoomOut")
                }
                Section {
                    Toggle("Show page number", isOn: Binding(
                        get: { model.state.readerPreferences.showPageNumber },
                        set: model.setReaderPageNumberVisible
                    ))
                    .id("reader.showPageNumber")
                    Toggle("Keep screen awake", isOn: Binding(
                        get: { model.state.readerPreferences.keepAwake },
                        set: model.setKeepAwake
                    ))
                    .id("reader.keepAwake")
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
                    .id("reader.colorFilter")

                    VStack(alignment: .leading, spacing: 8) {
                        LabeledContent("Grayscale", value: model.state.readerPreferences.colorFilter.grayscale.formatted(.percent.precision(.fractionLength(0))))
                        Slider(value: Binding(
                            get: { model.state.readerPreferences.colorFilter.grayscale },
                            set: model.setColorFilterGrayscale
                        ), in: 0...1)
                        .accessibilityLabel("Grayscale")
                        .id("reader.grayscale")
                    }

                    VStack(alignment: .leading, spacing: 8) {
                        LabeledContent("Dimming", value: model.state.readerPreferences.colorFilter.dimming.formatted(.percent.precision(.fractionLength(0))))
                        Slider(value: Binding(
                            get: { model.state.readerPreferences.colorFilter.dimming },
                            set: model.setColorFilterDimming
                        ), in: 0...1)
                        .accessibilityLabel("Dimming")
                        .id("reader.dimming")
                    }
                } header: {
                    Label("Page Appearance", systemImage: "circle.lefthalf.filled")
                } footer: {
                    Text("The color filter adjusts chapter pages without changing the original images.")
                }
            }
            .task(id: focusSetting) {
                if let focusSetting { proxy.scrollTo(focusSetting, anchor: .center) }
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

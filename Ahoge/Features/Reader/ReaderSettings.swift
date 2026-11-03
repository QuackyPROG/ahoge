import SwiftUI

/// How pages are laid out, chosen per manga (Mihon's "reading mode").
enum ReadingMode: String, CaseIterable, Identifiable {
    case webtoon, leftToRight, rightToLeft, vertical

    var id: String { rawValue }

    var title: String {
        switch self {
        case .webtoon: "Webtoon"
        case .leftToRight: "Paged (left to right)"
        case .rightToLeft: "Paged (right to left)"
        case .vertical: "Paged (vertical)"
        }
    }

    var icon: String {
        switch self {
        case .webtoon: "rectangle.split.1x2"
        case .leftToRight: "arrow.right.square"
        case .rightToLeft: "arrow.left.square"
        case .vertical: "arrow.down.square"
        }
    }

    var isPaged: Bool { self != .webtoon }

    private static let defaultKey = Pref.readerMode.name
    private static func key(_ mangaKey: String) -> String { "reader.mode\n" + mangaKey }

    static var preferred: ReadingMode {
        get { UserDefaults.standard.string(forKey: defaultKey).flatMap(ReadingMode.init) ?? .webtoon }
        set { UserDefaults.standard.set(newValue.rawValue, forKey: defaultKey) }
    }

    /// The manga's own mode, or the default when it has none.
    static func load(for mangaKey: String) -> ReadingMode {
        UserDefaults.standard.string(forKey: key(mangaKey)).flatMap(ReadingMode.init) ?? preferred
    }

    func save(for mangaKey: String) { UserDefaults.standard.set(rawValue, forKey: Self.key(mangaKey)) }
}

enum ReaderBackground: String, CaseIterable, Identifiable {
    case black, gray, white

    var id: String { rawValue }
    var title: String { rawValue.capitalized }

    var color: Color {
        switch self {
        case .black: .black
        case .gray: Color(white: 0.13)
        case .white: .white
        }
    }

    /// Text drawn straight on the background (chapter transitions, placeholders).
    var foreground: Color { self == .white ? .black : .white }
}

struct ReaderSettingsSheet: View {
    @Binding var mode: ReadingMode
    @Binding var orientation: ReaderOrientation
    @AppStorage(Pref.readerBackground.name) private var background = ReaderBackground.black
    @AppStorage(Pref.readerShowPageNumber.name) private var showPageNumber = true
    @AppStorage(Pref.readerKeepScreenOn.name) private var keepScreenOn = true
    @AppStorage(Pref.readerShowModeToast.name) private var showModeOnOpen = true
    @AppStorage(Pref.readerDrawUnderCutout.name) private var drawUnderCutout = true
    @AppStorage(Pref.readerAlwaysShowTransition.name) private var alwaysShowTransition = true
    @AppStorage(Pref.readerBrightness.name) private var brightness = 0
    @AppStorage(Pref.readerColorFilter.name) private var colorFilter = false
    @AppStorage(Pref.readerColorFilterColor.name) private var colorFilterColor = Pref.readerColorFilterColor.defaultValue
    @AppStorage(Pref.readerColorFilterMode.name) private var colorFilterMode = ColorFilterMode.normal
    @AppStorage(Pref.readerGrayscale.name) private var grayscale = false
    @AppStorage(Pref.readerInvertColors.name) private var invertColors = false
    @AppStorage(Pref.readerScaleType.name) private var scaleType = ReaderScaleType.fitScreen
    @AppStorage(Pref.readerZoomStart.name) private var zoomStart = ReaderZoomStart.auto
    @AppStorage(Pref.readerCropBordersPaged.name) private var cropPaged = false
    @AppStorage(Pref.readerWidePages.name) private var widePages = WidePageMode.off
    @AppStorage(Pref.readerInvertSplit.name) private var invertSplit = false
    @AppStorage(Pref.readerDualPage.name) private var dualPage = DualPageMode.off
    @AppStorage(Pref.readerTapLayout.name) private var tapLayout = TapZoneLayout.standard
    @AppStorage(Pref.readerInvertTaps.name) private var invertTaps = false
    @AppStorage(Pref.readerShowTapZones.name) private var showTapZones = true
    @AppStorage(Pref.readerDoubleTapZoom.name) private var doubleTapZoom = true
    @AppStorage(Pref.readerDoubleTapSpeed.name) private var doubleTapSpeed = 1
    @AppStorage(Pref.readerDisableZoomOut.name) private var disableZoomOut = false
    @AppStorage(Pref.readerWebtoonPadding.name) private var webtoonPadding = 0.0
    @AppStorage(Pref.readerWebtoonGap.name) private var webtoonGap = false
    @AppStorage(Pref.readerCropBordersWebtoon.name) private var cropWebtoon = false
    @AppStorage(Pref.readerHideMenuOnScroll.name) private var hideMenuOnScroll = 2
    @AppStorage(Pref.readerSkipRead.name) private var skipRead = false
    @AppStorage(Pref.readerSkipFiltered.name) private var skipFiltered = true
    @AppStorage(Pref.readerSkipDuplicates.name) private var skipDuplicates = false
    @AppStorage(Pref.readerPreloadOnlyOnWiFi.name) private var preloadOnlyOnWiFi = false
    @Environment(\.dismiss) private var dismiss

    var body: some View {
        NavigationStack {
            Form {
                modeSection
                displaySection
                colourSection
                if mode.isPaged { pagedSection } else { webtoonSection }
                readingSection
            }
            .navigationTitle("Reader settings")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar { ToolbarItem(placement: .confirmationAction) { Button("Done") { dismiss() } } }
        }
        .presentationDetents([.medium, .large])
        .presentationDragIndicator(.visible)
        .presentationBackground(.regularMaterial)
        .preferredColorScheme(.dark)
    }

    private var modeSection: some View {
        Section("This series") {
            Picker("Reading mode", selection: $mode) {
                ForEach(ReadingMode.allCases) { Label($0.title, systemImage: $0.icon).tag($0) }
            }
            Picker("Rotation", selection: $orientation) {
                ForEach(ReaderOrientation.allCases) { Text($0.title).tag($0) }
            }
            Button("Use for new series") {
                ReadingMode.preferred = mode
                ReaderOrientation.preferred = orientation
            }
            .disabled(ReadingMode.preferred == mode && ReaderOrientation.preferred == orientation)
        }
    }

    private var displaySection: some View {
        Section("Display") {
            Picker("Background", selection: $background) {
                ForEach(ReaderBackground.allCases) { Text($0.title).tag($0) }
            }
            .pickerStyle(.segmented)
            Toggle("Show page number", isOn: $showPageNumber)
            Toggle("Keep screen on", isOn: $keepScreenOn)
            Toggle("Show reading mode on open", isOn: $showModeOnOpen)
            Toggle("Draw under the notch", isOn: $drawUnderCutout)
            Toggle("Always show chapter transition", isOn: $alwaysShowTransition)
        }
    }

    private var colourSection: some View {
        Section {
            LabeledContent("Brightness") {
                HStack {
                    Slider(value: Binding(get: { Double(brightness) }, set: { brightness = Int($0.rounded()) }), in: -75...100, step: 1)
                    Text(brightness == 0 ? "Off" : "\(brightness)")
                        .monospacedDigit()
                        .frame(minWidth: 34, alignment: .trailing)
                }
            }
            Toggle("Colour filter", isOn: $colorFilter)
            if colorFilter {
                ColorPicker("Filter colour", selection: Binding(get: { FilterColor.color(colorFilterColor) }, set: { colorFilterColor = FilterColor.argb($0) }))
                Picker("Blend mode", selection: $colorFilterMode) {
                    ForEach(ColorFilterMode.allCases) { Text($0.title).tag($0) }
                }
            }
            Toggle("Grayscale", isOn: $grayscale)
            Toggle("Invert colours", isOn: $invertColors)
        } header: {
            Text("Brightness and colour")
        } footer: {
            Text("Below zero dims the pages. Above zero sets the screen brightness until the reader closes.")
        }
    }

    private var pagedSection: some View {
        Section {
            Picker("Scale type", selection: $scaleType) {
                ForEach(ReaderScaleType.allCases) { Text($0.title).tag($0) }
            }
            Picker("Zoom start position", selection: $zoomStart) {
                ForEach(ReaderZoomStart.allCases) { Text($0.title).tag($0) }
            }
            Toggle("Crop borders", isOn: $cropPaged)
            Picker("Wide pages", selection: $widePages) {
                ForEach(WidePageMode.allCases) { Text($0.title).tag($0) }
            }
            if widePages == .split {
                Toggle("Invert split order", isOn: $invertSplit)
            }
            if mode != .vertical {
                Picker("Dual page view", selection: $dualPage) {
                    ForEach(DualPageMode.allCases) { Text($0.title).tag($0) }
                }
            }
            Picker("Tap zones", selection: $tapLayout) {
                ForEach(TapZoneLayout.allCases) { Text($0.title).tag($0) }
            }
            if tapLayout != .disabled {
                Toggle("Invert tap zones", isOn: $invertTaps)
                Toggle("Show tap zones on open", isOn: $showTapZones)
            }
            Toggle("Double tap to zoom", isOn: $doubleTapZoom)
            if doubleTapZoom {
                Picker("Double tap animation", selection: $doubleTapSpeed) {
                    Text("None").tag(0)
                    Text("Normal").tag(1)
                    Text("Fast").tag(2)
                }
            }
            Toggle("Disable zoom out", isOn: $disableZoomOut)
        } header: {
            Text("Paged")
        } footer: {
            Text("Pinch to zoom. Dual page view keeps wide pages on their own.")
        }
    }

    private var webtoonSection: some View {
        Section("Webtoon") {
            Picker("Side padding", selection: $webtoonPadding) {
                ForEach([0.0, 0.05, 0.1, 0.15, 0.2, 0.25], id: \.self) { Text($0.formatted(.percent)).tag($0) }
            }
            Toggle("Gap between pages", isOn: $webtoonGap)
            Toggle("Crop borders", isOn: $cropWebtoon)
            Picker("Hide menu on scroll", selection: $hideMenuOnScroll) {
                Text("Off").tag(0)
                Text("Low sensitivity").tag(1)
                Text("Medium sensitivity").tag(2)
                Text("High sensitivity").tag(3)
            }
        }
    }

    private var readingSection: some View {
        Section {
            Toggle("Skip read chapters", isOn: $skipRead)
            Toggle("Skip filtered chapters", isOn: $skipFiltered)
            Toggle("Skip duplicate chapters", isOn: $skipDuplicates)
            Toggle("Preload only on Wi-Fi", isOn: $preloadOnlyOnWiFi)
        } header: {
            Text("Reading")
        } footer: {
            Text("Skip rules apply the next time the reader opens. Duplicates are chapters with the same number from another group.")
        }
    }
}

enum PerSeriesReaderSettings {
    /// Forgets every series' own reading mode and orientation, so each follows the defaults again.
    @discardableResult
    static func reset(in defaults: UserDefaults = .standard) -> Int {
        let keys = defaults.dictionaryRepresentation().keys.filter { $0.hasPrefix("reader.mode\n") || $0.hasPrefix("reader.orientation\n") }
        for key in keys { defaults.removeObject(forKey: key) }
        return keys.count
    }
}

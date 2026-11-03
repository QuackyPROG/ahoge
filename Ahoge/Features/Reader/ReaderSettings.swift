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
    @AppStorage(Pref.readerBackground.name) private var background = ReaderBackground.black
    @AppStorage(Pref.readerShowPageNumber.name) private var showPageNumber = true
    @AppStorage(Pref.readerKeepScreenOn.name) private var keepScreenOn = true
    @AppStorage(Pref.readerDim.name) private var dim = 0.0
    @AppStorage(Pref.readerTapZones.name) private var tapZones = true
    @AppStorage(Pref.readerInvertTaps.name) private var invertTaps = false
    @AppStorage(Pref.readerWebtoonPadding.name) private var webtoonPadding = 0.0
    @AppStorage(Pref.readerWebtoonGap.name) private var webtoonGap = false
    @Environment(\.dismiss) private var dismiss

    var body: some View {
        NavigationStack {
            Form {
                Section("Reading mode") {
                    Picker("This series", selection: $mode) {
                        ForEach(ReadingMode.allCases) { Label($0.title, systemImage: $0.icon).tag($0) }
                    }
                    Button("Use for new series") { ReadingMode.preferred = mode }
                        .disabled(ReadingMode.preferred == mode)
                }
                Section("Display") {
                    Picker("Background", selection: $background) {
                        ForEach(ReaderBackground.allCases) { Text($0.title).tag($0) }
                    }
                    .pickerStyle(.segmented)
                    Toggle("Show page number", isOn: $showPageNumber)
                    Toggle("Keep screen on", isOn: $keepScreenOn)
                    LabeledContent("Dim") {
                        Slider(value: $dim, in: 0...0.8)
                    }
                }
                if mode.isPaged {
                    Section {
                        Toggle("Tap zones", isOn: $tapZones)
                        Toggle("Invert tap zones", isOn: $invertTaps).disabled(!tapZones)
                    } header: {
                        Text("Paged")
                    } footer: {
                        Text("Tap the edges to turn pages and the middle for the menu. Double tap or pinch to zoom.")
                    }
                } else {
                    Section("Webtoon") {
                        Picker("Side padding", selection: $webtoonPadding) {
                            ForEach([0.0, 0.05, 0.1, 0.15, 0.2, 0.25], id: \.self) { Text($0.formatted(.percent)).tag($0) }
                        }
                        Toggle("Gap between pages", isOn: $webtoonGap)
                    }
                }
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
}

import Foundation

/// Which repository sources to show by their 18+ flag (`nsfw` in the repository index).
enum ContentFilter: String, CaseIterable, Identifiable {
    /// Every source, 18+ ones marked.
    case all
    /// Hides sources the index marks 18+.
    case safe
    /// Only sources the index marks 18+.
    case adult

    var id: String { rawValue }

    var title: String {
        switch self {
        case .all: "All sources"
        case .safe: "Hide 18+ sources"
        case .adult: "Only 18+ sources"
        }
    }

    func allows(nsfw: Bool) -> Bool {
        switch self {
        case .all: true
        case .safe: !nsfw
        case .adult: nsfw
        }
    }
}

/// The Sources filter screen's choices: disabled sources and languages and the content filter.
/// Hidden sources stay installed; they leave Sources and global search only.
struct SourceVisibility: Equatable {
    var disabledSources: Set<String> = []
    var disabledLanguages: Set<String> = []
    var content = ContentFilter.all

    static func current(in defaults: UserDefaults = .standard) -> SourceVisibility {
        SourceVisibility(
            disabledSources: Set(Pref.disabledSources.value(in: defaults)),
            disabledLanguages: Set(Pref.disabledLanguages.value(in: defaults)),
            content: ContentFilter(rawValue: Pref.browseContentFilter.value(in: defaults)) ?? .all
        )
    }

    func shows(_ source: InstalledSource) -> Bool {
        !disabledSources.contains(source.id) && !disabledLanguages.contains(source.lang) && content.allows(nsfw: source.nsfw)
    }
}

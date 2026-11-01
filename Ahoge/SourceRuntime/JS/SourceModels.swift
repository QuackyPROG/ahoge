import Foundation

struct MangaStub: Codable, Hashable {
    let url: String
    let title: String
    let cover: String

    init(url: String, title: String, cover: String) {
        self.url = url
        self.title = title
        self.cover = cover
    }

    init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        url = try c.decode(String.self, forKey: .url)
        title = try c.decodeIfPresent(String.self, forKey: .title) ?? ""
        cover = try c.decodeIfPresent(String.self, forKey: .cover) ?? ""
    }
}

struct MangaListPage: Codable {
    let manga: [MangaStub]
    let hasNextPage: Bool
}

struct MangaDetails: Codable, Equatable {
    let title: String
    let cover: String
    let author: String
    let artist: String
    let description: String
    let genres: [String]
    let status: String

    init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        title = try c.decodeIfPresent(String.self, forKey: .title) ?? ""
        cover = try c.decodeIfPresent(String.self, forKey: .cover) ?? ""
        author = try c.decodeIfPresent(String.self, forKey: .author) ?? ""
        artist = try c.decodeIfPresent(String.self, forKey: .artist) ?? ""
        description = try c.decodeIfPresent(String.self, forKey: .description) ?? ""
        genres = try c.decodeIfPresent([String].self, forKey: .genres) ?? []
        status = try c.decodeIfPresent(String.self, forKey: .status) ?? "unknown"
    }
}

struct SourceChapter: Codable, Hashable {
    let url: String
    let name: String
    let number: Double
    /// Milliseconds since the epoch.
    let date: Double?
    let scanlator: String?
}

struct SourcePage: Codable, Hashable {
    let url: String
    let headers: [String: String]
}

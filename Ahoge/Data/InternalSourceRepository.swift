// Modified for Ahoge from an Apache-2.0-licensed prior implementation.
// See THIRD_PARTY_NOTICES.md for attribution and license information.

//
//  InternalSourceRepository.swift
//  Ahoge
//

import Foundation

/// Minimal built-in fallback used only for local reader files.
/// Remote manga sources are intentionally not bundled; they must be imported
/// through Source Repositories so source configuration can evolve separately
/// from the app binary.
struct InternalSourceRepository: SourceRepository {
    private let sourcesData: [Source]
    private let descriptorData: [SourceDescriptor]

    init(now: Date = .now) {
        _ = now

        let local = Source(
            id: "local-files",
            name: "Local Files",
            kind: .local,
            engineFamily: .local,
            summary: "Local source entry point for CBZ, EPUB, ZIP, and imported reader files.",
            systemImage: "internaldrive",
            language: .multi,
            isEnabled: true,
            isPinned: false,
            allowsAdultContent: false
        )

        self.sourcesData = [local]
        self.descriptorData = [
            Self.makeDescriptor(
                for: local,
                capabilities: [.mangaDetail, .chapterList, .pageList, .reader],
                featureFlags: ["local-content"]
            )
        ]
    }

    func sources() -> [Source] {
        sourcesData
    }

    func descriptors() -> [SourceDescriptor] {
        descriptorData
    }

    func descriptor(for sourceID: String) -> SourceDescriptor? {
        descriptorData.first { $0.sourceID == sourceID }
    }

    func mangas(for sourceID: String) -> [Manga] {
        []
    }

    func chapters(for mangaID: String) -> [Chapter] {
        []
    }

    func activeSources() -> [Source] {
        sourcesData.filter(\.isEnabled)
    }

    func popularManga(sourceID: String) async throws -> [Manga] {
        []
    }

    func latestManga(sourceID: String) async throws -> [Manga] {
        []
    }

    func searchManga(sourceID: String, query: String, filters: [SourceFilterValue]) async throws -> [Manga] {
        []
    }

    func mangaDetails(sourceID: String, mangaIDOrURL: String) async throws -> SourceMangaDetails {
        throw NSError(
            domain: "InternalSourceRepository",
            code: 404,
            userInfo: [NSLocalizedDescriptionKey: "Manga not found in local fallback"]
        )
    }

    func chapters(sourceID: String, manga: Manga) async throws -> SourceChapterDetails {
        SourceChapterDetails(chapters: [])
    }

    func pages(sourceID: String, chapter: Chapter) async throws -> SourcePageAsset {
        SourcePageAsset(pages: chapter.pages, errorMessage: nil)
    }

    func genreTags(sourceID: String) async throws -> [GenreTag] {
        []
    }

    private static func makeDescriptor(
        for source: Source,
        capabilities: Set<SourceCapability>,
        featureFlags: [String]
    ) -> SourceDescriptor {
        SourceDescriptor(
            id: "descriptor::\(source.id)",
            sourceID: source.id,
            name: source.name,
            engineFamily: source.engineFamily,
            kind: source.kind,
            language: source.language,
            baseURL: nil,
            capabilities: capabilities,
            featureFlags: featureFlags,
            overrides: [:],
            context: nil,
            filterSchema: [],
            preferenceSchema: [
                SourcePreferenceSchema(
                    id: "\(source.id)-family",
                    title: "Engine Family",
                    detail: source.engineFamily.title
                )
            ],
            packageName: nil,
            version: nil,
            languageCode: nil,
            origin: "built-in-local",
            supportStatus: .unsupported
        )
    }
}

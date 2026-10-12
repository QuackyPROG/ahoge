// Modified for Ahoge from an Apache-2.0-licensed prior implementation.
// See THIRD_PARTY_NOTICES.md for attribution and license information.

//
//  SourceRepoImporter.swift
//  Ahoge
//

import Foundation

/// Classifies legacy Keiyoushi-style repository entries that do not declare an
/// iOS-native engine explicitly. New Quacky manifests should provide `engine`
/// and, where needed, `adapter` in the source object.
struct SourceFamilyClassifier {
    private struct OverrideProfile {
        let overrides: [String: String]
        let additionalFlags: [String]
    }

    private let explicitFamilyBySlug: [String: SourceEngineFamily] = [
        "asurascans": .asuraScans,
        "mangabat": .mangaBox,
        "manganato": .mangaBox,
        "komikindoid": .komikIndoID,
    ]

    private let coverageBySlug: [String: SourceEngineFamily]
    private let coverageByLanguageAndSlug: [String: SourceEngineFamily]

    private let knownProfilesBySlug: [String: OverrideProfile] = [
        "kiryuu": OverrideProfile(
            overrides: ["chapterListPageOverride": "1"],
            additionalFlags: ["natsuid-v1"]
        ),
        "ainzscansid": OverrideProfile(
            overrides: ["mangaSubPath": "series", "dateFormat": "MMMM dd, yyyy", "hasProjectPage": "true"],
            additionalFlags: ["themesia-series"]
        ),
        "madaradex": OverrideProfile(
            overrides: ["mangaSubPath": "title", "dateFormat": "MMM d, yyyy"],
            additionalFlags: ["madara-title-path"]
        ),
        "asurascans": OverrideProfile(
            overrides: [:],
            additionalFlags: ["source-asura", "asura-2026"]
        ),
        "mangabat": OverrideProfile(
            overrides: ["adapter": "mangabox"],
            additionalFlags: ["family-mangabox"]
        ),
        "manganato": OverrideProfile(
            overrides: ["adapter": "mangabox"],
            additionalFlags: ["family-mangabox"]
        ),
        "komikindoid": OverrideProfile(
            overrides: ["dateFormat": "MMM d, yyyy"],
            additionalFlags: ["source-komikindoid"]
        ),
    ]

    init(fileManager: FileManager = .default, bundle: Bundle = .main) {
        let decoder = JSONDecoder()
        var slugMap: [String: SourceEngineFamily] = [:]
        var scopedMap: [String: SourceEngineFamily] = [:]

        if let coverageURL = Self.coverageURL(fileManager: fileManager, bundle: bundle),
           let data = try? Data(contentsOf: coverageURL),
           let payload = try? decoder.decode(SourceCoveragePayload.self, from: data) {
            for (familyKey, entries) in payload.families {
                guard let family = SourceEngineFamily(rawValue: familyKey) else { continue }
                for entry in entries {
                    slugMap[entry.slug] = family
                    scopedMap["\(entry.language)::\(entry.slug)"] = family
                }
            }
        }

        coverageBySlug = slugMap
        coverageByLanguageAndSlug = scopedMap
    }

    func classify(packageName: String, sourceName: String, languageCode: String, baseURL: String) -> SourceClassificationResult {
        let slug = packageName.split(separator: ".").last.map(String.init) ?? normalizedSlug(sourceName)
        let normalizedLanguage = languageCode.lowercased()

        let family: SourceEngineFamily
        let reason: String

        if let explicit = explicitFamilyBySlug[slug] {
            family = explicit
            reason = "Matched explicit curated runtime mapping."
        } else if let covered = coverageByLanguageAndSlug["\(normalizedLanguage)::\(slug)"] ?? coverageBySlug[slug] {
            family = covered
            reason = "Matched local extension coverage data."
        } else {
            let haystack = "\(packageName) \(sourceName) \(baseURL)".lowercased()
            if haystack.contains("kiryuu") || haystack.contains("natsu") || haystack.contains("mangatale") {
                family = .natsuId
            } else if haystack.contains("madara") {
                family = .madara
            } else if haystack.contains("mangabat") || haystack.contains("manganato") || haystack.contains("natomanga") {
                family = .mangaBox
            } else if haystack.contains("asurascans") || haystack.contains("asuracomic") {
                family = .asuraScans
            } else if haystack.contains("komikindoid") || haystack.contains("komikindo.ch") {
                family = .komikIndoID
            } else if haystack.contains("themesia") || haystack.contains("ainzscans") {
                family = .mangaThemesia
            } else if haystack.contains("zeist") {
                family = .zeistManga
            } else if haystack.contains("fmreader") {
                family = .fmReader
            } else if haystack.contains("foolslide") {
                family = .foolSlide
            } else if haystack.contains("newtoki") {
                family = .newToki
            } else {
                family = .unknown
            }
            reason = family == .unknown
                ? "No family match found from metadata heuristics."
                : "Matched source family from repo metadata heuristics."
        }

        let profile = overrideProfile(for: slug, family: family, baseURL: baseURL)
        return SourceClassificationResult(
            engineFamily: family,
            supportStatus: supportStatus(for: family),
            featureFlags: featureFlags(for: family) + profile.additionalFlags,
            overrides: profile.overrides,
            reason: reason
        )
    }

    private func supportStatus(for family: SourceEngineFamily) -> SourceSupportStatus {
        switch family {
        case .natsuId, .mangaBox, .asuraScans:
            return .live
        case .madara, .mangaThemesia, .komikIndoID, .zeistManga, .fmReader, .foolSlide, .newToki, .customParsed, .api:
            return .planned
        case .internalCatalog, .local, .unknown:
            return .unsupported
        }
    }

    private func featureFlags(for family: SourceEngineFamily) -> [String] {
        switch supportStatus(for: family) {
        case .live: return ["runtime-live", "repo-imported"]
        case .planned: return ["family-scaffold", "repo-imported"]
        case .unsupported: return ["unsupported", "repo-imported"]
        }
    }

    private func defaultOverrides(for family: SourceEngineFamily, slug: String) -> [String: String] {
        switch family {
        case .natsuId:
            return slug == "kiryuu" ? ["chapterListPageOverride": "1"] : [:]
        case .madara:
            return ["mangaSubPath": "manga", "dateFormat": "MMM d, yyyy"]
        case .mangaThemesia:
            return ["mangaSubPath": "series", "dateFormat": "MMMM dd, yyyy", "hasProjectPage": "true"]
        case .newToki:
            return ["dateFormat": "yyyy.MM.dd"]
        default:
            return [:]
        }
    }

    private func overrideProfile(for slug: String, family: SourceEngineFamily, baseURL: String) -> OverrideProfile {
        var overrides = defaultOverrides(for: family, slug: slug)
        var flags: [String] = []
        if let known = knownProfilesBySlug[slug] {
            overrides.merge(known.overrides) { _, new in new }
            flags.append(contentsOf: known.additionalFlags)
        }

        let host = URL(string: baseURL)?.host?.lowercased() ?? ""
        if family == .madara, host.contains("dex") {
            overrides["mangaSubPath"] = "title"
            flags.append("madara-title-path")
        }
        return OverrideProfile(overrides: overrides, additionalFlags: Array(Set(flags)).sorted())
    }

    private func normalizedSlug(_ value: String) -> String {
        value.lowercased().replacingOccurrences(of: "[^a-z0-9]+", with: "", options: .regularExpression)
    }

    private static func coverageURL(fileManager: FileManager, bundle: Bundle) -> URL? {
        let cwdURL = URL(fileURLWithPath: fileManager.currentDirectoryPath)
        let direct = cwdURL.appendingPathComponent("Docs/source-engine-coverage.generated.json")
        if fileManager.fileExists(atPath: direct.path) { return direct }
        return bundle.url(forResource: "source-engine-coverage.generated", withExtension: "json")
    }
}

struct SourceDescriptorFactory {
    func makeImportedSource(recordURL: String, package: SourceRepoPackage, descriptor: ImportedSourceDescriptor) -> (Source, SourceDescriptor) {
        let source = Source(
            id: descriptor.sourceID,
            name: descriptor.name,
            kind: .remote,
            engineFamily: descriptor.engineFamily,
            summary: descriptor.summary,
            systemImage: systemImage(for: descriptor.engineFamily),
            language: descriptor.language,
            isEnabled: descriptor.supportStatus != .unsupported,
            isPinned: false,
            allowsAdultContent: descriptor.allowsAdultContent
        )

        let requestRate = Int(descriptor.overrides["rateLimit"] ?? "") ?? requestRate(for: descriptor.engineFamily)
        let context = SourceRuntimeContext(
            baseURL: descriptor.baseURL,
            language: descriptor.language,
            authMode: .none,
            requestPolicy: SourceRequestPolicy(
                rateLimit: max(requestRate, 1),
                referrer: "\(descriptor.baseURL)/",
                userAgent: SourceEngineUtilities.defaultUserAgent,
                requiresCookies: descriptor.engineFamily == .madara || descriptor.engineFamily == .customParsed
            )
        )

        return (
            source,
            SourceDescriptor(
                id: descriptor.id,
                sourceID: descriptor.sourceID,
                name: descriptor.name,
                engineFamily: descriptor.engineFamily,
                kind: .remote,
                language: descriptor.language,
                baseURL: descriptor.baseURL,
                capabilities: descriptor.capabilities,
                featureFlags: descriptor.featureFlags,
                overrides: descriptor.overrides,
                context: context,
                filterSchema: filterSchema(for: descriptor),
                preferenceSchema: [
                    SourcePreferenceSchema(id: "\(descriptor.sourceID)-package", title: "Package", detail: package.packageName),
                    SourcePreferenceSchema(id: "\(descriptor.sourceID)-repo", title: "Source Link", detail: recordURL),
                ],
                packageName: package.packageName,
                version: package.version,
                languageCode: descriptor.languageCode,
                origin: recordURL,
                supportStatus: descriptor.supportStatus
            )
        )
    }

    private func filterSchema(for descriptor: ImportedSourceDescriptor) -> [SourceFilterSchema] {
        guard descriptor.capabilities.contains(.filters) else { return [] }
        return [
            SourceFilterSchema(id: "\(descriptor.sourceID)-sort", title: "Sort", kind: "select"),
            SourceFilterSchema(id: "\(descriptor.sourceID)-genre", title: "Genre", kind: "multi-select"),
        ]
    }

    private func systemImage(for family: SourceEngineFamily) -> String {
        switch family {
        case .natsuId: return "text.book.closed"
        case .madara: return "building.columns"
        case .mangaThemesia: return "square.stack.3d.up"
        case .mangaBox: return "books.vertical.circle"
        case .asuraScans: return "bolt.horizontal.circle"
        case .komikIndoID: return "text.book.closed.fill"
        case .zeistManga: return "sparkles.rectangle.stack"
        case .fmReader: return "book.pages"
        case .foolSlide: return "doc.text.image"
        case .newToki: return "rectangle.stack.badge.person.crop"
        case .customParsed: return "network.badge.shield.half.filled"
        case .api: return "network"
        case .internalCatalog: return "sparkle.magnifyingglass"
        case .local: return "internaldrive"
        case .unknown: return "questionmark.app"
        }
    }

    private func requestRate(for family: SourceEngineFamily) -> Int {
        family == .natsuId ? 4 : 2
    }
}

struct SourceRegistryBuilder {
    private let descriptorFactory = SourceDescriptorFactory()

    func build(internalSources: [Source], internalDescriptors: [SourceDescriptor], repoRecords: [SourceRepoRecord]) -> ([Source], [SourceDescriptor]) {
        var sources = internalSources
        var descriptors = internalDescriptors
        var seenKeys = Set(internalDescriptors.map { Self.identityKey(for: $0) })

        for record in repoRecords {
            for package in record.packages {
                for imported in package.sources {
                    let (source, descriptor) = descriptorFactory.makeImportedSource(recordURL: record.url, package: package, descriptor: imported)
                    let key = Self.identityKey(for: descriptor)
                    if seenKeys.contains(key) { continue }
                    sources.append(source)
                    descriptors.append(descriptor)
                    seenKeys.insert(key)
                }
            }
        }
        return (sources, descriptors)
    }

    static func identityKey(_ descriptor: SourceDescriptor) -> String { identityKey(for: descriptor) }
    static func identityKey(for descriptor: SourceDescriptor) -> String {
        "\(descriptor.engineFamily.rawValue)|\((descriptor.baseURL ?? descriptor.sourceID).lowercased())"
    }
}

final class SourceRepoImporter {
    private let session: URLSession
    private let classifier: SourceFamilyClassifier

    init(session: URLSession = .shared, classifier: SourceFamilyClassifier = SourceFamilyClassifier()) {
        self.session = session
        self.classifier = classifier
    }

    func importRepo(from urlString: String) async throws -> SourceRepoRecord {
        let normalizedURL = normalizeURLString(urlString)
        guard let url = repoURL(from: normalizedURL) else { throw SourceRepoImportError.invalidURL }
        let data = try await fetchData(from: url)
        let packages = try decodePackages(from: data, repoURL: normalizedURL)
        guard !packages.isEmpty else { throw SourceRepoImportError.invalidPayload }

        let sourceNames = packages.flatMap(\.sources).map(\.name)
        let title = sourceNames.count == 1 ? (sourceNames.first ?? normalizedURL) : (URL(string: normalizedURL)?.host ?? normalizedURL)
        return SourceRepoRecord(
            id: normalizedURL,
            url: normalizedURL,
            title: title,
            fetchedAt: .now,
            packages: packages,
            importedSources: packages.flatMap(\.sources),
            lastError: nil
        )
    }

    func failedRecord(for urlString: String, error: Error) -> SourceRepoRecord {
        let normalizedURL = normalizeURLString(urlString)
        return SourceRepoRecord(
            id: normalizedURL,
            url: normalizedURL,
            title: URL(string: normalizedURL)?.host ?? normalizedURL,
            fetchedAt: .now,
            packages: [],
            importedSources: [],
            lastError: (error as? LocalizedError)?.errorDescription ?? error.localizedDescription
        )
    }

    func refresh(_ record: SourceRepoRecord) async -> SourceRepoRecord {
        do { return try await importRepo(from: record.url) }
        catch { return failedRecord(for: record.url, error: error) }
    }

    private func normalizeURLString(_ value: String) -> String {
        value.trimmingCharacters(in: .whitespacesAndNewlines)
    }

    private func repoURL(from value: String) -> URL? {
        if let url = URL(string: value), url.scheme != nil { return url }
        let pathURL = URL(fileURLWithPath: value)
        return FileManager.default.fileExists(atPath: pathURL.path) ? pathURL : nil
    }

    private func fetchData(from url: URL) async throws -> Data {
        if url.isFileURL {
            guard let data = try? Data(contentsOf: url) else { throw SourceRepoImportError.unreadablePayload }
            return data
        }
        let (data, response) = try await session.data(from: url)
        guard let http = response as? HTTPURLResponse, (200..<300).contains(http.statusCode) else {
            throw SourceRepoImportError.unreadablePayload
        }
        return data
    }

    /// Accepts all of these forms:
    /// 1. Keiyoushi array: `[package, package]`
    /// 2. Repository object: `{ "packages": [...] }`
    /// 3. Single pasteable package: `{ "name": ..., "pkg": ..., "sources": [...] }`
    private func decodePackages(from data: Data, repoURL: String) throws -> [SourceRepoPackage] {
        guard let json = try? JSONSerialization.jsonObject(with: data),
              let packageObjects = packageObjects(from: json) else {
            throw SourceRepoImportError.invalidPayload
        }

        let repoBaseURL = URL(string: repoURL)
        return packageObjects.compactMap { packageObject in
            guard let name = packageObject["name"] as? String,
                  let packageName = packageObject["pkg"] as? String,
                  let languageCode = packageObject["lang"] as? String,
                  let sourceObjects = packageObject["sources"] as? [[String: Any]] else {
                return nil
            }

            let version = packageObject["version"] as? String ?? "1.0.0"
            let packageApk = normalizedAPKURL(rawValue: packageObject["apk"], repoBaseURL: repoBaseURL)
            let allowsAdultContent = boolValue(packageObject["nsfw"])

            let sources = sourceObjects.compactMap { sourceObject -> ImportedSourceDescriptor? in
                guard let sourceName = sourceObject["name"] as? String,
                      let sourceLanguageCode = sourceObject["lang"] as? String,
                      let baseURL = sourceObject["baseUrl"] as? String else {
                    return nil
                }

                let sourceIDValue = sourceObject["id"].map(String.init(describing:)) ?? normalizedID(sourceName)
                let legacy = classifier.classify(
                    packageName: packageName,
                    sourceName: sourceName,
                    languageCode: sourceLanguageCode,
                    baseURL: baseURL
                )

                let declaredFamily = (sourceObject["engine"] as? String)
                    .flatMap(SourceEngineFamily.init(rawValue:))
                    ?? (sourceObject["family"] as? String).flatMap(SourceEngineFamily.init(rawValue:))
                let family = declaredFamily ?? legacy.engineFamily

                var overrides = legacy.overrides
                if let explicitOverrides = sourceObject["overrides"] as? [String: Any] {
                    for (key, value) in explicitOverrides { overrides[key] = String(describing: value) }
                }
                if let adapter = sourceObject["adapter"] as? String { overrides["adapter"] = adapter }
                if let apiURL = (sourceObject["apiUrl"] as? String) ?? (sourceObject["apiURL"] as? String) {
                    overrides["apiURL"] = apiURL
                }
                if let rateLimit = sourceObject["rateLimit"] { overrides["rateLimit"] = String(describing: rateLimit) }

                let explicitlyRunnable = runtimeIsAvailable(family: family, overrides: overrides)
                let supportStatus: SourceSupportStatus = explicitlyRunnable ? .live : (declaredFamily == nil ? legacy.supportStatus : .planned)
                var flags = legacy.featureFlags
                if declaredFamily != nil { flags.append("native-manifest") }
                if explicitlyRunnable { flags.append("runtime-live") }
                flags.append("repo-imported")
                flags = Array(Set(flags)).sorted()

                return ImportedSourceDescriptor(
                    id: "repo-descriptor::\(packageName)::\(sourceIDValue)",
                    sourceID: "repo::\(packageName)::\(sourceIDValue)",
                    name: sourceName,
                    language: Self.mapLanguage(code: sourceLanguageCode),
                    languageCode: sourceLanguageCode,
                    baseURL: baseURL,
                    packageName: packageName,
                    version: version,
                    allowsAdultContent: boolValue(sourceObject["nsfw"]) || allowsAdultContent,
                    apkURL: packageApk,
                    engineFamily: family,
                    supportStatus: supportStatus,
                    capabilities: Self.capabilities(for: family),
                    featureFlags: flags,
                    overrides: overrides,
                    origin: repoURL,
                    summary: "Native iOS source imported from \(URL(string: repoURL)?.host ?? repoURL)."
                )
            }

            guard !sources.isEmpty else { return nil }
            return SourceRepoPackage(
                id: packageName,
                name: name,
                packageName: packageName,
                apkURL: packageApk,
                languageCode: languageCode,
                version: version,
                allowsAdultContent: allowsAdultContent,
                sources: sources
            )
        }
    }

    private func packageObjects(from json: Any) -> [[String: Any]]? {
        if let items = json as? [[String: Any]] { return items }
        if let root = json as? [String: Any] {
            for key in ["packages", "extensions", "results"] {
                if let items = root[key] as? [[String: Any]] { return items }
            }
            // This is the new copy/paste source-link format: one package per URL.
            if root["pkg"] != nil, root["sources"] != nil { return [root] }
        }
        return nil
    }

    private func runtimeIsAvailable(family: SourceEngineFamily, overrides: [String: String]) -> Bool {
        switch family {
        case .asuraScans, .natsuId, .madara, .mangaThemesia:
            return true
        case .mangaBox:
            return overrides["adapter"] == "mangabox"
        case .api:
            return ["ezmanhwa", "heancms", "mangadex"].contains(overrides["adapter"] ?? "") && overrides["apiURL"] != nil
        default:
            return false
        }
    }

    private func boolValue(_ value: Any?) -> Bool {
        if let bool = value as? Bool { return bool }
        if let int = value as? Int { return int != 0 }
        if let string = value as? String { return ["1", "true", "yes"].contains(string.lowercased()) }
        return false
    }

    private func normalizedID(_ value: String) -> String {
        value.lowercased().replacingOccurrences(of: "[^a-z0-9]+", with: "-", options: .regularExpression)
            .trimmingCharacters(in: CharacterSet(charactersIn: "-"))
    }

    private func normalizedAPKURL(rawValue: Any?, repoBaseURL: URL?) -> String? {
        guard let rawValue else { return nil }
        let value = String(describing: rawValue)
        guard !value.isEmpty else { return nil }
        guard let repoBaseURL else { return value }
        if URL(string: value)?.scheme != nil { return value }
        return repoBaseURL.deletingLastPathComponent().appendingPathComponent(value).absoluteString
    }

    static func mapLanguage(code: String) -> SourceLanguage {
        switch code.lowercased() {
        case "en": return .english
        case "id": return .indonesian
        case "ja", "jp", "ko": return .japanese
        default: return .multi
        }
    }

    static func capabilities(for family: SourceEngineFamily) -> Set<SourceCapability> {
        switch family {
        case .natsuId, .madara, .mangaThemesia, .mangaBox, .asuraScans, .komikIndoID, .newToki, .api:
            return [.popular, .latest, .search, .mangaDetail, .chapterList, .pageList, .filters, .reader]
        case .zeistManga, .fmReader:
            return [.popular, .latest, .search, .mangaDetail, .chapterList, .pageList, .reader]
        case .foolSlide:
            return [.latest, .search, .mangaDetail, .chapterList, .pageList, .reader]
        case .customParsed:
            return [.search, .mangaDetail, .chapterList, .pageList, .reader]
        case .internalCatalog, .local, .unknown:
            return [.search]
        }
    }
}

private struct SourceCoveragePayload: Decodable {
    let families: [String: [SourceCoverageEntry]]
}

private struct SourceCoverageEntry: Decodable {
    let language: String
    let slug: String
}

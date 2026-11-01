import Foundation

/// Repositories, their indexes, and installed source scripts (stored in Application Support).
@MainActor
final class ExtensionStore: ObservableObject {
    static let defaultRepoURL = "https://raw.githubusercontent.com/QuackyPROG/ahoge-extension/repo/index.json"

    private struct State: Codable {
        var repos: [ExtensionRepo] = []
        var installed: [InstalledSource] = []
    }

    @Published private(set) var repos: [ExtensionRepo] = []
    @Published private(set) var installed: [InstalledSource] = []
    @Published private(set) var indexes: [String: RepoIndex] = [:]
    @Published private(set) var lastError: String?
    @Published private(set) var isRefreshing = false

    private let directory: URL
    private let client: RepoClient

    nonisolated static func defaultDirectory() -> URL {
        FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask)[0].appendingPathComponent("Extensions")
    }

    init(directory: URL = ExtensionStore.defaultDirectory(), client: RepoClient = RepoClient(transport: URLSessionTransport.shared)) {
        self.directory = directory
        self.client = client
        load()
    }

    // MARK: Repositories

    func addRepo(_ urlString: String) async throws {
        let url = urlString.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !repos.contains(where: { $0.url == url }) else { throw RepoError.duplicate(url) }
        let index = try await client.fetchIndex(url)
        repos.append(ExtensionRepo(url: url, name: index.name))
        indexes[url] = index
        save()
    }

    func removeRepo(_ url: String) {
        repos.removeAll { $0.url == url }
        indexes[url] = nil
        save()
    }

    /// Re-fetches every repository index; a failing repository keeps its last good index.
    func refresh() async {
        isRefreshing = true
        defer { isRefreshing = false }
        var failures: [String] = []
        for repo in repos {
            do {
                let index = try await client.fetchIndex(repo.url)
                indexes[repo.url] = index
                if let i = repos.firstIndex(of: repo) { repos[i].name = index.name }
            } catch {
                failures.append("\(repo.name): \(error.localizedDescription)")
            }
        }
        lastError = failures.isEmpty ? nil : failures.joined(separator: "\n")
        save()
    }

    // MARK: Sources

    func install(_ source: RepoSource, from repoURL: String) async throws {
        guard source.runtime <= JSHost.runtimeVersion else { throw RepoError.requiresNewerApp(source.id) }
        let data = try await client.downloadScript(for: source, indexURL: repoURL)
        try FileManager.default.createDirectory(at: scriptsDirectory, withIntermediateDirectories: true)
        try data.write(to: scriptURL(source.id), options: .atomic)
        let entry = InstalledSource(
            id: source.id,
            repoURL: repoURL,
            name: source.name,
            lang: source.lang,
            version: source.version,
            nsfw: source.nsfw,
            baseUrl: source.baseUrl,
            iconURL: source.icon.flatMap { RepoClient.resolve($0, indexURL: repoURL) },
            sha256: source.sha256
        )
        installed.removeAll { $0.id == source.id }
        installed.append(entry)
        save()
    }

    func uninstall(_ id: String) {
        try? FileManager.default.removeItem(at: scriptURL(id))
        installed.removeAll { $0.id == id }
        save()
    }

    func scriptText(for id: String) throws -> String {
        let data = try Data(contentsOf: scriptURL(id))
        return String(decoding: data, as: UTF8.self)
    }

    /// One row per source id across all repositories (first repository wins), plus installed
    /// sources whose repository index is not loaded.
    func rows() -> [ExtensionRow] {
        var rows: [ExtensionRow] = []
        var seen = Set<String>()
        for repo in repos {
            guard let index = indexes[repo.url] else { continue }
            for source in index.sources where seen.insert(source.id).inserted {
                rows.append(ExtensionRow(
                    source: source,
                    repoURL: repo.url,
                    iconURL: source.icon.flatMap { RepoClient.resolve($0, indexURL: repo.url) },
                    state: state(of: source)
                ))
            }
        }
        for item in installed where !seen.contains(item.id) {
            let source = RepoSource(
                id: item.id, name: item.name, lang: item.lang, version: item.version, runtime: JSHost.runtimeVersion,
                nsfw: item.nsfw, baseUrl: item.baseUrl, icon: nil, script: "", sha256: item.sha256,
                health: .init(status: "unknown", checkedAt: nil)
            )
            rows.append(ExtensionRow(source: source, repoURL: item.repoURL, iconURL: item.iconURL, state: .installed))
        }
        return rows.sorted { $0.source.name.localizedCaseInsensitiveCompare($1.source.name) == .orderedAscending }
    }

    private func state(of source: RepoSource) -> ExtensionState {
        if let item = installed.first(where: { $0.id == source.id }) {
            return item.sha256 == source.sha256 ? .installed : .updateAvailable
        }
        return source.runtime > JSHost.runtimeVersion ? .requiresAppUpdate : .available
    }

    // MARK: Persistence

    private var stateURL: URL { directory.appendingPathComponent("state.json") }
    private var scriptsDirectory: URL { directory.appendingPathComponent("scripts") }
    private func scriptURL(_ id: String) -> URL { scriptsDirectory.appendingPathComponent("\(id).js") }

    private func load() {
        guard let data = try? Data(contentsOf: stateURL), let state = try? JSONDecoder().decode(State.self, from: data) else { return }
        repos = state.repos
        installed = state.installed
    }

    private func save() {
        do {
            try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
            let data = try JSONEncoder().encode(State(repos: repos, installed: installed))
            try data.write(to: stateURL, options: .atomic)
        } catch {
            lastError = "Could not save extensions: \(error.localizedDescription)"
        }
    }
}

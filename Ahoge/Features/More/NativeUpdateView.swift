//
//  NativeUpdateView.swift
//  Ahoge
//

import Combine
import Foundation
import SwiftUI

enum DistributionChannel: String {
    case development
    case sideload
    case appStore

    static var current: DistributionChannel {
        if let rawValue = Bundle.main.object(forInfoDictionaryKey: "AhogeDistributionChannel") as? String,
           let channel = DistributionChannel(rawValue: rawValue) {
            return channel
        }

        #if DEBUG
        return .development
        #else
        return .sideload
        #endif
    }

    var title: String {
        switch self {
        case .development: return "Development"
        case .sideload: return "SideStore / AltStore"
        case .appStore: return "App Store / TestFlight"
        }
    }
}

struct NativeReleaseManifest: Decodable, Hashable {
    let schemaVersion: Int
    let available: Bool
    let channel: String?
    let sourceURL: String?
    let version: String?
    let build: String?
    let minimumOSVersion: String?
    let releaseDate: String?
    let downloadURL: String?
    let sha256: String?
    let releaseNotesURL: String?
    let releaseNotes: String?
    let size: Int?
}

enum NativeUpdateState {
    case idle
    case checking
    case upToDate(NativeReleaseManifest?)
    case updateAvailable(NativeReleaseManifest)
    case unsupported(NativeReleaseManifest)
    case unable(String)
}

struct NativeUpdateService {
    static let manifestURL = URL(string: "https://raw.githubusercontent.com/QuackyPROG/ahoge/main/Distribution/latest.json")!
    static let sourceURL = "https://raw.githubusercontent.com/QuackyPROG/ahoge/main/Distribution/source.json"

    func fetchLatest() async throws -> NativeReleaseManifest {
        var request = URLRequest(url: Self.manifestURL)
        request.cachePolicy = .reloadRevalidatingCacheData
        request.timeoutInterval = 10
        request.setValue("application/json", forHTTPHeaderField: "Accept")

        let (data, response) = try await URLSession.shared.data(for: request)
        guard let http = response as? HTTPURLResponse, (200..<300).contains(http.statusCode) else {
            throw URLError(.badServerResponse)
        }
        return try JSONDecoder().decode(NativeReleaseManifest.self, from: data)
    }
}

@MainActor
final class NativeUpdateViewModel: ObservableObject {
    @Published private(set) var state: NativeUpdateState = .idle

    let installedVersion: String
    let installedBuild: String
    let distributionChannel: DistributionChannel

    private let service: NativeUpdateService

    init(service: NativeUpdateService = NativeUpdateService()) {
        self.service = service
        self.installedVersion = Bundle.main.object(forInfoDictionaryKey: "CFBundleShortVersionString") as? String ?? "0.0.0"
        self.installedBuild = Bundle.main.object(forInfoDictionaryKey: "CFBundleVersion") as? String ?? "0"
        self.distributionChannel = .current
    }

    func check() async {
        state = .checking
        do {
            let manifest = try await service.fetchLatest()
            guard manifest.available, let latestVersion = manifest.version else {
                state = .upToDate(manifest)
                return
            }

            if let minimumOSVersion = manifest.minimumOSVersion,
               compareVersions(currentOSVersion, minimumOSVersion) == .orderedAscending {
                state = .unsupported(manifest)
                return
            }

            let versionComparison = compareVersions(installedVersion, latestVersion)
            let installedBuildNumber = Int(installedBuild) ?? 0
            let latestBuildNumber = Int(manifest.build ?? "0") ?? 0
            let hasNewerVersion = versionComparison == .orderedAscending
            let hasNewerBuild = versionComparison == .orderedSame && latestBuildNumber > installedBuildNumber

            state = (hasNewerVersion || hasNewerBuild) ? .updateAvailable(manifest) : .upToDate(manifest)
        } catch {
            state = .unable(error.localizedDescription)
        }
    }

    func primaryUpdateURL(for manifest: NativeReleaseManifest) -> URL? {
        switch distributionChannel {
        case .sideload:
            var components = URLComponents()
            components.scheme = "sidestore"
            components.host = "source"
            components.queryItems = [URLQueryItem(name: "url", value: NativeUpdateService.sourceURL)]
            return components.url
        case .development:
            return manifest.releaseNotesURL.flatMap(URL.init(string:))
        case .appStore:
            return nil
        }
    }

    func releaseNotesURL(for manifest: NativeReleaseManifest) -> URL? {
        manifest.releaseNotesURL.flatMap(URL.init(string:))
    }

    private var currentOSVersion: String {
        let version = ProcessInfo.processInfo.operatingSystemVersion
        return "\(version.majorVersion).\(version.minorVersion).\(version.patchVersion)"
    }

    private func compareVersions(_ lhs: String, _ rhs: String) -> ComparisonResult {
        let left = numericVersion(lhs)
        let right = numericVersion(rhs)
        let count = max(left.count, right.count, 3)

        for index in 0..<count {
            let leftValue = index < left.count ? left[index] : 0
            let rightValue = index < right.count ? right[index] : 0
            if leftValue < rightValue { return .orderedAscending }
            if leftValue > rightValue { return .orderedDescending }
        }
        return .orderedSame
    }

    private func numericVersion(_ rawValue: String) -> [Int] {
        let core = rawValue.split(separator: "-", maxSplits: 1).first.map(String.init) ?? rawValue
        return core.split(separator: ".").map { Int($0) ?? 0 }
    }
}

struct NativeUpdateView: View {
    @StateObject private var model = NativeUpdateViewModel()
    @Environment(\.openURL) private var openURL

    var body: some View {
        Form {
            Section("Installed") {
                LabeledContent("Version", value: model.installedVersion)
                LabeledContent("Build", value: model.installedBuild)
                LabeledContent("Distribution", value: model.distributionChannel.title)
            }

            statusSection

            Section("Actions") {
                Button("Check Again") {
                    Task { await model.check() }
                }
                .disabled(isChecking)
            }
        }
        .navigationTitle("App Updates")
        .task {
            if case .idle = model.state {
                await model.check()
            }
        }
    }

    @ViewBuilder
    private var statusSection: some View {
        Section("Status") {
            switch model.state {
            case .idle, .checking:
                HStack {
                    ProgressView()
                    Text("Checking for a newer Ahoge release…")
                }
            case .upToDate(let manifest):
                Label("Ahoge is up to date.", systemImage: "checkmark.circle")
                if let manifest {
                    releaseDetails(manifest)
                }
            case .unable(let message):
                Label("Unable to check for updates.", systemImage: "wifi.exclamationmark")
                Text(message)
                    .font(.footnote)
                    .foregroundStyle(.secondary)
            case .unsupported(let manifest):
                Label("The newest release requires a newer iOS version.", systemImage: "exclamationmark.triangle")
                if let minimum = manifest.minimumOSVersion {
                    LabeledContent("Required iOS", value: minimum)
                }
                releaseDetails(manifest)
            case .updateAvailable(let manifest):
                Label("A newer Ahoge release is available.", systemImage: "arrow.down.circle")
                releaseDetails(manifest)

                if let updateURL = model.primaryUpdateURL(for: manifest) {
                    Button(model.distributionChannel == .sideload ? "Open Ahoge in SideStore" : "View Release") {
                        openURL(updateURL)
                    }
                } else if model.distributionChannel == .appStore {
                    Text("This build uses App Store/TestFlight distribution. Update through that channel instead of sideloading an IPA.")
                        .font(.footnote)
                        .foregroundStyle(.secondary)
                }
            }
        }
    }

    @ViewBuilder
    private func releaseDetails(_ manifest: NativeReleaseManifest) -> some View {
        if let version = manifest.version {
            LabeledContent("Latest Version", value: version)
        }
        if let build = manifest.build {
            LabeledContent("Latest Build", value: build)
        }
        if let minimum = manifest.minimumOSVersion {
            LabeledContent("Minimum iOS", value: minimum)
        }
        if let notes = manifest.releaseNotes, !notes.isEmpty {
            Text(notes)
                .font(.footnote)
                .textSelection(.enabled)
        }
        if let releaseURL = model.releaseNotesURL(for: manifest) {
            Button("Release Notes") {
                openURL(releaseURL)
            }
        }
    }

    private var isChecking: Bool {
        if case .checking = model.state { return true }
        return false
    }
}

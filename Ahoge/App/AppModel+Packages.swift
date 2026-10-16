import Foundation

extension AppModel {
    static func admittedRecords(_ records: [SourceRepoRecord], installations: [String: PackageInstallation]) -> [SourceRepoRecord] {
        PackageAdmission.records(records, installations: installations)
    }

    var sourcePackageUpdateCount: Int {
        repoRecords.reduce(0) { count, record in count + record.packages.filter { package in
            guard let installed = state.packageInstallations?[record.id + "::" + package.id] else { return false }
            return PackageVersion.newer(package.version, than: installed.package.version)
        }.count }
    }

    func packageInstallation(_ id: String) -> PackageInstallation? { state.packageInstallations?[id] }

    func installPackage(_ id: String, trustConsent: Bool) throws {
        guard let record = repoRecords.first(where: { record in record.packages.contains { record.id + "::" + $0.id == id } }),
            let package = record.packages.first(where: { record.id + "::" + $0.id == id }) else { throw BackupError.invalid("Refresh the repository to find this package.") }
        guard trustConsent || state.packageInstallations?[id]?.trusted == true else { throw BackupError.invalid("Explicit trust consent is required; HTTPS alone does not establish trust.") }
        guard !package.sources.isEmpty, Set(package.sources.map(\.sourceID)).count == package.sources.count, package.sources.allSatisfy({ definition in
            guard let base = URL(string: definition.baseURL), base.scheme == "https", base.host != nil else { return false }
            if let api = definition.overrides["apiURL"] { guard let url = URL(string: api), url.scheme == "https", url.host != nil else { return false } }
            if let raw = definition.overrides["rateLimit"] { guard let rate = Int(raw), (1...10).contains(rate) else { return false } }
            return true
        }) else { throw BackupError.invalid("Package definitions need HTTPS endpoints and a valid request rate from 1 to 10.") }
        let probeRecord = SourceRepoRecord(id: record.id, url: record.url, title: record.title, fetchedAt: record.fetchedAt,
            packages: [package], importedSources: package.sources, lastError: nil)
        let probe = RuntimeSourceRepository(repoRecords: [probeRecord], cache: cacheController)
        guard probe.sources().contains(where: { $0.kind == .remote && probe.hasRuntime(for: $0.id) }) else { throw DiscoveryError.unsupported }
        if state.packageInstallations == nil { state.packageInstallations = [:] }
        let order = state.packageInstallations?[id]?.admissionOrder ?? ((state.packageInstallations ?? [:]).values.map(\.admissionOrder).max() ?? -1) + 1
        state.packageInstallations?[id] = PackageInstallation(package: package, trusted: true, enabled: true, admissionOrder: order)
        rebuildSourceRepository(); persist()
    }

    func setPackageEnabled(_ id: String, enabled: Bool) {
        guard var installed = state.packageInstallations?[id], installed.trusted else { return }
        installed.enabled = enabled; state.packageInstallations?[id] = installed
        rebuildSourceRepository(); persist()
    }

    func uninstallPackage(_ id: String) {
        guard state.packageInstallations?[id] != nil else { return }
        state.packageInstallations?.removeValue(forKey: id)
        rebuildSourceRepository(); persist()
    }
}

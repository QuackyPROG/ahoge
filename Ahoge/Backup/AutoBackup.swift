import Foundation

/// The when and what-to-delete rules for automatic backups, kept pure so they can be tested.
enum BackupSchedule {
    /// The intervals offered in settings, in hours; 0 is off.
    static let intervalHours = [0, 6, 12, 24, 48, 168]

    static func isDue(last: Date?, intervalHours: Int, now: Date) -> Bool {
        guard intervalHours > 0 else { return false }
        guard let last else { return true }
        return now.timeIntervalSince(last) >= Double(intervalHours) * 3600
    }

    /// Names of the files to delete so only the `keep` newest remain (same dates: the later name stays).
    static func rotate(files: [(name: String, date: Date)], keep: Int) -> [String] {
        let newestFirst = files.sorted { ($0.date, $0.name) > ($1.date, $1.name) }
        return newestFirst.dropFirst(max(keep, 1)).map(\.name)
    }
}

/// Writes backups to Documents/Backups, which the Files app shows (see UIFileSharingEnabled).
@MainActor
enum AutoBackup {
    static func folder() throws -> URL {
        let documents = try FileManager.default.url(for: .documentDirectory, in: .userDomainMask, appropriateFor: nil, create: true)
        let folder = documents.appendingPathComponent("Backups", isDirectory: true)
        try FileManager.default.createDirectory(at: folder, withIntermediateDirectories: true)
        return folder
    }

    /// Makes a backup when the interval has passed, then deletes the oldest ones. True when one was written.
    @discardableResult
    static func runIfDue(repo: LibraryRepository, store: ExtensionStore, defaults: UserDefaults = .standard, now: Date = Date()) -> Bool {
        let hours = Pref.autoBackupInterval.value(in: defaults)
        let lastSeconds = Pref.autoBackupLast.value(in: defaults)
        let last = lastSeconds > 0 ? Date(timeIntervalSince1970: lastSeconds) : nil
        guard BackupSchedule.isDue(last: last, intervalHours: hours, now: now) else { return false }
        do {
            let directory = try folder()
            let data = try BackupCodec.encode(BackupService.snapshot(of: repo, store: store, defaults: defaults, now: now))
            try data.write(to: directory.appendingPathComponent(BackupFile.name(at: now)), options: .atomic)
            Pref.autoBackupLast.set(now.timeIntervalSince1970, in: defaults)
            rotate(in: directory, keep: Pref.autoBackupKeep.value(in: defaults))
            return true
        } catch {
            return false
        }
    }

    private static func rotate(in folder: URL, keep: Int) {
        let urls = (try? FileManager.default.contentsOfDirectory(at: folder, includingPropertiesForKeys: [.contentModificationDateKey])) ?? []
        let files = urls.filter { $0.pathExtension == BackupFile.fileExtension }.map { url in
            (name: url.lastPathComponent, date: (try? url.resourceValues(forKeys: [.contentModificationDateKey]).contentModificationDate) ?? .distantPast)
        }
        for name in BackupSchedule.rotate(files: files, keep: keep) {
            try? FileManager.default.removeItem(at: folder.appendingPathComponent(name))
        }
    }
}

import UIKit

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

    private static var running = false
    private static var backgroundTime = UIBackgroundTaskIdentifier.invalid

    /// Makes a backup when the interval has passed, then deletes the oldest ones. True when one was written.
    /// The snapshot is taken here; encoding and writing run off the main actor.
    @discardableResult
    static func runIfDue(repo: LibraryRepository, store: ExtensionStore, defaults: UserDefaults = .standard, folder: URL? = nil, now: Date = Date()) async -> Bool {
        let hours = Pref.autoBackupInterval.value(in: defaults)
        let lastSeconds = Pref.autoBackupLast.value(in: defaults)
        let last = lastSeconds > 0 ? Date(timeIntervalSince1970: lastSeconds) : nil
        guard !running, BackupSchedule.isDue(last: last, intervalHours: hours, now: now) else { return false }
        running = true
        defer { running = false }
        do {
            let directory = try folder ?? Self.folder()
            let backup = BackupService.snapshot(of: repo, store: store, defaults: defaults, now: now)
            let file = directory.appendingPathComponent(BackupFile.name(at: now))
            let write = Task.detached(priority: .utility) {
                let data = try BackupCodec.encode(backup)
                try Task.checkCancellation()
                try data.write(to: file, options: .atomic)
            }
            try await withTaskCancellationHandler { try await write.value } onCancel: { write.cancel() }
            Pref.autoBackupLast.set(now.timeIntervalSince1970, in: defaults)
            rotate(in: directory, keep: Pref.autoBackupKeep.value(in: defaults))
            return true
        } catch {
            return false
        }
    }

    /// `runIfDue` when the app leaves the screen, holding background time until it ends (or iOS takes it back).
    static func runInBackground(repo: LibraryRepository, store: ExtensionStore) {
        guard backgroundTime == .invalid else { return }
        let work = Task { await runIfDue(repo: repo, store: store) }
        let time = UIApplication.shared.beginBackgroundTask(withName: "Auto backup") {
            MainActor.assumeIsolated {
                work.cancel()
                endBackgroundTime()
            }
        }
        backgroundTime = time
        Task {
            _ = await work.value
            if backgroundTime == time { endBackgroundTime() }
        }
    }

    private static func endBackgroundTime() {
        guard backgroundTime != .invalid else { return }
        UIApplication.shared.endBackgroundTask(backgroundTime)
        backgroundTime = .invalid
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

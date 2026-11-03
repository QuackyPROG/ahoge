import BackgroundTasks

/// Runs library updates and backups when iOS grants background time. iOS decides when; the
/// intervals in settings are the earliest it may start.
@MainActor
enum BackgroundRefresh {
    /// Updates as a short app refresh.
    nonisolated static let refreshId = "app.ahoge.refresh"
    /// Updates as a processing task, used when "only while charging" is on.
    nonisolated static let updateId = "app.ahoge.update"
    nonisolated static let backupId = "app.ahoge.backup"

    /// What the tasks work on; set by the app when it starts, before iOS can call a task.
    struct Context {
        let repo: LibraryRepository
        let sources: SourceManager
        let updater: LibraryUpdater
        let extensions: ExtensionStore
    }

    static var context: Context?

    /// Must run before the app finishes launching (called from the app delegate).
    nonisolated static func register() {
        let scheduler = BGTaskScheduler.shared
        scheduler.register(forTaskWithIdentifier: refreshId, using: nil) { task in
            Task { @MainActor in runUpdate(task) }
        }
        scheduler.register(forTaskWithIdentifier: updateId, using: nil) { task in
            Task { @MainActor in runUpdate(task) }
        }
        scheduler.register(forTaskWithIdentifier: backupId, using: nil) { task in
            Task { @MainActor in runBackup(task) }
        }
    }

    /// Asks iOS for the next runs from the current settings; replaces earlier requests.
    nonisolated static func schedule() {
        let scheduler = BGTaskScheduler.shared
        for id in [refreshId, updateId, backupId] { scheduler.cancel(taskRequestWithIdentifier: id) }

        let updateHours = Pref.autoUpdateInterval.value()
        if updateHours > 0 {
            let begin = Date(timeIntervalSinceNow: Double(updateHours) * 3600)
            if Pref.autoUpdateOnlyCharging.value() {
                let request = BGProcessingTaskRequest(identifier: updateId)
                request.requiresExternalPower = true
                request.requiresNetworkConnectivity = true
                request.earliestBeginDate = begin
                try? scheduler.submit(request)
            } else {
                let request = BGAppRefreshTaskRequest(identifier: refreshId)
                request.earliestBeginDate = begin
                try? scheduler.submit(request)
            }
        }

        let backupHours = Pref.autoBackupInterval.value()
        if backupHours > 0 {
            let request = BGProcessingTaskRequest(identifier: backupId)
            request.requiresNetworkConnectivity = false
            request.earliestBeginDate = Date(timeIntervalSinceNow: Double(backupHours) * 3600)
            try? scheduler.submit(request)
        }
    }

    private static func runUpdate(_ task: BGTask) {
        schedule()
        guard let context else {
            task.setTaskCompleted(success: false)
            return
        }
        let updater = context.updater
        // Stops after the title being fetched; titles already done stay saved.
        task.expirationHandler = { Task { @MainActor in updater.cancel() } }
        Task { @MainActor in
            await updater.update(context.repo.library, repo: context.repo, sources: context.sources, trigger: .automatic)
            task.setTaskCompleted(success: true)
        }
    }

    private static func runBackup(_ task: BGTask) {
        schedule()
        guard let context else {
            task.setTaskCompleted(success: false)
            return
        }
        AutoBackup.runIfDue(repo: context.repo, store: context.extensions)
        task.setTaskCompleted(success: true)
    }
}

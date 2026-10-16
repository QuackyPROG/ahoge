// Modified for Ahoge from an Apache-2.0-licensed prior implementation.
// See THIRD_PARTY_NOTICES.md for attribution and license information.

//
//  AppModel+Tracking.swift
//  Ahoge
//

import Foundation

extension AppModel {
    func updateTracker(_ binding: TrackerBinding, status: String, progress: String, score: String) throws {
        guard !state.securityPreferences.lockLibraryEdits else { throw BackupError.invalid("Library edits are locked.") }
        guard ["Reading", "Completed", "On hold", "Dropped", "Plan to read"].contains(status),
            Int(progress).map({ $0 >= 0 }) == true,
            score.isEmpty || score == "-" || Double(score).map({ $0.isFinite && $0 >= 0 && $0 <= 10 }) == true
            else { throw BackupError.invalid("Use a valid status, nonnegative chapter count and score from 0 to 10.") }
        guard let index = state.trackers.firstIndex(where: { $0.id == binding.id }) else { return }
        state.trackers[index].status = status; state.trackers[index].progressText = progress; state.trackers[index].score = score
        persist()
    }

    func trackerBindings(for manga: Manga) -> [TrackerBinding] {
        state.trackers.filter { $0.mangaID == manga.id }
    }

    func linkTracker(service: TrackerService, to manga: Manga) {
        guard !state.securityPreferences.lockLibraryEdits else { return }
        guard !state.trackers.contains(where: { $0.mangaID == manga.id && $0.service == service }) else { return }
        state.trackers.append(
            TrackerBinding(
                id: UUID(),
                mangaID: manga.id,
                service: service,
                remoteTitle: manga.title,
                status: "Reading",
                progressText: "0",
                score: "-"
            )
        )
        persist()
    }

    func unlinkTracker(_ binding: TrackerBinding) {
        guard !state.securityPreferences.lockLibraryEdits else { return }
        state.trackers.removeAll { $0.id == binding.id }
        persist()
    }
}


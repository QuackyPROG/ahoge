// Modified for Ahoge from an Apache-2.0-licensed prior implementation.
// See THIRD_PARTY_NOTICES.md for attribution and license information.
import SwiftUI

struct TrackingCenterView: View {
    @EnvironmentObject private var model: AppModel
    var body: some View {
        List {
            Section { TrackingAvailabilityView() }
            Section("Local records") {
                if model.bindings().isEmpty { ContentUnavailableView("No local tracking records", systemImage: "person.badge.clock", description: Text("Add a local record from a title’s Tracking screen.")) }
                ForEach(model.bindings()) { binding in
                    NavigationLink { TrackerRecordEditor(binding: binding) } label: {
                        VStack(alignment: .leading, spacing: 3) { Text(binding.remoteTitle); Text("\(binding.service.rawValue) · \(binding.status) · \(binding.progressText)").font(.caption).foregroundStyle(.secondary) }
                    }
                }
            }
        }.navigationTitle("Local Tracking")
    }
}
private struct TrackingAvailabilityView: View {
    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            Label("Stored on this device", systemImage: "internaldrive").font(.headline)
            Text("Service labels organize local records. No account is connected; remote login, title search and synchronization are unavailable.").font(.subheadline).foregroundStyle(.secondary)
        }
    }
}
struct MangaTrackingView: View {
    @EnvironmentObject private var model: AppModel
    let manga: Manga
    @State private var removal: TrackerBinding?
    var body: some View {
        List {
            Section { Text(manga.title).font(.headline); TrackingAvailabilityView() }
            Section("Local records") {
                if model.trackerBindings(for: manga).isEmpty { Text("No local records for this title.").foregroundStyle(.secondary) }
                ForEach(model.trackerBindings(for: manga)) { binding in
                    NavigationLink { TrackerRecordEditor(binding: binding) } label: {
                        VStack(alignment: .leading, spacing: 4) {
                            Label(binding.service.rawValue, systemImage: binding.service.systemImage)
                            Text("\(binding.status) · \(binding.progressText) · Score \(binding.score)").font(.caption).foregroundStyle(.secondary)
                        }
                    }.swipeActions { Button("Remove", role: .destructive) { removal = binding }.disabled(model.state.securityPreferences.lockLibraryEdits) }
                }
            }
            Section("Add local record") {
                ForEach(TrackerService.allCases) { service in
                    Button { model.linkTracker(service: service, to: manga) } label: { Label(service.rawValue, systemImage: service.systemImage) }
                        .disabled(model.state.securityPreferences.lockLibraryEdits || model.trackerBindings(for: manga).contains { $0.service == service })
                }
            }
            Section { NavigationLink("Remote service availability") { TrackerSearchView(manga: manga) } }
        }.navigationTitle("Local Tracking")
        .confirmationDialog("Remove this local record?", isPresented: Binding(get: { removal != nil }, set: { if !$0 { removal = nil } })) {
            Button("Remove local record", role: .destructive) { if let binding = removal { model.unlinkTracker(binding) }; removal = nil }
        } message: { Text("This affects this device only.") }
    }
}
private struct TrackerRecordEditor: View {
    @EnvironmentObject private var model: AppModel
    @Environment(\.dismiss) private var dismiss
    let binding: TrackerBinding
    @State private var status: String
    @State private var progress: String
    @State private var score: String
    @State private var error: String?
    @State private var removal = false
    init(binding: TrackerBinding) {
        self.binding = binding
        _status = State(initialValue: binding.status)
        _progress = State(initialValue: Int(binding.progressText) == nil ? "" : binding.progressText)
        _score = State(initialValue: binding.score)
    }
    var body: some View {
        Form {
            Section { Text(binding.remoteTitle).font(.headline); LabeledContent("Service label", value: binding.service.rawValue); TrackingAvailabilityView() }
            Section("Local values") {
                Picker("Status", selection: $status) { ForEach(["Reading", "Completed", "On hold", "Dropped", "Plan to read"], id: \.self) { Text($0).tag($0) } }.accessibilityLabel("Local status")
                TextField("Chapter count (0 or more)", text: $progress).keyboardType(.numberPad).accessibilityLabel("Local chapter progress")
                if Int(binding.progressText) == nil { Text("Previous value: \(binding.progressText). Enter the completed chapter count to update this record.").font(.caption).foregroundStyle(.secondary) }
                TextField("Score (0–10, or blank)", text: $score).keyboardType(.decimalPad).accessibilityLabel("Local score")
            }.disabled(model.state.securityPreferences.lockLibraryEdits)
            if let error { Text(error).foregroundStyle(.red) }
            Section {
                Button("Save local record") {
                    do { try model.updateTracker(binding, status: status, progress: progress, score: score); dismiss() }
                    catch { self.error = error.localizedDescription }
                }.disabled(model.state.securityPreferences.lockLibraryEdits)
                Button("Remove local record", role: .destructive) { removal = true }.disabled(model.state.securityPreferences.lockLibraryEdits)
            }
        }.navigationTitle("Edit Local Record")
        .confirmationDialog("Remove this local record?", isPresented: $removal) { Button("Remove", role: .destructive) { model.unlinkTracker(binding); dismiss() } }
    }
}
struct TrackerSearchView: View {
    let manga: Manga
    var body: some View {
        List {
            Section { Text(manga.title).font(.headline); TrackingAvailabilityView() }
            ForEach(TrackerService.allCases) { service in
                Section(service.rawValue) {
                    LabeledContent("Account login", value: "Unavailable")
                    LabeledContent("Remote title search", value: "Unavailable")
                    LabeledContent("Remote synchronization", value: "Unavailable")
                }
            }
        }.navigationTitle("Service Availability")
    }
}

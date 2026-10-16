import SwiftUI
import UniformTypeIdentifiers

struct BackupFile: FileDocument {
    static var readableContentTypes: [UTType] { [.json] }
    var data: Data
    init(data: Data) { self.data = data }
    init(configuration: ReadConfiguration) throws { data = configuration.file.regularFileContents ?? Data() }
    func fileWrapper(configuration: WriteConfiguration) throws -> FileWrapper { FileWrapper(regularFileWithContents: data) }
}

struct CreateBackupView: View {
    @EnvironmentObject private var model: AppModel
    @State private var selection = Set(BackupSection.allCases)
    @State private var file = BackupFile(data: Data())
    @State private var exporting = false
    @State private var message: String?
    var body: some View {
        Form {
            Section("Contents") {
                ForEach(BackupSection.allCases) { section in
                    Toggle(section.rawValue.capitalized, isOn: Binding(get: { selection.contains(section) }, set: { if $0 { selection.insert(section) } else { selection.remove(section) } }))
                }
            }
            Section {
                Text("Selected contents only. Local imports, downloaded images, cookies, credentials and security settings are excluded. Keep original files for reimport on another device.")
                Button("Export Backup") {
                    do { file = BackupFile(data: try model.exportBackup(sections: selection).encoded()); exporting = true }
                    catch { message = error.localizedDescription }
                }.disabled(selection.isEmpty)
            }
            if let message { Text(message).foregroundStyle(.secondary) }
        }.navigationTitle("Create Backup")
        .fileExporter(isPresented: $exporting, document: file, contentType: .json, defaultFilename: "Ahoge-backup") { result in
            switch result { case .success: message = "Backup exported."; case .failure(let error): message = error.localizedDescription }
        }
    }
}

struct RestoreBackupView: View {
    @EnvironmentObject private var model: AppModel
    @State private var importing = false
    @State private var backup: AhogeBackup?
    @State private var confirming = false
    @State private var message: String?
    var body: some View {
        Form {
            Button("Choose Backup File") { importing = true }
            if let backup {
                Section("Validated contents") {
                    LabeledContent("Created", value: backup.createdAt.formatted())
                    LabeledContent("Application", value: backup.appVersion)
                    ForEach(backup.sections.sorted { $0.rawValue < $1.rawValue }) { Text($0.rawValue.capitalized) }
                    Text("Replace these sections and preserve unselected sections. Offline files stay intact; files from another device require reimport. Source definitions require renewed trust before activation.")
                    Button("Restore Selected Sections", role: .destructive) { confirming = true }
                        .disabled(model.state.securityPreferences.lockLibraryEdits)
                }
            }
            if let message { Text(message) }
        }.navigationTitle("Restore Backup")
        .fileImporter(isPresented: $importing, allowedContentTypes: [.json], allowsMultipleSelection: false) { result in
            do {
                guard let url = try result.get().first else { return }
                let access = url.startAccessingSecurityScopedResource(); defer { if access { url.stopAccessingSecurityScopedResource() } }
                let size = try url.resourceValues(forKeys: [.fileSizeKey]).fileSize ?? 0
                guard size <= AhogeBackup.maximumBytes else { throw BackupError.invalid("Backup exceeds 32 MB.") }
                backup = try AhogeBackup.decode(Data(contentsOf: url)); message = nil
            } catch { backup = nil; message = error.localizedDescription }
        }
        .confirmationDialog("Replace the selected backup sections?", isPresented: $confirming, titleVisibility: .visible) {
            Button("Restore", role: .destructive) {
                guard let backup else { return }
                do { try model.restoreBackup(backup); message = "Selected sections restored. Original offline files preserved."; self.backup = nil }
                catch { message = "Restore failed; original state preserved. " + error.localizedDescription }
            }
        }
    }
}

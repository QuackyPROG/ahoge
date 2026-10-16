// Native adaptation of stable Mihon reader behavior.
// See THIRD_PARTY_NOTICES.md for attribution and license information.

import SwiftUI
import UIKit
import UniformTypeIdentifiers

struct ReaderExportDocument: FileDocument {
    static var readableContentTypes: [UTType] { [.png] }
    let data: Data
    init(data: Data) { self.data = data }
    init(configuration: ReadConfiguration) throws { data = configuration.file.regularFileContents ?? Data() }
    func fileWrapper(configuration: WriteConfiguration) throws -> FileWrapper { FileWrapper(regularFileWithContents: data) }
}
struct ReaderShareImage: Identifiable {
    let id = UUID()
    let image: UIImage
}
struct ReaderPageShareSheet: UIViewControllerRepresentable {
    let image: UIImage
    func makeUIViewController(context: Context) -> UIActivityViewController {
        UIActivityViewController(activityItems: [image], applicationActivities: nil)
    }
    func updateUIViewController(_ uiViewController: UIActivityViewController, context: Context) {}
}
extension ReaderView {
    func exportCurrentPage(save: Bool) {
        guard let selection = currentProgressSelection,
              let page = currentPages.first(where: { $0.id == selection.focusedSourceID }) else { return }
        guard page.assetKind == .image else {
            pageExportError = "This page contains text rather than an exportable image."
            return
        }
        let localURL = model.fileURL(for: page)
        let remoteURL = page.remoteURL.flatMap(URL.init(string:))
        exportingPage = true
        exportTask?.cancel()
        exportTask = Task { @MainActor in
            defer { exportingPage = false }
            do {
                let image: UIImage
                if let localURL {
                    let data = try await Task.detached(priority: .userInitiated) { try Data(contentsOf: localURL) }.value
                    guard let localImage = UIImage(data: data) else { throw CocoaError(.fileReadCorruptFile) }
                    image = localImage
                } else if let remoteURL {
                    image = try await imagePipeline.image(for: remoteURL, forceRefresh: false)
                } else { throw CocoaError(.fileNoSuchFile) }
                guard !Task.isCancelled else { return }
                if save {
                    guard let data = await Task.detached(priority: .userInitiated, operation: { image.pngData() }).value else { throw CocoaError(.fileWriteUnknown) }
                    guard !Task.isCancelled else { return }
                    exportedPage = ReaderExportDocument(data: data)
                    showFileExporter = true
                } else { pageShareImage = ReaderShareImage(image: image) }
            } catch {
                guard !Task.isCancelled else { return }
                pageExportError = "The original page image could not be loaded. Retry the page or restore its download."
            }
        }
    }
}

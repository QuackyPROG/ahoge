import Photos
import UIKit

/// Adds a page to the photo library. Needs only add access, so the app never reads existing photos.
enum PhotoSaver {
    struct Denied: LocalizedError {
        var errorDescription: String? { "Allow Ahoge to add photos in Settings to save pages." }
    }

    static func save(_ image: UIImage) async throws {
        let status = await PHPhotoLibrary.requestAuthorization(for: .addOnly)
        guard status == .authorized || status == .limited else { throw Denied() }
        try await PHPhotoLibrary.shared().performChanges {
            PHAssetChangeRequest.creationRequestForAsset(from: image)
        }
    }
}

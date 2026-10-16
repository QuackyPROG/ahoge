import Foundation

struct StorageUsage: Hashable {
    var importedBytes: Int64
    var downloadedBytes: Int64
}

extension AppModel {
    func refreshStorageUsage() async {
        let urls = storageDirectoryURLs
        storageUsage = await Task.detached(priority: .utility) {
            func bytes(_ directory: URL) -> Int64 {
                let keys: Set<URLResourceKey> = [.isRegularFileKey, .isSymbolicLinkKey, .fileAllocatedSizeKey, .fileSizeKey]
                guard let enumerator = FileManager.default.enumerator(at: directory, includingPropertiesForKeys: Array(keys), options: [.skipsHiddenFiles]) else { return 0 }
                var total: Int64 = 0
                for case let file as URL in enumerator {
                    if Task.isCancelled { break }
                    guard let resource = try? file.resourceValues(forKeys: keys), resource.isSymbolicLink != true, resource.isRegularFile == true else { continue }
                    total += Int64(resource.fileAllocatedSize ?? resource.fileSize ?? 0)
                }
                return total
            }
            return StorageUsage(importedBytes: bytes(urls[0]), downloadedBytes: bytes(urls[1]))
        }.value
    }
}

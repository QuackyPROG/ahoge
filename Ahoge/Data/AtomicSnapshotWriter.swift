import Foundation

enum AtomicSnapshotWriter {
    static func write(_ data: Data, to destination: URL) throws {
        try data.write(to: destination, options: .atomic)
    }
}

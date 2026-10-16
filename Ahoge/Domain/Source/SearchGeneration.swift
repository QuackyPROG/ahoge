import Foundation

struct SearchGeneration: Hashable {
    private(set) var token = UUID()
    mutating func invalidate() { token = UUID() }
    func accepts(_ candidate: UUID) -> Bool { token == candidate }
}

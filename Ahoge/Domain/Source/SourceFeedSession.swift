import Foundation

struct SourceFeedDescriptor: Hashable {
    let sourceID: String
    let mode: SourceFeedKind
    let query: String
    let filters: [SourceFilterValue]
    var allowsPagination: Bool = true
}

/// Captures request identity and cursor together; mutable search/filter controls
/// never supply arguments to a later page of an already submitted feed.
struct SourceFeedSession {
    struct Request: Hashable {
        let descriptor: SourceFeedDescriptor
        let generation: UUID
        let page: Int
    }
    private(set) var descriptor: SourceFeedDescriptor?
    private var generation = UUID()
    private(set) var page = 0
    private(set) var isLoading = false
    private(set) var reachedEnd = false

    mutating func invalidate() {
        generation = UUID(); descriptor = nil
        page = 0; isLoading = false; reachedEnd = false
    }
    mutating func begin(_ descriptor: SourceFeedDescriptor) -> Request {
        invalidate(); self.descriptor = descriptor; isLoading = true
        return Request(descriptor: descriptor, generation: generation, page: 1)
    }
    mutating func nextRequest() -> Request? {
        guard let descriptor, descriptor.allowsPagination, page > 0, !isLoading, !reachedEnd else { return nil }
        isLoading = true
        return Request(descriptor: descriptor, generation: generation, page: page + 1)
    }
    func accepts(_ request: Request) -> Bool {
        isLoading && request.generation == generation && request.descriptor == descriptor && request.page == page + 1
    }
    mutating func finish(_ request: Request, addedCount: Int) {
        guard accepts(request) else { return }
        page = request.page; reachedEnd = addedCount == 0 || !request.descriptor.allowsPagination; isLoading = false
    }
    mutating func fail(_ request: Request) {
        guard accepts(request) else { return }
        isLoading = false
    }
}

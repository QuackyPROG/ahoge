import Foundation

// Identity travels with the originating host callback, including terminal callbacks.
struct ReaderSurfaceIdentity: Hashable {
    let epoch: UUID
    let member: String
    let host: UUID
    let generation: Int
}

enum ReaderSurfaceActivity: Hashable { case pan, pinch, deceleration, animatedZoom, animatedScroll }
enum ReaderSurfaceEvent: Equatable {
    case register, begin(ReaderSurfaceActivity), change(ReaderSurfaceActivity)
    case end(ReaderSurfaceActivity), panEnded(decelerates: Bool), scrollPhase(ReaderSurfaceActivity?), retire, viewport
}

// Foundation vocabulary mapped one-for-one from the native ScrollPhase adapter.
// Phase replacement is atomic, so drag -> deceleration has no idle gap.
enum ReaderContinuousScrollPhase {
    case idle, tracking, interacting, decelerating, animating
    var event: ReaderSurfaceEvent {
        switch self {
        case .idle: return .scrollPhase(nil)
        case .tracking, .interacting: return .scrollPhase(.pan)
        case .decelerating: return .scrollPhase(.deceleration)
        case .animating: return .scrollPhase(.animatedScroll)
        }
    }
}

struct ReaderSurfaceActivities: Equatable {
    private(set) var active: Set<ReaderSurfaceActivity> = []
    mutating func apply(_ event: ReaderSurfaceEvent) {
        switch event {
        case .begin(let activity): active.insert(activity)
        case .change: break // A delayed changed event cannot reacquire ownership.
        case .end(let activity): active.remove(activity)
        case .panEnded(let decelerates):
            if active.remove(.pan) != nil, decelerates { active.insert(.deceleration) }
        case .scrollPhase(let activity):
            if let activity { active = [activity] } else { active = [] }
        case .retire: active.removeAll()
        case .register, .viewport: break
        }
    }
}

struct ReaderSurfaceOwnership {
    private(set) var registrations: [String: ReaderSurfaceIdentity] = [:]
    private(set) var activities: [String: ReaderSurfaceActivities] = [:]
    private var retired: Set<ReaderSurfaceIdentity> = []

    mutating func receive(_ event: ReaderSurfaceEvent, from identity: ReaderSurfaceIdentity,
                          epoch: UUID, visible: Set<String>) -> Bool {
        guard identity.epoch == epoch, !retired.contains(identity) else { return false }
        if event == .register {
            guard visible.contains(identity.member) else { return false }
            if let old = registrations[identity.member], old != identity {
                if old.host == identity.host, old.generation > identity.generation { return false }
                retired.insert(old)
                activities[identity.member] = nil
            }
            registrations[identity.member] = identity
        }
        guard registrations[identity.member] == identity else { return false }
        if event == .retire {
            retired.insert(identity)
            registrations[identity.member] = nil
            activities[identity.member] = nil
            return true
        }
        guard visible.contains(identity.member) else { return false }
        var state = activities[identity.member] ?? ReaderSurfaceActivities()
        state.apply(event)
        activities[identity.member] = state
        return true
    }

    mutating func reconcile(visible: Set<String>) {
        for (member, identity) in registrations where !visible.contains(member) {
            retired.insert(identity)
            registrations[member] = nil
            activities[member] = nil
        }
    }
    var isOwned: Bool { activities.values.contains { !$0.active.isEmpty } }
}

struct ReaderPublicationGate {
    let surfaceOwned: Bool
    let pagerIdle: Bool
    let hasTransition: Bool
    let chapterTransitioning: Bool
    var permitsPublication: Bool { !surfaceOwned && pagerIdle && !hasTransition && !chapterTransitioning }
}

// Keeps explicit source intent across later metadata/configuration requests.
struct ReaderPendingPublication<Snapshot, Anchor> {
    private(set) var snapshot: Snapshot?
    private(set) var chapter: String?
    private(set) var anchor: Anchor?
    private(set) var chapterEnd = false
    mutating func request(_ snapshot: Snapshot, chapter: String, anchor: Anchor?, chapterEnd: Bool = false) {
        if self.chapter != chapter { self.anchor = nil; self.chapterEnd = false }
        self.snapshot = snapshot
        self.chapter = chapter
        if let anchor { self.anchor = anchor; self.chapterEnd = false }
        if chapterEnd { self.anchor = nil; self.chapterEnd = true }
    }
    mutating func focusChanged() { anchor = nil; chapterEnd = false }
    mutating func take(chapter: String, gate: ReaderPublicationGate) -> (Snapshot, Anchor?, Bool)? {
        guard self.chapter == chapter else { self = Self(); return nil }
        guard gate.permitsPublication, let snapshot else { return nil }
        let result = (snapshot, anchor, chapterEnd)
        self = Self() // Consume before any effect/reconciliation callback.
        return result
    }
}

struct ReaderSurfaceNavigationPolicy {
    let surfaceOwned: Bool
    let spread: Bool
    let scale: Double
    let edgeReady: Bool
    var permitsTap: Bool { !surfaceOwned && scale <= 1.01 }
    var permitsCapture: Bool { !surfaceOwned && (scale <= 1.01 || (!spread && edgeReady)) }
}

// The View's measured geometry and UIKit's visibility configuration share these
// boundaries with the Foundation harness. Layout safety never implies measurement.
struct ReaderViewportMeasurement: Equatable {
    let measuredSize: CGSize?
    let layoutSize: CGSize

    init(_ raw: CGSize) {
        func safe(_ value: CGFloat) -> CGFloat { value.isFinite && value > 0 ? max(value, 1) : 1 }
        layoutSize = CGSize(width: safe(raw.width), height: safe(raw.height))
        measuredSize = raw.width.isFinite && raw.height.isFinite && raw.width > 0 && raw.height > 0 ? raw : nil
    }
}

enum ReaderSurfaceVisibility {
    static let continuousScrollMember = "reader:continuous-scroll"
    static func visibleMembers(mode: ReaderMode, pagedMembers: Set<String>, continuousMembers: Set<String>,
                               frames: [String: CGRect], viewportSize: CGSize) -> Set<String> {
        guard mode == .vertical || mode == .webtoon else { return pagedMembers }
        guard let size = ReaderViewportMeasurement(viewportSize).measuredSize else { return [continuousScrollMember] }
        let viewport = CGRect(origin: .zero, size: size)
        return Set(frames.compactMap { member, frame in
            guard continuousMembers.contains(member), frame.origin.x.isFinite, frame.origin.y.isFinite,
                  frame.width.isFinite, frame.height.isFinite, frame.width > 0, frame.height > 0 else { return nil }
            let overlap = frame.intersection(viewport)
            return !overlap.isNull && overlap.width > 0 && overlap.height > 0 ? member : nil
        }).union([continuousScrollMember])
    }
}

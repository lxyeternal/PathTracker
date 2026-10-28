import SwiftUI

/// Which stamps have been seen landing. A stamp shown for the first time is pressed in front
/// of you; after that it simply sits on its page. Kept in iCloud too, so a new phone doesn't
/// press them all again.
@MainActor
enum SeenStamps {
    private static let key = "stamps.seen"
    private static let store = SyncedSet(key: key)

    static func contains(_ id: String) -> Bool { store.contains(id) }
    static func insert(_ id: String) { store.insert([id]) }
    static func insert(_ ids: [String]) { store.insert(ids) }
}

/// A set of ids kept in this device's defaults and in iCloud's key-value store, merged both
/// ways. Saves are gathered up, since a page of stamps lands at once.
@MainActor
final class SyncedSet {
    private let key: String
    private var values: Set<String>
    private var pendingSave: Task<Void, Never>?
    private var observer: NSObjectProtocol?
    private let cloud = NSUbiquitousKeyValueStore.default

    init(key: String) {
        self.key = key
        values = Set(UserDefaults.standard.stringArray(forKey: key) ?? [])
            .union(NSUbiquitousKeyValueStore.default.array(forKey: key) as? [String] ?? [])
        observer = NotificationCenter.default.addObserver(forName: NSUbiquitousKeyValueStore.didChangeExternallyNotification,
                                                          object: cloud, queue: .main) { [weak self] _ in
            MainActor.assumeIsolated { self?.merge() }
        }
    }

    /// Nil until anything has been stored, on this device or another.
    var stored: Set<String>? {
        UserDefaults.standard.stringArray(forKey: key) == nil && cloud.array(forKey: key) == nil ? nil : values
    }

    func contains(_ id: String) -> Bool { values.contains(id) }

    func insert(_ ids: [String], now: Bool = false) {
        let before = values.count
        values.formUnion(ids)
        guard values.count != before || stored == nil else { return }
        pendingSave?.cancel()
        if now { save(); return }
        pendingSave = Task {
            try? await Task.sleep(for: .seconds(1))
            guard !Task.isCancelled else { return }
            save()
        }
    }

    private func merge() {
        values.formUnion(cloud.array(forKey: key) as? [String] ?? [])
        UserDefaults.standard.set(Array(values), forKey: key)
    }

    private func save() {
        let list = Array(values)
        UserDefaults.standard.set(list, forKey: key)
        // The key-value store holds a megabyte in all; plenty for ids, but stop well short.
        if list.count < 6000 { cloud.set(list, forKey: key) }
    }
}

/// Lands a stamp the first time it's on screen: lifted and faint, then pressed down hard with
/// a thump you can feel, the ink settling as it lifts away.
private struct StampIn: ViewModifier {
    let id: String
    let delay: Double
    let tilt: Double
    @State private var phase: Phase

    enum Phase { case resting, raised, pressed }

    init(id: String, delay: Double, tilt: Double) {
        self.id = id
        self.delay = delay
        self.tilt = tilt
        _phase = State(initialValue: SeenStamps.contains(id) ? .resting : .raised)
    }

    func body(content: Content) -> some View {
        content
            .scaleEffect(phase == .raised ? 1.45 : (phase == .pressed ? 0.94 : 1))
            .opacity(phase == .raised ? 0 : 1)
            .rotationEffect(.degrees(tilt + (phase == .raised ? -7 : 0)))
            .blur(radius: phase == .raised ? 3 : 0)
            .task {
                guard phase == .raised else { return }
                guard (try? await Task.sleep(for: .seconds(delay))) != nil else { return }
                withAnimation(.easeIn(duration: 0.16)) { phase = .pressed }
                try? await Task.sleep(for: .seconds(0.16))
                UIImpactFeedbackGenerator(style: .rigid).impactOccurred(intensity: 0.9)
                withAnimation(.spring(response: 0.32, dampingFraction: 0.55)) { phase = .resting }
                SeenStamps.insert(id)
            }
    }
}

extension View {
    /// Tilts the stamp as it lies on the page, landing it first if it hasn't been seen.
    func stampIn(_ stamp: Stamp, delay: Double = 0, tilt: Double? = nil) -> some View {
        modifier(StampIn(id: stamp.id, delay: delay, tilt: tilt ?? stamp.tilt))
    }
}

/// Holds the route for a city stamp, loading it the first time the stamp is drawn.
struct StampWithRoute: View {
    let stamp: Stamp
    @Environment(\.modelContext) private var context
    @State private var route: [CGPoint]

    init(stamp: Stamp) {
        self.stamp = stamp
        _route = State(initialValue: StampRoute.cached(stamp) ?? [])
    }

    var body: some View {
        StampArt(stamp: stamp, route: route)
            .task(id: stamp.id) {
                guard stamp.kind == .city, StampRoute.cached(stamp) == nil else { return }
                route = StampRoute.load(stamp, context: context)
            }
    }
}

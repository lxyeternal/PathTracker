import SwiftUI

/// Which stamps have been seen landing. A stamp shown for the first time is pressed in front
/// of you; after that it simply sits on its page.
@MainActor
enum SeenStamps {
    private static let key = "stamps.seen"
    private static var seen: Set<String> = Set(UserDefaults.standard.stringArray(forKey: key) ?? [])
    private static var pendingSave: Task<Void, Never>?

    static func contains(_ id: String) -> Bool { seen.contains(id) }

    static func insert(_ id: String) {
        guard seen.insert(id).inserted else { return }
        // A page of stamps lands at once: save once they've all landed.
        pendingSave?.cancel()
        pendingSave = Task {
            try? await Task.sleep(for: .seconds(1))
            guard !Task.isCancelled else { return }
            UserDefaults.standard.set(Array(seen), forKey: key)
        }
    }

    static func insert(_ ids: [String]) { ids.forEach(insert) }
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

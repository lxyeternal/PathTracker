import SwiftUI
import CoreMotion
import Observation

/// How the phone is tilted from where it was held when a card was opened, smoothed. Runs
/// only while a card is open.
@MainActor
@Observable
final class CardTilt {
    static let shared = CardTilt()

    private(set) var x: Double = 0
    private(set) var y: Double = 0

    @ObservationIgnored private let motion = CMMotionManager()
    @ObservationIgnored private var reference: CMAttitude?
    @ObservationIgnored private var users = 0

    private init() {}

    func start() {
        users += 1
        guard users == 1, motion.isDeviceMotionAvailable else { return }
        motion.deviceMotionUpdateInterval = 1 / 30
        reference = nil
        motion.startDeviceMotionUpdates(to: .main) { [weak self] data, _ in
            guard let self, let attitude = data?.attitude.copy() as? CMAttitude else { return }
            if let reference { attitude.multiply(byInverseOf: reference) } else { reference = attitude.copy() as? CMAttitude }
            // A gentle follow, so the light glides rather than jitters.
            x += (max(-1, min(1, attitude.roll / 0.5)) - x) * 0.15
            y += (max(-1, min(1, attitude.pitch / 0.5)) - y) * 0.15
        }
    }

    func stop() {
        users = max(0, users - 1)
        guard users == 0 else { return }
        motion.stopDeviceMotionUpdates()
        withAnimation(.smooth(duration: 0.6)) { x = 0; y = 0 }
    }
}

/// A card that catches the light: it leans a few degrees as the phone tilts, and a soft
/// iridescent band slides across it the way light moves over a laminated visa.
struct CardSheen: ViewModifier {
    var active: Bool
    var cornerRadius: CGFloat = 16
    private var tilt = CardTilt.shared
    @State private var sweep = false

    init(active: Bool, cornerRadius: CGFloat = 16) {
        self.active = active
        self.cornerRadius = cornerRadius
    }

    func body(content: Content) -> some View {
        content
            .overlay {
                if active {
                    GeometryReader { proxy in
                        let travel = proxy.size.width * 0.9
                        LinearGradient(stops: [.init(color: .clear, location: 0.0),
                                               .init(color: Color(red: 1, green: 0.85, blue: 0.95).opacity(0.12), location: 0.4),
                                               .init(color: .white.opacity(0.22), location: 0.5),
                                               .init(color: Color(red: 0.8, green: 0.95, blue: 1).opacity(0.12), location: 0.6),
                                               .init(color: .clear, location: 1.0)],
                                       startPoint: .leading, endPoint: .trailing)
                            .frame(width: proxy.size.width * 0.55, height: proxy.size.height * 2)
                            .rotationEffect(.degrees(24))
                            .offset(x: (sweep ? 0.3 : -1.2) * travel + tilt.x * travel * 0.6, y: -proxy.size.height * 0.5 + tilt.y * 30)
                            .blendMode(.plusLighter)
                    }
                    .clipShape(.rect(cornerRadius: cornerRadius, style: .continuous))
                    .allowsHitTesting(false)
                    .transition(.opacity)
                }
            }
            .rotation3DEffect(.degrees(active ? tilt.x * 7 : 0), axis: (x: 0, y: 1, z: 0), perspective: 0.5)
            .rotation3DEffect(.degrees(active ? -tilt.y * 5 : 0), axis: (x: 1, y: 0, z: 0), perspective: 0.5)
            .onChange(of: active, initial: true) {
                if active {
                    tilt.start()
                    sweep = false
                    // One slow pass of light as the card comes up.
                    withAnimation(.easeInOut(duration: 1.4).delay(0.35)) { sweep = true }
                } else {
                    tilt.stop()
                }
            }
            .onDisappear { if active { tilt.stop() } }
    }
}

extension View {
    func cardSheen(_ active: Bool, cornerRadius: CGFloat = 16) -> some View {
        modifier(CardSheen(active: active, cornerRadius: cornerRadius))
    }
}

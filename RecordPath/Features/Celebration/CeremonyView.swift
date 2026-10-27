import SwiftUI
import MapKit

/// Plays the waiting firsts one after another. Countries, provinces and milestones wait to be
/// lit by hand — press and hold — because earning something should feel like a moment. Cities
/// light themselves.
struct CeremonyView: View {
    let items: [Celebrations.Item]
    @Environment(\.dismiss) private var dismiss
    @State private var index = 0

    var body: some View {
        ZStack {
            Color.black.ignoresSafeArea()
            if items.indices.contains(index) {
                let item = items[index]
                Group {
                    if item.kind == .milestone, let milestone = item.milestone {
                        MilestoneCeremony(item: item, milestone: milestone, isLast: index == items.count - 1, next: advance)
                    } else {
                        PlaceCeremony(item: item, isLast: index == items.count - 1, next: advance)
                    }
                }
                .id(item.id)
                .transition(.asymmetric(insertion: .opacity.combined(with: .scale(scale: 1.08)),
                                        removal: .opacity.combined(with: .scale(scale: 0.94))))
            }
        }
        .overlay(alignment: .top) {
            HStack(spacing: 4) {
                if items.count > 1 {
                    ForEach(items.indices, id: \.self) { i in
                        Capsule().fill(.white.opacity(i <= index ? 0.9 : 0.25)).frame(height: 3)
                    }
                }
                Spacer(minLength: 0)
                Button {
                    items.forEach(Celebrations.shared.finish)
                    dismiss()
                } label: {
                    Image(systemName: "xmark")
                        .font(.subheadline.weight(.bold))
                        .frame(width: 34, height: 34)
                        .background(.white.opacity(0.15), in: .circle)
                }
                .tint(.white)
                .accessibilityLabel("关闭")
                .padding(.leading, 8)
            }
            .padding(.horizontal, 16)
            .padding(.top, 8)
        }
        .preferredColorScheme(.dark)
        .statusBarHidden()
    }

    private func advance() {
        Celebrations.shared.finish(items[index])
        if index + 1 < items.count {
            withAnimation(.smooth(duration: 0.6)) { index += 1 }
        } else {
            dismiss()
        }
    }
}

// MARK: - Press and hold

/// Fills a ring while the finger stays down, ticking harder as it fills, and calls `lit`
/// when it's full. Letting go early drains it.
private struct HoldToLight: ViewModifier {
    let isLit: Bool
    @Binding var progress: CGFloat
    let duration: Double
    let lit: () -> Void
    @State private var ticks: Task<Void, Never>?

    func body(content: Content) -> some View {
        content
            .onLongPressGesture(minimumDuration: duration, maximumDistance: 60) {
                guard !isLit else { return }
                ticks?.cancel()
                lit()
            } onPressingChanged: { pressing in
                guard !isLit else { return }
                if pressing {
                    withAnimation(.linear(duration: duration)) { progress = 1 }
                    ticks = Task { @MainActor in
                        for step in 1...10 {
                            try? await Task.sleep(for: .seconds(duration / 10))
                            if Task.isCancelled { return }
                            UIImpactFeedbackGenerator(style: .soft).impactOccurred(intensity: 0.25 + 0.075 * Double(step))
                        }
                    }
                } else {
                    ticks?.cancel()
                    if !isLit { withAnimation(.spring(response: 0.4, dampingFraction: 0.8)) { progress = 0 } }
                }
            }
            .accessibilityAction(named: Text("点亮")) { if !isLit { lit() } }
    }
}

private extension View {
    func holdToLight(isLit: Bool, progress: Binding<CGFloat>, duration: Double = 1.4, lit: @escaping () -> Void) -> some View {
        modifier(HoldToLight(isLit: isLit, progress: progress, duration: duration, lit: lit))
    }
}

private struct HoldHint: View {
    let isLit: Bool
    let progress: CGFloat
    @State private var breathe = false

    var body: some View {
        Label("按住点亮", systemImage: "hand.tap.fill")
            .font(.subheadline.weight(.semibold))
            .foregroundStyle(.white.opacity(0.85))
            .padding(.horizontal, 16).padding(.vertical, 9)
            .background(.white.opacity(0.12), in: .capsule)
            .opacity(isLit ? 0 : (breathe ? 1 : 0.55))
            .scaleEffect(progress > 0 ? 0.92 : 1)
            .animation(.easeInOut(duration: 1.1).repeatForever(autoreverses: true), value: breathe)
            .animation(.smooth, value: isLit)
            .onAppear { breathe = true }
    }
}

// MARK: - Milestone

private struct MilestoneCeremony: View {
    let item: Celebrations.Item
    let milestone: Milestone
    let isLast: Bool
    let next: () -> Void

    @State private var hold: CGFloat = 0
    @State private var isLit = false
    @State private var appeared = false
    @State private var burst: Date?
    @State private var flash = false
    @State private var share: Image?

    var body: some View {
        let colors = milestone.kind.colors
        ZStack {
            RadialGradient(colors: [colors[1].opacity(isLit ? 0.85 : 0.25), .black], center: .center, startRadius: 20, endRadius: 520)
                .animation(.easeOut(duration: 1.2), value: isLit)
                // An overlay, so the oversized beams never widen the page.
                .overlay {
                    Rays(color: milestone.metal[0])
                        .frame(width: 720, height: 720)
                        .opacity(isLit ? 0.55 : 0)
                        .scaleEffect(isLit ? 1 : 0.4)
                        .animation(.spring(response: 1.2, dampingFraction: 0.8), value: isLit)
                }
                .clipped()
                .ignoresSafeArea()
                .allowsHitTesting(false)

            VStack(spacing: 26) {
                Spacer()
                Text(isLit ? "达成里程碑" : "新的奖牌")
                    .textCase(.uppercase)
                    .font(.footnote.weight(.bold))
                    .tracking(3)
                    .foregroundStyle(.white.opacity(0.7))
                    .contentTransition(.opacity)

                ZStack {
                    // The hold ring sits just outside the rosette.
                    Circle().stroke(.white.opacity(isLit ? 0 : 0.12), lineWidth: 4)
                    Circle()
                        .trim(from: 0, to: hold)
                        .stroke(LinearGradient(colors: [.white, milestone.metal[0]], startPoint: .top, endPoint: .bottom),
                                style: StrokeStyle(lineWidth: 4, lineCap: .round))
                        .rotationEffect(.degrees(-90))
                        .opacity(isLit ? 0 : 1)
                    MilestoneBadge(milestone: milestone, size: 210, shimmers: true)
                        .saturation(isLit ? 1 : Double(hold) * 0.6)
                        .brightness(isLit ? 0 : -0.35 + Double(hold) * 0.25)
                        .scaleEffect(isLit ? 1 : 0.92 + hold * 0.06)
                        .rotation3DEffect(.degrees(isLit ? 360 : 0), axis: (x: 0, y: 1, z: 0), perspective: 0.5)
                        .shadow(color: colors[1].opacity(isLit ? 0.8 : 0), radius: 40)
                        .padding(18)
                    Circle()
                        .fill(.white)
                        .scaleEffect(flash ? 2.4 : 0.3)
                        .opacity(flash ? 0 : (isLit ? 0.9 : 0))
                        .allowsHitTesting(false)
                }
                .frame(width: 262, height: 262)
                .contentShape(.circle)
                .holdToLight(isLit: isLit, progress: $hold) { light() }
                .scaleEffect(appeared ? 1 : 0.3)
                .opacity(appeared ? 1 : 0)

                VStack(spacing: 8) {
                    Text(milestone.title)
                        .font(.system(size: 30, weight: .heavy, design: .rounded))
                        .multilineTextAlignment(.center)
                    Text(isLit ? item.date.formatted(.dateTime.year().month().day().locale(appLocale)) : milestone.kind.title)
                        .font(.headline)
                        .foregroundStyle(.white.opacity(0.7))
                        .contentTransition(.opacity)
                }
                .foregroundStyle(.white)
                .opacity(appeared ? 1 : 0)
                .offset(y: appeared ? 0 : 20)

                Spacer()
                ZStack {
                    HoldHint(isLit: isLit, progress: hold)
                    CeremonyActions(isLit: isLit, isLast: isLast, share: share, next: next)
                }
                .frame(height: 60)
                .padding(.bottom, 24)
            }
            .padding(.horizontal, 28)

            if let burst { Confetti(start: burst, colors: colors + [milestone.metal[0], .white]).allowsHitTesting(false) }
        }
        .onAppear {
            withAnimation(.spring(response: 0.8, dampingFraction: 0.7).delay(0.15)) { appeared = true }
        }
    }

    private func light() {
        UINotificationFeedbackGenerator().notificationOccurred(.success)
        withAnimation(.spring(response: 1.1, dampingFraction: 0.75)) { isLit = true }
        withAnimation(.easeOut(duration: 0.7)) { flash = true }
        burst = Date()
        share = CeremonyShareCard.render(title: milestone.title, subtitle: item.date.formatted(.dateTime.year().month().day().locale(appLocale))) {
            MilestoneBadge(milestone: milestone, size: 200)
        }
    }
}

// MARK: - Places

private struct PlaceCeremony: View {
    let item: Celebrations.Item
    let isLast: Bool
    let next: () -> Void

    @State private var map: UIImage?
    @State private var hold: CGFloat = 0
    @State private var isLit = false
    @State private var reveal: CGFloat = 0
    @State private var zoom: CGFloat = 1.3
    @State private var pulse = false
    @State private var ripple = false
    @State private var burst: Date?
    @State private var share: Image?

    /// Cities light themselves; countries and provinces are lit by hand.
    private var isHeld: Bool { item.kind != .city }

    private var tint: Color {
        switch item.kind {
        case .country: Color(red: 1, green: 0.45, blue: 0.4)
        case .province: Color(red: 1, green: 0.62, blue: 0.2)
        default: Color(red: 0.5, green: 0.55, blue: 1)
        }
    }

    var body: some View {
        ZStack {
            // Map and pin cover the whole screen; the words stay inside the safe area.
            GeometryReader { geo in
                ZStack {
                    mapLayer(size: geo.size, diagonal: hypot(geo.size.width, geo.size.height))
                    LinearGradient(stops: [.init(color: .black.opacity(0.75), location: 0), .init(color: .clear, location: 0.3),
                                           .init(color: .clear, location: 0.5), .init(color: .black.opacity(0.9), location: 0.85)],
                                   startPoint: .top, endPoint: .bottom)
                        .allowsHitTesting(false)
                    pin
                        .position(x: geo.size.width / 2, y: geo.size.height * 0.42)
                }
            }
            .ignoresSafeArea()

                VStack(alignment: .leading, spacing: 10) {
                    Spacer()
                    if item.kind == .country, let code = item.countryCode {
                        Text(String.flag(for: code))
                            .font(.system(size: 64))
                            .rotationEffect(.degrees(isLit ? 0 : -25))
                            .offset(y: isLit ? 0 : -260)
                            .opacity(isLit ? 1 : 0)
                            .animation(.spring(response: 0.7, dampingFraction: 0.55).delay(0.35), value: isLit)
                    }
                    Text(kindLabel)
                        .textCase(.uppercase)
                        .font(.footnote.weight(.bold)).tracking(3)
                        .foregroundStyle(tint)
                    Text(displayTitle)
                        .font(.system(size: 36, weight: .heavy))
                        .minimumScaleFactor(0.6).lineLimit(2)
                    Text(item.subtitle)
                        .font(.title3.weight(.semibold))
                        .foregroundStyle(.white.opacity(0.75))
                        .opacity(isLit ? 1 : 0)
                        .offset(y: isLit ? 0 : 12)
                        .animation(.smooth(duration: 0.6).delay(0.5), value: isLit)
                    ZStack {
                        if isHeld { HoldHint(isLit: isLit, progress: hold) }
                        CeremonyActions(isLit: isLit, isLast: isLast, share: share, next: next)
                    }
                    .frame(maxWidth: .infinity)
                    .frame(height: 60)
                    .padding(.top, 18)
                    .padding(.bottom, 24)
                }
                .foregroundStyle(.white)
                .padding(.horizontal, 28)

                if let burst { Confetti(start: burst, colors: [tint, .white, .yellow, .pink]).allowsHitTesting(false) }
        }
        .task {
            map = await Self.snapshot(item)
            withAnimation(.easeOut(duration: 3.2)) { zoom = 1.0 }
            if !isHeld {
                try? await Task.sleep(for: .seconds(0.9))
                light()
            }
        }
        .onAppear { pulse = true }
    }

    /// The flag drops in on its own, so it isn't repeated at the end of the title.
    private var displayTitle: String {
        guard item.kind == .country, let code = item.countryCode else { return item.title }
        return item.title.replacingOccurrences(of: String.flag(for: code), with: "").trimmingCharacters(in: .whitespaces)
    }

    private var kindLabel: LocalizedStringKey {
        switch item.kind {
        case .country: "新的国家和地区"
        case .province: "新的省份"
        default: "新的城市"
        }
    }

    @ViewBuilder
    private func mapLayer(size: CGSize, diagonal: CGFloat) -> some View {
        ZStack {
            if let map {
                let image = Image(uiImage: map).resizable().scaledToFill()
                image.saturation(0).brightness(-0.25).contrast(0.9)
                image
                    .mask {
                        Circle()
                            .frame(width: diagonal * 2 * reveal, height: diagonal * 2 * reveal)
                            .position(x: size.width / 2, y: size.height * 0.42)
                            .blur(radius: 30 * (1 - reveal) + 6)
                    }
            } else {
                RadialGradient(colors: [tint.opacity(0.4), .black], center: .center, startRadius: 10, endRadius: 500)
            }
        }
        .frame(width: size.width, height: size.height)
        .scaleEffect(zoom, anchor: UnitPoint(x: 0.5, y: 0.42))
        .clipped()
    }

    private var pin: some View {
        ZStack {
            // Breathing while it waits, a wide ripple when it lights.
            Circle()
                .stroke(tint.opacity(0.6), lineWidth: 2)
                .frame(width: 120, height: 120)
                .scaleEffect(pulse ? 1.15 : 0.7)
                .opacity(isLit ? 0 : (pulse ? 0.1 : 0.8))
                .animation(.easeInOut(duration: 1.4).repeatForever(autoreverses: false), value: pulse)
            Circle()
                .stroke(.white, lineWidth: 3)
                .frame(width: 120, height: 120)
                .scaleEffect(ripple ? 4 : 0.5)
                .opacity(ripple ? 0 : 0.9)
            if isHeld {
                Circle()
                    .trim(from: 0, to: hold)
                    .stroke(.white, style: StrokeStyle(lineWidth: 4, lineCap: .round))
                    .rotationEffect(.degrees(-90))
                    .frame(width: 96, height: 96)
                    .opacity(isLit ? 0 : 1)
            }
            Circle()
                .fill(isLit ? AnyShapeStyle(tint.gradient) : AnyShapeStyle(Color.white.opacity(0.18)))
                .frame(width: 70, height: 70)
                .overlay(Circle().stroke(.white, lineWidth: 3))
                .overlay {
                    Image(systemName: item.kind == .country ? "globe.asia.australia.fill" : item.kind == .province ? "map.fill" : "building.2.fill")
                        .font(.system(size: 28, weight: .semibold))
                        .foregroundStyle(.white)
                        .symbolEffect(.bounce, value: isLit)
                }
                .shadow(color: tint.opacity(isLit ? 0.9 : 0), radius: 24)
                .scaleEffect(isLit ? 1 : 0.9 + hold * 0.15)
        }
        .frame(width: 140, height: 140)
        .contentShape(.circle)
        .holdToLight(isLit: isLit || !isHeld, progress: $hold) { light() }
    }

    private func light() {
        guard !isLit else { return }
        UINotificationFeedbackGenerator().notificationOccurred(.success)
        withAnimation(.spring(response: 0.6, dampingFraction: 0.6)) { isLit = true }
        withAnimation(.easeOut(duration: 1.6)) { reveal = 1 }
        withAnimation(.easeOut(duration: 1.2)) { ripple = true }
        if item.kind != .city { burst = Date() }
        share = CeremonyShareCard.render(title: item.title, subtitle: item.subtitle) {
            Group {
                if let map {
                    Image(uiImage: map).resizable().scaledToFill()
                        .frame(width: 300, height: 220)
                        .clipShape(.rect(cornerRadius: 24, style: .continuous))
                }
            }
        }
    }

    private static func snapshot(_ item: Celebrations.Item) async -> UIImage? {
        guard let coordinate = item.coordinate else { return nil }
        let meters: CLLocationDistance = switch item.kind {
        case .country: 1_400_000
        case .province: 420_000
        default: 26_000
        }
        let options = MKMapSnapshotter.Options()
        options.region = MKCoordinateRegion(center: coordinate.onMap, latitudinalMeters: meters * 1.6, longitudinalMeters: meters)
        let screen = UIScreen.main.bounds.size
        options.size = CGSize(width: screen.width, height: screen.height)
        options.traitCollection = UITraitCollection(userInterfaceStyle: .dark)
        let configuration = MKStandardMapConfiguration(elevationStyle: .realistic, emphasisStyle: .default)
        configuration.pointOfInterestFilter = .excludingAll
        options.preferredConfiguration = configuration
        return try? await MKMapSnapshotter(options: options).start().image
    }
}

// MARK: - Shared pieces

private struct CeremonyActions: View {
    let isLit: Bool
    let isLast: Bool
    let share: Image?
    let next: () -> Void

    var body: some View {
        HStack(spacing: 12) {
            if let share {
                ShareLink(item: share, preview: SharePreview(AppInfo.name, image: share)) {
                    Image(systemName: "square.and.arrow.up")
                        .font(.headline)
                        .frame(width: 54, height: 54)
                        .background(.white.opacity(0.15), in: .circle)
                }
                .tint(.white)
                .accessibilityLabel("分享")
            }
            Button(action: next) {
                Text(isLast ? "完成" : "继续")
                    .font(.headline)
                    .foregroundStyle(.black)
                    .frame(maxWidth: .infinity)
                    .frame(height: 54)
                    .background(.white, in: .capsule)
            }
        }
        .opacity(isLit ? 1 : 0)
        .offset(y: isLit ? 0 : 16)
        .allowsHitTesting(isLit)
        .animation(.smooth(duration: 0.5).delay(isLit ? 0.9 : 0), value: isLit)
    }
}

/// Slowly turning beams of light behind a lit medal.
private struct Rays: View {
    let color: Color
    @State private var turn = false

    var body: some View {
        Canvas { context, size in
            let center = CGPoint(x: size.width / 2, y: size.height / 2)
            let radius = min(size.width, size.height) / 2
            for i in 0..<14 {
                let angle = Double(i) / 14 * 2 * .pi
                var beam = Path()
                beam.move(to: center)
                beam.addArc(center: center, radius: radius, startAngle: .radians(angle - 0.07), endAngle: .radians(angle + 0.07), clockwise: false)
                beam.closeSubpath()
                context.fill(beam, with: .radialGradient(Gradient(colors: [color.opacity(0.9), color.opacity(0)]),
                                                         center: center, startRadius: 40, endRadius: radius))
            }
        }
        .rotationEffect(.degrees(turn ? 360 : 0))
        .animation(.linear(duration: 40).repeatForever(autoreverses: false), value: turn)
        .onAppear { turn = true }
    }
}

/// A burst of paper falling from the middle of the screen.
private struct Confetti: View {
    let start: Date
    let colors: [Color]

    private struct Piece {
        let angle: Double, speed: Double, spin: Double, size: CGSize, color: Int, wobble: Double
    }

    private let pieces: [Piece]

    init(start: Date, colors: [Color]) {
        self.start = start
        self.colors = colors
        pieces = (0..<110).map { _ in
            Piece(angle: .random(in: 0...(2 * .pi)), speed: .random(in: 180...620), spin: .random(in: -9...9),
                  size: CGSize(width: .random(in: 6...11), height: .random(in: 9...16)),
                  color: .random(in: 0..<max(colors.count, 1)), wobble: .random(in: 0...6))
        }
    }

    var body: some View {
        TimelineView(.animation) { timeline in
            let t = timeline.date.timeIntervalSince(start)
            Canvas { context, size in
                guard t < 4.5 else { return }
                let origin = CGPoint(x: size.width / 2, y: size.height * 0.4)
                for piece in pieces {
                    // Thrown outward, slowed by air, pulled down.
                    let drag = (1 - exp(-2.2 * t)) / 2.2
                    let x = origin.x + cos(piece.angle) * piece.speed * drag + sin(t * 5 + piece.wobble) * 8
                    let y = origin.y + sin(piece.angle) * piece.speed * drag + 160 * t * t
                    var copy = context
                    copy.opacity = max(0, 1 - max(0, t - 3) / 1.5)
                    copy.translateBy(x: x, y: y)
                    copy.rotate(by: .radians(piece.spin * t))
                    copy.scaleBy(x: 1, y: abs(cos(t * 6 + piece.wobble)))
                    copy.fill(Path(CGRect(origin: CGPoint(x: -piece.size.width / 2, y: -piece.size.height / 2), size: piece.size)),
                              with: .color(colors[piece.color % colors.count]))
                }
            }
        }
        .ignoresSafeArea()
    }
}

/// The picture shared from a ceremony.
enum CeremonyShareCard {
    @MainActor
    static func render<Art: View>(title: String, subtitle: String, @ViewBuilder art: () -> Art) -> Image? {
        let card = VStack(spacing: 18) {
            art()
            VStack(spacing: 6) {
                Text(title).font(.system(size: 26, weight: .heavy, design: .rounded)).multilineTextAlignment(.center)
                Text(subtitle).font(.headline).opacity(0.75).multilineTextAlignment(.center)
            }
            Text(AppInfo.name).font(.footnote.weight(.bold)).opacity(0.6).padding(.top, 6)
        }
        .foregroundStyle(.white)
        .padding(32)
        .frame(width: 360, height: 480)
        .background(LinearGradient(colors: [Color(red: 0.1, green: 0.08, blue: 0.25), Color(red: 0.35, green: 0.12, blue: 0.45)],
                                   startPoint: .top, endPoint: .bottom))
        .environment(\.locale, appLocale)
        let renderer = ImageRenderer(content: card)
        renderer.scale = 3
        return renderer.uiImage.map { Image(uiImage: $0) }
    }
}

// MARK: - Sight banner

/// A quiet banner for a new sight, at the top of the screen for a few seconds.
struct SightBanner: View {
    let item: Celebrations.Item
    let done: () -> Void
    @State private var shown = false

    var body: some View {
        HStack(spacing: 12) {
            ZStack {
                Circle().fill(LinearGradient(colors: [.yellow, .orange], startPoint: .top, endPoint: .bottom))
                Image(systemName: "star.fill").font(.system(size: 18, weight: .bold)).foregroundStyle(.white)
                    .symbolEffect(.bounce, value: shown)
            }
            .frame(width: 42, height: 42)
            VStack(alignment: .leading, spacing: 1) {
                Text(item.title).font(.headline).lineLimit(1)
                Text(item.subtitle).font(.footnote).foregroundStyle(.secondary).lineLimit(1)
            }
            Spacer(minLength: 0)
        }
        .padding(.horizontal, 14).padding(.vertical, 10)
        .glassEffect(.regular, in: .capsule)
        .padding(.horizontal, 16)
        .offset(y: shown ? 0 : -140)
        .onTapGesture { hide() }
        .task {
            withAnimation(.spring(response: 0.55, dampingFraction: 0.72)) { shown = true }
            UIImpactFeedbackGenerator(style: .light).impactOccurred()
            // Taken off screen early (a ceremony, another sheet): it hasn't been seen, keep it.
            guard (try? await Task.sleep(for: .seconds(4))) != nil else { return }
            hide()
        }
    }

    private func hide() {
        withAnimation(.smooth(duration: 0.4)) { shown = false }
        Task {
            try? await Task.sleep(for: .seconds(0.45))
            done()
        }
    }
}

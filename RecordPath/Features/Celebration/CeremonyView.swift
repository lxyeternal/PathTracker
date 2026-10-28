import SwiftUI
import MapKit
import SwiftData

/// Plays the waiting firsts one after another. A new country, province or city earns a stamp,
/// pressed by hand — press and hold — because earning something should feel like a moment;
/// cities stamp themselves. Milestones are lit the same way, and coming back somewhere after
/// years away gets a quiet page of its own.
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
                    } else if item.kind == .postcard {
                        PostcardCeremony(item: item, isLast: index == items.count - 1, next: advance)
                    } else if item.kind == .reunion {
                        ReunionCeremony(item: item, isLast: index == items.count - 1, next: advance)
                    } else if let stamp = item.stamp {
                        StampCeremony(item: item, stamp: stamp, isLast: index == items.count - 1, next: advance)
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
    var label: LocalizedStringKey = "按住点亮"
    @State private var breathe = false

    var body: some View {
        Label(label, systemImage: "hand.tap.fill")
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

    fileprivate static func snapshot(_ item: Celebrations.Item) async -> UIImage? {
        guard let coordinate = item.coordinate else { return nil }
        let meters: CLLocationDistance = switch item.kind {
        case .country: 1_400_000
        case .province: 420_000
        case .reunion: 2_400
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

// MARK: - Stamps

/// A page of the passport, the seal book or the city book, and the stamp above it. Holding
/// lowers the stamp onto the paper, ticking harder as it nears; when it lands it thumps, the
/// page jolts, and the ink spreads out from the middle.
private struct StampCeremony: View {
    let item: Celebrations.Item
    let stamp: Stamp
    let isLast: Bool
    let next: () -> Void

    @Environment(\.modelContext) private var context
    @State private var map: UIImage?
    @State private var route: [CGPoint] = []
    @State private var hold: CGFloat = 0
    @State private var isStamped = false
    @State private var ink: CGFloat = 0
    @State private var squash = false
    @State private var shake: CGFloat = 0
    @State private var splash: Date?
    @State private var appeared = false
    @State private var share: Image?

    /// Cities stamp themselves; countries and provinces are stamped by hand.
    private var isHeld: Bool { stamp.kind != .city }

    private var paperStyle: StampPaper.Style {
        switch stamp.kind {
        case .entry, .exit: .passport
        case .province: .seals
        case .city, .special, .set: .book
        }
    }

    private var kindLabel: LocalizedStringKey {
        switch stamp.kind {
        case .entry, .exit: "新的入境章"
        case .province: "新的省份印"
        case .city: "新的城市章"
        case .special: "特别的章"
        case .set: "集齐套章"
        }
    }

    private var pageLabel: String {
        switch stamp.kind {
        case .entry, .exit: "VISAS"
        case .province: String(localized: "省份印", bundle: .appLanguage)
        case .city: String(localized: "城市章", bundle: .appLanguage)
        case .special, .set: String(localized: "纪念章", bundle: .appLanguage)
        }
    }

    private var inkColor: Color {
        switch stamp.kind {
        case .entry, .exit: CountryStampStyle.of(stamp.countryCode ?? "").ink.color
        case .province: Ink.cinnabar.color
        case .city: CityStampStyle.of(city: stamp.city ?? "", countryCode: stamp.countryCode, coordinate: stamp.coordinate).ink.color
        case .special: SpecialStampStyle.of(stamp.code ?? "").ink.color
        case .set: (StampSet.named(stamp.code)?.ink ?? .crimson).color
        }
    }

    private var stampSize: CGSize {
        switch stamp.kind {
        case .province: CGSize(width: 150, height: 150)
        case .set: CGSize(width: 230, height: 230)
        default: CGSize(width: 210, height: 190)
        }
    }

    private var displayTitle: String {
        guard item.kind == .country, let code = item.countryCode else { return item.title }
        return item.title.replacingOccurrences(of: String.flag(for: code), with: "").trimmingCharacters(in: .whitespaces)
    }

    var body: some View {
        ZStack {
            GeometryReader { geo in
                Group {
                    if let map {
                        Image(uiImage: map).resizable().scaledToFill()
                            .saturation(0.2).brightness(-0.35).blur(radius: 6)
                    } else {
                        RadialGradient(colors: [inkColor.opacity(0.35), .black], center: .center, startRadius: 10, endRadius: 500)
                    }
                }
                .frame(width: geo.size.width, height: geo.size.height)
                .clipped()
                .overlay(RadialGradient(colors: [inkColor.opacity(isStamped ? 0.35 : 0), .clear], center: .center, startRadius: 40, endRadius: 420))
                .animation(.easeOut(duration: 1.2), value: isStamped)
            }
            .ignoresSafeArea()
            .allowsHitTesting(false)

            VStack(spacing: 16) {
                Spacer(minLength: 0)
                VStack(spacing: 6) {
                    if item.kind == .country, let code = item.countryCode {
                        Text(String.flag(for: code)).font(.system(size: 40))
                    }
                    Text(kindLabel)
                        .textCase(.uppercase)
                        .font(.footnote.weight(.bold)).tracking(3)
                        .foregroundStyle(.white.opacity(0.7))
                    Text(displayTitle)
                        .font(.system(size: 30, weight: .heavy))
                        .multilineTextAlignment(.center)
                        .minimumScaleFactor(0.6).lineLimit(2)
                }
                .foregroundStyle(.white)
                .opacity(appeared ? 1 : 0)
                .offset(y: appeared ? 0 : -16)

                page
                    .scaleEffect(appeared ? 1 : 0.9)
                    .opacity(appeared ? 1 : 0)

                Text(item.subtitle)
                    .font(.headline)
                    .foregroundStyle(.white.opacity(0.75))
                    .multilineTextAlignment(.center)
                    .opacity(isStamped ? 1 : 0)
                    .offset(y: isStamped ? 0 : 10)
                    .animation(.smooth(duration: 0.6).delay(0.5), value: isStamped)
                Spacer(minLength: 0)
                ZStack {
                    if isHeld { HoldHint(isLit: isStamped, progress: hold, label: "按住盖章") }
                    CeremonyActions(isLit: isStamped, isLast: isLast, share: share, next: next)
                }
                .frame(height: 60)
                .padding(.bottom, 24)
            }
            .padding(.horizontal, 28)
        }
        .task {
            withAnimation(.spring(response: 0.7, dampingFraction: 0.8).delay(0.1)) { appeared = true }
            if stamp.kind == .city { route = StampRoute.load(stamp, context: context) }
            map = await PlaceCeremony.snapshot(item)
            guard !isHeld else { return }
            try? await Task.sleep(for: .seconds(1.0))
            withAnimation(.easeIn(duration: 0.45)) { hold = 1 }
            try? await Task.sleep(for: .seconds(0.45))
            press()
        }
    }

    private var page: some View {
        let tilt = stamp.tilt
        return ZStack {
            StampPaper(style: paperStyle)
            VStack {
                Text(verbatim: pageLabel.uppercased()).font(.custom("AvenirNextCondensed-DemiBold", fixedSize: 10)).tracking(3)
                Spacer()
                // Seals carry no date of their own.
                if stamp.kind == .province {
                    Text(item.date.formatted(.dateTime.year().month().day().locale(appLocale))).font(.system(size: 10, design: .monospaced))
                }
            }
            .foregroundStyle(StampPaper.line)
            .padding(.vertical, 14)

            // Where it will land.
            StampArt(stamp: stamp, route: route, inked: false)
                .frame(width: stampSize.width, height: stampSize.height)
                .rotationEffect(.degrees(tilt))
                .opacity(isStamped ? 0 : 0.7)

            // The print it leaves, the ink spreading out from the middle.
            StampArt(stamp: stamp, route: route)
                .frame(width: stampSize.width, height: stampSize.height)
                .rotationEffect(.degrees(tilt))
                .mask {
                    Circle()
                        .frame(width: 320, height: 320)
                        .scaleEffect(0.15 + ink * 1.1)
                        .blur(radius: 18 * (1 - ink) + 2)
                }
                .opacity(isStamped ? 1 : 0)

            // The stamp itself, coming down as you hold.
            StampArt(stamp: stamp, route: route)
                .frame(width: stampSize.width, height: stampSize.height)
                .rotationEffect(.degrees(tilt - 6 * (1 - hold)))
                .scaleEffect(1.3 - 0.24 * hold)
                .offset(y: -30 * (1 - hold))
                .blur(radius: 2.5 * (1 - hold))
                .opacity(isStamped ? 0 : 0.15 + 0.55 * hold)
                .shadow(color: .black.opacity(0.4 * (1 - hold) + 0.15), radius: 22 * (1 - hold) + 3, y: 18 * (1 - hold) + 2)

            if let splash { InkSplash(start: splash, color: inkColor).allowsHitTesting(false) }
        }
        .frame(width: 300, height: stamp.kind == .province ? 300 : 340)
        .clipShape(.rect(cornerRadius: 18, style: .continuous))
        .shadow(color: .black.opacity(0.5), radius: 30, y: 16)
        .rotationEffect(.degrees(-1.2))
        .scaleEffect(squash ? 0.975 : 1)
        .offset(x: shake, y: squash ? 3 : 0)
        .contentShape(.rect)
        .holdToLight(isLit: isStamped || !isHeld, progress: $hold, duration: 1.2) { press() }
        .accessibilityAction(named: Text("盖章")) { press() }
    }

    private func press() {
        guard !isStamped else { return }
        UIImpactFeedbackGenerator(style: .heavy).impactOccurred(intensity: 1)
        isStamped = true
        splash = Date()
        withAnimation(.easeOut(duration: 0.07)) { squash = true }
        withAnimation(.spring(response: 0.4, dampingFraction: 0.5).delay(0.07)) { squash = false }
        withAnimation(.easeOut(duration: 0.7)) { ink = 1 }
        Task {
            for offset in [7.0, -5, 3, -1.5, 0] {
                withAnimation(.easeOut(duration: 0.05)) { shake = offset }
                try? await Task.sleep(for: .seconds(0.05))
            }
            try? await Task.sleep(for: .seconds(0.2))
            UINotificationFeedbackGenerator().notificationOccurred(.success)
        }
        share = CeremonyShareCard.render(title: item.title, subtitle: item.subtitle) {
            ZStack {
                StampPaper(style: paperStyle)
                StampArt(stamp: stamp, route: route)
                    .frame(width: stampSize.width, height: stampSize.height)
                    .rotationEffect(.degrees(stamp.tilt))
            }
            .frame(width: 280, height: 240)
            .clipShape(.rect(cornerRadius: 18, style: .continuous))
        }
    }
}

/// A few drops of ink thrown out as the stamp lands.
private struct InkSplash: View {
    let start: Date
    let color: Color

    private struct Drop { let angle: Double, distance: Double, size: Double }
    private let drops: [Drop] = (0..<16).map { _ in
        Drop(angle: .random(in: 0...(2 * .pi)), distance: .random(in: 95...150), size: .random(in: 1.5...4))
    }

    var body: some View {
        TimelineView(.animation) { timeline in
            let t = timeline.date.timeIntervalSince(start)
            Canvas { context, size in
                guard t < 0.9 else { return }
                let center = CGPoint(x: size.width / 2, y: size.height / 2)
                let travel = 1 - pow(1 - min(t / 0.25, 1), 3)
                context.opacity = max(0, 1 - max(0, t - 0.35) / 0.55)
                for drop in drops {
                    let d = drop.distance * travel
                    let point = CGPoint(x: center.x + cos(drop.angle) * d, y: center.y + sin(drop.angle) * d)
                    context.fill(Path(ellipseIn: CGRect(x: point.x - drop.size / 2, y: point.y - drop.size / 2, width: drop.size, height: drop.size)),
                                 with: .color(color))
                }
            }
        }
    }
}

// MARK: - Reunion

/// Back somewhere after more than a year: how long it's been, counted up in front of you, and
/// the visits before, as a line through time.
private struct ReunionCeremony: View {
    let item: Celebrations.Item
    let isLast: Bool
    let next: () -> Void

    @State private var map: UIImage?
    @State private var shown = false
    @State private var days = 0
    @State private var counted = false
    @State private var share: Image?

    private let warm = Color(red: 1, green: 0.78, blue: 0.5)
    private var totalDays: Int {
        guard let last = item.lastVisit else { return 0 }
        return Calendar.current.dateComponents([.day], from: Calendar.current.startOfDay(for: last),
                                               to: Calendar.current.startOfDay(for: item.date)).day ?? 0
    }

    var body: some View {
        ZStack {
            GeometryReader { geo in
                Group {
                    if let map {
                        Image(uiImage: map).resizable().scaledToFill()
                            .saturation(0.35).colorMultiply(warm).brightness(-0.3)
                    } else {
                        Color.black
                    }
                }
                .frame(width: geo.size.width, height: geo.size.height)
                .clipped()
                .overlay(LinearGradient(colors: [.black.opacity(0.5), .black.opacity(0.2), .black.opacity(0.92)], startPoint: .top, endPoint: .bottom))
            }
            .ignoresSafeArea()
            .allowsHitTesting(false)

            VStack(spacing: 14) {
                Spacer(minLength: 0)
                Text("重逢")
                    .font(.footnote.weight(.bold)).tracking(6)
                    .foregroundStyle(warm)
                Text(item.title)
                    .font(.system(size: 32, weight: .heavy))
                    .multilineTextAlignment(.center)
                    .lineLimit(2).minimumScaleFactor(0.6)
                if !item.subtitle.isEmpty {
                    Text(item.subtitle).font(.headline).foregroundStyle(.white.opacity(0.7))
                }
                VStack(spacing: 0) {
                    Text("\(days)")
                        .font(.system(size: 84, weight: .heavy, design: .rounded))
                        .monospacedDigit()
                        .contentTransition(.numericText(value: Double(days)))
                    Text("天没来这里了")
                        .font(.title3.weight(.semibold))
                        .foregroundStyle(.white.opacity(0.8))
                }
                .padding(.vertical, 18)
                timeline
                    .opacity(counted ? 1 : 0)
                    .offset(y: counted ? 0 : 12)
                Spacer(minLength: 0)
                CeremonyActions(isLit: counted, isLast: isLast, share: share, next: next)
                    .frame(height: 60)
                    .padding(.bottom, 24)
            }
            .foregroundStyle(.white)
            .padding(.horizontal, 28)
            .opacity(shown ? 1 : 0)
        }
        .task {
            map = await PlaceCeremony.snapshot(item)
            withAnimation(.easeOut(duration: 1.2)) { shown = true }
            try? await Task.sleep(for: .seconds(0.9))
            // Counted up quickly at first, slowing as it nears the end, like time catching up.
            let total = totalDays
            for step in 1...36 {
                let t = Double(step) / 36
                withAnimation(.snappy(duration: 0.08)) { days = Int((1 - pow(1 - t, 3)) * Double(total)) }
                if step % 6 == 0 { UIImpactFeedbackGenerator(style: .soft).impactOccurred(intensity: 0.3 + t * 0.4) }
                try? await Task.sleep(for: .seconds(0.045))
            }
            days = total
            UINotificationFeedbackGenerator().notificationOccurred(.success)
            withAnimation(.smooth(duration: 0.6)) { counted = true }
            share = CeremonyShareCard.render(title: item.title, subtitle: String(localized: "\(total) 天后，又来到这里", bundle: .appLanguage)) {
                Text("重逢").font(.system(size: 54, weight: .heavy)).foregroundStyle(warm)
            }
        }
    }

    /// First visit, last visit, today.
    private var timeline: some View {
        let format = Date.FormatStyle.dateTime.year().month().day().locale(appLocale)
        var marks: [(LocalizedStringKey, String)] = []
        if let first = item.firstVisit, let last = item.lastVisit, !Calendar.current.isDate(first, inSameDayAs: last) {
            marks.append(("第一次", first.formatted(format)))
        }
        if let last = item.lastVisit { marks.append(("上一次", last.formatted(format))) }
        marks.append(("今天", item.date.formatted(format)))
        return VStack(spacing: 14) {
            HStack(alignment: .top, spacing: 0) {
                ForEach(marks.indices, id: \.self) { index in
                    VStack(spacing: 6) {
                        Circle()
                            .fill(index == marks.count - 1 ? warm : .white.opacity(0.6))
                            .frame(width: 10, height: 10)
                        Text(marks[index].0).font(.caption.weight(.semibold)).foregroundStyle(.white.opacity(0.7))
                        Text(marks[index].1).font(.caption2).foregroundStyle(.white.opacity(0.6)).monospacedDigit()
                    }
                    .frame(maxWidth: .infinity)
                }
            }
            // One line from the first mark to today, behind the dots.
            .background(alignment: .topLeading) {
                GeometryReader { geo in
                    let column = geo.size.width / CGFloat(marks.count)
                    Rectangle()
                        .fill(.white.opacity(0.3))
                        .frame(width: column * CGFloat(marks.count - 1), height: 1.5)
                        .offset(x: column / 2, y: 4.25)
                }
            }
            if let visits = item.visits {
                Text("这是你第 \(visits) 次来这里").font(.subheadline).foregroundStyle(.white.opacity(0.75))
            }
        }
    }
}

// MARK: - Postcard

/// A postcard sent a year ago arrives: it drops in from above, lands, and turns over to show
/// what you wrote.
private struct PostcardCeremony: View {
    let item: Celebrations.Item
    let isLast: Bool
    let next: () -> Void

    @Environment(\.modelContext) private var context
    @State private var content: PostcardContent?
    @State private var landed = false
    @State private var flipped = false
    @State private var share: Image?

    var body: some View {
        ZStack {
            RadialGradient(colors: [Color(red: 0.45, green: 0.25, blue: 0.12), .black], center: .center, startRadius: 20, endRadius: 520)
                .ignoresSafeArea()
            VStack(spacing: 18) {
                Spacer(minLength: 0)
                VStack(spacing: 6) {
                    Text("来自一年前的你")
                        .font(.footnote.weight(.bold)).tracking(4)
                        .foregroundStyle(Color(red: 1, green: 0.8, blue: 0.55))
                    Text(trip.map { "\($0.coverEmoji) \($0.title)" } ?? item.title)
                        .font(.system(size: 26, weight: .heavy))
                        .multilineTextAlignment(.center)
                    Text(String(localized: "寄出于 \(item.subtitle)", bundle: .appLanguage))
                        .font(.subheadline).foregroundStyle(.white.opacity(0.65))
                }
                .foregroundStyle(.white)
                .opacity(landed ? 1 : 0)
                if let content {
                    PostcardView(content: content, flipped: $flipped)
                        .rotationEffect(.degrees(landed ? -2 : -24))
                        .offset(y: landed ? 0 : -520)
                        .scaleEffect(landed ? 1 : 0.85)
                        .opacity(landed ? 1 : 0)
                        .padding(.horizontal, 6)
                }
                Label(flipped ? "轻点翻回正面" : "轻点翻到背面", systemImage: "hand.tap")
                    .font(.footnote).foregroundStyle(.white.opacity(0.6))
                    .opacity(landed ? 1 : 0)
                Spacer(minLength: 0)
                CeremonyActions(isLit: flipped || share != nil, isLast: isLast, share: share, next: next)
                    .frame(height: 60)
                    .padding(.bottom, 24)
            }
            .padding(.horizontal, 22)
        }
        .task {
            var made = makeContent()
            content = made
            // Once the screen has finished sliding up.
            try? await Task.sleep(for: .seconds(0.7))
            withAnimation(.spring(response: 0.8, dampingFraction: 0.68)) { landed = true }
            try? await Task.sleep(for: .seconds(0.5))
            UIImpactFeedbackGenerator(style: .medium).impactOccurred()
            if let trip = trip {
                let interval = trip.interval
                let assets = DayPhotos.canRead ? await Task.detached { DayPhotos.assets(in: interval) }.value : []
                made.image = await PostcardContent.picture(trip: trip, chunks: chunks(trip), assets: assets,
                                                           home: TripSuggestionCard.homeBase(in: context))
                withAnimation(.smooth) { content = made }
            }
            try? await Task.sleep(for: .seconds(1.2))
            flipped = true
            share = PostcardImage.render(made)
        }
    }

    private var trip: Trip? {
        guard let id = item.code.flatMap(UUID.init(uuidString:)) else { return nil }
        return try? context.fetch(FetchDescriptor<Trip>(predicate: #Predicate { $0.id == id })).first
    }

    private func chunks(_ trip: Trip) -> [TrackChunk] {
        let start = trip.startDate, end = trip.endDate ?? Date()
        return (try? context.fetch(FetchDescriptor<TrackChunk>(predicate: #Predicate { $0.endDate >= start && $0.startDate <= end }))) ?? []
    }

    private func makeContent() -> PostcardContent {
        guard let trip else {
            return PostcardContent(title: item.title, subtitle: item.subtitle, message: item.value ?? "",
                                   postmark: Stamp(id: "postmark.\(item.id)", kind: .city, date: item.date, city: AppInfo.name),
                                   sent: item.date)
        }
        let start = trip.startDate, end = trip.endDate ?? Date()
        let stays = ((try? context.fetch(FetchDescriptor<Stay>(predicate: #Predicate { $0.arrival <= end }))) ?? [])
            .filter { ($0.departure ?? Date()) >= start }
        var made = PostcardContent.make(trip: trip, stays: stays, chunks: chunks(trip), home: TripSuggestionCard.homeBase(in: context))
        made.message = item.value ?? made.message
        made.sent = item.date
        return made
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

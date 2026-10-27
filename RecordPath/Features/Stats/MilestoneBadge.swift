import SwiftUI

/// A milestone as an illustrated medal: a scalloped metal rosette (bronze, silver, gold,
/// platinum by tier) around a small painted scene for the kind — a road for distance, a globe
/// under a flight path for countries, mountains for provinces, a night skyline for cities, a
/// sunrise for days. The number sits on a scroll across the front, stars above it show the tier.
/// Locked medals are the same scene faded to grey with progress drawn around the face.
struct MilestoneBadge: View {
    let milestone: Milestone
    var isReached = true
    var progress: Double = 0
    var size: CGFloat = 72
    /// A slow shine across the rim, for the large medal.
    var shimmers = false

    @State private var shine = false

    var body: some View {
        ZStack(alignment: .top) {
            if isReached { ribbon.offset(y: size * 0.6) }
            ZStack {
                rim
                scene
                if !isReached { progressRing }
                stars.offset(y: -size * 0.33)
                banner.offset(y: size * 0.27)
            }
            .frame(width: size, height: size)
        }
        .frame(width: size, height: size * (isReached ? 1.16 : 1), alignment: .top)
        .accessibilityElement()
        .accessibilityLabel(milestone.title)
        .accessibilityValue(isReached ? String(localized: "已达成", bundle: .appLanguage)
                                      : progress.formatted(.percent.precision(.fractionLength(0)).locale(appLocale)))
        .onAppear {
            guard shimmers else { return }
            withAnimation(.linear(duration: 3.2).repeatForever(autoreverses: false)) { shine = true }
        }
    }

    private var faceInset: CGFloat { size * 0.12 }
    private var stroke: CGFloat { max(0.75, size * 0.01) }

    // MARK: Rim

    @ViewBuilder private var rim: some View {
        if isReached {
            Rosette(points: 20, depth: 0.04)
                .fill(AngularGradient(colors: rimShine, center: .center, angle: .degrees(shine ? 360 : 0)))
                .shadow(color: milestone.kind.colors[1].opacity(0.35), radius: size * 0.09, y: size * 0.06)
            Rosette(points: 20, depth: 0.04)
                .stroke(.white.opacity(0.4), lineWidth: stroke)
            Circle()
                .fill(LinearGradient(colors: [milestone.metal[1], milestone.metal[0]], startPoint: .top, endPoint: .bottom))
                .padding(faceInset - size * 0.028)
        } else {
            Rosette(points: 20, depth: 0.04).fill(Color.secondary.opacity(0.12))
            Rosette(points: 20, depth: 0.04).stroke(Color.secondary.opacity(0.18), lineWidth: stroke)
        }
    }

    private var rimShine: [Color] {
        let light = milestone.metal[0], dark = milestone.metal[1]
        return [light, dark, light, .white.opacity(0.9), light, dark, light]
    }

    // MARK: Scene

    private var scene: some View {
        MedalScene(kind: milestone.kind, tier: milestone.tier)
            .clipShape(.circle)
            .overlay {
                // Glass sheen across the top of the painting.
                Circle()
                    .fill(LinearGradient(colors: [.white.opacity(0.35), .white.opacity(0)], startPoint: .top, endPoint: .center))
                    .mask(Ellipse().scale(x: 0.9, y: 0.55, anchor: .top))
            }
            .overlay(Circle().strokeBorder(.black.opacity(0.12), lineWidth: stroke))
            .grayscale(isReached ? 0 : 1)
            .opacity(isReached ? 1 : 0.4)
            .padding(faceInset)
    }

    private var progressRing: some View {
        Circle()
            .trim(from: 0, to: progress)
            .stroke(milestone.kind.colors[1].gradient, style: StrokeStyle(lineWidth: size * 0.045, lineCap: .round))
            .rotationEffect(.degrees(-90))
            .padding(faceInset - size * 0.01)
    }

    // MARK: Stars and scroll

    private var stars: some View {
        let count = min(milestone.tier + 1, 5)
        return HStack(spacing: size * 0.008) {
            ForEach(0..<count, id: \.self) { index in
                Image(systemName: "star.fill")
                    .font(.system(size: size * (index == count / 2 ? 0.085 : 0.068), weight: .black))
                    .offset(y: abs(CGFloat(index) - CGFloat(count - 1) / 2) * size * 0.018)
            }
        }
        .foregroundStyle(isReached ? AnyShapeStyle(LinearGradient(colors: [.white, milestone.metal[0]], startPoint: .top, endPoint: .bottom))
                                   : AnyShapeStyle(Color.secondary.opacity(0.5)))
        .shadow(color: .black.opacity(isReached ? 0.35 : 0), radius: size * 0.01, y: size * 0.008)
    }

    private var banner: some View {
        ZStack {
            ScrollBanner()
                .fill(isReached ? AnyShapeStyle(LinearGradient(colors: [milestone.metal[0], milestone.metal[1]], startPoint: .top, endPoint: .bottom))
                                : AnyShapeStyle(Color(uiColor: .systemGray5)))
                .shadow(color: .black.opacity(isReached ? 0.25 : 0.08), radius: size * 0.02, y: size * 0.015)
            ScrollBanner()
                .stroke(.white.opacity(isReached ? 0.5 : 0.2), lineWidth: stroke)
            HStack(alignment: .firstTextBaseline, spacing: size * 0.02) {
                Text(milestone.badgeNumber)
                    .font(.system(size: size * 0.15, weight: .black, design: .rounded))
                if size >= 56 {
                    Text(milestone.kind.badgeUnit)
                        .font(.system(size: size * 0.065, weight: .heavy, design: .rounded))
                        .opacity(0.8)
                }
            }
            .foregroundStyle(isReached ? Color.black.opacity(0.72) : Color.secondary)
            .lineLimit(1)
            .minimumScaleFactor(0.5)
            .frame(width: size * 0.62)
            .offset(y: -size * 0.004)
        }
        .frame(width: size * 0.94, height: size * 0.22)
    }

    // MARK: Ribbon

    private var ribbon: some View {
        HStack(spacing: size * 0.06) {
            RibbonTail().fill(milestone.kind.colors[1].gradient).rotationEffect(.degrees(14), anchor: .top)
            RibbonTail().fill(milestone.kind.colors[0].gradient).rotationEffect(.degrees(-14), anchor: .top)
        }
        .frame(width: size * 0.5, height: size * 0.5)
        .shadow(color: .black.opacity(0.15), radius: 2, y: 1)
    }
}

/// A scroll with folded, notched ends, for the number across the medal.
struct ScrollBanner: Shape {
    func path(in rect: CGRect) -> Path {
        let w = rect.width, h = rect.height
        let tail = w * 0.12, notch = tail * 0.45, lift = h * 0.18
        var path = Path()
        // Middle band, slightly curved like it wraps the medal.
        path.move(to: CGPoint(x: tail, y: lift))
        path.addQuadCurve(to: CGPoint(x: w - tail, y: lift), control: CGPoint(x: w / 2, y: -lift * 0.6))
        path.addLine(to: CGPoint(x: w - tail, y: h - lift))
        path.addQuadCurve(to: CGPoint(x: tail, y: h - lift), control: CGPoint(x: w / 2, y: h - lift * 2.6))
        path.closeSubpath()
        // Notched ends tucked behind.
        for side in [0.0, 1.0] {
            let x0 = side == 0 ? 0 : w, x1 = side == 0 ? tail * 1.2 : w - tail * 1.2
            let xn = side == 0 ? notch : w - notch
            path.move(to: CGPoint(x: x1, y: lift * 1.8))
            path.addLine(to: CGPoint(x: x0, y: lift * 1.8))
            path.addLine(to: CGPoint(x: xn, y: (h + lift * 0.8) / 2 + lift * 0.5))
            path.addLine(to: CGPoint(x: x0, y: h - lift * 0.2))
            path.addLine(to: CGPoint(x: x1, y: h - lift * 0.2))
            path.closeSubpath()
        }
        return path
    }
}

/// The painting on a medal's face, drawn in unit space so it stays sharp at any size.
struct MedalScene: View {
    let kind: Milestone.Kind
    let tier: Int

    var body: some View {
        Canvas { context, size in
            let s = size.width
            func p(_ x: CGFloat, _ y: CGFloat) -> CGPoint { CGPoint(x: x * s, y: y * s) }
            func rect(_ x: CGFloat, _ y: CGFloat, _ w: CGFloat, _ h: CGFloat) -> CGRect { CGRect(x: x * s, y: y * s, width: w * s, height: h * s) }
            let full = CGRect(origin: .zero, size: size)
            let sky = Self.sky(kind, tier: tier)
            context.fill(Path(full), with: .linearGradient(Gradient(colors: sky), startPoint: .zero, endPoint: p(0, 1)))
            if tier >= 3, kind != .cities {
                // Higher tiers come at dusk, with the first stars out.
                for (x, y) in [(0.15, 0.14), (0.3, 0.26), (0.48, 0.1), (0.86, 0.3), (0.38, 0.06)] {
                    context.fill(Path(ellipseIn: rect(x, y, 0.016, 0.016)), with: .color(.white.opacity(0.8)))
                }
            }

            switch kind {
            case .distance:
                // Sun, rolling hills, and a road running off to the horizon.
                context.fill(Path(ellipseIn: rect(0.62, 0.2, 0.18, 0.18)), with: .color(.white.opacity(0.9)))
                var far = Path()
                far.move(to: p(0, 0.56))
                far.addQuadCurve(to: p(0.55, 0.52), control: p(0.25, 0.4))
                far.addQuadCurve(to: p(1, 0.5), control: p(0.8, 0.42))
                far.addLine(to: p(1, 1)); far.addLine(to: p(0, 1)); far.closeSubpath()
                context.fill(far, with: .color(Color(red: 0.45, green: 0.78, blue: 0.55)))
                var near = Path()
                near.move(to: p(0, 0.66))
                near.addQuadCurve(to: p(1, 0.62), control: p(0.5, 0.54))
                near.addLine(to: p(1, 1)); near.addLine(to: p(0, 1)); near.closeSubpath()
                context.fill(near, with: .color(Color(red: 0.24, green: 0.6, blue: 0.4)))
                var road = Path()
                road.move(to: p(0.47, 0.56)); road.addLine(to: p(0.53, 0.56))
                road.addQuadCurve(to: p(0.78, 1), control: p(0.5, 0.78))
                road.addLine(to: p(0.22, 1))
                road.addQuadCurve(to: p(0.47, 0.56), control: p(0.42, 0.78))
                context.fill(road, with: .color(Color(white: 0.28)))
                var line = Path()
                line.move(to: p(0.5, 0.58)); line.addQuadCurve(to: p(0.5, 1), control: p(0.47, 0.8))
                context.stroke(line, with: .color(.white.opacity(0.9)), style: StrokeStyle(lineWidth: s * 0.018, dash: [s * 0.04, s * 0.035]))

            case .countries:
                // A globe rising from below with a dashed flight arc and a plane.
                let globe = rect(0.12, 0.5, 0.76, 0.76)
                context.fill(Path(ellipseIn: globe), with: .linearGradient(Gradient(colors: [Color(red: 0.4, green: 0.75, blue: 1), Color(red: 0.1, green: 0.4, blue: 0.8)]),
                                                                          startPoint: p(0.5, 0.5), endPoint: p(0.5, 1)))
                var land = Path()
                land.addEllipse(in: rect(0.25, 0.6, 0.22, 0.12))
                land.addEllipse(in: rect(0.52, 0.66, 0.2, 0.16))
                land.addEllipse(in: rect(0.36, 0.78, 0.14, 0.1))
                context.clip(to: Path(ellipseIn: globe))
                context.fill(land, with: .color(Color(red: 0.4, green: 0.8, blue: 0.5)))
                for i in 1...3 {
                    let inset = CGFloat(i) * 0.1
                    context.stroke(Path(ellipseIn: rect(0.12 + inset, 0.5, 0.76 - inset * 2, 0.76)), with: .color(.white.opacity(0.25)), lineWidth: s * 0.008)
                }
                context.stroke(Path(ellipseIn: rect(0.12, 0.66, 0.76, 0.14)), with: .color(.white.opacity(0.25)), lineWidth: s * 0.008)
            case .provinces:
                // Three ranges of mountains, the tallest with snow.
                context.fill(Path(ellipseIn: rect(0.18, 0.2, 0.16, 0.16)), with: .color(.white.opacity(0.85)))
                func range(_ peaks: [(CGFloat, CGFloat)], base: CGFloat, color: Color) {
                    var path = Path()
                    path.move(to: p(0, base))
                    for peak in peaks { path.addLine(to: p(peak.0, peak.1)) }
                    path.addLine(to: p(1, base)); path.addLine(to: p(1, 1)); path.addLine(to: p(0, 1)); path.closeSubpath()
                    context.fill(path, with: .color(color))
                }
                range([(0.2, 0.5), (0.35, 0.58), (0.6, 0.42), (0.85, 0.55)], base: 0.6, color: Color(red: 0.98, green: 0.72, blue: 0.55))
                range([(0.15, 0.62), (0.42, 0.34), (0.58, 0.52), (0.78, 0.46)], base: 0.7, color: Color(red: 0.75, green: 0.35, blue: 0.3))
                var snow = Path()
                snow.move(to: p(0.42, 0.34)); snow.addLine(to: p(0.5, 0.43)); snow.addLine(to: p(0.45, 0.41))
                snow.addLine(to: p(0.41, 0.45)); snow.addLine(to: p(0.37, 0.41)); snow.addLine(to: p(0.35, 0.42)); snow.closeSubpath()
                context.fill(snow, with: .color(.white))
                range([(0.3, 0.7), (0.55, 0.78), (0.8, 0.66)], base: 0.82, color: Color(red: 0.45, green: 0.18, blue: 0.25))

            case .cities:
                // Night sky, moon, and a skyline with lit windows.
                for (x, y) in [(0.2, 0.2), (0.35, 0.32), (0.55, 0.18), (0.8, 0.36), (0.28, 0.42), (0.7, 0.26)] {
                    context.fill(Path(ellipseIn: rect(x, y, 0.02, 0.02)), with: .color(.white.opacity(0.85)))
                }
                var moon = Path(ellipseIn: rect(0.6, 0.12, 0.2, 0.2))
                moon = moon.subtracting(Path(ellipseIn: rect(0.66, 0.09, 0.2, 0.2)))
                context.fill(moon, with: .color(Color(red: 1, green: 0.92, blue: 0.6)))
                let buildings: [(CGFloat, CGFloat, CGFloat)] = [(0.0, 0.62, 0.16), (0.14, 0.48, 0.14), (0.27, 0.56, 0.12), (0.38, 0.36, 0.13),
                                                                (0.5, 0.52, 0.12), (0.61, 0.42, 0.15), (0.75, 0.58, 0.12), (0.86, 0.5, 0.14)]
                for (x, top, w) in buildings {
                    context.fill(Path(rect(x, top, w, 1 - top)), with: .color(Color(red: 0.16, green: 0.12, blue: 0.38)))
                    var row = top + 0.06
                    while row < 0.95 {
                        var col = x + 0.025
                        while col < x + w - 0.03 {
                            if Int((col + row) * 100) % 3 != 0 {
                                context.fill(Path(rect(col, row, 0.025, 0.03)), with: .color(Color(red: 1, green: 0.85, blue: 0.45).opacity(0.9)))
                            }
                            col += 0.045
                        }
                        row += 0.065
                    }
                }
                var spire = Path()
                spire.move(to: p(0.445, 0.36)); spire.addLine(to: p(0.445, 0.24))
                context.stroke(spire, with: .color(Color(red: 0.16, green: 0.12, blue: 0.38)), lineWidth: s * 0.015)

            case .days:
                // A sun coming up over water, with rays.
                let center = p(0.5, 0.62)
                for i in 0..<12 {
                    let angle = Double(i) / 12 * .pi * 2
                    var ray = Path()
                    ray.move(to: center)
                    ray.addLine(to: CGPoint(x: center.x + cos(angle - 0.08) * s, y: center.y + sin(angle - 0.08) * s))
                    ray.addLine(to: CGPoint(x: center.x + cos(angle + 0.08) * s, y: center.y + sin(angle + 0.08) * s))
                    ray.closeSubpath()
                    context.fill(ray, with: .color(.white.opacity(0.14)))
                }
                context.fill(Path(ellipseIn: rect(0.27, 0.39, 0.46, 0.46)), with: .linearGradient(Gradient(colors: [Color(red: 1, green: 0.95, blue: 0.6), Color(red: 1, green: 0.65, blue: 0.3)]),
                                                                                                  startPoint: p(0.5, 0.39), endPoint: p(0.5, 0.75)))
                context.fill(Path(rect(0, 0.64, 1, 0.36)), with: .linearGradient(Gradient(colors: [Color(red: 0.1, green: 0.55, blue: 0.62), Color(red: 0.03, green: 0.32, blue: 0.42)]),
                                                                                 startPoint: p(0, 0.64), endPoint: p(0, 1)))
                for (y, w) in [(0.69, 0.4), (0.75, 0.28), (0.81, 0.18)] {
                    context.fill(Path(roundedRect: rect(0.5 - w / 2, y, w, 0.018), cornerRadius: s * 0.01), with: .color(Color(red: 1, green: 0.85, blue: 0.5).opacity(0.7)))
                }
            }
        }
        .overlay {
            if kind == .countries { FlightArc().stroke(.white, style: StrokeStyle(lineWidth: 1.4, lineCap: .round, dash: [3, 3])) }
        }
        .overlay {
            if kind == .countries {
                GeometryReader { geo in
                    Image(systemName: "airplane")
                        .font(.system(size: geo.size.width * 0.14, weight: .bold))
                        .foregroundStyle(.white)
                        .rotationEffect(.degrees(-20))
                        .position(x: geo.size.width * 0.74, y: geo.size.height * 0.3)
                        .shadow(color: .black.opacity(0.2), radius: 1, y: 1)
                }
            }
        }
    }

    /// The sky moves through the day as the tiers go up: the kind's own sky, then midday,
    /// golden hour and dusk.
    static func sky(_ kind: Milestone.Kind, tier: Int) -> [Color] {
        guard kind != .cities else { return sky(kind) }
        switch tier {
        case 0: return sky(kind)
        case 1: return [Color(red: 0.25, green: 0.6, blue: 1), Color(red: 0.6, green: 0.85, blue: 1)]
        case 2: return [Color(red: 1, green: 0.55, blue: 0.35), Color(red: 1, green: 0.85, blue: 0.5)]
        default: return [Color(red: 0.2, green: 0.15, blue: 0.45), Color(red: 0.9, green: 0.45, blue: 0.5)]
        }
    }

    static func sky(_ kind: Milestone.Kind) -> [Color] {
        switch kind {
        case .distance: [Color(red: 0.45, green: 0.75, blue: 1), Color(red: 0.75, green: 0.9, blue: 1)]
        case .countries: [Color(red: 1, green: 0.55, blue: 0.5), Color(red: 1, green: 0.8, blue: 0.65)]
        case .provinces: [Color(red: 1, green: 0.62, blue: 0.3), Color(red: 1, green: 0.85, blue: 0.55)]
        case .cities: [Color(red: 0.12, green: 0.08, blue: 0.32), Color(red: 0.42, green: 0.32, blue: 0.85)]
        case .days: [Color(red: 0.2, green: 0.7, blue: 0.75), Color(red: 1, green: 0.78, blue: 0.55)]
        }
    }
}

/// The dashed flight path over the globe.
private struct FlightArc: Shape {
    func path(in rect: CGRect) -> Path {
        var path = Path()
        path.move(to: CGPoint(x: rect.width * 0.2, y: rect.height * 0.58))
        path.addQuadCurve(to: CGPoint(x: rect.width * 0.68, y: rect.height * 0.33), control: CGPoint(x: rect.width * 0.3, y: rect.height * 0.2))
        return path
    }
}

/// A circle with a scalloped edge, like a rosette or bottle cap.
struct Rosette: Shape {
    var points = 18
    /// Scallop depth as a share of the radius.
    var depth: CGFloat = 0.05

    func path(in rect: CGRect) -> Path {
        let center = CGPoint(x: rect.midX, y: rect.midY)
        let radius = min(rect.width, rect.height) / 2
        var path = Path()
        let steps = points * 12
        for i in 0...steps {
            let angle = Double(i) / Double(steps) * 2 * .pi
            let r = radius * (1 - depth * (1 - cos(Double(points) * angle)) / 2)
            let point = CGPoint(x: center.x + r * cos(angle), y: center.y + r * sin(angle))
            i == 0 ? path.move(to: point) : path.addLine(to: point)
        }
        path.closeSubpath()
        return path
    }
}

/// One ribbon tail with a notched end.
struct RibbonTail: Shape {
    func path(in rect: CGRect) -> Path {
        var path = Path()
        let w = rect.width * 0.42
        path.move(to: CGPoint(x: rect.midX - w / 2, y: rect.minY))
        path.addLine(to: CGPoint(x: rect.midX + w / 2, y: rect.minY))
        path.addLine(to: CGPoint(x: rect.midX + w / 2, y: rect.maxY))
        path.addLine(to: CGPoint(x: rect.midX, y: rect.maxY - w * 0.55))
        path.addLine(to: CGPoint(x: rect.midX - w / 2, y: rect.maxY))
        path.closeSubpath()
        return path
    }
}

extension Milestone {
    /// The number on the medal: "100", "1K", "40K".
    var badgeNumber: String {
        threshold >= 1000 ? (threshold % 1000 == 0 || threshold >= 10_000
                             ? "\(threshold / 1000)K" : String(format: "%.1fK", Double(threshold) / 1000))
                          : "\(threshold)"
    }
}

extension Milestone.Kind {
    /// The small word under the number.
    var badgeUnit: String {
        switch self {
        case .distance: String(localized: "公里", bundle: .appLanguage).uppercased()
        case .countries: String(localized: "国家", bundle: .appLanguage).uppercased()
        case .provinces: String(localized: "省份", bundle: .appLanguage).uppercased()
        case .cities: String(localized: "城市", bundle: .appLanguage).uppercased()
        case .days: String(localized: "天", bundle: .appLanguage).uppercased()
        }
    }
}

/// The medal large, turning with your finger, with what it took or what's left.
struct MilestoneDetailSheet: View {
    let status: MilestoneProgress.Status
    @State private var tilt: CGSize = .zero
    @State private var spin: Double = 0

    var body: some View {
        VStack(spacing: 18) {
            MilestoneBadge(milestone: status.milestone, isReached: status.isReached, progress: status.fraction,
                           size: 170, shimmers: status.isReached)
                .rotation3DEffect(.degrees(spin + Double(tilt.width) / 3), axis: (x: 0, y: 1, z: 0), perspective: 0.6)
                .rotation3DEffect(.degrees(-Double(tilt.height) / 5), axis: (x: 1, y: 0, z: 0), perspective: 0.6)
                .gesture(DragGesture()
                    .onChanged { tilt = $0.translation }
                    .onEnded { _ in withAnimation(.spring(response: 0.5, dampingFraction: 0.55)) { tilt = .zero } })
                .padding(.top, 30)
                .onAppear {
                    guard status.isReached else { return }
                    withAnimation(.spring(response: 1.2, dampingFraction: 0.72).delay(0.15)) { spin = 360 }
                }
                .sensoryFeedback(.success, trigger: spin) { _, new in new == 360 }

            VStack(spacing: 6) {
                Text(status.milestone.title).font(.title2.bold())
                Text(status.milestone.kind.title).font(.subheadline).foregroundStyle(.secondary)
            }

            if let date = status.date {
                Label(String(localized: "\(date.formatted(.dateTime.year().month().day().locale(appLocale))) 达成", bundle: .appLanguage),
                      systemImage: "checkmark.seal.fill")
                    .font(.subheadline.weight(.semibold))
                    .foregroundStyle(status.milestone.kind.colors[1])
                    .padding(.horizontal, 14).padding(.vertical, 8)
                    .background(status.milestone.kind.colors[1].opacity(0.12), in: .capsule)
            } else {
                VStack(spacing: 8) {
                    ProgressView(value: status.fraction)
                        .tint(status.milestone.kind.colors[1])
                        .frame(width: 220)
                    Text(remaining).font(.subheadline).foregroundStyle(.secondary)
                }
            }
            Spacer()
        }
        .frame(maxWidth: .infinity)
        .presentationDetents([.medium])
        .presentationDragIndicator(.visible)
    }

    private var remaining: String {
        let left = max(0, Double(status.milestone.threshold) - status.current)
        let value = status.milestone.kind == .distance ? Int(left.rounded(.up)) : Int(left)
        return switch status.milestone.kind {
        case .distance: String(localized: "还差 \(value) 公里", bundle: .appLanguage)
        case .countries: String(localized: "还差 \(value) 个国家和地区", bundle: .appLanguage)
        case .provinces: String(localized: "还差 \(value) 个省份", bundle: .appLanguage)
        case .cities: String(localized: "还差 \(value) 座城市", bundle: .appLanguage)
        case .days: String(localized: "还差 \(value) 天", bundle: .appLanguage)
        }
    }
}

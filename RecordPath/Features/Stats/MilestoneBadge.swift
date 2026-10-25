import SwiftUI

/// A milestone as a medal: a scalloped metal rosette (bronze, silver, gold, platinum by tier)
/// around an enamel face in the milestone's colours, the number large in the middle, a small
/// icon above it, and ribbon tails below. Locked medals are embossed grey with progress drawn
/// around the face.
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
            if isReached { ribbon.offset(y: size * 0.62) }
            ZStack {
                if isReached { reached } else { locked }
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

    // MARK: Reached

    private var faceInset: CGFloat { size * 0.15 }

    private var reached: some View {
        ZStack {
            // Rosette rim in polished metal.
            Rosette(points: 18, depth: 0.045)
                .fill(AngularGradient(colors: rimShine, center: .center, angle: .degrees(shine ? 360 : 0)))
                .shadow(color: milestone.kind.colors[1].opacity(0.35), radius: size * 0.09, y: size * 0.06)
            Rosette(points: 18, depth: 0.045)
                .stroke(.white.opacity(0.35), lineWidth: max(0.75, size * 0.01))
            // Bevel between rim and face.
            Circle()
                .fill(LinearGradient(colors: [milestone.metal[1], milestone.metal[0]], startPoint: .top, endPoint: .bottom))
                .padding(faceInset - size * 0.03)
            // Enamel face.
            Circle()
                .fill(RadialGradient(colors: [milestone.kind.colors[0], milestone.kind.colors[1]],
                                     center: UnitPoint(x: 0.35, y: 0.3), startRadius: 0, endRadius: size * 0.42))
                .padding(faceInset)
            // Fine engraved ring.
            Circle()
                .strokeBorder(.white.opacity(0.3), style: StrokeStyle(lineWidth: max(0.6, size * 0.008), dash: [size * 0.012, size * 0.02]))
                .padding(faceInset + size * 0.045)
            face(color: .white, secondary: .white.opacity(0.85))
                .shadow(color: .black.opacity(0.25), radius: size * 0.012, y: size * 0.012)
            // Glass sheen on the face.
            Circle()
                .fill(LinearGradient(colors: [.white.opacity(0.45), .white.opacity(0)], startPoint: .top, endPoint: .center))
                .padding(faceInset)
                .mask(Ellipse().scale(x: 0.95, y: 0.6, anchor: .top).padding(faceInset))
        }
    }

    private var rimShine: [Color] {
        let light = milestone.metal[0], dark = milestone.metal[1]
        return [light, dark, light, .white.opacity(0.9), light, dark, light]
    }

    private var ribbon: some View {
        HStack(spacing: size * 0.06) {
            RibbonTail().fill(milestone.kind.colors[1].gradient).rotationEffect(.degrees(14), anchor: .top)
            RibbonTail().fill(milestone.kind.colors[0].gradient).rotationEffect(.degrees(-14), anchor: .top)
        }
        .frame(width: size * 0.5, height: size * 0.5)
        .shadow(color: .black.opacity(0.15), radius: 2, y: 1)
    }

    // MARK: Locked

    private var locked: some View {
        ZStack {
            Rosette(points: 18, depth: 0.045)
                .fill(Color.secondary.opacity(0.12))
            Rosette(points: 18, depth: 0.045)
                .stroke(Color.secondary.opacity(0.18), lineWidth: max(0.75, size * 0.012))
            Circle()
                .fill(Color.secondary.opacity(0.08))
                .padding(faceInset)
            Circle()
                .stroke(Color.secondary.opacity(0.15), lineWidth: size * 0.04)
                .padding(faceInset + size * 0.02)
            Circle()
                .trim(from: 0, to: progress)
                .stroke(milestone.kind.colors[1].gradient, style: StrokeStyle(lineWidth: size * 0.04, lineCap: .round))
                .rotationEffect(.degrees(-90))
                .padding(faceInset + size * 0.02)
            face(color: .secondary.opacity(0.7), secondary: .secondary.opacity(0.55))
        }
    }

    // MARK: Face

    private func face(color: Color, secondary: Color) -> some View {
        VStack(spacing: size * 0.005) {
            Image(systemName: milestone.symbol)
                .font(.system(size: size * 0.13, weight: .bold))
                .foregroundStyle(secondary)
            Text(milestone.badgeNumber)
                .font(.system(size: size * (milestone.badgeNumber.count > 3 ? 0.2 : 0.24), weight: .heavy, design: .rounded))
                .foregroundStyle(color)
                .minimumScaleFactor(0.5)
                .lineLimit(1)
            if size >= 60 {
                // The face narrows towards the bottom, so the unit gets a narrower box than the number.
                Text(milestone.kind.badgeUnit)
                    .font(.system(size: size * 0.07, weight: .bold, design: .rounded))
                    .foregroundStyle(secondary)
                    .lineLimit(1)
                    .minimumScaleFactor(0.4)
                    .frame(maxWidth: size * 0.36)
            }
        }
        .frame(maxWidth: size * 0.5)
        .offset(y: -size * 0.02)
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

import SwiftUI

/// A medal for a milestone: a rounded hexagon in the milestone's colours, rimmed in bronze,
/// silver, gold or platinum by tier. Locked ones are grey, with how far along you are drawn
/// around the rim.
struct MilestoneBadge: View {
    let milestone: Milestone
    var isReached = true
    var progress: Double = 0
    var size: CGFloat = 72

    var body: some View {
        ZStack {
            if isReached { reached } else { locked }
        }
        .frame(width: size, height: size * 1.1)
        .accessibilityElement()
        .accessibilityLabel(milestone.title)
        .accessibilityValue(isReached ? String(localized: "已达成", bundle: .appLanguage)
                                      : progress.formatted(.percent.precision(.fractionLength(0)).locale(appLocale)))
    }

    private var rim: CGFloat { max(2.5, size * 0.055) }

    private var reached: some View {
        ZStack {
            // Metal rim.
            Hexagon(cornerRadius: size * 0.16)
                .fill(LinearGradient(colors: milestone.metal, startPoint: .topLeading, endPoint: .bottomTrailing))
                .shadow(color: milestone.kind.colors[1].opacity(0.35), radius: size * 0.08, y: size * 0.05)
            // Face.
            Hexagon(cornerRadius: size * 0.13)
                .fill(LinearGradient(colors: milestone.kind.colors, startPoint: .top, endPoint: .bottom))
                .padding(rim)
            // Sheen across the top half.
            Hexagon(cornerRadius: size * 0.13)
                .fill(LinearGradient(colors: [.white.opacity(0.38), .white.opacity(0)], startPoint: .top, endPoint: .center))
                .padding(rim)
            // Inner engraved line.
            Hexagon(cornerRadius: size * 0.10)
                .stroke(.white.opacity(0.28), lineWidth: max(1, size * 0.015))
                .padding(rim + size * 0.07)
            Image(systemName: milestone.symbol)
                .font(.system(size: size * 0.34, weight: .bold))
                .foregroundStyle(.white)
                .shadow(color: .black.opacity(0.22), radius: 1.5, y: 1)
        }
    }

    private var locked: some View {
        ZStack {
            Hexagon(cornerRadius: size * 0.16)
                .fill(Color.secondary.opacity(0.12))
            Hexagon(cornerRadius: size * 0.16)
                .stroke(Color.secondary.opacity(0.18), lineWidth: rim)
            Hexagon(cornerRadius: size * 0.16)
                .trim(from: 0, to: progress)
                .stroke(milestone.kind.colors[1].gradient, style: StrokeStyle(lineWidth: rim, lineCap: .round))
            Image(systemName: milestone.symbol)
                .font(.system(size: size * 0.32, weight: .semibold))
                .foregroundStyle(.tertiary)
        }
    }
}

/// A hexagon standing on a point, with rounded corners.
struct Hexagon: Shape {
    var cornerRadius: CGFloat = 10

    func path(in rect: CGRect) -> Path {
        let center = CGPoint(x: rect.midX, y: rect.midY)
        let rx = rect.width / 2, ry = rect.height / 2
        let corners = (0..<6).map { i -> CGPoint in
            let angle = Double(i) * .pi / 3 - .pi / 2
            return CGPoint(x: center.x + rx * cos(angle), y: center.y + ry * sin(angle))
        }
        var path = Path()
        // Start between the last and first corner so every corner gets rounded.
        let start = CGPoint(x: (corners[5].x + corners[0].x) / 2, y: (corners[5].y + corners[0].y) / 2)
        path.move(to: start)
        for i in 0..<6 {
            path.addArc(tangent1End: corners[i], tangent2End: corners[(i + 1) % 6], radius: cornerRadius)
        }
        path.closeSubpath()
        return path
    }
}

/// The badge large, tilting with your finger, with what it took or what's left.
struct MilestoneDetailSheet: View {
    let status: MilestoneProgress.Status
    @State private var tilt: CGSize = .zero
    @State private var spin: Double = 0
    @Environment(\.dismiss) private var dismiss

    var body: some View {
        VStack(spacing: 18) {
            MilestoneBadge(milestone: status.milestone, isReached: status.isReached, progress: status.fraction, size: 150)
                .rotation3DEffect(.degrees(spin + Double(tilt.width) / 4), axis: (x: 0, y: 1, z: 0))
                .rotation3DEffect(.degrees(-Double(tilt.height) / 6), axis: (x: 1, y: 0, z: 0))
                .gesture(DragGesture()
                    .onChanged { tilt = $0.translation }
                    .onEnded { _ in withAnimation(.spring(response: 0.5, dampingFraction: 0.55)) { tilt = .zero } })
                .padding(.top, 28)
                .onAppear {
                    guard status.isReached else { return }
                    withAnimation(.spring(response: 1.1, dampingFraction: 0.7).delay(0.15)) { spin = 360 }
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
        return String(localized: "还差 \(value.formatted(.number.locale(appLocale))) \(status.milestone.kind.unit)", bundle: .appLanguage)
    }
}

import SwiftUI

/// Each road's own scenery: its colours and the land it runs through.
extension ClassicRoute {
    enum Scenery { case water, peaks, dunes, mesas }

    var sky: [Color] {
        switch id {
        case "canal": [Color(red: 0.12, green: 0.3, blue: 0.38), Color(red: 0.42, green: 0.64, blue: 0.64)]
        case "318": [Color(red: 0.16, green: 0.18, blue: 0.4), Color(red: 0.93, green: 0.55, blue: 0.38)]
        case "silk": [Color(red: 0.5, green: 0.28, blue: 0.16), Color(red: 0.95, green: 0.76, blue: 0.47)]
        default: [Color(red: 0.32, green: 0.11, blue: 0.24), Color(red: 0.97, green: 0.5, blue: 0.32)]
        }
    }

    var scenery: Scenery {
        switch id {
        case "canal": .water
        case "318": .peaks
        case "silk": .dunes
        default: .mesas
        }
    }
}

/// The land along the bottom of a route's poster.
struct RouteScenery: View {
    let scenery: ClassicRoute.Scenery

    var body: some View {
        Canvas { context, size in
            let w = size.width, h = size.height
            switch scenery {
            case .water:
                // An arched stone bridge over still water, and ripples.
                var bridge = Path()
                bridge.move(to: CGPoint(x: w * 0.08, y: h * 0.78))
                bridge.addQuadCurve(to: CGPoint(x: w * 0.62, y: h * 0.78), control: CGPoint(x: w * 0.35, y: h * 0.42))
                bridge.addLine(to: CGPoint(x: w * 0.62, y: h * 0.82))
                bridge.addQuadCurve(to: CGPoint(x: w * 0.08, y: h * 0.82), control: CGPoint(x: w * 0.35, y: h * 0.5))
                bridge.closeSubpath()
                context.fill(bridge, with: .color(.black.opacity(0.28)))
                var arch = Path()
                arch.addArc(center: CGPoint(x: w * 0.35, y: h * 0.82), radius: w * 0.1, startAngle: .degrees(180), endAngle: .degrees(0), clockwise: false)
                context.fill(arch, with: .color(.white.opacity(0.08)))
                context.fill(Path(CGRect(x: 0, y: h * 0.82, width: w, height: h * 0.18)), with: .color(.black.opacity(0.18)))
                for row in 0..<3 {
                    let y = h * (0.87 + Double(row) * 0.045)
                    var ripple = Path()
                    ripple.move(to: CGPoint(x: w * (0.1 + Double(row) * 0.15), y: y))
                    ripple.addLine(to: CGPoint(x: w * (0.4 + Double(row) * 0.2), y: y))
                    context.stroke(ripple, with: .color(.white.opacity(0.22)), lineWidth: 1)
                }
            case .peaks:
                // Snow peaks against the dusk, a near ridge in front.
                let far: [(CGFloat, CGFloat, CGFloat)] = [(0.05, 0.62, 0.32), (0.32, 0.5, 0.38), (0.62, 0.58, 0.34), (0.85, 0.66, 0.3)]
                for (x, top, half) in far {
                    var peak = Path()
                    peak.move(to: CGPoint(x: w * (x - half), y: h))
                    peak.addLine(to: CGPoint(x: w * x, y: h * top))
                    peak.addLine(to: CGPoint(x: w * (x + half), y: h))
                    context.fill(peak, with: .color(.black.opacity(0.22)))
                    var cap = Path()
                    cap.move(to: CGPoint(x: w * (x - half * 0.22), y: h * (top + 0.07)))
                    cap.addLine(to: CGPoint(x: w * x, y: h * top))
                    cap.addLine(to: CGPoint(x: w * (x + half * 0.22), y: h * (top + 0.07)))
                    cap.addLine(to: CGPoint(x: w * x, y: h * (top + 0.05)))
                    context.fill(cap, with: .color(.white.opacity(0.8)))
                }
                var ridge = Path()
                ridge.move(to: CGPoint(x: 0, y: h * 0.86))
                ridge.addCurve(to: CGPoint(x: w, y: h * 0.82), control1: CGPoint(x: w * 0.35, y: h * 0.74), control2: CGPoint(x: w * 0.65, y: h * 0.92))
                ridge.addLine(to: CGPoint(x: w, y: h))
                ridge.addLine(to: CGPoint(x: 0, y: h))
                context.fill(ridge, with: .color(.black.opacity(0.32)))
            case .dunes:
                // A low sun over two lines of dunes.
                context.fill(Path(ellipseIn: CGRect(x: w * 0.62, y: h * 0.5, width: w * 0.2, height: w * 0.2)), with: .color(.white.opacity(0.35)))
                for (index, base) in [0.74, 0.84].enumerated() {
                    var dune = Path()
                    dune.move(to: CGPoint(x: 0, y: h * base))
                    dune.addCurve(to: CGPoint(x: w, y: h * (base - 0.04)),
                                  control1: CGPoint(x: w * 0.3, y: h * (base - 0.14)), control2: CGPoint(x: w * 0.6, y: h * (base + 0.08)))
                    dune.addLine(to: CGPoint(x: w, y: h))
                    dune.addLine(to: CGPoint(x: 0, y: h))
                    context.fill(dune, with: .color(.black.opacity(index == 0 ? 0.16 : 0.26)))
                }
            case .mesas:
                // Flat-topped mesas against a setting sun.
                context.fill(Path(ellipseIn: CGRect(x: w * 0.38, y: h * 0.52, width: w * 0.24, height: w * 0.24)), with: .color(.yellow.opacity(0.4)))
                let mesas: [(CGFloat, CGFloat, CGFloat)] = [(0.0, 0.32, 0.66), (0.55, 0.38, 0.62), (0.3, 0.18, 0.72)]
                for (x, width, top) in mesas {
                    var mesa = Path()
                    mesa.move(to: CGPoint(x: w * x, y: h))
                    mesa.addLine(to: CGPoint(x: w * (x + 0.04), y: h * top))
                    mesa.addLine(to: CGPoint(x: w * (x + width - 0.04), y: h * top))
                    mesa.addLine(to: CGPoint(x: w * (x + width), y: h))
                    context.fill(mesa, with: .color(.black.opacity(0.3)))
                }
                context.fill(Path(CGRect(x: 0, y: h * 0.9, width: w, height: h * 0.1)), with: .color(.black.opacity(0.35)))
            }
        }
    }
}

/// A road as a small travel poster: its sky and land, its shape drawn in light, the part
/// you've walked glowing, its name and how far along you are.
struct RoutePosterCard: View {
    let route: ClassicRoute
    let travelled: Double
    let selected: Bool

    var body: some View {
        let fraction = min(travelled / max(route.length, 1), 1)
        let points = route.layout(aspect: 150 / 70, margin: 0.1)
        let shape = RouteShape(points: points)
        VStack(alignment: .leading, spacing: 0) {
            ZStack {
                shape.stroke(.white.opacity(0.4), style: StrokeStyle(lineWidth: 2, lineCap: .round, lineJoin: .round, dash: [2, 4]))
                shape.trim(from: 0, to: fraction)
                    .stroke(.white, style: StrokeStyle(lineWidth: 3.5, lineCap: .round, lineJoin: .round))
                    .shadow(color: .white.opacity(0.8), radius: 4)
                // Where the road starts and ends.
                GeometryReader { geo in
                    ForEach([points.first, points.last].compactMap { $0 }.indices, id: \.self) { index in
                        let point = index == 0 ? points[0] : points[points.count - 1]
                        Circle().fill(.white).frame(width: 6, height: 6)
                            .position(x: point.x * geo.size.width, y: point.y * geo.size.height)
                    }
                }
            }
            .frame(height: 70)
            .padding(.top, 14)
            .padding(.horizontal, 10)
            Spacer(minLength: 0)
            VStack(alignment: .leading, spacing: 3) {
                Text(route.localizedName)
                    .font(.system(.subheadline, design: .serif, weight: .bold))
                    .lineLimit(1).minimumScaleFactor(0.75)
                HStack(spacing: 5) {
                    Text(Format.distance(route.length))
                    Text(verbatim: "·")
                    if fraction >= 1 {
                        Image(systemName: "checkmark.seal.fill")
                    } else {
                        Text(fraction.formatted(.percent.precision(.fractionLength(0)).locale(appLocale)))
                    }
                }
                .font(.caption2.weight(.semibold)).opacity(0.85)
            }
            .padding(12)
        }
        .foregroundStyle(.white)
        .frame(width: 150, height: 170)
        .background {
            ZStack {
                LinearGradient(colors: route.sky, startPoint: .top, endPoint: .bottom)
                RouteScenery(scenery: route.scenery)
                LinearGradient(colors: [.clear, .black.opacity(0.35)], startPoint: .center, endPoint: .bottom)
            }
        }
        .clipShape(.rect(cornerRadius: 22, style: .continuous))
        .overlay(RoundedRectangle(cornerRadius: 22, style: .continuous)
            .strokeBorder(.white.opacity(selected ? 0.95 : 0.12), lineWidth: selected ? 2.5 : 1))
        .shadow(color: route.sky[1].opacity(selected ? 0.45 : 0), radius: 10, y: 5)
        .scaleEffect(selected ? 1 : 0.94)
        .opacity(selected ? 1 : 0.85)
    }
}

/// The stops down a rail: passed ones ticked off, where you are as a card with the way to
/// the next stop, the ones ahead quieter.
struct JourneyStops: View {
    let progress: JourneyProgress

    var body: some View {
        let route = progress.route
        VStack(alignment: .leading, spacing: 14) {
            HStack(alignment: .firstTextBaseline) {
                Text("沿途 \(route.stops.count) 站").font(.system(.title3, design: .serif, weight: .bold))
                Spacer()
                Text("已到 \(progress.lastStopIndex + 1) 站").font(.subheadline).foregroundStyle(route.tint)
            }
            VStack(spacing: 0) {
                ForEach(Array(route.stops.enumerated()), id: \.offset) { index, stop in
                    row(stop, index: index)
                }
            }
        }
    }

    private enum Kind { case passed, here, next, ahead }

    private func kind(_ index: Int) -> Kind {
        if index == progress.lastStopIndex && !progress.isComplete { return .here }
        if index <= progress.lastStopIndex { return .passed }
        return index == progress.lastStopIndex + 1 ? .next : .ahead
    }

    private func row(_ stop: ClassicRoute.Stop, index: Int) -> some View {
        let route = progress.route
        let kind = kind(index)
        let isLast = index == route.stops.count - 1
        return HStack(alignment: .top, spacing: 14) {
            // The rail: solid where you've been, dashed ahead.
            VStack(spacing: 0) {
                marker(kind, index: index, isLast: isLast)
                if !isLast {
                    Group {
                        if index < progress.lastStopIndex || (progress.isComplete) {
                            Rectangle().fill(route.tint.gradient).frame(width: 3)
                        } else {
                            Line().stroke(Color.secondary.opacity(0.35), style: StrokeStyle(lineWidth: 2, dash: [3, 4])).frame(width: 3)
                        }
                    }
                    .frame(maxHeight: .infinity)
                }
            }
            .frame(width: 30)

            Group {
                if kind == .here { hereCard(stop, index: index) } else { plain(stop, index: index, kind: kind) }
            }
            .padding(.bottom, isLast ? 0 : 18)
        }
    }

    @ViewBuilder private func marker(_ kind: Kind, index: Int, isLast: Bool) -> some View {
        let tint = progress.route.tint
        switch kind {
        case .passed:
            Image(systemName: isLast ? "flag.checkered" : "checkmark")
                .font(.system(size: 11, weight: .bold)).foregroundStyle(.white)
                .frame(width: 24, height: 24)
                .background(Circle().fill(tint.gradient))
        case .here:
            Image(systemName: "figure.walk")
                .font(.system(size: 13, weight: .bold)).foregroundStyle(.white)
                .frame(width: 30, height: 30)
                .background(Circle().fill(tint.gradient))
                .overlay(Circle().stroke(tint.opacity(0.3), lineWidth: 6).padding(-4))
        case .next:
            Text(verbatim: "\(index + 1)").font(.caption2.weight(.bold)).foregroundStyle(tint)
                .frame(width: 24, height: 24)
                .background(Circle().fill(Color(uiColor: .systemBackground)))
                .overlay(Circle().strokeBorder(tint, lineWidth: 2.5))
        case .ahead:
            Group {
                if isLast { Image(systemName: "flag.fill").font(.system(size: 10, weight: .bold)) }
                else { Text(verbatim: "\(index + 1)").font(.caption2.weight(.semibold)) }
            }
            .foregroundStyle(.secondary)
            .frame(width: 24, height: 24)
            .background(Circle().fill(Color(uiColor: .secondarySystemBackground)))
        }
    }

    private func plain(_ stop: ClassicRoute.Stop, index: Int, kind: Kind) -> some View {
        VStack(alignment: .leading, spacing: 4) {
            HStack(alignment: .firstTextBaseline, spacing: 8) {
                Text(stop.localizedName)
                    .font(.system(kind == .ahead ? .body : .headline, design: .serif, weight: .semibold))
                    .foregroundStyle(kind == .ahead ? .secondary : .primary)
                if kind == .next {
                    Text("下一站").font(.caption2.weight(.bold)).foregroundStyle(progress.route.tint)
                        .padding(.horizontal, 7).padding(.vertical, 2)
                        .background(progress.route.tint.opacity(0.12), in: .capsule)
                }
                Spacer()
                Text(index == 0 ? String(localized: "起点", bundle: .appLanguage) : Format.distance(progress.route.marks[index]))
                    .font(.caption).foregroundStyle(.tertiary).monospacedDigit()
            }
            Text(stop.localizedNote)
                .font(.subheadline)
                .foregroundStyle(kind == .ahead ? .tertiary : .secondary)
                .lineLimit(kind == .ahead ? 1 : 3)
        }
        .padding(.top, 2)
    }

    /// Where you are: the stop large, its story, and how far to the next.
    private func hereCard(_ stop: ClassicRoute.Stop, index: Int) -> some View {
        let route = progress.route
        let span = progress.nextStop == nil ? 1 : route.marks[index + 1] - route.marks[index]
        let along = progress.nextStop == nil ? 1 : (progress.shown - route.marks[index]) / max(span, 1)
        return VStack(alignment: .leading, spacing: 10) {
            Text("你在这里").font(.caption.weight(.bold)).foregroundStyle(route.tint).tracking(1)
            Text(stop.localizedName).font(.system(.title2, design: .serif, weight: .bold))
            Text(stop.localizedNote).font(.subheadline).foregroundStyle(.secondary)
                .fixedSize(horizontal: false, vertical: true)
            if let next = progress.nextStop {
                VStack(alignment: .leading, spacing: 6) {
                    GeometryReader { geo in
                        ZStack(alignment: .leading) {
                            Capsule().fill(route.tint.opacity(0.15))
                            Capsule().fill(route.tint.gradient).frame(width: max(8, geo.size.width * along))
                        }
                    }
                    .frame(height: 6)
                    Text("再走 \(Format.distance(progress.toNext)) 到\(next.localizedName)")
                        .font(.footnote.weight(.semibold)).foregroundStyle(route.tint)
                }
                .padding(.top, 2)
            }
        }
        .padding(16)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(
            LinearGradient(colors: [route.tint.opacity(0.16), route.tint.opacity(0.05)], startPoint: .topLeading, endPoint: .bottomTrailing),
            in: .rect(cornerRadius: 20, style: .continuous)
        )
        .overlay(RoundedRectangle(cornerRadius: 20, style: .continuous).strokeBorder(route.tint.opacity(0.25), lineWidth: 1))
    }
}

/// A vertical line, for dashed rails.
private struct Line: Shape {
    func path(in rect: CGRect) -> Path {
        Path { $0.move(to: CGPoint(x: rect.midX, y: rect.minY)); $0.addLine(to: CGPoint(x: rect.midX, y: rect.maxY)) }
    }
}

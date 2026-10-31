import SwiftUI

/// A small painted scene for each kind of traveller, like the art on a travel poster: a city
/// at night for the night walker, three skylines for the city collector, a road into the
/// mountains for the explorer. Drawn in unit space so it is sharp at any size.
struct PortraitScene: View {
    let archetype: TravellerPortrait.Archetype

    var body: some View {
        Canvas { context, size in
            let w = size.width, h = size.height
            func p(_ x: CGFloat, _ y: CGFloat) -> CGPoint { CGPoint(x: x * w, y: y * h) }
            func rect(_ x: CGFloat, _ y: CGFloat, _ rw: CGFloat, _ rh: CGFloat) -> CGRect { CGRect(x: x * w, y: y * h, width: rw * w, height: rh * h) }
            func color(_ r: Double, _ g: Double, _ b: Double, _ a: Double = 1) -> GraphicsContext.Shading { .color(Color(red: r, green: g, blue: b).opacity(a)) }
            func gradient(_ colors: [Color], _ from: CGPoint, _ to: CGPoint) -> GraphicsContext.Shading {
                .linearGradient(Gradient(colors: colors), startPoint: from, endPoint: to)
            }

            // Shared pieces.
            func sky(_ top: Color, _ bottom: Color) {
                context.fill(Path(CGRect(origin: .zero, size: size)), with: gradient([top, bottom], .zero, p(0, 1)))
            }
            func stars(_ count: Int, below: CGFloat = 0.55, seed: Int = 7) {
                var x = UInt64(seed)
                for _ in 0..<count {
                    x = x &* 6364136223846793005 &+ 1442695040888963407
                    let px = CGFloat(x >> 33 % 1000) / 1000
                    x = x &* 6364136223846793005 &+ 1442695040888963407
                    let py = CGFloat(x >> 33 % 1000) / 1000 * below
                    let r = (CGFloat(x >> 40 % 3) + 1) * 0.6
                    context.fill(Path(ellipseIn: CGRect(x: px * w, y: py * h, width: r, height: r)), with: .color(.white.opacity(0.75)))
                }
            }
            func glow(at point: CGPoint, radius: CGFloat, color: Color) {
                context.fill(Path(ellipseIn: CGRect(x: point.x - radius, y: point.y - radius, width: radius * 2, height: radius * 2)),
                             with: .radialGradient(Gradient(colors: [color, color.opacity(0)]), center: point, startRadius: 0, endRadius: radius))
            }
            func hills(_ base: CGFloat, _ amplitude: CGFloat, _ phase: CGFloat, _ fill: GraphicsContext.Shading) {
                var path = Path()
                path.move(to: p(0, 1))
                for i in 0...40 {
                    let x = CGFloat(i) / 40
                    path.addLine(to: p(x, base - amplitude * (sin(x * 5 + phase) * 0.6 + sin(x * 11 + phase * 2) * 0.4)))
                }
                path.addLine(to: p(1, 1)); path.closeSubpath()
                context.fill(path, with: fill)
            }
            func mountains(_ peaks: [(CGFloat, CGFloat)], base: CGFloat, _ fill: GraphicsContext.Shading) {
                var path = Path()
                path.move(to: p(0, base))
                for peak in peaks { path.addLine(to: p(peak.0, peak.1)) }
                path.addLine(to: p(1, base)); path.addLine(to: p(1, 1)); path.addLine(to: p(0, 1)); path.closeSubpath()
                context.fill(path, with: fill)
            }
            /// A row of buildings from (x, height) pairs; lit windows when asked.
            func skyline(_ buildings: [(x: CGFloat, w: CGFloat, top: CGFloat)], base: CGFloat, fill: GraphicsContext.Shading, windows: Color? = nil) {
                for b in buildings {
                    context.fill(Path(rect(b.x, b.top, b.w, base - b.top + 0.01)), with: fill)
                    guard let windows else { continue }
                    var row = b.top + 0.025
                    var n = Int(b.x * 100)
                    while row < base - 0.02 {
                        var col = b.x + 0.012
                        while col < b.x + b.w - 0.015 {
                            n = (n &* 1103515245 &+ 12345) & 0x7fffffff
                            if n % 3 != 0 { context.fill(Path(rect(col, row, 0.008, 0.012)), with: .color(windows.opacity(0.85))) }
                            col += 0.018
                        }
                        row += 0.028
                    }
                }
                context.fill(Path(rect(0, base, 1, 1 - base)), with: fill)
            }
            func dottedPath(_ points: [CGPoint], color: Color, width: CGFloat = 2.2) {
                var path = Path()
                path.move(to: points[0])
                for i in 1..<points.count {
                    let mid = CGPoint(x: (points[i - 1].x + points[i].x) / 2, y: (points[i - 1].y + points[i].y) / 2)
                    path.addQuadCurve(to: mid, control: points[i - 1])
                }
                path.addLine(to: points.last!)
                context.stroke(path, with: .color(color), style: StrokeStyle(lineWidth: width, lineCap: .round, dash: [0.1, width * 3.2]))
            }

            switch archetype {
            case .nightWalker:
                sky(Color(red: 0.06, green: 0.07, blue: 0.2), Color(red: 0.28, green: 0.2, blue: 0.45))
                stars(60)
                glow(at: p(0.78, 0.2), radius: w * 0.16, color: Color(red: 1, green: 0.95, blue: 0.75).opacity(0.35))
                var moon = Path(ellipseIn: rect(0.72, 0.13, 0.12, 0.12 * w / h))
                moon = moon.subtracting(Path(ellipseIn: rect(0.755, 0.115, 0.12, 0.12 * w / h)))
                context.fill(moon, with: color(1, 0.94, 0.72))
                skyline([(0, 0.12, 0.5), (0.1, 0.08, 0.42), (0.17, 0.1, 0.55), (0.3, 0.07, 0.38), (0.36, 0.12, 0.5),
                         (0.5, 0.09, 0.45), (0.58, 0.13, 0.36), (0.72, 0.1, 0.5), (0.83, 0.17, 0.44)],
                        base: 0.72, fill: color(0.1, 0.09, 0.22), windows: Color(red: 1, green: 0.82, blue: 0.45))
                for x in [0.18, 0.46, 0.74] as [CGFloat] {
                    context.stroke(Path { $0.move(to: p(x, 0.98)); $0.addLine(to: p(x, 0.8)) }, with: color(0.05, 0.05, 0.12), lineWidth: 2)
                    glow(at: p(x, 0.8), radius: w * 0.07, color: Color(red: 1, green: 0.8, blue: 0.45).opacity(0.7))
                }
                dottedPath([p(0.02, 0.97), p(0.3, 0.9), p(0.55, 0.95), p(0.98, 0.88)], color: Color(red: 1, green: 0.85, blue: 0.55))

            case .earlyRiser:
                sky(Color(red: 0.98, green: 0.62, blue: 0.48), Color(red: 1, green: 0.88, blue: 0.62))
                glow(at: p(0.5, 0.66), radius: w * 0.5, color: Color(red: 1, green: 0.96, blue: 0.8).opacity(0.7))
                context.fill(Path(ellipseIn: rect(0.36, 0.52, 0.28, 0.28 * w / h)), with: color(1, 0.96, 0.82))
                for (i, y) in [0.24, 0.3].enumerated() {
                    let x = 0.2 + CGFloat(i) * 0.08
                    var bird = Path()
                    bird.move(to: p(x, y)); bird.addQuadCurve(to: p(x + 0.03, y), control: p(x + 0.015, y - 0.02))
                    bird.addQuadCurve(to: p(x + 0.06, y), control: p(x + 0.045, y - 0.02))
                    context.stroke(bird, with: color(0.45, 0.25, 0.25, 0.7), lineWidth: 1.6)
                }
                hills(0.72, 0.04, 0.5, color(0.93, 0.55, 0.45))
                hills(0.82, 0.05, 2.0, color(0.78, 0.38, 0.38))
                hills(0.92, 0.03, 3.5, color(0.55, 0.24, 0.3))

            case .cityCollector:
                sky(Color(red: 0.24, green: 0.2, blue: 0.55), Color(red: 0.95, green: 0.62, blue: 0.62))
                stars(25, below: 0.3)
                glow(at: p(0.5, 0.62), radius: w * 0.45, color: Color(red: 1, green: 0.72, blue: 0.6).opacity(0.6))
                // Three cities, one behind the other: towers, a pagoda town, domes.
                skyline([(0.05, 0.06, 0.3), (0.12, 0.04, 0.38), (0.18, 0.07, 0.24), (0.27, 0.05, 0.34), (0.66, 0.06, 0.28), (0.74, 0.05, 0.36), (0.82, 0.07, 0.3)],
                        base: 0.62, fill: color(0.55, 0.42, 0.75, 0.7))
                for (x, top) in [(0.42, 0.4), (0.55, 0.45)] as [(CGFloat, CGFloat)] {
                    for tier in 0..<4 {
                        let t = CGFloat(tier)
                        let width = 0.1 - t * 0.018, y = top + 0.2 - t * 0.055
                        var roof = Path()
                        roof.move(to: p(x - width / 2 - 0.015, y)); roof.addQuadCurve(to: p(x + width / 2 + 0.015, y), control: p(x, y - 0.03))
                        roof.addLine(to: p(x + width / 2, y + 0.04)); roof.addLine(to: p(x - width / 2, y + 0.04)); roof.closeSubpath()
                        context.fill(roof, with: color(0.42, 0.26, 0.55))
                    }
                }
                skyline([(0, 0.14, 0.7), (0.12, 0.1, 0.64), (0.3, 0.16, 0.72), (0.58, 0.12, 0.66), (0.7, 0.14, 0.7), (0.85, 0.15, 0.62)],
                        base: 0.8, fill: color(0.24, 0.15, 0.38), windows: Color(red: 1, green: 0.85, blue: 0.55))
                context.fill(Path(ellipseIn: rect(0.43, 0.66, 0.14, 0.14 * w / h)), with: color(0.24, 0.15, 0.38))
                // A pin over each city, the way a collector marks them.
                for (x, y) in [(0.15, 0.2), (0.49, 0.3), (0.8, 0.22)] as [(CGFloat, CGFloat)] {
                    var pin = Path()
                    pin.addEllipse(in: CGRect(x: x * w - 7, y: y * h - 7, width: 14, height: 14))
                    pin.move(to: CGPoint(x: x * w - 5, y: y * h + 4)); pin.addLine(to: CGPoint(x: x * w, y: y * h + 13)); pin.addLine(to: CGPoint(x: x * w + 5, y: y * h + 4))
                    context.fill(pin, with: color(1, 0.84, 0.4))
                    context.fill(Path(ellipseIn: CGRect(x: x * w - 3, y: y * h - 3, width: 6, height: 6)), with: color(0.4, 0.2, 0.5))
                }

            case .globetrotter:
                sky(Color(red: 0.03, green: 0.2, blue: 0.45), Color(red: 0.3, green: 0.62, blue: 0.9))
                stars(30, below: 0.4)
                let globe = rect(-0.15, 0.55, 1.3, 1.3 * w / h)
                glow(at: p(0.5, 0.6), radius: w * 0.6, color: Color(red: 0.6, green: 0.85, blue: 1).opacity(0.5))
                context.fill(Path(ellipseIn: globe), with: gradient([Color(red: 0.2, green: 0.55, blue: 0.85), Color(red: 0.05, green: 0.25, blue: 0.55)], p(0.5, 0.55), p(0.5, 1)))
                var inside = context
                inside.clip(to: Path(ellipseIn: globe))
                // Continents as clusters of soft blobs rather than one shape each.
                for (cx, cy, spread) in [(0.22, 0.68, 0.1), (0.58, 0.66, 0.13), (0.7, 0.82, 0.07), (0.3, 0.86, 0.06)] as [(CGFloat, CGFloat, CGFloat)] {
                    for k in 0..<6 {
                        let a = CGFloat(k) * 1.1
                        let r = spread * (0.45 + 0.1 * CGFloat(k % 3))
                        inside.fill(Path(ellipseIn: rect(cx + cos(a) * spread * 0.5 - r / 2, cy + sin(a) * spread * 0.25 - r * 0.3, r, r * 0.6)),
                                    with: color(0.45, 0.78, 0.55))
                    }
                }
                for i in 1...4 {
                    inside.stroke(Path(ellipseIn: rect(-0.15 + CGFloat(i) * 0.13, 0.55, 1.3 - CGFloat(i) * 0.26, 1.3 * w / h)), with: .color(.white.opacity(0.15)), lineWidth: 1)
                }
                for (from, to, lift) in [(p(0.12, 0.62), p(0.6, 0.58), 0.25), (p(0.3, 0.7), p(0.88, 0.66), 0.32)] as [(CGPoint, CGPoint, CGFloat)] {
                    var arc = Path()
                    arc.move(to: from)
                    arc.addQuadCurve(to: to, control: CGPoint(x: (from.x + to.x) / 2, y: min(from.y, to.y) - lift * h))
                    context.stroke(arc, with: .color(.white.opacity(0.85)), style: StrokeStyle(lineWidth: 1.6, lineCap: .round, dash: [4, 5]))
                }
                // A little plane at the end of the second arc, nose along the route.
                var plane = Path()
                plane.move(to: CGPoint(x: 12, y: 0))
                plane.addLine(to: CGPoint(x: -8, y: -3)); plane.addLine(to: CGPoint(x: -3, y: -12)); plane.addLine(to: CGPoint(x: -6, y: -12))
                plane.addLine(to: CGPoint(x: -12, y: -3)); plane.addLine(to: CGPoint(x: -16, y: -3)); plane.addLine(to: CGPoint(x: -18, y: -8))
                plane.addLine(to: CGPoint(x: -20, y: -8)); plane.addLine(to: CGPoint(x: -18, y: 0)); plane.addLine(to: CGPoint(x: -20, y: 8))
                plane.addLine(to: CGPoint(x: -18, y: 8)); plane.addLine(to: CGPoint(x: -16, y: 3)); plane.addLine(to: CGPoint(x: -12, y: 3))
                plane.addLine(to: CGPoint(x: -6, y: 12)); plane.addLine(to: CGPoint(x: -3, y: 12)); plane.addLine(to: CGPoint(x: -8, y: 3)); plane.closeSubpath()
                let scale = w / 300
                context.fill(plane.applying(CGAffineTransform(scaleX: scale, y: scale).concatenating(CGAffineTransform(rotationAngle: 0.35))
                    .concatenating(CGAffineTransform(translationX: 0.74 * w, y: 0.42 * h))), with: .color(.white))

            case .explorer:
                sky(Color(red: 0.2, green: 0.5, blue: 0.55), Color(red: 0.86, green: 0.9, blue: 0.75))
                context.fill(Path(ellipseIn: rect(0.12, 0.14, 0.1, 0.1 * w / h)), with: .color(.white.opacity(0.9)))
                mountains([(0.15, 0.5), (0.32, 0.38), (0.5, 0.52), (0.7, 0.3), (0.9, 0.48)], base: 0.6, color(0.45, 0.62, 0.6))
                hills(0.68, 0.05, 1, color(0.25, 0.5, 0.42))
                hills(0.82, 0.04, 3, color(0.12, 0.36, 0.3))
                dottedPath([p(0.25, 1.0), p(0.45, 0.88), p(0.35, 0.78), p(0.55, 0.68), p(0.68, 0.45), p(0.7, 0.3)], color: Color(red: 1, green: 0.95, blue: 0.75))
                var flag = Path()
                flag.move(to: p(0.7, 0.3)); flag.addLine(to: p(0.7, 0.2))
                context.stroke(flag, with: .color(.white), lineWidth: 1.5)
                var cloth = Path()
                cloth.move(to: p(0.7, 0.2)); cloth.addLine(to: p(0.76, 0.225)); cloth.addLine(to: p(0.7, 0.25)); cloth.closeSubpath()
                context.fill(cloth, with: color(1, 0.45, 0.35))

            case .homebody:
                sky(Color(red: 0.3, green: 0.18, blue: 0.4), Color(red: 0.95, green: 0.6, blue: 0.5))
                stars(25, below: 0.35)
                hills(0.74, 0.05, 1.5, color(0.45, 0.25, 0.4))
                let house = rect(0.38, 0.52, 0.24, 0.22)
                glow(at: p(0.5, 0.64), radius: w * 0.35, color: Color(red: 1, green: 0.8, blue: 0.5).opacity(0.45))
                context.fill(Path(house), with: color(0.32, 0.17, 0.3))
                var roof = Path()
                roof.move(to: p(0.34, 0.53)); roof.addLine(to: p(0.5, 0.4)); roof.addLine(to: p(0.66, 0.53)); roof.closeSubpath()
                context.fill(roof, with: color(0.25, 0.12, 0.24))
                context.fill(Path(rect(0.56, 0.42, 0.04, 0.07)), with: color(0.25, 0.12, 0.24))
                for (x, y) in [(0.42, 0.57), (0.52, 0.57)] as [(CGFloat, CGFloat)] {
                    context.fill(Path(rect(x, y, 0.06, 0.06)), with: color(1, 0.84, 0.5))
                }
                context.fill(Path(rect(0.47, 0.66, 0.06, 0.08)), with: color(0.6, 0.35, 0.3))
                for i in 0..<3 {
                    let t = CGFloat(i)
                    context.fill(Path(ellipseIn: rect(0.575 + t * 0.02, 0.36 - t * 0.04, 0.03 + t * 0.01, 0.02 + t * 0.006)), with: .color(.white.opacity(0.3 - t * 0.07)))
                }
                hills(0.86, 0.03, 4, color(0.28, 0.13, 0.26))

            case .rider:
                sky(Color(red: 0.0, green: 0.55, blue: 0.62), Color(red: 0.75, green: 0.95, blue: 0.88))
                context.fill(Path(ellipseIn: rect(0.7, 0.16, 0.14, 0.14 * w / h)), with: color(1, 0.98, 0.85))
                hills(0.6, 0.05, 0.2, color(0.4, 0.75, 0.6))
                var road = Path()
                road.move(to: p(0.47, 0.6)); road.addLine(to: p(0.53, 0.6)); road.addLine(to: p(0.85, 1)); road.addLine(to: p(0.15, 1)); road.closeSubpath()
                hills(0.7, 0.03, 2, color(0.2, 0.55, 0.45))
                context.fill(road, with: color(0.25, 0.3, 0.33))
                var line = Path()
                line.move(to: p(0.5, 0.62)); line.addLine(to: p(0.5, 1))
                context.stroke(line, with: .color(.white.opacity(0.85)), style: StrokeStyle(lineWidth: 2, dash: [8, 8]))
                for (x, y, l) in [(0.08, 0.3, 0.22), (0.15, 0.38, 0.3), (0.05, 0.46, 0.18), (0.62, 0.42, 0.25)] as [(CGFloat, CGFloat, CGFloat)] {
                    var wind = Path()
                    wind.move(to: p(x, y)); wind.addCurve(to: p(x + l, y), control1: p(x + l * 0.3, y - 0.03), control2: p(x + l * 0.7, y + 0.03))
                    context.stroke(wind, with: .color(.white.opacity(0.7)), style: StrokeStyle(lineWidth: 1.6, lineCap: .round))
                }

            case .wanderer:
                sky(Color(red: 0.55, green: 0.78, blue: 0.95), Color(red: 0.95, green: 0.95, blue: 0.82))
                context.fill(Path(ellipseIn: rect(0.15, 0.15, 0.12, 0.12 * w / h)), with: color(1, 0.95, 0.7))
                hills(0.58, 0.05, 0.4, color(0.55, 0.78, 0.5))
                hills(0.7, 0.06, 1.8, color(0.35, 0.65, 0.38))
                hills(0.84, 0.04, 3.1, color(0.2, 0.5, 0.28))
                // A path through the fields with footprints on it, smaller as they go.
                for i in 0..<10 {
                    let t = CGFloat(i) / 9
                    // Points along the same curve.
                    let a = p(0.3, 1), c1 = p(0.75, 0.86), c2 = p(0.35, 0.7), b = p(0.56, 0.6)
                    let u = 1 - t
                    let x = u * u * u * a.x + 3 * u * u * t * c1.x + 3 * u * t * t * c2.x + t * t * t * b.x
                    let y = u * u * u * a.y + 3 * u * u * t * c1.y + 3 * u * t * t * c2.y + t * t * t * b.y
                    let side: CGFloat = i % 2 == 0 ? -1 : 1
                    let s = w * 0.045 * (1 - t * 0.6)
                    let foot = CGRect(x: x + side * s * 0.55 - s * 0.32, y: y - s * 0.5, width: s * 0.64, height: s)
                    context.fill(Path(ellipseIn: foot), with: .color(.white.opacity(0.9 - t * 0.35)))
                    context.fill(Path(ellipseIn: CGRect(x: foot.minX + s * 0.1, y: foot.minY - s * 0.42, width: s * 0.44, height: s * 0.36)),
                                 with: .color(.white.opacity(0.9 - t * 0.35)))
                }

            case .commuter:
                sky(Color(red: 0.1, green: 0.16, blue: 0.36), Color(red: 0.4, green: 0.55, blue: 0.85))
                stars(20, below: 0.3)
                skyline([(0, 0.1, 0.35), (0.12, 0.08, 0.28), (0.22, 0.12, 0.4), (0.4, 0.09, 0.3), (0.52, 0.13, 0.38), (0.7, 0.1, 0.26), (0.84, 0.16, 0.36)],
                        base: 0.62, fill: color(0.16, 0.22, 0.42), windows: Color(red: 0.75, green: 0.85, blue: 1))
                // An elevated line and a train with lit windows crossing it.
                context.fill(Path(rect(0, 0.66, 1, 0.025)), with: color(0.1, 0.13, 0.28))
                for x in stride(from: 0.06, to: 1, by: 0.22) {
                    context.fill(Path(rect(CGFloat(x), 0.68, 0.025, 0.32)), with: color(0.1, 0.13, 0.28))
                }
                context.fill(Path(roundedRect: rect(0.18, 0.565, 0.62, 0.09), cornerRadius: 8), with: color(0.92, 0.94, 0.98))
                context.fill(Path(rect(0.18, 0.635, 0.62, 0.012)), with: color(0.25, 0.5, 0.95))
                for x in stride(from: 0.21, to: 0.78, by: 0.055) {
                    context.fill(Path(roundedRect: rect(CGFloat(x), 0.578, 0.035, 0.035), cornerRadius: 2), with: color(1, 0.86, 0.5))
                }
                glow(at: p(0.8, 0.61), radius: w * 0.08, color: Color(red: 1, green: 0.95, blue: 0.7).opacity(0.8))
                context.fill(Path(rect(0, 0.92, 1, 0.08)), with: color(0.08, 0.1, 0.22))

            case .slowWalker:
                sky(Color(red: 0.62, green: 0.72, blue: 0.55), Color(red: 0.96, green: 0.92, blue: 0.78))
                context.fill(Path(ellipseIn: rect(0.66, 0.16, 0.13, 0.13 * w / h)), with: .color(.white.opacity(0.85)))
                hills(0.66, 0.05, 1, color(0.5, 0.62, 0.42))
                hills(0.8, 0.04, 2.5, color(0.36, 0.48, 0.3))
                for (x, y, angle) in [(0.2, 0.3, 0.6), (0.4, 0.45, -0.4), (0.62, 0.36, 0.9), (0.8, 0.52, -0.2), (0.3, 0.58, 0.3)] as [(CGFloat, CGFloat, CGFloat)] {
                    var leaf = Path()
                    leaf.move(to: .zero)
                    leaf.addQuadCurve(to: CGPoint(x: 16, y: 0), control: CGPoint(x: 8, y: -7))
                    leaf.addQuadCurve(to: .zero, control: CGPoint(x: 8, y: 7))
                    context.fill(leaf.applying(CGAffineTransform(rotationAngle: angle).concatenating(CGAffineTransform(translationX: x * w, y: y * h))),
                                 with: color(0.85, 0.55, 0.25, 0.85))
                }
            }

            // Film grain, very faint, so the flat colour reads as paper.
            var n: UInt64 = 99
            for _ in 0..<Int(w * h / 180) {
                n = n &* 6364136223846793005 &+ 1442695040888963407
                let x = CGFloat(n >> 33 % UInt64(max(w, 1)))
                n = n &* 6364136223846793005 &+ 1442695040888963407
                let y = CGFloat(n >> 33 % UInt64(max(h, 1)))
                context.fill(Path(CGRect(x: x, y: y, width: 1, height: 1)), with: .color(.white.opacity(0.06)))
            }
        }
    }
}

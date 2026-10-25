import SwiftUI
import MapKit

/// Routes drawn on a quiet map, as an image for covers and thumbnails. Cached by key.
enum RouteImage {
    struct Line {
        let coordinates: [CLLocationCoordinate2D]
        let color: Color
    }

    private static let cache = NSCache<NSString, UIImage>()

    /// `coordinates` are GPS (WGS-84); they're shifted for the map here.
    /// The map is drawn at `detail` times the size and scaled down, so its labels stay small.
    static func render(_ lines: [Line], size displaySize: CGSize, dark: Bool, key: String, minimumSpan: CLLocationDistance = 800,
                       lineWidth displayLineWidth: CGFloat = 3, detail: CGFloat = 2) async -> UIImage? {
        let size = CGSize(width: displaySize.width * detail, height: displaySize.height * detail)
        let lineWidth = displayLineWidth * detail
        let cacheKey = "\(key)-\(Int(size.width))x\(Int(size.height))-\(dark)" as NSString
        if let cached = cache.object(forKey: cacheKey) { return cached }
        let lines = lines.map { Line(coordinates: $0.coordinates.map(\.onMap), color: $0.color) }.filter { $0.coordinates.count > 1 }
        guard size.width > 0, size.height > 0, let first = lines.first?.coordinates.first else { return nil }

        var rect = MKMapRect.null
        for line in lines {
            for c in line.coordinates { rect = rect.union(MKMapRect(origin: MKMapPoint(c), size: MKMapSize(width: 1, height: 1))) }
        }
        let minimum = minimumSpan * MKMapPointsPerMeterAtLatitude(first.latitude)
        let aspect = size.width / size.height
        var width = max(rect.width, minimum), height = max(rect.height, minimum)
        if width / height < aspect { width = height * aspect } else { height = width / aspect }
        width *= 1.4; height *= 1.4

        let options = MKMapSnapshotter.Options()
        options.mapRect = MKMapRect(x: rect.midX - width / 2, y: rect.midY - height / 2, width: width, height: height)
        options.size = size
        options.traitCollection = UITraitCollection(userInterfaceStyle: dark ? .dark : .light)
        let configuration = MKStandardMapConfiguration(emphasisStyle: .muted)
        configuration.pointOfInterestFilter = .excludingAll
        options.preferredConfiguration = configuration
        guard let snapshot = try? await MKMapSnapshotter(options: options).start() else { return nil }

        let format = UIGraphicsImageRendererFormat()
        format.scale = 3 / detail
        let image = UIGraphicsImageRenderer(size: size, format: format).image { context in
            snapshot.image.draw(at: .zero)
            let cg = context.cgContext
            cg.setLineCap(.round)
            cg.setLineJoin(.round)
            for line in lines {
                let path = UIBezierPath()
                for (i, c) in line.coordinates.enumerated() {
                    let p = snapshot.point(for: c)
                    i == 0 ? path.move(to: p) : path.addLine(to: p)
                }
                UIColor.white.withAlphaComponent(0.92).setStroke()
                path.lineWidth = lineWidth + 2
                path.stroke()
                UIColor(line.color).setStroke()
                path.lineWidth = lineWidth
                path.stroke()
            }
            // Start and end dots.
            if let start = lines.first?.coordinates.first, let end = lines.last?.coordinates.last {
                for (coordinate, filled) in [(start, false), (end, true)] {
                    let p = snapshot.point(for: coordinate)
                    let r = lineWidth + 1.5
                    let dot = UIBezierPath(ovalIn: CGRect(x: p.x - r, y: p.y - r, width: r * 2, height: r * 2))
                    UIColor.white.setFill(); dot.fill()
                    UIColor(lines.last?.color ?? .blue).setStroke()
                    dot.lineWidth = 1.5
                    dot.stroke()
                    if filled {
                        UIColor(lines.last?.color ?? .blue).setFill()
                        UIBezierPath(ovalIn: CGRect(x: p.x - r + 2, y: p.y - r + 2, width: (r - 2) * 2, height: (r - 2) * 2)).fill()
                    }
                }
            }
        }
        cache.setObject(image, forKey: cacheKey)
        return image
    }
}

/// A route's shape on its own, Strava-style: the line in the travel mode's colour on a soft
/// tint with a faint dot grid. No map, so nothing competes with the line at small sizes.
struct RouteSketch: View {
    let lines: [RouteImage.Line]
    var tint: Color

    var body: some View {
        Canvas { context, size in
            let spacing: CGFloat = 9
            var grid = Path()
            for x in stride(from: spacing / 2, to: size.width, by: spacing) {
                for y in stride(from: spacing / 2, to: size.height, by: spacing) {
                    grid.addEllipse(in: CGRect(x: x - 0.6, y: y - 0.6, width: 1.2, height: 1.2))
                }
            }
            context.fill(grid, with: .color(tint.opacity(0.18)))

            let all = lines.flatMap(\.coordinates)
            guard all.count > 1 else { return }
            // Local flat projection: metres east and north of the first point.
            let origin = all[0]
            let k = cos(origin.latitude * .pi / 180)
            func local(_ c: CLLocationCoordinate2D) -> CGPoint {
                CGPoint(x: (c.longitude - origin.longitude) * 111_320 * k, y: -(c.latitude - origin.latitude) * 111_320)
            }
            let points = all.map(local)
            let minX = points.map(\.x).min()!, maxX = points.map(\.x).max()!
            let minY = points.map(\.y).min()!, maxY = points.map(\.y).max()!
            let inset: CGFloat = 10
            let scale = min((size.width - inset * 2) / max(maxX - minX, 1), (size.height - inset * 2) / max(maxY - minY, 1))
            let offset = CGPoint(x: (size.width - (maxX - minX) * scale) / 2, y: (size.height - (maxY - minY) * scale) / 2)
            func place(_ c: CLLocationCoordinate2D) -> CGPoint {
                let p = local(c)
                return CGPoint(x: offset.x + (p.x - minX) * scale, y: offset.y + (p.y - minY) * scale)
            }
            let style = StrokeStyle(lineWidth: 3, lineCap: .round, lineJoin: .round)
            for line in lines where line.coordinates.count > 1 {
                var path = Path()
                path.addLines(line.coordinates.map(place))
                context.stroke(path, with: .color(line.color.opacity(0.25)), style: StrokeStyle(lineWidth: 7, lineCap: .round, lineJoin: .round))
                context.stroke(path, with: .color(line.color), style: style)
            }
            if let first = lines.first?.coordinates.first, let last = lines.last?.coordinates.last {
                let s = place(first), e = place(last)
                context.fill(Path(ellipseIn: CGRect(x: s.x - 4, y: s.y - 4, width: 8, height: 8)), with: .color(.white))
                context.stroke(Path(ellipseIn: CGRect(x: s.x - 4, y: s.y - 4, width: 8, height: 8)), with: .color(tint), lineWidth: 2)
                context.fill(Path(ellipseIn: CGRect(x: e.x - 4.5, y: e.y - 4.5, width: 9, height: 9)), with: .color(tint))
                context.stroke(Path(ellipseIn: CGRect(x: e.x - 4.5, y: e.y - 4.5, width: 9, height: 9)), with: .color(.white), lineWidth: 2)
            }
        }
        .background(LinearGradient(colors: [tint.opacity(0.07), tint.opacity(0.16)], startPoint: .topLeading, endPoint: .bottomTrailing))
    }
}

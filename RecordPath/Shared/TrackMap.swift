import SwiftUI
import MapKit

/// Draws tracks (colored by how they were travelled) and stays on a map.
struct TrackMap: View {
    let chunks: [TrackChunk]
    let stays: [Stay]
    var livePoints: [TrackPoint] = []
    var interactive = true
    var showsUser = false
    var mapStyle: MapStyle = .standard(elevation: .realistic, pointsOfInterest: .excludingAll)
    var onSelectStay: ((Stay) -> Void)?

    @State private var position: MapCameraPosition = .automatic
    @State private var lines: [Line] = []

    struct Line: Identifiable {
        let id: Int
        let coordinates: [CLLocationCoordinate2D]
        let color: Color
        /// Drawn dashed: the way between two places when there was no signal on it.
        var inferred = false
    }

    var body: some View {
        Map(position: $position, interactionModes: interactive ? .all : []) {
            ForEach(lines) { line in
                MapPolyline(coordinates: line.coordinates)
                    .stroke(.white.opacity(0.9), style: StrokeStyle(lineWidth: 7, lineCap: .round, lineJoin: .round))
                MapPolyline(coordinates: line.coordinates)
                    .stroke(line.color.gradient, style: StrokeStyle(lineWidth: 4.5, lineCap: .round, lineJoin: .round,
                                                                    dash: line.inferred ? [6, 8] : []))
            }
            if livePoints.count > 1 {
                MapPolyline(coordinates: livePoints.map(\.coordinate.onMap))
                    .stroke(.green, style: StrokeStyle(lineWidth: 4.5, lineCap: .round, lineJoin: .round, dash: [1, 7]))
            }
            ForEach(stays) { stay in
                Annotation(stay.displayName, coordinate: stay.coordinate.onMap, anchor: .center) {
                    Button {
                        onSelectStay?(stay)
                    } label: {
                        PlaceIcon(category: stay.category, isLandmark: stay.isLandmark, size: interactive ? 30 : 22)
                            .overlay(Circle().stroke(.white, lineWidth: 2))
                            .shadow(color: .black.opacity(0.2), radius: 3, y: 1)
                    }
                    .buttonStyle(.plain)
                    .disabled(onSelectStay == nil)
                }
                .annotationTitles(interactive ? .automatic : .hidden)
            }
            if showsUser { UserAnnotation() }
        }
        .mapStyle(mapStyle)
        .mapControls {
            if interactive {
                MapUserLocationButton()
                MapCompass()
                MapScaleView()
            }
        }
        .task(id: chunks.map(\.persistentModelID) + stays.map(\.persistentModelID)) {
            lines = Self.makeLines(chunks)
            position = framing
        }
        .onChange(of: livePoints.count / 15) {
            // Keep a live recording in view as it grows, unless the user is exploring the map.
            guard !interactive else { return }
            withAnimation(.smooth(duration: 0.8)) { position = framing }
        }
    }

    /// Frames everything with some breathing room, never zooming in closer than a few
    /// streets; with nothing to show it follows the user.
    private var framing: MapCameraPosition {
        let all = lines.flatMap(\.coordinates) + stays.map(\.coordinate.onMap) + livePoints.map(\.coordinate.onMap)
        let coordinates = Self.mainRegion(all, stays: stays.map(\.coordinate.onMap))
        // With nothing to frame, a wide view, not the user's location: following it would keep
        // GPS on for as long as the map is showing.
        guard !coordinates.isEmpty else { return .automatic }
        var rect = MKMapRect.null
        for coordinate in coordinates {
            rect = rect.union(MKMapRect(origin: MKMapPoint(coordinate), size: MKMapSize(width: 0, height: 0)))
        }
        let minimumSide = 1_600 * MKMapPointsPerMeterAtLatitude(coordinates[0].latitude)
        let side = max(rect.width, rect.height) * 0.35
        rect = rect.insetBy(dx: -side, dy: -side)
        if rect.width < minimumSide || rect.height < minimumSide {
            let width = max(rect.width, minimumSide), height = max(rect.height, minimumSide)
            rect = MKMapRect(x: rect.midX - width / 2, y: rect.midY - height / 2, width: width, height: height)
        }
        return .rect(rect)
    }

    /// A trip to Switzerland that starts and ends at home in Singapore should open on
    /// Switzerland, not on half the world. Keeps the coordinates near where most places are;
    /// the far-off ones stay on the map, one pinch away.
    static func mainRegion(_ coordinates: [CLLocationCoordinate2D], stays: [CLLocationCoordinate2D]) -> [CLLocationCoordinate2D] {
        let size = 20.0
        func cell(_ c: CLLocationCoordinate2D) -> Int64 {
            Int64(floor(c.latitude / size)) * 1_000 + Int64(floor((c.longitude + 180) / size))
        }
        // Places say where the time went; a long flight line would outweigh them point for point.
        let votes = stays.isEmpty ? coordinates : stays
        var weight: [Int64: Int] = [:]
        for c in votes { weight[cell(c), default: 0] += 1 }
        guard weight.count > 1, let busiest = weight.max(by: { $0.value < $1.value }) else { return coordinates }
        let members = votes.filter { cell($0) == busiest.key }
        let lat = members.map(\.latitude).reduce(0, +) / Double(members.count)
        let lon = members.map(\.longitude).reduce(0, +) / Double(members.count)
        let near = coordinates.filter {
            abs($0.latitude - lat) <= 25 && abs(($0.longitude - lon).remainder(dividingBy: 360)) <= 35
        }
        return near.isEmpty ? coordinates : near
    }

    /// Long days are simplified so thousands of points still pan smoothly.
    static func makeLines(_ chunks: [TrackChunk]) -> [Line] {
        let total = chunks.reduce(0) { $0 + $1.pointCount }
        let tolerance: Double = total > 20_000 ? 25 : total > 5_000 ? 10 : 3
        let simplified = chunks.map { $0.points.simplified(tolerance: tolerance).map(\.coordinate.onMap) }
        let apart = separated(simplified)
        return chunks.enumerated().compactMap { index, chunk in
            guard apart[index].count > 1 else { return nil }
            return Line(id: index, coordinates: apart[index], color: chunk.mode.color, inferred: chunk.mode == .subway)
        }
    }

    /// Where the way there and the way back run along the same street, each keeps a little to
    /// its own right, so zoomed in you see two lines side by side instead of one. Elsewhere a
    /// line stays exactly where it was recorded; the shift fades in and out over a few points.
    static func separated(_ lines: [[CLLocationCoordinate2D]], by metres: Double = 6) -> [[CLLocationCoordinate2D]] {
        guard let origin = lines.first(where: { !$0.isEmpty })?.first else { return lines }
        let metresPerLat = 111_320.0, metresPerLon = 111_320.0 * cos(origin.latitude * .pi / 180)
        func local(_ c: CLLocationCoordinate2D) -> SIMD2<Double> {
            SIMD2((c.longitude - origin.longitude) * metresPerLon, (c.latitude - origin.latitude) * metresPerLat)
        }
        let points = lines.map { $0.map(local) }
        // Each point's direction of travel.
        let headings: [[SIMD2<Double>]] = points.map { line in
            line.indices.map { i in
                let d = line[min(i + 1, line.count - 1)] - line[max(i - 1, 0)]
                let length = (d * d).sum().squareRoot()
                return length > 0.5 ? d / length : .zero
            }
        }
        // Points in 25 m cells, to find a neighbour heading the other way without comparing all pairs.
        let cell = 25.0
        func key(_ p: SIMD2<Double>) -> SIMD2<Int> { SIMD2(Int((p.x / cell).rounded(.down)), Int((p.y / cell).rounded(.down))) }
        var grid: [SIMD2<Int>: [(Int, Int)]] = [:]
        for (l, line) in points.enumerated() { for (i, p) in line.enumerated() { grid[key(p), default: []].append((l, i)) } }

        return points.indices.map { l in
            let line = points[l]
            guard line.count > 1 else { return lines[l] }
            let shared: [Double] = line.indices.map { i in
                let p = line[i], h = headings[l][i], k = key(p)
                for dx in -1...1 { for dy in -1...1 {
                    for (ol, oi) in grid[k &+ SIMD2(dx, dy)] ?? [] where ol != l || abs(oi - i) > 3 {
                        let q = points[ol][oi], d = q - p
                        if (d * d).sum() < cell * cell, (headings[ol][oi] * h).sum() < -0.7 { return 1 }
                    }
                } }
                return 0
            }
            // Ease the shift in and out so the line bends over rather than steps.
            let eased: [Double] = line.indices.map { i in
                let window = shared[max(0, i - 3)...min(line.count - 1, i + 3)]
                return window.reduce(0, +) / Double(window.count)
            }
            return line.indices.map { i in
                let h = headings[l][i], right = SIMD2(h.y, -h.x)
                let p = line[i] + right * metres * eased[i]
                return CLLocationCoordinate2D(latitude: origin.latitude + p.y / metresPerLat,
                                              longitude: origin.longitude + p.x / metresPerLon)
            }
        }
    }
}

extension MapStyleChoice {
    var style: MapStyle {
        switch self {
        case .standard: .standard(elevation: .realistic, pointsOfInterest: .excludingAll)
        case .hybrid: .hybrid(elevation: .realistic)
        case .imagery: .imagery(elevation: .realistic)
        }
    }
}

enum MapStyleChoice: String, CaseIterable, Identifiable {
    case standard, hybrid, imagery
    var id: String { rawValue }

    var title: LocalizedStringKey {
        switch self {
        case .standard: "标准"
        case .hybrid: "混合"
        case .imagery: "卫星"
        }
    }
}

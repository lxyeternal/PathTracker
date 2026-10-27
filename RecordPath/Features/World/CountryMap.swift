import SwiftUI
import MapKit

/// Country outlines from Natural Earth (public domain, 1:50m), loaded on first use. Mainland
/// China, Hong Kong, Macao, Taiwan and India are left out on purpose: a border drawn by the app
/// there is not an approved map in China, so those countries show their visited cities only.
enum CountryBorders {
    @MainActor private static var loaded: [String: [[CLLocationCoordinate2D]]]?

    @MainActor
    static func rings(for code: String) -> [[CLLocationCoordinate2D]] {
        if loaded == nil {
            guard let url = Bundle.main.url(forResource: "CountryBorders", withExtension: "json"),
                  let data = try? Data(contentsOf: url),
                  let raw = try? JSONDecoder().decode([String: [[[Double]]]].self, from: data) else {
                loaded = [:]
                return []
            }
            loaded = raw.mapValues { rings in
                rings.map { ring in ring.map { CLLocationCoordinate2D(latitude: $0[1], longitude: $0[0]).onMap } }
            }
        }
        return loaded?[code] ?? []
    }

    static func contains(_ ring: [CLLocationCoordinate2D], _ point: CLLocationCoordinate2D) -> Bool {
        var inside = false
        var j = ring.count - 1
        for i in ring.indices {
            let a = ring[i], b = ring[j]
            if (a.latitude > point.latitude) != (b.latitude > point.latitude),
               point.longitude < (b.longitude - a.longitude) * (point.latitude - a.latitude) / (b.latitude - a.latitude) + a.longitude {
                inside.toggle()
            }
            j = i
        }
        return inside
    }
}

/// A city lit up on the country map: where its visits are, how far they spread, how many days.
struct CityGlow: Identifiable {
    let name: String
    let center: CLLocationCoordinate2D
    let radius: CLLocationDistance
    let days: Int
    var id: String { name }

    static func glows(for stays: [Stay]) -> [CityGlow] {
        let names = CityNames.canonical(for: stays)
        let calendar = Calendar.current
        let groups = Dictionary(grouping: stays.filter { $0.city != nil }) { CityNames.key($0).flatMap { names[$0] } ?? $0.city! }
        return groups.map { name, members in
            let lat = members.map(\.latitude).reduce(0, +) / Double(members.count)
            let lon = members.map(\.longitude).reduce(0, +) / Double(members.count)
            let center = CLLocation(latitude: lat, longitude: lon)
            // Big enough to cover most of the visits, small enough to stay a city.
            let distances = members.map { $0.location.distance(from: center) }.sorted()
            let spread = distances[min(distances.count - 1, Int(Double(distances.count) * 0.8))]
            let days = Set(members.map { calendar.startOfDay(for: $0.arrival) }).count
            return CityGlow(name: name, center: CLLocationCoordinate2D(latitude: lat, longitude: lon).onMap,
                            radius: min(max(spread, 3_000), 30_000), days: days)
        }
        .sorted { $0.days > $1.days }
    }
}

/// The country page's map: the country outlined and softly filled, each visited city glowing
/// with its name, and the places themselves once you zoom in.
struct CountryMap: View {
    let code: String
    let stays: [Stay]
    var onSelect: (Stay) -> Void = { _ in }

    @State private var outline: [[CLLocationCoordinate2D]] = []
    @State private var glows: [CityGlow] = []
    @State private var dots: [MapDot] = []
    @State private var shown: [MapDot] = []
    @State private var position: MapCameraPosition = .automatic
    @State private var span: Double = 100
    @State private var ready = false
    /// Cities whose name is shown: a smaller city's label that would sit on a bigger one's is left off.
    @State private var labelled: Set<String> = []

    private let tint = Color.accentColor

    var body: some View {
        Map(position: $position) {
            ForEach(outline.indices, id: \.self) { index in
                MapPolygon(coordinates: outline[index])
                    .foregroundStyle(tint.opacity(0.08))
                    .stroke(tint.opacity(0.85), lineWidth: 1.6)
            }
            ForEach(glows) { glow in
                MapCircle(center: glow.center, radius: glow.radius * 1.6)
                    .foregroundStyle(Color.orange.opacity(0.14))
                MapCircle(center: glow.center, radius: glow.radius)
                    .foregroundStyle(Color.orange.opacity(0.28))
                    .stroke(Color.orange.opacity(0.7), lineWidth: 1)
                Annotation("", coordinate: glow.center, anchor: .center) {
                    // A light of fixed size: at country scale the city's own area is a speck.
                    ZStack {
                        Circle()
                            .fill(RadialGradient(colors: [Color.orange.opacity(0.75), Color.orange.opacity(0)],
                                                 center: .center, startRadius: 2, endRadius: 30))
                            .frame(width: 60, height: 60)
                        Circle()
                            .fill(Color.orange.gradient)
                            .frame(width: 11, height: 11)
                            .overlay(Circle().stroke(.white, lineWidth: 2))
                        if labelled.contains(glow.id) {
                        VStack(spacing: 0) {
                            Text(glow.name).font(.caption.weight(.bold)).lineLimit(1)
                            Text("\(glow.days) 天").font(.caption2.weight(.semibold)).foregroundStyle(.secondary)
                        }
                        .padding(.horizontal, 7).padding(.vertical, 2)
                        .background(.regularMaterial, in: .capsule)
                        .fixedSize()
                        .offset(y: -30)
                        }
                    }
                    .opacity(span < 0.6 ? 0 : 1)
                    .animation(.smooth, value: span < 0.6)
                }
                .annotationTitles(.hidden)
            }
            ForEach(shown) { dot in
                Annotation("", coordinate: dot.coordinate, anchor: .center) {
                    Button { if let stay = PlaceSummaries.shared.stay(dot.id) { onSelect(stay) } } label: {
                        Circle()
                            .fill(dot.isLandmark ? Color.yellow : Color.accentColor)
                            .frame(width: 12, height: 12)
                            .overlay(Circle().stroke(.white, lineWidth: 2))
                    }
                    .buttonStyle(.plain)
                }
                .annotationTitles(.hidden)
            }
        }
        .mapStyle(.standard(elevation: .flat, emphasis: .muted, pointsOfInterest: .excludingAll))
        .onMapCameraChange(frequency: .onEnd) { context in
            span = context.region.span.latitudeDelta
            updateShown(region: context.region)
            updateLabels(span: context.region.span)
        }
        .task(id: stays.count) { load() }
    }

    private func load() {
        dots = MapDot.dots(for: stays)
        glows = CityGlow.glows(for: stays)
        let rings = CountryBorders.rings(for: code)
        // Outline only the parts of the country that were visited (France without its
        // overseas regions, the US without Alaska unless you went), and frame on them.
        let visited = rings.filter { ring in dots.contains { CountryBorders.contains(ring, $0.coordinate) } }
        outline = visited.isEmpty ? rings.filter { $0.count > 30 }.prefix(1).map { $0 } : visited
        guard !ready else { return }
        ready = true
        let points = outline.flatMap { $0 } + dots.map(\.coordinate)
        if let region = Self.region(around: points) {
            position = .region(region)
            updateLabels(span: region.span)
        }
    }

    private func updateLabels(span: MKCoordinateSpan) {
        // A label is about a sixth of the map wide and a tenth tall.
        var kept: [CityGlow] = []
        for glow in glows where !kept.contains(where: {
            abs($0.center.latitude - glow.center.latitude) < span.latitudeDelta / 9
                && abs($0.center.longitude - glow.center.longitude) < span.longitudeDelta / 4
        }) {
            kept.append(glow)
        }
        labelled = Set(kept.map(\.id))
    }

    /// Places appear once you're zoomed in to a city; further out, the cities speak for them.
    private func updateShown(region: MKCoordinateRegion) {
        guard region.span.latitudeDelta < 0.6 else {
            shown = []
            return
        }
        let visible = dots.filter {
            abs($0.coordinate.latitude - region.center.latitude) <= region.span.latitudeDelta * 0.75
                && abs($0.coordinate.longitude - region.center.longitude) <= region.span.longitudeDelta * 0.75
        }
        shown = MapDot.thinned(visible, cell: max(region.span.latitudeDelta / 22, 0.001), limit: 200)
    }

    private static func region(around points: [CLLocationCoordinate2D]) -> MKCoordinateRegion? {
        let lats = points.map(\.latitude), lons = points.map(\.longitude)
        guard let minLat = lats.min(), let maxLat = lats.max(), let minLon = lons.min(), let maxLon = lons.max() else { return nil }
        return MKCoordinateRegion(center: CLLocationCoordinate2D(latitude: (minLat + maxLat) / 2 + (maxLat - minLat) * 0.08, longitude: (minLon + maxLon) / 2),
                                  // Extra room at the top for the labels above each city.
                                  span: MKCoordinateSpan(latitudeDelta: min(max((maxLat - minLat) * 1.45, 0.08), 140),
                                                         longitudeDelta: min(max((maxLon - minLon) * 1.25, 0.08), 300)))
    }
}

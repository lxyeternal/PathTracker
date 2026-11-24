import SwiftUI
import MapKit

/// The globe full screen, to turn and zoom. The countries you've been to are outlined and lit
/// with their flags on them; tapping a flag flies there. Closer in, the roads you've travelled
/// appear, finer the closer you go, down to every street walked.
struct FootprintExplorer: View {
    let countries: [CountrySummary]
    let cities: [CitySummary]
    let dots: [MapDot]
    let home: CLLocationCoordinate2D?

    @Environment(\.dismiss) private var dismiss
    private var atlas = RouteAtlas.shared

    @State private var position: MapCameraPosition
    @State private var region: MKCoordinateRegion?
    @State private var shapes: [Outline] = []
    @State private var flags: [Flag] = []
    @State private var roads: [Road] = []
    @State private var selected: String?

    private struct Outline: Identifiable { let id: String; let code: String; let ring: [CLLocationCoordinate2D] }
    private struct Flag: Identifiable { var id: String { code }; let code: String; let coordinate: CLLocationCoordinate2D }
    private struct Road: Identifiable { let id: Int; let mode: MovementMode; let points: [CLLocationCoordinate2D] }

    /// The whole Earth in view.
    private static let globeDistance: CLLocationDistance = 23_000_000

    init(countries: [CountrySummary], cities: [CitySummary], dots: [MapDot], home: CLLocationCoordinate2D?) {
        self.countries = countries
        self.cities = cities
        self.dots = dots
        self.home = home
        _position = State(initialValue: .camera(MapCamera(centerCoordinate: Self.globeCentre(home), distance: Self.globeDistance)))
    }

    private static func globeCentre(_ home: CLLocationCoordinate2D?) -> CLLocationCoordinate2D {
        guard let home else { return CLLocationCoordinate2D(latitude: 20, longitude: 110) }
        return CLLocationCoordinate2D(latitude: max(-30, min(30, home.latitude - 8)), longitude: home.longitude).onMap
    }

    /// How far in the camera is, in degrees of latitude across the screen.
    private var span: Double { region?.span.latitudeDelta ?? 180 }

    var body: some View {
        ZStack {
            Color.black.ignoresSafeArea()
            Map(position: $position) {
                ForEach(shapes) { shape in
                    MapPolygon(coordinates: shape.ring)
                        .foregroundStyle(FootprintNight.glow.opacity(shape.code == selected ? 0.2 : 0.11))
                        .stroke(FootprintNight.glow.opacity(0.85), style: StrokeStyle(lineWidth: shape.code == selected ? 1.6 : 1, lineJoin: .round))
                }
                ForEach(roads) { road in
                    MapPolyline(coordinates: road.points)
                        .stroke(road.mode.color.opacity(span < 1 ? 0.9 : 0.7),
                                style: StrokeStyle(lineWidth: span < 1 ? 3 : 2, lineCap: .round, lineJoin: .round))
                }
                // Far out a city is a light; close in the roads say more than a dot.
                if span > 1.5 {
                    ForEach(lights) { dot in
                        Annotation("", coordinate: dot.coordinate, anchor: .center) {
                            Circle()
                                .fill(FootprintNight.glow)
                                .frame(width: 5, height: 5)
                                .shadow(color: FootprintNight.glow, radius: 5)
                        }
                        .annotationTitles(.hidden)
                    }
                }
                ForEach(flags) { flag in
                    Annotation("", coordinate: flag.coordinate, anchor: .bottom) {
                        Button { fly(to: flag.code) } label: {
                            Text(String.flag(for: flag.code))
                                .font(.system(size: span > 60 ? 22 : 28))
                                .padding(5)
                                .background(.ultraThinMaterial, in: .circle)
                                .overlay(Circle().strokeBorder(.white.opacity(flag.code == selected ? 0.9 : 0.25), lineWidth: 1))
                                .shadow(color: .black.opacity(0.4), radius: 4, y: 2)
                        }
                        .buttonStyle(PressableStyle())
                        .accessibilityLabel(appLocale.localizedString(forRegionCode: flag.code) ?? flag.code)
                    }
                    .annotationTitles(.hidden)
                }
            }
            // From space the Earth as photographed at night; close in, the land itself.
            .mapStyle(.imagery(elevation: .realistic))
            .mapControls { MapCompass() }
            .onMapCameraChange(frequency: .onEnd) { context in
                region = context.region
                updateRoads()
            }
            .ignoresSafeArea()
        }
        .environment(\.colorScheme, .dark)
        .overlay(alignment: .top) { header }
        .safeAreaInset(edge: .bottom) { flagStrip }
        .task {
            load()
            // A slow push in on opening. It also makes the map take up the flags and lights
            // just added; on a globe that hasn't moved they wouldn't show.
            try? await Task.sleep(for: .milliseconds(150))
            withAnimation(.smooth(duration: 1.6)) {
                position = .camera(MapCamera(centerCoordinate: Self.globeCentre(home), distance: Self.globeDistance * 0.8))
            }
            await atlas.load()
            updateRoads()
        }
        .statusBarHidden(false)
    }

    // MARK: Pieces

    private var lights: [MapDot] {
        MapDot.thinned(dots, cell: max(span / 30, 0.05), limit: 220)
    }

    private var header: some View {
        HStack(alignment: .top) {
            Button { dismiss() } label: {
                Image(systemName: "xmark")
                    .font(.body.weight(.semibold))
                    .foregroundStyle(.white)
                    .frame(width: 44, height: 44)
            }
            .glassEffect(.regular.interactive(), in: .circle)
            .accessibilityLabel("关闭")
            Spacer()
            if let code = selected, let country = countries.first(where: { $0.code == code }) {
                VStack(alignment: .trailing, spacing: 2) {
                    Text(verbatim: "\(country.flag) \(country.name)")
                        .font(.headline)
                        .foregroundStyle(.white)
                    Text(country.cities.isEmpty
                         ? String(localized: "\(country.days.count) 天", bundle: .appLanguage)
                         : String(localized: "\(country.days.count) 天 · \(country.cities.count) 城", bundle: .appLanguage))
                        .font(.footnote)
                        .foregroundStyle(FootprintNight.secondary)
                }
                .padding(.horizontal, 14)
                .padding(.vertical, 9)
                .glassEffect(.regular, in: .rect(cornerRadius: 18, style: .continuous))
                .transition(.opacity.combined(with: .move(edge: .top)))
            }
        }
        .padding(.horizontal, 16)
        .padding(.top, 8)
        .animation(.smooth, value: selected)
    }

    /// Every country you've been to, to fly to; the globe first, to come back out.
    private var flagStrip: some View {
        ScrollView(.horizontal) {
            HStack(spacing: 8) {
                Button { backToGlobe() } label: {
                    Image(systemName: "globe.asia.australia.fill")
                        .font(.title3)
                        .foregroundStyle(.white)
                        .frame(width: 48, height: 48)
                }
                .glassEffect(.regular.interactive(), in: .circle)
                .accessibilityLabel("地球")
                ForEach(countries) { country in
                    Button { fly(to: country.code) } label: {
                        HStack(spacing: 6) {
                            Text(country.flag).font(.title3)
                            Text(country.name)
                                .font(.subheadline.weight(.semibold))
                                .foregroundStyle(.white)
                                .lineLimit(1)
                                .fixedSize()
                        }
                        .padding(.horizontal, 14)
                        .frame(height: 48)
                    }
                    .glassEffect(country.code == selected ? .regular.tint(FootprintNight.glow.opacity(0.35)).interactive() : .regular.interactive(),
                                 in: .capsule)
                }
            }
            .padding(.horizontal, 16)
        }
        .scrollIndicators(.hidden)
        .padding(.bottom, 8)
    }

    // MARK: Flying

    private func fly(to code: String) {
        selected = code
        guard let target = frame(of: code) else { return }
        withAnimation(.smooth(duration: 1.8)) { position = .region(target) }
    }

    private func backToGlobe() {
        selected = nil
        withAnimation(.smooth(duration: 1.8)) {
            position = .camera(MapCamera(centerCoordinate: region?.center ?? Self.globeCentre(home), distance: Self.globeDistance))
        }
    }

    /// Where you went in a country, with room around it; the whole country when that's
    /// unknown. A country as large as Russia isn't shown whole for a week in Moscow.
    private func frame(of code: String) -> MKCoordinateRegion? {
        let mine = cities.filter { $0.countryCode == code }.map { $0.center.onMap }
        let points = mine.isEmpty ? shapes.filter { $0.code == code }.flatMap(\.ring) : mine
        let lats = points.map(\.latitude), lons = points.map(\.longitude)
        guard let south = lats.min(), let north = lats.max(), let west = lons.min(), let east = lons.max() else { return nil }
        let center = CLLocationCoordinate2D(latitude: (south + north) / 2, longitude: (west + east) / 2)
        return MKCoordinateRegion(center: center, span: MKCoordinateSpan(latitudeDelta: min(max((north - south) * 1.6, 1.2), 60),
                                                                         longitudeDelta: min(max((east - west) * 1.6, 1.2), 90)))
    }

    // MARK: Data

    private func load() {
        var outlines: [Outline] = []
        var pins: [Flag] = []
        for country in countries {
            let mine = cities.filter { $0.countryCode == country.code }.map { $0.center.onMap }
            // The larger pieces: hundreds of islets cost the map more than they show from here.
            let rings = Array(WorldStampMap.pieces(of: country.code, visited: mine).sorted { $0.count > $1.count }.prefix(30))
            for (index, ring) in rings.enumerated() {
                outlines.append(Outline(id: "\(country.code).\(index)", code: country.code, ring: ring))
            }
            // The flag stands where you spent the most days in it, else on the mainland.
            let spot = cities.first { $0.countryCode == country.code }?.center.onMap
                ?? rings.first.flatMap { ring in
                    let lats = ring.map(\.latitude), lons = ring.map(\.longitude)
                    return CLLocationCoordinate2D(latitude: (lats.min()! + lats.max()!) / 2, longitude: (lons.min()! + lons.max()!) / 2)
                }
            if let spot { pins.append(Flag(code: country.code, coordinate: spot)) }
        }
        shapes = outlines
        flags = pins
    }

    /// The roads in view, at the detail the zoom can show: none from space, every street
    /// close in. A few hundred lines at most, the newest first.
    private func updateRoads() {
        guard let region, span < 25 else {
            if !roads.isEmpty { roads = [] }
            return
        }
        let detail: AtlasLine.Detail = span < 0.4 ? .street : span < 4 ? .city : .country
        let half = (lat: region.span.latitudeDelta * 0.6, lon: region.span.longitudeDelta * 0.6)
        let box = AtlasBox(minLat: Float(region.center.latitude - half.lat), maxLat: Float(region.center.latitude + half.lat),
                           minLon: Float(region.center.longitude - half.lon), maxLon: Float(region.center.longitude + half.lon))
        let found = atlas.lines(near: box, excluding: nil, limit: 600)
        roads = found.enumerated().compactMap { index, line in
            let points = line.coordinates(detail)
            return points.count > 1 ? Road(id: index, mode: line.mode, points: points) : nil
        }
    }
}

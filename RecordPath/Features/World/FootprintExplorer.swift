import SwiftUI
import MapKit
import Photos
import SwiftData

/// The globe full screen, to turn and zoom. The countries you've been to are outlined in white
/// with their flags on them; tapping a flag flies there. What it shows changes with how close
/// you are: lights from space, then cities by name and the roads between them, then the
/// places themselves, each with a picture taken there when there is one.
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
    @State private var places: [Place] = []
    @State private var placeWork: Task<Void, Never>?
    @State private var pictures: [PersistentIdentifier: PHAsset?] = [:]
    @State private var openedStay: Stay?

    private struct Outline: Identifiable { let id: String; let code: String; let ring: [CLLocationCoordinate2D] }
    private struct Flag: Identifiable { var id: String { code }; let code: String; let coordinate: CLLocationCoordinate2D }
    private struct Place: Identifiable { let id: PersistentIdentifier; let coordinate: CLLocationCoordinate2D; let name: String; let asset: PHAsset? }
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
                // White reads on the sea, on forest and on desert alike; gold was lost on dry land.
                // The outlines are drawn for a view of the whole country; close in they'd cut
                // across bays and headlands, so they bow out.
                ForEach(span > 4 ? shapes : []) { shape in
                    MapPolygon(coordinates: shape.ring)
                        .foregroundStyle(shape.code == selected ? FootprintNight.glow.opacity(0.14) : Color.white.opacity(0.05))
                        .stroke(.white.opacity(shape.code == selected ? 1 : 0.8),
                                style: StrokeStyle(lineWidth: shape.code == selected ? 1.4 : 0.9, lineJoin: .round))
                }
                ForEach(roads) { road in
                    // A dark edge under each road keeps it clear of the ground it crosses.
                    MapPolyline(coordinates: road.points)
                        .stroke(.black.opacity(0.35), style: StrokeStyle(lineWidth: tier == .places ? 4.5 : 3.6, lineCap: .round, lineJoin: .round))
                    MapPolyline(coordinates: road.points)
                        .stroke(road.mode.color, style: StrokeStyle(lineWidth: tier == .places ? 2.6 : 2, lineCap: .round, lineJoin: .round))
                }
                switch tier {
                case .space:
                    ForEach(lights) { dot in
                        Annotation("", coordinate: dot.coordinate, anchor: .center) { light }
                            .annotationTitles(.hidden)
                    }
                case .cities:
                    ForEach(namedCities) { city in
                        Annotation("", coordinate: city.center.onMap, anchor: .center) {
                            // In one stack, so the map gives the name room; an overlay is cut off at the dot.
                            Button { dive(into: city) } label: {
                                ZStack { light; caption(city.name).offset(y: 17) }
                                    .frame(minWidth: 44, minHeight: 44)
                                    .contentShape(.rect)
                            }
                            .buttonStyle(PressableStyle())
                        }
                        .annotationTitles(.hidden)
                    }
                case .places:
                    ForEach(places) { place in
                        Annotation("", coordinate: place.coordinate, anchor: .center) {
                            Button { openedStay = PlaceSummaries.shared.stay(place.id) } label: { marker(place) }
                                .buttonStyle(PressableStyle())
                                .accessibilityLabel(place.name)
                        }
                        .annotationTitles(.hidden)
                    }
                }
                if tier != .places {
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
            }
            // From space the Earth as photographed at night; close in, the land itself.
            .mapStyle(.imagery(elevation: .realistic))
            .mapControls { MapCompass() }
            .onMapCameraChange(frequency: .onEnd) { context in
                region = context.region
                updateRoads()
                updatePlaces()
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
        .sheet(item: $openedStay) { StayDetailView(stay: $0) }
        // Dragging the map down must move the map, not put the globe away.
        .interactiveDismissDisabled()
    }

    // MARK: Pieces

    /// What the map shows at this distance.
    private enum Tier { case space, cities, places }
    private var tier: Tier { span > 30 ? .space : span > 0.6 ? .cities : .places }

    /// Whether a point is on the part of the Earth in view, with a margin.
    private func inView(_ coordinate: CLLocationCoordinate2D) -> Bool {
        guard let region, span < 120 else { return true }
        return abs(coordinate.latitude - region.center.latitude) <= region.span.latitudeDelta * 0.65
            && abs((coordinate.longitude - region.center.longitude).remainder(dividingBy: 360)) <= region.span.longitudeDelta * 0.65
    }

    /// The lights of where you've been, from far out: only those in view, so that coming
    /// closer brings out more of them rather than fewer.
    private var lights: [MapDot] {
        MapDot.thinned(dots.filter { inView($0.coordinate) }, cell: max(span / 40, 0.05), limit: 160)
    }

    /// The cities in view, the ones you've spent longest in first; one that would sit on a
    /// bigger one's name is left out.
    private var namedCities: [CitySummary] {
        let gap = span / 9
        var kept: [CitySummary] = []
        for city in cities.filter({ inView($0.center.onMap) }).sorted(by: { $0.days > $1.days }) {
            let clear = kept.allSatisfy { abs($0.center.latitude - city.center.latitude) > gap * 0.5
                || abs($0.center.longitude - city.center.longitude) > gap }
            if clear { kept.append(city) }
            if kept.count == 18 { break }
        }
        return kept
    }

    /// A point of light: white at the heart so it shows on sand as well as on the sea.
    private var light: some View {
        ZStack {
            Circle()
                .fill(RadialGradient(colors: [FootprintNight.glow.opacity(0.85), FootprintNight.glow.opacity(0)],
                                     center: .center, startRadius: 1, endRadius: 11))
                .frame(width: 22, height: 22)
            Circle().fill(.white).frame(width: 4.5, height: 4.5)
        }
        .allowsHitTesting(false)
    }

    private func caption(_ text: String) -> some View {
        Text(text)
            .font(.system(size: 11, weight: .semibold))
            .foregroundStyle(.white)
            .shadow(color: .black.opacity(0.9), radius: 2)
            .shadow(color: .black.opacity(0.6), radius: 5)
            .lineLimit(1)
            .frame(maxWidth: 120)
            .fixedSize()
    }

    /// A place close in: a picture taken there, ringed in white, or a light where there's none.
    private func marker(_ place: Place) -> some View {
        let side: CGFloat = place.asset == nil ? 14 : 46
        return ZStack {
            if let asset = place.asset {
                AssetThumbnail(asset: asset, side: side)
                    .clipShape(.circle)
                    .overlay(Circle().strokeBorder(.white, lineWidth: 2))
                    .shadow(color: .black.opacity(0.45), radius: 5, y: 2)
            } else {
                Circle()
                    .fill(FootprintNight.glow)
                    .frame(width: side, height: side)
                    .overlay(Circle().strokeBorder(.white, lineWidth: 2))
                    .shadow(color: .black.opacity(0.45), radius: 4, y: 1)
            }
            caption(place.name).offset(y: side / 2 + 10)
        }
        .frame(minWidth: 44, minHeight: 44)
        .contentShape(.rect)
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

    /// Down into a city, close enough to see its places one by one.
    private func dive(into city: CitySummary) {
        selected = city.countryCode
        withAnimation(.smooth(duration: 1.6)) {
            position = .region(MKCoordinateRegion(center: city.center.onMap,
                                                  span: MKCoordinateSpan(latitudeDelta: 0.16, longitudeDelta: 0.16)))
        }
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

    /// The places in view once close enough to tell them apart, spread so their pictures don't
    /// pile up, each with a picture taken there when the library has one.
    private func updatePlaces() {
        placeWork?.cancel()
        guard tier == .places else {
            if !places.isEmpty { places = [] }
            return
        }
        let picked = MapDot.thinned(dots.filter { inView($0.coordinate) }, cell: span / 10, limit: 30)
        placeWork = Task {
            var found: [Place] = []
            for dot in picked {
                guard !Task.isCancelled, let stay = PlaceSummaries.shared.stay(dot.id) else { continue }
                let asset: PHAsset?
                if let known = pictures[dot.id] {
                    asset = known
                } else {
                    asset = DayPhotos.assets(in: DayPhotos.interval(of: stay), near: stay.location).first
                    pictures[dot.id] = .some(asset)
                    await Task.yield()
                }
                found.append(Place(id: dot.id, coordinate: dot.coordinate, name: stay.displayName, asset: asset))
            }
            if !Task.isCancelled { places = found }
        }
    }

    /// The roads in view, at the detail the zoom can show: none from space, every street
    /// close in. A few hundred lines at most, the newest first.
    private func updateRoads() {
        guard let region, span < 30 else {
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

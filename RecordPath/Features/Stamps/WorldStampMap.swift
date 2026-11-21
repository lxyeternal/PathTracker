import SwiftUI
import MapKit

/// The countries you've been to, on a map kept dark until you arrive: each one outlined and
/// lit, its flag standing on it, your cities as points of light. Continents along the top move
/// the map and narrow the list beneath it.
struct WorldStampMap: View {
    let visited: Set<String>
    let countries: [CountrySummary]
    let cities: [Stamp]
    let continentsVisited: Int
    var onOpen: (CountrySummary) -> Void = { _ in }

    @State private var selection: String?
    @State private var position: MapCameraPosition = .automatic
    @State private var shapes: [Shape] = []
    @State private var pins: [Pin] = []
    @State private var span: Double = 120
    @State private var showsUnvisited = false
    @State private var isFullScreen = false

    private static let glow = Color(red: 1.0, green: 0.78, blue: 0.36)
    private static let night = Color(red: 0.06, green: 0.07, blue: 0.12)

    struct Shape: Identifiable {
        let id: String
        let code: String
        let ring: [CLLocationCoordinate2D]
    }

    struct Pin: Identifiable {
        let code: String
        let coordinate: CLLocationCoordinate2D
        var id: String { code }
    }

    private var continents: [Continent] {
        Continent.all.sorted {
            let a = $0.regions.filter(visited.contains).count, b = $1.regions.filter(visited.contains).count
            return a != b ? a > b : $0.id < $1.id
        }
    }

    private var total: Int { Continent.all.reduce(0) { $0 + $1.regions.count } }
    private var selected: Continent? { selection.flatMap { id in Continent.all.first { $0.id == id } } }
    private var scope: [String] { selected?.regions ?? Continent.all.flatMap(\.regions) }

    private var listed: [CountrySummary] {
        let codes = Set(scope)
        return countries.filter { codes.contains($0.code) }.sorted { $0.days.count > $1.days.count }
    }

    private var unvisited: [String] { scope.filter { !visited.contains($0) }.sorted() }

    var body: some View {
        VStack(alignment: .leading, spacing: 14) {
            header
            chips
            // Still on the page, so the page scrolls past it; opened up, it moves freely.
            map(interactive: false)
                .frame(height: 340)
                .clipShape(.rect(cornerRadius: 28, style: .continuous))
                .overlay(RoundedRectangle(cornerRadius: 28, style: .continuous).strokeBorder(.white.opacity(0.08), lineWidth: 1))
                .overlay(alignment: .bottomLeading) { keyLegend.padding(12) }
                .overlay(alignment: .topTrailing) {
                    Button { isFullScreen = true } label: {
                        Image(systemName: "arrow.up.left.and.arrow.down.right")
                            .font(.footnote.weight(.bold))
                            .foregroundStyle(.white)
                            .frame(width: 38, height: 38)
                            .glassEffect(.regular.interactive(), in: .circle)
                    }
                    .environment(\.colorScheme, .dark)
                    .accessibilityLabel("查看地图")
                    .padding(12)
                }
            if listed.isEmpty {
                Text(selected == nil ? "出国旅行后，去过的国家会在地图上亮起来。" : "这片大陆还在等你。")
                    .font(.subheadline).foregroundStyle(.secondary)
                    .frame(maxWidth: .infinity)
                    .padding(.vertical, 18)
            } else {
                list
            }
            if !unvisited.isEmpty { waiting }
        }
        .task(id: visited.count + cities.count) { load() }
        .fullScreenCover(isPresented: $isFullScreen) { fullScreen }
    }

    // MARK: Pieces

    private var header: some View {
        HStack(alignment: .firstTextBaseline, spacing: 6) {
            Text("\(visited.count)")
                .font(.system(size: 40, weight: .bold, design: .rounded))
                .contentTransition(.numericText())
            Text("/ \(total)").font(.title3).foregroundStyle(.secondary)
            Spacer()
            VStack(alignment: .trailing, spacing: 1) {
                Text("去过的国家和地区").font(.subheadline.weight(.semibold))
                Text("跨越 \(continentsVisited) 个大洲").font(.footnote).foregroundStyle(.secondary)
            }
        }
        .padding(.horizontal, 4)
    }

    private var chips: some View {
        ScrollView(.horizontal) {
            HStack(spacing: 8) {
                chip(title: String(localized: "全部", bundle: .appLanguage), count: "\(visited.count)", id: nil)
                ForEach(continents) { continent in
                    let lit = continent.regions.filter(visited.contains).count
                    chip(title: continent.name, count: "\(lit)/\(continent.regions.count)", id: continent.id)
                }
            }
            .padding(.horizontal, 1)
        }
        .scrollIndicators(.hidden)
        .scrollClipDisabled()
    }

    private func chip(title: String, count: String, id: String?) -> some View {
        let on = selection == id
        return Button {
            withAnimation(.smooth(duration: 0.9)) {
                selection = id
                position = .region(region(for: id))
            }
        } label: {
            HStack(spacing: 6) {
                Text(verbatim: title).font(.subheadline.weight(.semibold))
                Text(verbatim: count).font(.caption.weight(.semibold)).monospacedDigit().opacity(0.7)
            }
            .foregroundStyle(on ? Color.black : .primary)
            .padding(.horizontal, 14).padding(.vertical, 8)
            .background(on ? AnyShapeStyle(Self.glow) : AnyShapeStyle(.background.secondary), in: .capsule)
        }
        .buttonStyle(PressableStyle())
        .sensoryFeedback(.selection, trigger: on)
    }

    private var fullScreen: some View {
        map(interactive: true)
            .ignoresSafeArea()
            .overlay(alignment: .top) {
                HStack(alignment: .top, spacing: 10) {
                    chips.environment(\.colorScheme, .dark)
                    Button { isFullScreen = false } label: {
                        Image(systemName: "xmark")
                            .font(.subheadline.weight(.bold))
                            .foregroundStyle(.white)
                            .frame(width: 40, height: 40)
                            .glassEffect(.regular.interactive(), in: .circle)
                    }
                    .accessibilityLabel("关闭")
                }
                .padding(.horizontal, 16)
                .padding(.top, 6)
                .environment(\.colorScheme, .dark)
            }
            .overlay(alignment: .bottomLeading) { keyLegend.padding(16) }
            .environment(\.locale, appLocale)
    }

    private var keyLegend: some View {
        HStack(spacing: 10) {
            legend(color: Self.glow, text: "去过的国家")
            legend(color: .white, text: "城市")
        }
        .padding(.horizontal, 12).padding(.vertical, 7)
        .glassEffect(.regular, in: .capsule)
        .environment(\.colorScheme, .dark)
    }

    private func map(interactive: Bool) -> some View {
        Map(position: $position, interactionModes: interactive ? [.pan, .zoom, .rotate] : []) {
            ForEach(shapes) { shape in
                MapPolygon(coordinates: shape.ring)
                    .foregroundStyle(Self.glow.opacity(0.3))
                    .stroke(Self.glow.opacity(0.95), style: StrokeStyle(lineWidth: 1.4, lineCap: .round, lineJoin: .round))
            }
            // The fog lifts around each city, outline or not.
            ForEach(cities) { stamp in
                MapCircle(center: stamp.coordinate.onMap, radius: 70_000)
                    .foregroundStyle(Self.glow.opacity(0.16))
            }
            ForEach(cities) { stamp in
                Annotation("", coordinate: stamp.coordinate.onMap, anchor: .center) {
                    ZStack {
                        Circle()
                            .fill(RadialGradient(colors: [Self.glow.opacity(0.7), Self.glow.opacity(0)], center: .center, startRadius: 1, endRadius: 11))
                            .frame(width: 22, height: 22)
                        Circle().fill(.white).frame(width: 4.5, height: 4.5)
                        if span < 14 {
                            Text(CityStampStyle.displayName(stamp))
                                .font(.system(size: 10, weight: .semibold))
                                .foregroundStyle(.white)
                                .shadow(color: .black, radius: 2)
                                .fixedSize()
                                .offset(y: 12)
                        }
                    }
                    .allowsHitTesting(false)
                }
                .annotationTitles(.hidden)
            }
            ForEach(pins) { pin in
                Annotation("", coordinate: pin.coordinate, anchor: .bottom) {
                    flag(pin.code)
                }
                .annotationTitles(.hidden)
            }
        }
        .mapStyle(.standard(elevation: .flat, emphasis: .muted, pointsOfInterest: .excludingAll))
        .mapControls { }
        .onMapCameraChange(frequency: .onEnd) { span = $0.region.span.latitudeDelta }
        .environment(\.colorScheme, .dark)
    }

    private func legend(color: Color, text: LocalizedStringKey) -> some View {
        HStack(spacing: 5) {
            Circle().fill(color).frame(width: 7, height: 7)
            Text(text).font(.caption2.weight(.semibold)).foregroundStyle(.white.opacity(0.85))
        }
    }

    /// A flag planted on its country; tapping opens the country.
    @ViewBuilder
    private func flag(_ code: String) -> some View {
        let badge = VStack(spacing: 0) {
            Text(String.flag(for: code))
                .font(.system(size: 17))
                .frame(width: 29, height: 29)
                .background(Self.night, in: .circle)
                .overlay(Circle().strokeBorder(Self.glow, lineWidth: 1.5))
                .shadow(color: Self.glow.opacity(0.6), radius: 6)
            Rectangle().fill(Self.glow).frame(width: 1.5, height: 7)
        }
        if let country = countries.first(where: { $0.code == code }) {
            Button {
                isFullScreen = false
                onOpen(country)
            } label: { badge }
                .buttonStyle(PressableStyle())
                .accessibilityLabel(country.name)
        } else {
            badge
        }
    }

    private var list: some View {
        VStack(spacing: 0) {
            ForEach(listed) { country in
                Button { onOpen(country) } label: {
                    HStack(spacing: 12) {
                        Text(country.flag).font(.system(size: 30))
                        VStack(alignment: .leading, spacing: 2) {
                            Text(country.name).font(.body.weight(.semibold))
                            Text(country.cities.sorted { $0.value > $1.value }.prefix(3).map(\.key).joined(separator: "、"))
                                .font(.footnote).foregroundStyle(.secondary).lineLimit(1)
                        }
                        Spacer(minLength: 8)
                        VStack(alignment: .trailing, spacing: 2) {
                            Text("\(country.days.count) 天").font(.subheadline.weight(.semibold)).monospacedDigit()
                            Text(country.firstVisit.formatted(.dateTime.year().locale(appLocale)))
                                .font(.caption).foregroundStyle(.secondary)
                        }
                        Image(systemName: "chevron.right").font(.caption.weight(.semibold)).foregroundStyle(.tertiary)
                    }
                    .padding(.horizontal, 16).padding(.vertical, 11)
                    .contentShape(.rect)
                }
                .buttonStyle(.plain)
                if country.id != listed.last?.id { Divider().padding(.leading, 58) }
            }
        }
        .background(.background.secondary, in: .rect(cornerRadius: 24, style: .continuous))
    }

    /// Everywhere not reached yet, folded away: there to browse, not to scold.
    private var waiting: some View {
        VStack(alignment: .leading, spacing: 10) {
            Button {
                withAnimation(.smooth) { showsUnvisited.toggle() }
            } label: {
                HStack {
                    Text("还没去过的 \(unvisited.count) 个").font(.subheadline.weight(.medium))
                    Spacer()
                    Image(systemName: "chevron.down")
                        .font(.caption.weight(.bold))
                        .rotationEffect(.degrees(showsUnvisited ? 180 : 0))
                }
                .foregroundStyle(.secondary)
                .padding(.horizontal, 4)
                .contentShape(.rect)
            }
            .buttonStyle(.plain)
            if showsUnvisited {
                LazyVGrid(columns: [GridItem(.adaptive(minimum: 34), spacing: 6)], spacing: 6) {
                    ForEach(unvisited, id: \.self) { code in
                        Text(String.flag(for: code))
                            .font(.system(size: 26))
                            .grayscale(1)
                            .opacity(0.3)
                            .accessibilityLabel(appLocale.localizedString(forRegionCode: code) ?? code)
                            .accessibilityValue(String(localized: "还没去过", bundle: .appLanguage))
                    }
                }
                .padding(14)
                .background(.background.secondary, in: .rect(cornerRadius: 22, style: .continuous))
                .transition(.opacity.combined(with: .move(edge: .top)))
            }
        }
    }

    // MARK: Geometry

    private func load() {
        var newShapes: [Shape] = []
        var newPins: [Pin] = []
        for code in visited.sorted() {
            let mine = cities.filter { $0.countryCode == code }.map { $0.coordinate.onMap }
            // The larger pieces only: a country's hundred islets would cost more than they show.
            let rings = Self.pieces(of: code, visited: mine)
            for (index, ring) in rings.enumerated() {
                newShapes.append(Shape(id: "\(code).\(index)", code: code, ring: ring))
            }
            // The flag stands where you were, or on the mainland when no city is known.
            if let spot = Self.centre(of: mine) ?? rings.first.flatMap(Self.centre(of:)) {
                newPins.append(Pin(code: code, coordinate: spot))
            }
        }
        shapes = newShapes
        pins = newPins
        position = .region(region(for: selection))
    }

    /// The pieces of a country worth drawing from far away: its larger ones, at least its three
    /// largest however small (Singapore is one small ring), and any island you actually went to.
    static func pieces(of code: String, visited: [CLLocationCoordinate2D]) -> [[CLLocationCoordinate2D]] {
        let all = CountryBorders.rings(for: code).sorted { $0.count > $1.count }
        guard !CountryBorders.drawnWhole.contains(code) else { return all }
        var kept = Set(all.indices.filter { all[$0].count >= 12 }.prefix(80))
        kept.formUnion(all.indices.prefix(3))
        for index in all.indices where !kept.contains(index) {
            let lats = all[index].map(\.latitude), lons = all[index].map(\.longitude)
            guard let south = lats.min(), let north = lats.max(), let west = lons.min(), let east = lons.max() else { continue }
            // Near enough: a city's centre is often a little way off the coastline as drawn.
            if visited.contains(where: { $0.latitude > south - 0.3 && $0.latitude < north + 0.3 && $0.longitude > west - 0.3 && $0.longitude < east + 0.3 }) {
                kept.insert(index)
            }
        }
        return kept.sorted().map { all[$0] }
    }

    private static func centre(of points: [CLLocationCoordinate2D]) -> CLLocationCoordinate2D? {
        guard !points.isEmpty else { return nil }
        let lats = points.map(\.latitude), lons = points.map(\.longitude)
        return CLLocationCoordinate2D(latitude: (lats.min()! + lats.max()!) / 2, longitude: (lons.min()! + lons.max()!) / 2)
    }

    /// A continent's frame, or for everything, a frame around where the flags stand.
    private func region(for continent: String?) -> MKCoordinateRegion {
        func make(_ lat: Double, _ lon: Double, _ dLat: Double, _ dLon: Double) -> MKCoordinateRegion {
            MKCoordinateRegion(center: CLLocationCoordinate2D(latitude: lat, longitude: lon),
                               span: MKCoordinateSpan(latitudeDelta: dLat, longitudeDelta: dLon))
        }
        switch continent {
        case "142": return make(30, 95, 80, 110)
        case "150": return make(54, 15, 42, 62)
        case "002": return make(2, 20, 82, 82)
        case "019": return make(12, -88, 130, 120)
        case "009": return make(-22, 150, 58, 85)
        default:
            // The countries themselves, not just the flags; far-off islets don't stretch the frame.
            let points = pins.map(\.coordinate) + shapes.filter { $0.ring.count >= 60 }.flatMap(\.ring)
            let lats = points.map(\.latitude), lons = points.map(\.longitude)
            guard let minLat = lats.min(), let maxLat = lats.max(), let minLon = lons.min(), let maxLon = lons.max() else {
                return make(25, 105, 110, 150)
            }
            // Flags on both sides of the Pacific: show the whole world rather than guess a seam.
            // Too wide to fit: the whole world won't show at once on a phone, so the map settles
            // on the middle of where the flags are thickest and the continents above do the rest.
            guard maxLon - minLon < 200 else {
                let flags = pins.map(\.coordinate)
                guard !flags.isEmpty else { return make(20, 20, 140, 340) }
                let middleLat = flags.map(\.latitude).sorted()[flags.count / 2]
                let middleLon = flags.map(\.longitude).sorted()[flags.count / 2]
                return make(min(max(middleLat, -30), 45), middleLon, 140, 340)
            }
            return make((minLat + maxLat) / 2, (minLon + maxLon) / 2,
                        min(max((maxLat - minLat) * 1.25, 40), 140), min(max((maxLon - minLon) * 1.2, 50), 340))
        }
    }
}

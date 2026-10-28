import SwiftUI
import SwiftData
import MapKit

struct WorldView: View {
    @Binding var showingSettings: Bool
    private var summaries = PlaceSummaries.shared
    @Environment(\.placeTagger) private var tagger
    private var stays: [Stay] { summaries.stays }
    private var insights: WorldInsights { summaries.world }
    private var lightUp: LightUpInsights { summaries.lightUp }
    @State private var importingPhotos = false
    @AppStorage("photoImport.lastRun") private var photoImportRun: Double = 0
    @State private var selectedStay: Stay?
    @State private var showingMap = false
    @State private var search = ""
    @Namespace private var namespace

    var body: some View {
        NavigationStack {
            ScrollView {
                // Lazy: sections further down are built when they come into view, so the tab
                // opens at once however many places there are.
                LazyVStack(alignment: .leading, spacing: 16) {
                    if stays.isEmpty {
                        ContentUnavailableView("足迹会在这里出现",
                                               systemImage: "globe.asia.australia",
                                               description: Text("去过的国家、城市和景点会被自动整理出来。"))
                            .padding(.top, 60)
                        PhotoImportCard { importingPhotos = true }
                    } else if !search.isEmpty {
                        PlaceSearchResults(query: search, stays: stays, countries: insights.countries)
                    } else {
                        summaryGrid
                        lightUpCard
                        if photoImportRun == 0 { PhotoImportCard { importingPhotos = true } }
                        mapCard
                        GalleryPreview()
                        if !insights.countries.isEmpty { countries }
                        if !insights.frequentPlaces.isEmpty { frequentPlaces }
                        if !insights.landmarks.isEmpty { landmarks }
                    }
                }
                .padding(.horizontal)
                .padding(.bottom, 24)
            }
            .navigationTitle("足迹")
            .searchable(text: $search, prompt: "搜索地点、城市或国家")
            .navigationDestination(for: PlaceVisits.self) { PlaceVisitsView(place: $0) }
            .navigationDestination(for: PlaceAround.self) { route in
                if let stay = summaries.stay(route.id) {
                    PlaceVisitsView(place: PlaceVisits.around(stay, in: summaries.stays))
                }
            }
            .toolbar {
                ToolbarItem(placement: .topBarTrailing) {
                    ProfileToolbarButton(showingSettings: $showingSettings)
                }
            }
            .navigationDestination(for: CountrySummary.self) { country in
                CountryDetailView(country: country)
            }
            .navigationDestination(for: PlacesList.self) { list in
                PlacesListView(list: list)
            }
            .navigationDestination(for: LightUpRoute.self) { _ in
                LightUpView()
            }
            .navigationDestination(for: GalleryRoute.self) { _ in GalleryView() }
            .navigationDestination(for: Province.self) { ProvinceDetailView(province: $0) }
            .navigationDestination(for: CityStint.self) { CityStintView(stint: $0) }
            .navigationDestination(for: DayRoute.self) { DayPage(day: $0.day) }
            .sheet(isPresented: $importingPhotos) { PhotoImportSheet() }
            .sheet(item: $selectedStay) { StayDetailView(stay: $0) }
            .task(id: insights.frequentPlaces.map(\.id)) {
                tagger?.nameFrequentPlaces(insights.frequentPlaces.map(\.representative))
            }
            .fullScreenCover(isPresented: $showingMap) {
                WorldMapScreen(dots: summaries.dots)
                    .navigationTransition(.zoom(sourceID: "world", in: namespace))
            }
        }
    }

    private var summaryGrid: some View {
        MetricGrid {
            MetricTile(title: "国家与地区", value: "\(insights.countries.count)", symbol: "flag.fill", tint: .red)
            MetricTile(title: "城市", value: "\(insights.cityCount)", symbol: "building.2.fill", tint: .indigo)
            MetricTile(title: "景点", value: "\(insights.landmarks.count)", symbol: "star.fill", tint: .yellow)
            MetricTile(title: "记录天数", value: "\(insights.trackedDays)", symbol: "calendar", tint: .teal)
        }
    }

    /// A peek at the light-up map: the province tiles, small, with the counts.
    private var lightUpCard: some View {
        NavigationLink(value: LightUpRoute()) {
            HStack(spacing: 16) {
                ProvinceTileMap(insights: lightUp, showsLabels: false)
                    .allowsHitTesting(false)
                    .frame(width: 104)
                VStack(alignment: .leading, spacing: 4) {
                    Text("点亮地图").font(.headline)
                    Text("\(lightUp.provinces.count) 个省级行政区 · \(lightUp.countries.count) 个国家和地区")
                        .font(.subheadline).foregroundStyle(.secondary)
                }
                Spacer(minLength: 0)
                Image(systemName: "chevron.right").font(.caption.weight(.semibold)).foregroundStyle(.tertiary)
            }
            .padding(14)
            .background(.background.secondary, in: .rect(cornerRadius: 24, style: .continuous))
        }
        .buttonStyle(PressableStyle())
    }

    private var mapCard: some View {
        Button { showingMap = true } label: {
            WorldMap(dots: summaries.dots, interactive: false, focused: true)
                .allowsHitTesting(false)
                .frame(height: 240)
                .clipShape(.rect(cornerRadius: 28, style: .continuous))
                .overlay(alignment: .bottomLeading) {
                    Label("全部足迹", systemImage: "arrow.up.left.and.arrow.down.right")
                        .font(.footnote.weight(.semibold))
                        .padding(.horizontal, 12)
                        .padding(.vertical, 8)
                        .glassEffect(.regular, in: .capsule)
                        .padding(12)
                }
        }
        .buttonStyle(PressableStyle())
        .matchedTransitionSource(id: "world", in: namespace)
    }

    private var countries: some View {
        VStack(alignment: .leading, spacing: 10) {
            SectionHeader(title: "国家和地区")
            VStack(spacing: 0) {
                ForEach(insights.countries) { country in
                    NavigationLink(value: country) {
                        HStack(spacing: 14) {
                            Text(country.flag).font(.system(size: 34))
                            VStack(alignment: .leading, spacing: 2) {
                                Text(country.name).font(.body.weight(.semibold))
                                Text("\(country.days.count) 天 · \(country.cities.count) 座城市")
                                    .font(.subheadline).foregroundStyle(.secondary)
                            }
                            Spacer()
                            Image(systemName: "chevron.right").font(.caption.weight(.semibold)).foregroundStyle(.tertiary)
                        }
                        .padding(.horizontal, 16)
                        .padding(.vertical, 10)
                        .contentShape(.rect)
                    }
                    .buttonStyle(.plain)
                    if country.id != insights.countries.last?.id { Divider().padding(.leading, 64) }
                }
            }
            .padding(.vertical, 6)
            .background(.background.secondary, in: .rect(cornerRadius: 24, style: .continuous))
        }
    }

    private var frequentPlaces: some View {
        VStack(alignment: .leading, spacing: 10) {
            HStack {
                SectionHeader(title: "常去的地方")
                NavigationLink("全部", value: PlacesList.frequent).font(.subheadline).padding(.top, 8).padding(.trailing, 4)
            }
            ScrollView(.horizontal) {
                HStack(spacing: 12) {
                    ForEach(insights.frequentPlaces) { place in
                        NavigationLink(value: PlaceAround(place.representative)) {
                            FrequentPlaceCard(place: place)
                        }
                        .buttonStyle(PressableStyle())
                        .scrollTransition(.interactive, axis: .horizontal) { content, phase in
                            content.scaleEffect(phase.isIdentity ? 1 : 0.94).opacity(phase.isIdentity ? 1 : 0.8)
                        }
                    }
                }
                .scrollTargetLayout()
            }
            .scrollIndicators(.hidden)
            .scrollTargetBehavior(.viewAligned)
            .scrollClipDisabled()
            Text("给常去的地方起个名字，比如“家”或“学校”，以后每次到访都会自动用上。")
                .font(.footnote).foregroundStyle(.secondary).padding(.horizontal, 4)
        }
    }

    private var landmarks: some View {
        VStack(alignment: .leading, spacing: 10) {
            HStack {
                SectionHeader(title: "去过的景点")
                NavigationLink("全部", value: PlacesList.landmarks).font(.subheadline).padding(.top, 8).padding(.trailing, 4)
            }
            ScrollView(.horizontal) {
                HStack(spacing: 12) {
                    ForEach(insights.landmarks.prefix(10)) { stay in
                        NavigationLink(value: PlaceAround(stay)) { SightCard(stay: stay) }
                            .buttonStyle(PressableStyle())
                            .scrollTransition(.interactive, axis: .horizontal) { content, phase in
                                content.scaleEffect(phase.isIdentity ? 1 : 0.94).opacity(phase.isIdentity ? 1 : 0.8)
                            }
                    }
                }
                .scrollTargetLayout()
            }
            .scrollIndicators(.hidden)
            .scrollTargetBehavior(.viewAligned)
            .scrollClipDisabled()
        }
    }
}

struct FrequentPlaceCard: View {
    let place: FrequentPlace

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            PlacePicture(stay: place.representative)
                .frame(height: 96)
            VStack(alignment: .leading, spacing: 2) {
                Text(place.representative.displayName)
                    .font(.subheadline.weight(.semibold))
                    .lineLimit(1)
                Text("\(place.visits) 次 · \(Format.duration(place.totalTime))")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
            .padding(.horizontal, 12)
            .padding(.vertical, 10)
        }
        .frame(width: 150, alignment: .leading)
        .background(.background.secondary)
        .clipShape(.rect(cornerRadius: 20, style: .continuous))
    }
}

struct PlaceRow: View {
    let stay: Stay
    /// Within a day's list, show the time range instead of the date.
    var timeOnly = false

    var body: some View {
        HStack(spacing: 14) {
            PlaceThumb(stay: stay)
            VStack(alignment: .leading, spacing: 2) {
                Text(stay.displayName).font(.body.weight(.semibold)).lineLimit(1)
                Text([stay.city, timeOnly ? timeRange : stay.arrival.formatted(Date.FormatStyle(date: .abbreviated, time: .omitted, locale: appLocale))].compactMap { $0 }.joined(separator: " · "))
                    .font(.subheadline).foregroundStyle(.secondary)
            }
            Spacer()
            Image(systemName: "chevron.right").font(.caption.weight(.semibold)).foregroundStyle(.tertiary)
        }
        .padding(.horizontal, 16)
        .padding(.vertical, 10)
        .contentShape(.rect)
    }

    private var timeRange: String {
        let end = stay.departure.map(Format.time) ?? String(localized: "现在", bundle: .appLanguage)
        return "\(Format.time(stay.arrival)) – \(end)"
    }
}

/// One dot per place visited (merged when close together) and flags per country.
struct WorldMap: View {
    let dots: [MapDot]
    var interactive = true
    /// Opens on where the person has been lately rather than on everywhere at once.
    var focused = false
    var onSelect: ((Stay) -> Void)?

    @State private var position: MapCameraPosition = .automatic
    @State private var region: MKCoordinateRegion?
    @State private var shown: [MapDot]

    init(dots: [MapDot], interactive: Bool = true, focused: Bool = false, onSelect: ((Stay) -> Void)? = nil) {
        self.dots = dots
        self.interactive = interactive
        self.focused = focused
        self.onSelect = onSelect
        let framed = focused ? MapDot.focus(dots) : dots
        _shown = State(initialValue: Self.overview(framed))
        // Framed once from the places themselves. An automatic camera re-frames whenever the
        // dots change, and the dots change when the camera moves: the two would chase each other.
        _position = State(initialValue: Self.framing(framed))
    }

    var body: some View {
        Map(position: $position, interactionModes: interactive ? .all : []) {
            ForEach(shown) { dot in
                Annotation("", coordinate: dot.coordinate, anchor: .center) {
                    Button { if let stay = PlaceSummaries.shared.stay(dot.id) { onSelect?(stay) } } label: {
                        Circle()
                            .fill(dot.isLandmark ? Color.yellow : Color.accentColor)
                            .frame(width: interactive ? 14 : 10, height: interactive ? 14 : 10)
                            .overlay(Circle().stroke(.white, lineWidth: 2))
                    }
                    .buttonStyle(.plain)
                    .disabled(onSelect == nil)
                }
                .annotationTitles(.hidden)
            }
        }
        .mapStyle(.standard(elevation: .realistic, emphasis: .muted, pointsOfInterest: .excludingAll))
        .onMapCameraChange(frequency: .onEnd) { context in
            guard interactive else { return }
            region = context.region
            updateShown()
        }
        .onChange(of: dots.count) {
            region = nil
            updateShown()
            position = Self.framing(focused ? MapDot.focus(dots) : dots)
        }
    }

    /// A few hundred dots at most: the ones in view, spread out at a spacing that suits the
    /// zoom. Thousands of annotations at once make the map crawl.
    private static func framing(_ dots: [MapDot]) -> MapCameraPosition {
        let lats = dots.map(\.coordinate.latitude)
        guard let minLat = lats.min(), let maxLat = lats.max() else { return .automatic }
        // Longitudes wrap: San Francisco and Tokyo are close across the Pacific. The places
        // fill the circle except for its widest empty stretch.
        let lons = Set(dots.map { ($0.coordinate.longitude * 10).rounded() / 10 }).sorted()
        var widest = lons.first! + 360 - lons.last!, west = lons.first!
        for (a, b) in zip(lons, lons.dropFirst()) where b - a > widest {
            widest = b - a
            west = b
        }
        let lonSpan = 360 - widest
        var centerLon = west + lonSpan / 2
        if centerLon > 180 { centerLon -= 360 }
        let center = CLLocationCoordinate2D(latitude: (minLat + maxLat) / 2, longitude: centerLon)
        let span = MKCoordinateSpan(latitudeDelta: min(max((maxLat - minLat) * 1.4, 0.02), 150),
                                    longitudeDelta: min(max(lonSpan * 1.4, 0.02), 340))
        return .region(MKCoordinateRegion(center: center, span: span))
    }

    /// Spaced to the area the places cover: a city's worth of dots doesn't become a blot.
    private static func overview(_ dots: [MapDot]) -> [MapDot] {
        let lats = dots.map(\.coordinate.latitude), lons = dots.map(\.coordinate.longitude)
        guard let minLat = lats.min(), let maxLat = lats.max(), let minLon = lons.min(), let maxLon = lons.max() else { return [] }
        let span = max(maxLat - minLat, maxLon - minLon)
        return MapDot.thinned(dots, cell: max(span / 18, 0.002), limit: 150)
    }

    private func updateShown() {
        guard let region else {
            shown = Self.overview(focused ? MapDot.focus(dots) : dots)
            return
        }
        let span = region.span
        let visible = dots.filter {
            abs($0.coordinate.latitude - region.center.latitude) <= span.latitudeDelta * 0.75
                && abs(($0.coordinate.longitude - region.center.longitude).remainder(dividingBy: 360)) <= span.longitudeDelta * 0.75
        }
        shown = MapDot.thinned(visible, cell: max(span.latitudeDelta / 22, 0.002), limit: 200)
    }
}

private struct WorldMapScreen: View {
    let dots: [MapDot]
    @Environment(\.dismiss) private var dismiss
    @Environment(AppNavigator.self) private var navigator
    @State private var selected: Stay?

    var body: some View {
        NavigationStack {
            WorldMap(dots: dots, interactive: true, focused: true, onSelect: { selected = $0 })
                .ignoresSafeArea()
                .navigationTitle("全部足迹")
                .navigationBarTitleDisplayMode(.inline)
                .toolbar {
                    ToolbarItem(placement: .cancellationAction) {
                        Button("关闭", systemImage: "xmark") { dismiss() }
                    }
                }
                .sheet(item: $selected) { StayDetailView(stay: $0) }
                .onChange(of: navigator.jumpCount) { dismiss() }
        }
    }
}

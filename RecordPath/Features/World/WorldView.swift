import SwiftUI
import SwiftData
import MapKit

struct WorldView: View {
    @Binding var showingSettings: Bool
    private var summaries = PlaceSummaries.shared
    @Environment(\.placeTagger) private var tagger
    private var stays: [Stay] { summaries.stays }
    private var insights: WorldInsights { summaries.world }
    @State private var importingPhotos = false
    @State private var selectedStay: Stay?
    @State private var showingMap = false
    @State private var search = ""
    /// The sights shown: "" for all, "mustSee", or a country's code.
    @State private var sightFilter = ""
    @Namespace private var namespace

    var body: some View {
        NavigationStack {
            ScrollView {
                // Edge to edge, outside the page's margins: the globe isn't in a box, it's in the sky.
                if !stays.isEmpty, search.isEmpty { globe }
                // Lazy: sections further down are built when they come into view, so the tab
                // opens at once however many places there are.
                LazyVStack(alignment: .leading, spacing: 34) {
                    if stays.isEmpty {
                        ContentUnavailableView("足迹会在这里出现",
                                               systemImage: "globe.asia.australia",
                                               description: Text("去过的国家、城市和景点会被自动整理出来。"))
                            .padding(.top, 60)
                        PhotoImportCard { importingPhotos = true }
                    } else if !search.isEmpty {
                        PlaceSearchResults(query: search, stays: stays, countries: insights.countries)
                    } else {
                        // The globe, the figures and the flags are one picture: the world at
                        // night with what you've seen of it written across the sky.
                        VStack(spacing: 18) {
                            FootprintFigures(countries: insights.countries.count, cities: insights.cityCount,
                                             sights: insights.landmarks.count, days: insights.trackedDays,
                                             since: insights.firstDay)
                                .padding(.top, 4)
                            if !insights.countries.isEmpty { countries.padding(.top, 10) }
                        }
                        FootprintCollections(book: summaries.stamps)
                        if !insights.cities.isEmpty { cities }
                        GalleryPreview()
                        if !insights.frequentPlaces.isEmpty { frequentPlaces }
                        if !insights.landmarks.isEmpty { landmarks }
                    }
                }
                .padding(.horizontal)
                .padding(.bottom, 24)
                // The whole page is the night sky the globe hangs in.
                .environment(\.colorScheme, .dark)
            }
            .background { FootprintNight.background }
            // Pulling the globe down past the top of the page opens it full screen.
            .onScrollGeometryChange(for: CGFloat.self) { $0.contentOffset.y + $0.contentInsets.top } action: { _, pulled in
                if pulled < -110, !showingMap, !stays.isEmpty, search.isEmpty {
                    showingMap = true
                }
            }
            .sensoryFeedback(.impact(weight: .light), trigger: showingMap) { _, open in open }
            .scrollIndicators(.hidden)
            .navigationTitle("足迹")
            .navigationBarTitleDisplayMode(.inline)
            // A bar the colour of the sky, so the title reads white and nothing shows its edge.
            .toolbarBackground(Color.black, for: .navigationBar)
            .toolbarBackground(.visible, for: .navigationBar)
            .toolbarColorScheme(.dark, for: .navigationBar)
            // Pulled down into view, so the page opens on the sky.
            .searchable(text: $search, placement: .navigationBarDrawer(displayMode: .automatic), prompt: "搜索地点、城市或国家")
            .navigationDestination(for: PlaceVisits.self) { PlaceVisitsView(place: $0) }
            .navigationDestination(for: PlaceAround.self) { route in
                if let stay = summaries.stay(route.id) {
                    PlaceVisitsView(place: PlaceVisits.around(stay, in: summaries.stays))
                }
            }
            .toolbar {
                // The title is drawn on the page itself; the bar only holds the buttons.
                ToolbarItem(placement: .principal) { Color.clear.frame(width: 1, height: 1) }
                ToolbarItem(placement: .topBarTrailing) {
                    ProfileToolbarButton(showingSettings: $showingSettings)
                }
            }
            .navigationDestination(for: CountrySummary.self) { country in
                CountryDetailView(country: country)
            }
            .navigationDestination(for: CountriesRoute.self) { CountriesListView(route: $0) }
            .navigationDestination(for: CityRoute.self) { route in
                let names = CityNames.canonical(for: summaries.stays)
                let visits = summaries.stays.filter { stay in CityNames.key(stay).flatMap { names[$0] } == route.name
                    && route.key.hasPrefix("\(stay.countryCode ?? "")|") }
                if !visits.isEmpty { PlaceVisitsView(place: PlaceVisits(name: route.name, visits: visits)) }
            }
            .navigationDestination(for: PlacesList.self) { list in
                PlacesListView(list: list)
            }
            .navigationDestination(for: StampBookRoute.self) { _ in
                StampBookView()
            }
            .navigationDestination(for: VisaWalletRoute.self) { _ in VisaWalletView() }
            .navigationDestination(for: GalleryRoute.self) { _ in GalleryView() }
            .navigationDestination(for: MustSeeRoute.self) { MustSeeView(list: $0.list) }
            .navigationDestination(for: BlindBoxRoute.self) { _ in BlindBoxView() }
            .navigationDestination(for: Province.self) { ProvinceDetailView(province: $0) }
            .navigationDestination(for: CityStint.self) { CityStintView(stint: $0) }
            .navigationDestination(for: DayRoute.self) { DayPage(day: $0.day) }
            .navigationDestination(for: MustSeeFromPlaceRoute.self) { route in
                if let place = (MustSee.china + MustSee.world).first(where: { $0.id == route.id }) { MustSeePlaceView(place: place) }
            }
            .sheet(isPresented: $importingPhotos) { PhotoImportSheet() }
            .sheet(item: $selectedStay) { StayDetailView(stay: $0) }
            .task(id: insights.frequentPlaces.map(\.id)) {
                tagger?.nameFrequentPlaces(insights.frequentPlaces.map(\.representative))
            }
            .fullScreenCover(isPresented: $showingMap) {
                FootprintExplorer(countries: insights.countries, cities: insights.cities, dots: summaries.dots,
                                  home: insights.frequentPlaces.first?.representative.coordinate)
                    .navigationTransition(.zoom(sourceID: "world", in: namespace))
            }
        }
    }

    private var globe: some View {
        Button { showingMap = true } label: {
            FootprintGlobe(dots: summaries.dots,
                           home: insights.frequentPlaces.first?.representative.coordinate,
                           cities: insights.cities)
                .frame(height: 430)
                .frame(maxWidth: .infinity)
                // The page's title is written in the sky above the Earth.
                .overlay(alignment: .topLeading) {
                    Text("足迹")
                        .font(.system(size: 34, weight: .bold))
                        .foregroundStyle(.white)
                        .padding(.leading, 20)
                        .accessibilityAddTraits(.isHeader)
                }
        }
        .buttonStyle(PressableStyle())
        .matchedTransitionSource(id: "world", in: namespace)
    }

    /// Countries by their flags, most days first, swiped through.
    private var countries: some View {
        let all = insights.countries
        return VStack(alignment: .leading, spacing: 14) {
            NightHeader(title: "国家和地区") {
                NavigationLink(value: CountriesRoute(continent: "")) {
                    HStack(spacing: 3) {
                        Text("全部 \(all.count)")
                        Image(systemName: "chevron.forward").font(.caption.weight(.semibold))
                    }
                }
            }
            ScrollView(.horizontal) {
                HStack(spacing: 8) {
                    ForEach(all.prefix(Self.countriesShown)) { country in
                        NavigationLink(value: country) { CountryFlag(country: country) }
                            .buttonStyle(PressableStyle())
                    }
                }
                .scrollTargetLayout()
            }
            .scrollIndicators(.hidden)
            .scrollTargetBehavior(.viewAligned)
            .scrollClipDisabled()
        }
    }

    private static let countriesShown = 20

    /// Cities as small night maps, most days first.
    private var cities: some View {
        VStack(alignment: .leading, spacing: 12) {
            NightHeader(title: "城市") { Text("\(insights.cityCount) 座") }
            ScrollView(.horizontal) {
                LazyHStack(spacing: 12) {
                    ForEach(insights.cities.prefix(30)) { city in
                        NavigationLink(value: CityRoute(key: city.key, name: city.name)) { CityCard(city: city) }
                            .buttonStyle(PressableStyle())
                    }
                }
                .scrollTargetLayout()
            }
            .scrollIndicators(.hidden)
            .scrollTargetBehavior(.viewAligned)
            .scrollClipDisabled()
        }
    }

    private var frequentPlaces: some View {
        VStack(alignment: .leading, spacing: 10) {
            NightHeader(title: "常去的地方") {
                NavigationLink(value: PlacesList.frequent) {
                    HStack(spacing: 3) {
                        Text("全部")
                        Image(systemName: "chevron.forward").font(.caption.weight(.semibold))
                    }
                }
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

    /// What the sights can be narrowed to: the places worth a lifetime, then each country
    /// with sights in it, most first. Only offered when there's a choice to make.
    private var sightFilters: [(id: String, title: String)] {
        let sights = insights.landmarks
        var options: [(String, String)] = []
        if sights.contains(where: { MustSee.place(for: $0) != nil }) {
            options.append(("mustSee", String(localized: "此生必去", bundle: .appLanguage)))
        }
        let byCountry = Dictionary(grouping: sights.compactMap(\.countryCode), by: { $0 }).mapValues(\.count)
        if byCountry.count > 1 {
            for code in byCountry.keys.sorted(by: { byCountry[$0]! > byCountry[$1]! }) {
                options.append((code, "\(String.flag(for: code)) \(WorldInsights.countryName(code: code, fallback: nil))"))
            }
        }
        return options.isEmpty ? [] : [("", String(localized: "route.span.all", defaultValue: "全部", bundle: .appLanguage))] + options
    }

    private var filteredSights: [Stay] {
        switch sightFilter {
        case "": insights.landmarks
        case "mustSee": insights.landmarks.filter { MustSee.place(for: $0) != nil }
        case let code: insights.landmarks.filter { $0.countryCode == code }
        }
    }

    private var landmarks: some View {
        let filters = sightFilters
        return VStack(alignment: .leading, spacing: 12) {
            NightHeader(title: "景点") {
                NavigationLink(value: PlacesList.landmarks) {
                    HStack(spacing: 3) {
                        Text("全部 \(insights.landmarks.count)")
                        Image(systemName: "chevron.forward").font(.caption.weight(.semibold))
                    }
                }
            }
            if filters.count > 1 {
                ScrollView(.horizontal) {
                    HStack(spacing: 8) {
                        ForEach(filters, id: \.id) { option in
                            Button {
                                withAnimation(.smooth) { sightFilter = option.id }
                            } label: {
                                Text(verbatim: option.title)
                                    .font(.subheadline.weight(.medium))
                                    .foregroundStyle(sightFilter == option.id ? Color.black : .white)
                                    .padding(.horizontal, 14)
                                    .padding(.vertical, 7)
                                    .background {
                                        if sightFilter == option.id { Capsule().fill(.white) }
                                        else { Capsule().strokeBorder(FootprintNight.hairline, lineWidth: 1) }
                                    }
                                    .contentShape(.capsule)
                            }
                            .buttonStyle(.plain)
                        }
                    }
                }
                .scrollIndicators(.hidden)
                .scrollClipDisabled()
                .sensoryFeedback(.selection, trigger: sightFilter)
            }
            ScrollView(.horizontal) {
                HStack(spacing: 12) {
                    ForEach(filteredSights.prefix(20)) { stay in
                        NavigationLink(value: PlaceAround(stay)) { SightPoster(stay: stay) }
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
            .id(sightFilter)
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
                HStack(spacing: 6) {
                    Text(stay.displayName).font(.body.weight(.semibold)).lineLimit(1)
                    if MustSee.place(for: stay) != nil { MustSeeTag(compact: true) }
                }
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
        let zone = stay.localTimeZone
        let end = stay.departure.map { Format.time($0, in: zone) } ?? String(localized: "现在", bundle: .appLanguage)
        return "\(Format.time(stay.arrival, in: zone)) – \(end)"
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
                    .accessibilityHidden(onSelect == nil)
                    .accessibilityLabel(onSelect == nil ? "" : PlaceSummaries.shared.stay(dot.id)?.displayName ?? "")
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

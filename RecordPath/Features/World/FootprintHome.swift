import SwiftUI
import MapKit

// The top of the footprints page: the whole world as a globe at night with every place you've
// been glowing on it, the counts beneath it as plain figures, then countries by their flags,
// cities as small night maps and sights as pictures.

/// The page's night: what the globe floats in and everything below it sits on.
enum FootprintNight {
    static let sky = Color(red: 0.012, green: 0.016, blue: 0.035)
    static let deep = Color(red: 0.035, green: 0.05, blue: 0.10)

    /// Black, like the space the globe is drawn in, so the map has no edge against the page.
    static var background: some View { Color.black.ignoresSafeArea() }

    /// A warm light, like a city seen from orbit at night.
    static let glow = Color(red: 1.0, green: 0.78, blue: 0.42)
    static let secondary = Color.white.opacity(0.56)
    static let tertiary = Color.white.opacity(0.32)
    static let hairline = Color.white.opacity(0.10)
}

/// Every place you've been, on the Earth at night, with no frame: it floats in the page's sky.
/// Tapping it opens the full map.
struct FootprintGlobe: View {
    let dots: [MapDot]
    let home: CLLocationCoordinate2D?
    let cities: [CitySummary]

    @State private var position: MapCameraPosition
    @State private var arrived = false

    /// From this far out the Earth is a whole ball in the frame.
    private static let distance: CLLocationDistance = 23_000_000

    init(dots: [MapDot], home: CLLocationCoordinate2D?, cities: [CitySummary]) {
        self.dots = dots
        self.home = home
        self.cities = cities
        let center = Self.center(home: home, dots: dots)
        // Starts turned a little to the west and settles on home, as if the globe had been spun.
        _position = State(initialValue: .camera(MapCamera(centerCoordinate: CLLocationCoordinate2D(latitude: center.latitude, longitude: center.longitude - 60),
                                                          distance: Self.distance)))
    }

    private static func center(home: CLLocationCoordinate2D?, dots: [MapDot]) -> CLLocationCoordinate2D {
        // A little south of home, so home sits in the upper half where the eye lands.
        if let home { return CLLocationCoordinate2D(latitude: max(-30, min(30, home.latitude - 8)), longitude: home.longitude) }
        guard !dots.isEmpty else { return CLLocationCoordinate2D(latitude: 20, longitude: 110) }
        let lat = dots.map(\.coordinate.latitude).reduce(0, +) / Double(dots.count)
        let lon = dots.map(\.coordinate.longitude).reduce(0, +) / Double(dots.count)
        return CLLocationCoordinate2D(latitude: max(-30, min(30, lat - 8)), longitude: lon)
    }

    /// One glow per area: a city's hundred visits are one light seen from space.
    private var lights: [MapDot] { MapDot.thinned(dots, cell: 1.2, limit: 140) }

    /// Lines from home to the cities you've travelled to, like routes on an airline's map.
    private var routes: [[CLLocationCoordinate2D]] {
        guard let home else { return [] }
        let from = CLLocation(latitude: home.latitude, longitude: home.longitude)
        return cities.lazy
            .filter { from.distance(from: CLLocation(latitude: $0.center.latitude, longitude: $0.center.longitude)) > 150_000 }
            .prefix(40)
            .map { [home.onMap, $0.center.onMap] }
    }

    var body: some View {
        Map(position: $position, interactionModes: []) {
            ForEach(Array(routes.enumerated()), id: \.offset) { _, line in
                MapPolyline(coordinates: line, contourStyle: .geodesic)
                    .stroke(FootprintNight.glow.opacity(0.5), style: StrokeStyle(lineWidth: 1.2, lineCap: .round))
            }
            ForEach(lights) { dot in
                Annotation("", coordinate: dot.coordinate, anchor: .center) {
                    Circle()
                        .fill(FootprintNight.glow)
                        .frame(width: 5, height: 5)
                        .shadow(color: FootprintNight.glow, radius: 4)
                        .shadow(color: FootprintNight.glow.opacity(0.6), radius: 10)
                }
                .annotationTitles(.hidden)
            }
            if let home {
                Annotation("", coordinate: home.onMap, anchor: .center) {
                    Circle().fill(.white).frame(width: 7, height: 7)
                        .shadow(color: .white, radius: 6)
                }
                .annotationTitles(.hidden)
            }
        }
        .mapStyle(.imagery(elevation: .realistic))
        .mapControlVisibility(.hidden)
        .allowsHitTesting(false)
        // The sky above it runs into the navigation bar with no line between.
        .mask(LinearGradient(stops: [.init(color: .clear, location: 0), .init(color: .black, location: 0.12), .init(color: .black, location: 1)],
                             startPoint: .top, endPoint: .bottom))
        .environment(\.colorScheme, .dark)
        // The map itself takes no touches, so the whole area is made the button's.
        .contentShape(.rect)
        .task {
            guard !arrived else { return }
            arrived = true
            try? await Task.sleep(for: .milliseconds(250))
            withAnimation(.smooth(duration: 2.8)) {
                position = .camera(MapCamera(centerCoordinate: Self.center(home: home, dots: dots), distance: Self.distance))
            }
        }
        .accessibilityElement(children: .ignore)
        .accessibilityLabel("全部足迹")
        .accessibilityAddTraits(.isButton)
    }

    static let glow = FootprintNight.glow
}

/// The counts as figures written on the night: no tiles around them.
struct FootprintFigures: View {
    let countries: Int
    let cities: Int
    let sights: Int
    let days: Int
    let since: Date?

    var body: some View {
        VStack(spacing: 12) {
            // A faint plate under the four, ruled between them: one group, set apart from the
            // sky, without a solid box competing with the globe.
            HStack(alignment: .center, spacing: 0) {
                figure(countries, "国家和地区")
                rule
                figure(cities, "城市")
                rule
                figure(sights, "景点")
                rule
                figure(days, "天")
            }
            .padding(.vertical, 16)
            .background {
                RoundedRectangle(cornerRadius: 22, style: .continuous)
                    .fill(LinearGradient(colors: [.white.opacity(0.08), .white.opacity(0.03)], startPoint: .top, endPoint: .bottom))
                    .overlay(RoundedRectangle(cornerRadius: 22, style: .continuous).strokeBorder(.white.opacity(0.12), lineWidth: 0.5))
            }
            if let since {
                Text("自 \(since.formatted(.dateTime.year().month(.wide).locale(appLocale))) 起记录")
                    .font(.footnote)
                    .foregroundStyle(FootprintNight.tertiary)
            }
        }
    }

    private var rule: some View {
        Rectangle().fill(.white.opacity(0.12)).frame(width: 0.5, height: 40)
    }

    private func figure(_ value: Int, _ label: LocalizedStringKey) -> some View {
        VStack(spacing: 2) {
            Text(value, format: .number)
                .font(.system(size: 34, weight: .light, design: .rounded))
                .foregroundStyle(.white)
                .monospacedDigit()
                .contentTransition(.numericText())
                .lineLimit(1)
                .minimumScaleFactor(0.6)
            Text(label)
                .font(.caption)
                .tracking(0.5)
                .foregroundStyle(FootprintNight.secondary)
                .lineLimit(1)
                .minimumScaleFactor(0.8)
        }
        .frame(maxWidth: .infinity)
        .accessibilityElement(children: .combine)
    }
}

/// A section's title on the night page: small, spaced, quiet; "全部" at its end.
struct NightHeader<Trailing: View>: View {
    let title: LocalizedStringKey
    @ViewBuilder var trailing: Trailing

    var body: some View {
        HStack(alignment: .firstTextBaseline) {
            Text(title)
                .font(.title3.weight(.semibold))
                .foregroundStyle(.white)
            Spacer()
            trailing
                .font(.subheadline)
                .foregroundStyle(FootprintNight.secondary)
        }
        .padding(.horizontal, 4)
    }
}

/// A country by its flag, standing on the night with nothing around it.
struct CountryFlag: View {
    let country: CountrySummary

    var body: some View {
        VStack(spacing: 8) {
            Text(country.flag)
                .font(.system(size: 50))
                .shadow(color: .black.opacity(0.5), radius: 8, y: 4)
                .frame(height: 56)
            VStack(spacing: 1) {
                Text(country.name)
                    .font(.footnote.weight(.semibold))
                    .foregroundStyle(.white)
                    .lineLimit(1)
                    .minimumScaleFactor(0.75)
                Text("\(country.days.count) 天")
                    .font(.caption2)
                    .foregroundStyle(FootprintNight.secondary)
            }
        }
        .frame(width: 76)
        .contentShape(.rect)
    }
}

/// One of the things you collect along the way: the passport, the visas, the places worth a
/// lifetime and the blind box. Four of them side by side, alike, each with its own small picture.
struct CollectionTile<Art: View>: View {
    let title: LocalizedStringKey
    let value: String
    let note: String
    @ViewBuilder var art: Art

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            art
                .frame(height: 64, alignment: .leading)
            Spacer(minLength: 12)
            Text(value)
                .font(.system(size: 24, weight: .light, design: .rounded))
                .foregroundStyle(.white)
                .monospacedDigit()
                .lineLimit(1)
                .minimumScaleFactor(0.7)
            Text(title)
                .font(.subheadline.weight(.semibold))
                .foregroundStyle(.white)
                .padding(.top, 2)
            Text(note)
                .font(.caption)
                .foregroundStyle(FootprintNight.secondary)
                .lineLimit(1)
                .minimumScaleFactor(0.85)
                .padding(.top, 1)
        }
        .padding(16)
        .frame(maxWidth: .infinity, minHeight: 186, alignment: .leading)
        .background {
            RoundedRectangle(cornerRadius: 26, style: .continuous)
                .fill(LinearGradient(colors: [.white.opacity(0.075), .white.opacity(0.035)], startPoint: .top, endPoint: .bottom))
                .overlay(RoundedRectangle(cornerRadius: 26, style: .continuous).strokeBorder(FootprintNight.hairline, lineWidth: 0.5))
        }
        .contentShape(.rect(cornerRadius: 26, style: .continuous))
    }
}

/// The four collections, two by two.
struct FootprintCollections: View {
    let book: StampBook
    private var documents = TravelDocuments.shared
    private var mustSee = MustSeeProgress.shared
    private var boxes = BlindBoxStore.shared
    private var summaries = PlaceSummaries.shared

    init(book: StampBook) { self.book = book }

    var body: some View {
        VStack(spacing: 12) {
            // The passport and its stamps keep a row of their own, then the visas beside it in
            // the same shape; the two kinds of travel ideas share the row below.
            NavigationLink(value: StampBookRoute()) { passportRow }
            NavigationLink(value: VisaWalletRoute()) { visaRow }
            NavigationLink(value: MustSeeRoute()) { mustSeeRow }
            NavigationLink(value: BlindBoxRoute()) { blindBoxRow }
        }
        .buttonStyle(PressableStyle())
        .task(id: summaries.revision) { await mustSee.update(from: summaries.stays) }
    }

    /// The two lists side by side, a hundred places each: China and the world are two goals,
    /// not one of two hundred.
    private var mustSeeRow: some View {
        VStack(alignment: .leading, spacing: 14) {
            HStack {
                Text("此生必去").font(.headline).foregroundStyle(.white)
                Spacer()
                Image(systemName: "chevron.forward").font(.footnote.weight(.semibold)).foregroundStyle(FootprintNight.tertiary)
            }
            HStack(spacing: 18) {
                mustSeeTally("中国", count: mustSee.count(.china))
                Rectangle().fill(FootprintNight.hairline).frame(width: 0.5)
                mustSeeTally("世界", count: mustSee.count(.world))
            }
            .fixedSize(horizontal: false, vertical: true)
        }
        .padding(16)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background { NightPlate() }
        .contentShape(.rect(cornerRadius: 26, style: .continuous))
    }

    private func mustSeeTally(_ title: LocalizedStringKey, count: Int) -> some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack(alignment: .firstTextBaseline, spacing: 4) {
                Text(title).font(.subheadline.weight(.semibold)).foregroundStyle(FootprintNight.secondary)
                Spacer(minLength: 4)
                Text(verbatim: "\(count)")
                    .font(.system(size: 26, weight: .light, design: .rounded))
                    .foregroundStyle(LinearGradient(colors: [Color(red: 1, green: 0.86, blue: 0.5), .orange], startPoint: .top, endPoint: .bottom))
                    .contentTransition(.numericText())
                Text(verbatim: "/ 100").font(.caption.weight(.medium)).foregroundStyle(FootprintNight.tertiary)
            }
            MiniLitGrid(lit: MustSeeView.filled(count, of: 100))
        }
        .frame(maxWidth: .infinity)
    }

    private var blindBoxRow: some View {
        WideRow {
            MysteryBox(open: 0, glow: 0.25)
                .scaleEffect(0.34)
                .frame(width: 70, height: 66)
        } text: {
            Text("旅行盲盒").font(.headline).foregroundStyle(.white)
            Text(boxes.waiting.isEmpty ? String(localized: "不知道去哪儿？这次让它替你选。", bundle: .appLanguage)
                                       : String(localized: "有 \(boxes.waiting.count) 张登机牌在等你", bundle: .appLanguage))
                .font(.footnote).foregroundStyle(FootprintNight.secondary)
        } trailing: {
            Image(systemName: "chevron.forward").font(.footnote.weight(.semibold)).foregroundStyle(FootprintNight.tertiary)
        }
    }

    /// The latest few stamps, fanned like the ones on the passport's page.
    private var latestStamps: [Stamp] {
        Array((book.passport.filter { $0.kind == .entry } + book.provinces + book.cities).sorted { $0.date > $1.date }.prefix(3))
    }

    private var passportRow: some View {
        WideRow {
            PassportCover(compact: true)
                .frame(width: 52, height: 72)
                .shadow(color: .black.opacity(0.5), radius: 6, y: 3)
        } text: {
            Text("护照与印章").font(.headline).foregroundStyle(.white)
            Text(passportNote).font(.footnote).foregroundStyle(FootprintNight.secondary)
        } trailing: {
            ZStack(alignment: .trailing) {
                ForEach(Array(latestStamps.enumerated()), id: \.element.id) { index, stamp in
                    StampWithRoute(stamp: stamp)
                        .frame(width: 38, height: 34)
                        .rotationEffect(.degrees(stamp.tilt))
                        .offset(x: -CGFloat(latestStamps.count - 1 - index) * 17)
                }
            }
            .frame(width: 72, height: 40, alignment: .trailing)
        }
    }

    private var visaRow: some View {
        WideRow {
            visaStack
        } text: {
            Text("签证夹").font(.headline).foregroundStyle(.white)
            Text(visaNote).font(.footnote).foregroundStyle(FootprintNight.secondary)
        } trailing: {
            if validVisas > 0 {
                VStack(alignment: .trailing, spacing: 0) {
                    Text("\(validVisas)")
                        .font(.system(size: 28, weight: .light, design: .rounded))
                        .foregroundStyle(.white)
                    Text("张有效").font(.caption2).foregroundStyle(FootprintNight.secondary)
                }
            }
        }
    }

    private var stampCount: Int {
        book.passport.filter { $0.kind == .entry }.count + book.provinces.count + book.cities.count + book.specials.count
    }

    private var passportNote: String {
        String(localized: "入境 \(book.passport.filter { $0.kind == .entry }.count) · 省份 \(book.provinces.count) · 城市 \(book.cities.count)", bundle: .appLanguage)
    }

    private var validVisas: Int { documents.all.filter { $0.kind != .passport && !$0.isExpired }.count }

    private var visaNote: String {
        let sorted = documents.sorted
        if sorted.isEmpty { return String(localized: "拍下签证页来添加", bundle: .appLanguage) }
        if let soon = sorted.first(where: \.isExpiringSoon) {
            let name = soon.kind == .passport ? String(localized: "护照", bundle: .appLanguage) : soon.countryName
            return String(localized: "\(name) \(soon.daysLeft()) 天后到期", bundle: .appLanguage)
        }
        return String(localized: "都在有效期内", bundle: .appLanguage)
    }

    private var litCount: Int { mustSee.count(.china) + mustSee.count(.world) }

    private var boxNote: String {
        boxes.waiting.isEmpty ? String(localized: "抽一个目的地", bundle: .appLanguage)
            : String(localized: "待出发的登机牌", bundle: .appLanguage)
    }

    private var visaStack: some View {
        let sorted = documents.sorted
        return ZStack(alignment: .bottomLeading) {
            if sorted.isEmpty {
                RoundedRectangle(cornerRadius: 8, style: .continuous)
                    .strokeBorder(FootprintNight.tertiary, style: StrokeStyle(lineWidth: 1, dash: [3, 3]))
                    .frame(width: 70, height: 46)
                    .overlay(Image(systemName: "plus").font(.headline).foregroundStyle(FootprintNight.secondary))
            } else {
                ForEach(Array(sorted.prefix(3).enumerated().reversed()), id: \.element.id) { index, document in
                    VisaCard(document: document)
                        .frame(width: 62)
                        .shadow(color: .black.opacity(0.4), radius: 4, y: 2)
                        .rotationEffect(.degrees(Double(index) * -7), anchor: .bottomLeading)
                        .offset(x: CGFloat(index) * 4, y: CGFloat(index) * -4)
                }
            }
        }
        .frame(width: 76, height: 58, alignment: .bottomLeading)
    }
}

/// The faint plate every group on the night page sits on.
struct NightPlate: View {
    var body: some View {
        RoundedRectangle(cornerRadius: 26, style: .continuous)
            .fill(LinearGradient(colors: [.white.opacity(0.075), .white.opacity(0.035)], startPoint: .top, endPoint: .bottom))
            .overlay(RoundedRectangle(cornerRadius: 26, style: .continuous).strokeBorder(FootprintNight.hairline, lineWidth: 0.5))
    }
}

/// A full-width row in the same material as the tiles: a picture, two lines, something on the right.
private struct WideRow<Art: View, Words: View, Trailing: View>: View {
    @ViewBuilder var art: Art
    @ViewBuilder var text: Words
    @ViewBuilder var trailing: Trailing

    var body: some View {
        HStack(spacing: 14) {
            // One width for every row's picture, so the titles line up.
            art.frame(width: 76, alignment: .center)
            VStack(alignment: .leading, spacing: 3) { text }
                .lineLimit(1)
                .minimumScaleFactor(0.85)
            Spacer(minLength: 4)
            trailing
        }
        .padding(.horizontal, 16)
        .padding(.vertical, 14)
        .frame(maxWidth: .infinity, minHeight: 100, alignment: .leading)
        .background {
            RoundedRectangle(cornerRadius: 26, style: .continuous)
                .fill(LinearGradient(colors: [.white.opacity(0.075), .white.opacity(0.035)], startPoint: .top, endPoint: .bottom))
                .overlay(RoundedRectangle(cornerRadius: 26, style: .continuous).strokeBorder(FootprintNight.hairline, lineWidth: 0.5))
        }
        .contentShape(.rect(cornerRadius: 26, style: .continuous))
    }
}

/// How many of the two hundred places are lit, as a thin gold ring.
private struct MustSeeRing: View {
    let fraction: Double

    var body: some View {
        ZStack {
            Circle().stroke(.white.opacity(0.1), lineWidth: 5)
            Circle()
                .trim(from: 0, to: max(0.015, min(1, fraction)))
                .stroke(AngularGradient(colors: [Color(red: 1, green: 0.86, blue: 0.5), .orange, Color(red: 1, green: 0.86, blue: 0.5)], center: .center),
                        style: StrokeStyle(lineWidth: 5, lineCap: .round))
                .rotationEffect(.degrees(-90))
            Image(systemName: "star.fill")
                .font(.system(size: 18))
                .foregroundStyle(LinearGradient(colors: [Color(red: 1, green: 0.86, blue: 0.5), .orange], startPoint: .top, endPoint: .bottom))
        }
        .frame(width: 58, height: 58)
    }
}

/// A city as a small night map of it, its name across the bottom.
struct CityCard: View {
    let city: CitySummary
    @State private var snapshot: UIImage?

    private static let cache = NSCache<NSString, UIImage>()
    private static let size = CGSize(width: 220, height: 150)

    var body: some View {
        ZStack(alignment: .bottomLeading) {
            Color(red: 0.05, green: 0.08, blue: 0.14)
            if let snapshot {
                Image(uiImage: snapshot).resizable().scaledToFill()
                    // The city from above, cooled to the page's night.
                    .overlay { Self.night.opacity(0.45).blendMode(.multiply) }
                    .transition(.opacity)
            }
            LinearGradient(colors: [.black.opacity(0.1), .black.opacity(0.75)], startPoint: .center, endPoint: .bottom)
            VStack(alignment: .leading, spacing: 3) {
                Text(city.name)
                    .font(.title3.weight(.bold))
                    .foregroundStyle(.white)
                    .lineLimit(1)
                    .minimumScaleFactor(0.7)
                Text(verbatim: "\(String.flag(for: city.countryCode))  \(days)")
                    .font(.caption.weight(.medium))
                    .foregroundStyle(.white.opacity(0.75))
            }
            .padding(.horizontal, 14)
            // Above the map's own attribution in the corner.
            .padding(.bottom, 26)
        }
        .frame(width: Self.size.width, height: Self.size.height)
        .clipShape(.rect(cornerRadius: 22, style: .continuous))
        .overlay {
            Circle()
                .fill(FootprintNight.glow)
                .frame(width: 7, height: 7)
                .shadow(color: FootprintNight.glow, radius: 6)
                .offset(y: -22)
        }
        .contentShape(.rect(cornerRadius: 22, style: .continuous))
        .task(id: city.key) {
            if let image = await Self.snapshot(of: city) {
                withAnimation(.easeOut(duration: 0.3)) { snapshot = image }
            }
        }
    }

    private static let night = Color(red: 0.04, green: 0.08, blue: 0.20)

    private var days: String { String(localized: "\(city.days) 天", bundle: .appLanguage) }

    private static func snapshot(of city: CitySummary) async -> UIImage? {
        let key = city.key as NSString
        if let cached = cache.object(forKey: key) { return cached }
        let options = MKMapSnapshotter.Options()
        options.region = MKCoordinateRegion(center: city.center.onMap, latitudinalMeters: 26_000, longitudinalMeters: 38_000)
        options.size = size
        // Satellite, so no road numbers or place names crowd the city's own name.
        options.preferredConfiguration = MKImageryMapConfiguration(elevationStyle: .flat)
        guard let image = try? await MKMapSnapshotter(options: options).start().image else { return nil }
        cache.setObject(image, forKey: key)
        return image
    }
}

/// A sight as a picture, its name over it.
struct SightPoster: View {
    let stay: Stay

    var body: some View {
        let must = MustSee.place(for: stay)
        ZStack(alignment: .bottomLeading) {
            // Without a photo it's a map, drawn at night so the name over it reads.
            PlacePicture(stay: stay, coverID: must?.id)
                .environment(\.colorScheme, .dark)
            LinearGradient(colors: [.clear, .black.opacity(0.35), .black.opacity(0.8)], startPoint: .top, endPoint: .bottom)
            VStack(alignment: .leading, spacing: 2) {
                Text(stay.displayName)
                    .font(.subheadline.weight(.semibold))
                    .foregroundStyle(.white)
                    .lineLimit(2)
                Text([stay.city, stay.arrival.formatted(.dateTime.year().month().locale(appLocale))].compactMap { $0 }.joined(separator: " · "))
                    .font(.caption)
                    .foregroundStyle(.white.opacity(0.75))
                    .lineLimit(1)
            }
            .padding(.horizontal, 12)
            .padding(.top, 12)
            .padding(.bottom, 26)
        }
        .overlay(alignment: .topLeading) {
            if must != nil { MustSeeTag(compact: true).padding(10) }
        }
        .frame(width: 150, height: 200)
        .clipShape(.rect(cornerRadius: 22, style: .continuous))
        .contentShape(.rect(cornerRadius: 22, style: .continuous))
    }
}

/// Opens a city's visits.
struct CityRoute: Hashable {
    let key: String
    let name: String
}

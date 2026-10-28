import SwiftUI
import SwiftData
import CoreLocation
import MapKit
import Photos

/// The year in footprints as a story: full-screen pages on moving colour, numbers that count
/// up, the year's routes drawn as art, ending with a poster to share.
struct YearReportView: View {
    @Environment(\.dismiss) private var dismiss
    @Environment(\.modelContext) private var context
    @Environment(ActivityProvider.self) private var activityProvider
    @Query(sort: \Stay.arrival) private var stays: [Stay]
    @Query private var trips: [Trip]

    @State private var year = Calendar.current.component(.year, from: Date())
    @State private var data: StoryData?
    @State private var page = 0
    @State private var shareImage: Image?

    struct StoryData {
        var report: YearReport
        var routes: [RouteImage.Line]
        var longestDayRoutes: [RouteImage.Line]
        var photos: [TripPhoto]
        var lightUp: LightUpInsights
        /// The year's places on a dark map, drawn once the rest has loaded.
        var cover: UIImage?
        var placesMap: MapBackdrop?
        var placesPins: [String] = []
        /// Countries too far from the rest to fit on the map.
        var placesElsewhere: [String] = []
        var dayMap: MapBackdrop?
        /// Photos from the library this year: the ones to show, and how many there were.
        var libraryPhotos: [PHAsset] = []
        var libraryCount = 0
        var favoritePhoto: PHAsset?
    }

    var body: some View {
        ZStack {
            Color.black.ignoresSafeArea()
            if let data {
                if data.report.isEmpty {
                    emptyYear
                } else {
                    let pages = storyPages(data)
                    TabView(selection: $page) {
                        ForEach(pages.indices, id: \.self) { index in
                            pages[index].page(isActive: page == index).tag(index)
                        }
                    }
                    .tabViewStyle(.page(indexDisplayMode: .never))
                    .ignoresSafeArea()
                    .overlay(alignment: .top) { storyBar(count: pages.count) }
                }
            } else {
                ProgressView().tint(.white)
            }
        }
        .preferredColorScheme(.dark)
        .task(id: year) { await load() }
        .sensoryFeedback(.selection, trigger: page)
    }

    // MARK: Chrome

    private func storyBar(count: Int) -> some View {
        VStack(spacing: 10) {
            HStack(spacing: 4) {
                ForEach(0..<count, id: \.self) { index in
                    Capsule()
                        .fill(.white.opacity(index <= page ? 0.95 : 0.25))
                        .frame(height: 3)
                        .animation(.easeOut(duration: 0.25), value: page)
                }
            }
            HStack {
                if YearReport.years(in: stays).count > 1 {
                    Menu {
                        Picker("年份", selection: $year) {
                            ForEach(YearReport.years(in: stays), id: \.self) { Text(verbatim: String($0)).tag($0) }
                        }
                    } label: {
                        Label(String(year), systemImage: "chevron.down")
                            .font(.subheadline.weight(.semibold))
                            .padding(.horizontal, 12).padding(.vertical, 6)
                            .background(.white.opacity(0.15), in: .capsule)
                    }
                    .tint(.white)
                }
                Spacer()
                Button { dismiss() } label: {
                    Image(systemName: "xmark")
                        .font(.subheadline.weight(.bold))
                        .frame(width: 34, height: 34)
                        .background(.white.opacity(0.15), in: .circle)
                }
                .tint(.white)
                .accessibilityLabel("关闭")
            }
        }
        .padding(.horizontal, 16)
        .padding(.top, 8)
    }

    private var emptyYear: some View {
        VStack(spacing: 14) {
            Text(verbatim: String(year)).font(.system(size: 72, weight: .heavy, design: .rounded)).foregroundStyle(.white.opacity(0.3))
            Text("\(String(year)) 年还没有记录").font(.title3.bold())
            Text("记录一段时间之后，这里会整理出你的年度足迹。").foregroundStyle(.secondary)
        }
        .multilineTextAlignment(.center)
        .padding(32)
        .overlay(alignment: .topTrailing) {
            Button("关闭", systemImage: "xmark") { dismiss() }.labelStyle(.iconOnly).padding()
        }
    }

    // MARK: Loading

    private func load() async {
        data = nil
        page = 0
        let calendar = Calendar.current
        guard let start = calendar.date(from: DateComponents(year: year, month: 1, day: 1)),
              let end = calendar.date(byAdding: .year, value: 1, to: start) else { return }
        let chunks = (try? context.fetch(FetchDescriptor<TrackChunk>(predicate: #Predicate { $0.startDate >= start && $0.startDate < end },
                                                                      sortBy: [SortDescriptor(\.startDate)]))) ?? []
        let movements = chunks.map { YearReport.Movement(start: $0.startDate, distance: $0.distance, mode: $0.mode) }
        let days = min(calendar.dateComponents([.day], from: start, to: min(end, Date())).day ?? 0, 366) + 1
        let steps = await activityProvider.activity(from: start, days: days)
        let report = YearReport.make(year: year, stays: stays, movements: movements, steps: steps, trips: trips)

        let ground = chunks.filter { $0.mode != .flying }
        let routes = Self.homeArea(ground).map { RouteImage.Line(coordinates: $0.points.simplified(tolerance: 40).map(\.coordinate), color: $0.mode.color) }
        var longest: [RouteImage.Line] = []
        if let day = report.longestDay?.date {
            longest = ground.filter { calendar.isDate($0.startDate, inSameDayAs: day) }
                .map { RouteImage.Line(coordinates: $0.points.simplified(tolerance: 15).map(\.coordinate), color: $0.mode.color) }
        }
        let photos = ((try? context.fetch(FetchDescriptor<TripPhoto>(predicate: #Predicate { $0.takenAt >= start && $0.takenAt < end },
                                                                     sortBy: [SortDescriptor(\.takenAt)]))) ?? [])
        let lightUp = LightUpInsights(stays: stays.filter { $0.arrival >= start && $0.arrival < end })
        let story = StoryData(report: report, routes: routes, longestDayRoutes: longest, photos: photos, lightUp: lightUp)
        withAnimation(.smooth) { data = story }
        shareImage = render(story)

        let yearStays = stays.filter { $0.arrival >= start && $0.arrival < end }
        let cities = CityGlow.glows(for: yearStays)
        let size = UIScreen.main.bounds.size
        if let cover = await YearCover.render(cities: cities, routes: routes, size: size), data?.report.year == year {
            withAnimation(.easeOut(duration: 0.8)) { data?.cover = cover }
            if let data { shareImage = render(data) }
        }
        await loadPictures(yearStays: yearStays, interval: DateInterval(start: start, end: min(end, Date())),
                           longest: longest, report: report, size: size)
    }

    /// The pictures behind the later pages: countries pinned on a map, the longest day's
    /// route on its streets, and the year's photos from the library.
    private func loadPictures(yearStays: [Stay], interval: DateInterval, longest: [RouteImage.Line], report: YearReport, size: CGSize) async {
        let year = self.year
        // A pin per country, where most of its visits were.
        let byCountry = Dictionary(grouping: yearStays.filter { $0.countryCode != nil }, by: { $0.countryCode! })
        let pins = byCountry.map { code, stays -> (String, CLLocationCoordinate2D) in
            let lat = stays.map(\.latitude).reduce(0, +) / Double(stays.count)
            let lon = stays.map(\.longitude).reduce(0, +) / Double(stays.count)
            return (code, CLLocationCoordinate2D(latitude: lat, longitude: lon))
        }
        .sorted { (byCountry[$0.0]?.count ?? 0) > (byCountry[$1.0]?.count ?? 0) }
        // The map shows the part of the world with the most of them; the rest are named below it.
        func place(_ c: CLLocationCoordinate2D) -> CLLocation { CLLocation(latitude: c.latitude, longitude: c.longitude) }
        let anchor = pins.max { a, b in
            func weight(_ p: (String, CLLocationCoordinate2D)) -> Int {
                pins.filter { place($0.1).distance(from: place(p.1)) < 3_500_000 }.reduce(0) { $0 + (byCountry[$1.0]?.count ?? 0) }
            }
            return weight(a) < weight(b)
        }
        let framed = anchor.map { a in pins.filter { place($0.1).distance(from: place(a.1)) < 3_500_000 } } ?? []
        if let region = MapBackdrop.region(around: framed.map(\.1), size: size, minimumSpan: 8, lift: 0.12),
           let map = await MapBackdrop.render(region: region, size: size, pins: framed.map(\.1)), data?.report.year == year {
            data?.placesMap = map
            data?.placesPins = framed.map(\.0)
            data?.placesElsewhere = pins.map(\.0).filter { !data!.placesPins.contains($0) }
        }
        let dayLines = longest.map(\.coordinates).filter { $0.count > 1 }
        if let region = MapBackdrop.region(around: dayLines.flatMap { $0 }, size: size, minimumSpan: 0.02),
           let map = await MapBackdrop.render(region: region, size: size, lines: dayLines), data?.report.year == year {
            data?.dayMap = map
        }
        guard DayPhotos.canRead else { return }
        let all = DayPhotos.assets(in: interval)
        let favorites = all.filter(\.isFavorite)
        let pool = favorites.count >= 9 ? favorites : all
        let step = max(1, pool.count / 9)
        let picked = stride(from: 0, to: pool.count, by: step).prefix(9).map { pool[$0] }
        var favoritePhoto: PHAsset?
        if let stay = report.favoritePlace?.stay {
            let near = all.filter { ($0.location?.distance(from: stay.location) ?? .infinity) < 500 }
            favoritePhoto = near.isEmpty ? nil : near[near.count / 2]
        }
        guard data?.report.year == year else { return }
        data?.libraryPhotos = picked
        data?.libraryCount = all.count
        data?.favoritePhoto = favoritePhoto
    }

    /// The routes around where most of the year was spent, so the cover shows a web of
    /// streets rather than a few specks spread over a continent.
    private static func homeArea(_ chunks: [TrackChunk]) -> [TrackChunk] {
        guard chunks.count > 2 else { return chunks }
        let lats = chunks.map { ($0.minLatitude + $0.maxLatitude) / 2 }.sorted()
        let lons = chunks.map { ($0.minLongitude + $0.maxLongitude) / 2 }.sorted()
        let center = CLLocation(latitude: lats[lats.count / 2], longitude: lons[lons.count / 2])
        let near = chunks.filter {
            CLLocation(latitude: ($0.minLatitude + $0.maxLatitude) / 2, longitude: ($0.minLongitude + $0.maxLongitude) / 2)
                .distance(from: center) < 40_000
        }
        return near.isEmpty ? chunks : near
    }

    @MainActor
    private func render(_ data: StoryData) -> Image? {
        let renderer = ImageRenderer(content: YearPoster(data: data).frame(width: 390, height: 640).environment(\.locale, appLocale))
        renderer.scale = 3
        return renderer.uiImage.map { Image(uiImage: $0) }
    }

    // MARK: Pages

    private struct StoryPage {
        let page: (Bool) -> AnyView
        func page(isActive: Bool) -> AnyView { page(isActive) }
    }

    private func storyPages(_ data: StoryData) -> [StoryPage] {
        let r = data.report
        var pages: [StoryPage] = [
            StoryPage { AnyView(CoverPage(data: data, isActive: $0)) },
            StoryPage { AnyView(StoryDistancePage(report: r, isActive: $0)) },
        ]
        if r.steps > 0 { pages.append(StoryPage { AnyView(StoryStepsPage(report: r, isActive: $0)) }) }
        if !r.countries.isEmpty {
            pages.append(StoryPage { AnyView(StoryPlacesPage(report: r, backdrop: data.placesMap, pinCodes: data.placesPins,
                                                             elsewhere: data.placesElsewhere, isActive: $0)) })
        }
        if StoryPassportPage.hasStamps(year: r.year) {
            pages.append(StoryPage { AnyView(StoryPassportPage(year: r.year, isActive: $0)) })
        }
        if r.longestDay != nil, !data.longestDayRoutes.isEmpty {
            pages.append(StoryPage { AnyView(StoryLongestDayPage(report: r, backdrop: data.dayMap, isActive: $0)) })
        }
        if r.favoritePlace != nil || r.farthestPlace != nil {
            pages.append(StoryPage { AnyView(StoryFavoritePage(report: r, photo: data.favoritePhoto, isActive: $0)) })
        }
        if data.libraryPhotos.count >= 3 {
            pages.append(StoryPage { AnyView(StoryPhotosPage(assets: data.libraryPhotos, total: data.libraryCount, isActive: $0)) })
        }
        let image = shareImage
        pages.append(StoryPage { _ in AnyView(SharePage(data: data, image: image)) })
        return pages
    }
}

// MARK: - Building blocks

/// Slowly moving colour behind each page.
private struct StoryBackground: View {
    let colors: [Color]

    var body: some View {
        TimelineView(.animation(minimumInterval: 1 / 30)) { context in
            let t = context.date.timeIntervalSinceReferenceDate
            let wobble = { (phase: Double) -> Float in Float(0.5 + 0.18 * sin(t * 0.35 + phase)) }
            MeshGradient(width: 3, height: 3, points: [
                [0, 0], [wobble(0), 0], [1, 0],
                [0, wobble(1.3)], [wobble(2.1), wobble(0.7)], [1, wobble(2.7)],
                [0, 1], [wobble(3.4), 1], [1, 1],
            ], colors: colors)
        }
        .ignoresSafeArea()
    }
}

/// Counts from zero to `value` when the page becomes active.
private struct CountUp: View, Animatable {
    var value: Double
    let format: (Double) -> String

    var animatableData: Double {
        get { value }
        set { value = newValue }
    }

    var body: some View { Text(format(value)) }
}

private struct Reveal: ViewModifier {
    let isActive: Bool
    let delay: Double

    func body(content: Content) -> some View {
        content
            .opacity(isActive ? 1 : 0)
            .offset(y: isActive ? 0 : 24)
            .blur(radius: isActive ? 0 : 6)
            .animation(.spring(response: 0.7, dampingFraction: 0.85).delay(isActive ? delay : 0), value: isActive)
    }
}

private extension View {
    func reveal(_ isActive: Bool, after delay: Double = 0) -> some View { modifier(Reveal(isActive: isActive, delay: delay)) }
}

/// Routes as glowing lines on their own, for the cover and the longest day.
private struct RouteArt: View {
    let lines: [RouteImage.Line]
    var color: Color = .white
    var lineWidth: CGFloat = 1.6
    var progress: CGFloat = 1

    var body: some View {
        Canvas { context, size in
            let all = lines.flatMap(\.coordinates)
            guard all.count > 1 else { return }
            let origin = all[0]
            let k = cos(origin.latitude * .pi / 180)
            func local(_ c: CLLocationCoordinate2D) -> CGPoint {
                CGPoint(x: (c.longitude - origin.longitude) * k, y: -(c.latitude - origin.latitude))
            }
            let points = all.map(local)
            let minX = points.map(\.x).min()!, maxX = points.map(\.x).max()!
            let minY = points.map(\.y).min()!, maxY = points.map(\.y).max()!
            let inset: CGFloat = 24
            let scale = min((size.width - inset * 2) / max(maxX - minX, 1e-6), (size.height - inset * 2) / max(maxY - minY, 1e-6))
            let offset = CGPoint(x: (size.width - (maxX - minX) * scale) / 2, y: (size.height - (maxY - minY) * scale) / 2)
            var path = Path()
            for line in lines where line.coordinates.count > 1 {
                path.addLines(line.coordinates.map {
                    let p = local($0)
                    return CGPoint(x: offset.x + (p.x - minX) * scale, y: offset.y + (p.y - minY) * scale)
                })
            }
            let trimmed = path.trimmedPath(from: 0, to: progress)
            var glow = context
            glow.addFilter(.blur(radius: 6))
            glow.stroke(trimmed, with: .color(color.opacity(0.6)), style: StrokeStyle(lineWidth: lineWidth * 3, lineCap: .round, lineJoin: .round))
            context.stroke(trimmed, with: .color(color), style: StrokeStyle(lineWidth: lineWidth, lineCap: .round, lineJoin: .round))
        }
    }
}

private struct PageLayout<Content: View>: View {
    let colors: [Color]
    @ViewBuilder let content: Content

    var body: some View {
        ZStack {
            StoryBackground(colors: colors)
            VStack(alignment: .leading, spacing: 14) {
                Spacer(minLength: 90)
                content
                Spacer(minLength: 60)
            }
            .foregroundStyle(.white)
            .padding(.horizontal, 28)
            .frame(maxWidth: .infinity, alignment: .leading)
        }
    }
}

private enum Palette {
    static let night: [Color] = [.init(red: 0.05, green: 0.06, blue: 0.2), .init(red: 0.2, green: 0.1, blue: 0.4), .init(red: 0.05, green: 0.1, blue: 0.3),
                                 .init(red: 0.35, green: 0.12, blue: 0.5), .init(red: 0.95, green: 0.45, blue: 0.3), .init(red: 0.15, green: 0.1, blue: 0.4),
                                 .init(red: 0.05, green: 0.05, blue: 0.15), .init(red: 0.3, green: 0.1, blue: 0.35), .init(red: 0.08, green: 0.05, blue: 0.2)]
    static let ocean: [Color] = [.init(red: 0.0, green: 0.15, blue: 0.35), .init(red: 0.0, green: 0.35, blue: 0.6), .init(red: 0.0, green: 0.2, blue: 0.4),
                                 .init(red: 0.0, green: 0.45, blue: 0.7), .init(red: 0.2, green: 0.8, blue: 0.9), .init(red: 0.0, green: 0.3, blue: 0.55),
                                 .init(red: 0.0, green: 0.1, blue: 0.25), .init(red: 0.0, green: 0.25, blue: 0.45), .init(red: 0.0, green: 0.12, blue: 0.3)]
    static let forest: [Color] = [.init(red: 0.02, green: 0.18, blue: 0.12), .init(red: 0.05, green: 0.35, blue: 0.2), .init(red: 0.0, green: 0.2, blue: 0.15),
                                  .init(red: 0.1, green: 0.5, blue: 0.3), .init(red: 0.6, green: 0.9, blue: 0.4), .init(red: 0.05, green: 0.35, blue: 0.25),
                                  .init(red: 0.0, green: 0.12, blue: 0.08), .init(red: 0.05, green: 0.3, blue: 0.2), .init(red: 0.02, green: 0.15, blue: 0.1)]
    static let sunset: [Color] = [.init(red: 0.35, green: 0.05, blue: 0.15), .init(red: 0.7, green: 0.15, blue: 0.25), .init(red: 0.4, green: 0.08, blue: 0.2),
                                  .init(red: 0.9, green: 0.35, blue: 0.25), .init(red: 1.0, green: 0.75, blue: 0.35), .init(red: 0.8, green: 0.25, blue: 0.3),
                                  .init(red: 0.25, green: 0.04, blue: 0.12), .init(red: 0.6, green: 0.12, blue: 0.22), .init(red: 0.3, green: 0.05, blue: 0.15)]
    static let violet: [Color] = [.init(red: 0.15, green: 0.05, blue: 0.3), .init(red: 0.35, green: 0.1, blue: 0.6), .init(red: 0.2, green: 0.05, blue: 0.4),
                                  .init(red: 0.5, green: 0.2, blue: 0.8), .init(red: 0.9, green: 0.5, blue: 0.95), .init(red: 0.4, green: 0.15, blue: 0.7),
                                  .init(red: 0.1, green: 0.03, blue: 0.2), .init(red: 0.3, green: 0.08, blue: 0.5), .init(red: 0.15, green: 0.05, blue: 0.3)]
}

// MARK: - Pages

private struct CoverPage: View {
    let data: YearReportView.StoryData
    let isActive: Bool
    @State private var drawn: CGFloat = 0

    var body: some View {
        ZStack {
            StoryBackground(colors: Palette.night)
            if let cover = data.cover {
                // The year's map, drifting slowly closer, darkened where the words sit.
                Image(uiImage: cover)
                    .resizable()
                    .scaledToFill()
                    .scaleEffect(isActive ? 1.08 : 1.0)
                    .animation(.easeInOut(duration: 14), value: isActive)
                    .ignoresSafeArea()
                    .transition(.opacity)
                LinearGradient(stops: [.init(color: .black.opacity(0.35), location: 0), .init(color: .clear, location: 0.25),
                                       .init(color: .black.opacity(0.2), location: 0.5), .init(color: .black.opacity(0.85), location: 0.85)],
                               startPoint: .top, endPoint: .bottom)
                    .ignoresSafeArea()
            } else if data.routes.flatMap(\.coordinates).count > 200 {
                RouteArt(lines: data.routes, color: .white.opacity(0.85), lineWidth: 1.2, progress: drawn)
                    .padding(.top, 110)
                    .padding(.bottom, 370)
                    .opacity(0.9)
            }
            VStack(alignment: .leading, spacing: 6) {
                Spacer()
                Text(verbatim: String(data.report.year))
                    .font(.system(size: 96, weight: .black, design: .rounded))
                    .reveal(isActive, after: 0.2)
                Text("我的年度足迹").font(.system(size: 30, weight: .bold)).reveal(isActive, after: 0.35)
                Text("这一年去了 \(data.report.cities.count) 座城市，记录了 \(data.report.daysRecorded) 天。")
                    .font(.title3).foregroundStyle(.white.opacity(0.75)).reveal(isActive, after: 0.5)
                Label("向左滑动", systemImage: "hand.draw.fill")
                    .font(.footnote.weight(.semibold)).foregroundStyle(.white.opacity(0.6))
                    .padding(.top, 18).reveal(isActive, after: 0.9)
                    .padding(.bottom, 70)
            }
            .foregroundStyle(.white)
            .padding(.horizontal, 28)
            .frame(maxWidth: .infinity, alignment: .leading)
        }
        .onChange(of: isActive, initial: true) { _, active in
            drawn = 0
            if active { withAnimation(.easeInOut(duration: 2.4)) { drawn = 1 } }
        }
    }
}

private struct SharePage: View {
    let data: YearReportView.StoryData
    let image: Image?

    var body: some View {
        ZStack {
            StoryBackground(colors: Palette.night)
            if let cover = data.cover {
                Image(uiImage: cover).resizable().scaledToFill().blur(radius: 24).opacity(0.6).ignoresSafeArea()
            }
            VStack(spacing: 22) {
                Spacer(minLength: 80)
                // Laid out at the size it is shared at, shown smaller.
                YearPoster(data: data)
                    .frame(width: 390, height: 640)
                    .clipShape(.rect(cornerRadius: 38, style: .continuous))
                    .scaleEffect(300 / 390)
                    .frame(width: 300, height: 492)
                    .shadow(color: .black.opacity(0.4), radius: 30, y: 14)
                if let image {
                    ShareLink(item: image, preview: SharePreview(String(localized: "我的年度足迹", bundle: .appLanguage), image: image)) {
                        Label("分享年度足迹", systemImage: "square.and.arrow.up")
                            .font(.headline)
                            .foregroundStyle(.black)
                            .frame(maxWidth: .infinity)
                            .frame(height: 52)
                            .background(.white, in: .capsule)
                    }
                    .padding(.horizontal, 40)
                }
                Spacer(minLength: 40)
            }
        }
    }
}

/// The picture that gets shared: the year's routes as art behind the numbers.
private struct YearPoster: View {
    let data: YearReportView.StoryData

    var body: some View {
        let r = data.report
        ZStack(alignment: .topLeading) {
            if let cover = data.cover {
                // Filling the card without setting its size.
                Color.clear.overlay { Image(uiImage: cover).resizable().scaledToFill() }.clipped()
                LinearGradient(stops: [.init(color: .black.opacity(0.55), location: 0), .init(color: .clear, location: 0.3),
                                       .init(color: .black.opacity(0.85), location: 0.75)], startPoint: .top, endPoint: .bottom)
            } else {
                LinearGradient(colors: [Color(red: 0.08, green: 0.07, blue: 0.25), Color(red: 0.35, green: 0.12, blue: 0.45), Color(red: 0.95, green: 0.45, blue: 0.3)],
                               startPoint: .top, endPoint: .bottom)
                RouteArt(lines: data.routes, color: .white.opacity(0.7), lineWidth: 1.1)
                    .padding(.top, 150).padding(.bottom, 170)
            }
            VStack(alignment: .leading, spacing: 0) {
                HStack(alignment: .firstTextBaseline) {
                    Text(verbatim: String(r.year)).font(.system(size: 52, weight: .black, design: .rounded))
                    Spacer()
                    Text(AppInfo.name).font(.subheadline.weight(.bold)).opacity(0.8)
                }
                Text("年度足迹").font(.title3.weight(.bold)).opacity(0.85)
                Spacer()
                Grid(alignment: .leading, horizontalSpacing: 20, verticalSpacing: 12) {
                    GridRow {
                        stat(Format.distance(r.distance), String(localized: "移动距离", bundle: .appLanguage))
                        stat("\(r.daysRecorded)", String(localized: "记录天数", bundle: .appLanguage))
                    }
                    GridRow {
                        stat("\(r.countries.count)", String(localized: "国家和地区", bundle: .appLanguage))
                        stat("\(r.cities.count)", String(localized: "城市", bundle: .appLanguage))
                    }
                    if StoryPassportPage.hasStamps(year: r.year) {
                        GridRow {
                            stat("\(r.provinces.count)", String(localized: "省份", bundle: .appLanguage))
                            stat("\(YearStamps.count(year: r.year))", String(localized: "枚印章", bundle: .appLanguage))
                        }
                    }
                }
                if !r.countries.isEmpty {
                    Text(r.countries.prefix(10).map { String.flag(for: $0) }.joined(separator: " "))
                        .font(.title2).padding(.top, 12)
                }
            }
            .foregroundStyle(.white)
            .padding(24)
        }
    }

    private func stat(_ value: String, _ label: String) -> some View {
        VStack(alignment: .leading, spacing: 1) {
            Text(value).font(.system(.title2, design: .rounded, weight: .heavy)).monospacedDigit()
            Text(label).font(.caption.weight(.semibold)).opacity(0.75)
        }
    }
}

/// The year-report cover: a dark map of the year's places, each city a warm light, the
/// recorded routes as fine bright lines.
enum YearCover {
    @MainActor
    static func render(cities: [CityGlow], routes: [RouteImage.Line], size: CGSize) async -> UIImage? {
        guard !cities.isEmpty, size.width > 0 else { return nil }
        // Frame the part of the world where most of the year was spent: the cities within
        // reach of the one with the most days, weighed by their days. A trip to the other
        // side of the world doesn't pull the map out to an empty ocean.
        let best = cities.max { a, b in
            func weight(_ c: CityGlow) -> Int {
                let here = CLLocation(latitude: c.center.latitude, longitude: c.center.longitude)
                return cities.filter { CLLocation(latitude: $0.center.latitude, longitude: $0.center.longitude).distance(from: here) < 2_500_000 }
                    .reduce(0) { $0 + $1.days }
            }
            return weight(a) < weight(b)
        }!
        let anchor = CLLocation(latitude: best.center.latitude, longitude: best.center.longitude)
        let framed = cities.filter { CLLocation(latitude: $0.center.latitude, longitude: $0.center.longitude).distance(from: anchor) < 2_500_000 }
        let lats = framed.map(\.center.latitude), lons = framed.map(\.center.longitude)
        let minLat = lats.min()!, maxLat = lats.max()!, minLon = lons.min()!, maxLon = lons.max()!
        // Room around the cities, the lower part kept for the words.
        let latSpan = max((maxLat - minLat) * 1.6, 0.6)
        let lonSpan = max((maxLon - minLon) * 1.5, latSpan * size.width / size.height)
        let center = CLLocationCoordinate2D(latitude: (minLat + maxLat) / 2 - latSpan * 0.18, longitude: (minLon + maxLon) / 2)

        let options = MKMapSnapshotter.Options()
        options.region = MKCoordinateRegion(center: center, span: MKCoordinateSpan(latitudeDelta: min(latSpan * 1.5, 170), longitudeDelta: min(lonSpan, 360)))
        options.size = size
        options.traitCollection = UITraitCollection(userInterfaceStyle: .dark)
        let configuration = MKStandardMapConfiguration(elevationStyle: .flat, emphasisStyle: .muted)
        configuration.pointOfInterestFilter = .excludingAll
        options.preferredConfiguration = configuration
        guard let snapshot = try? await MKMapSnapshotter(options: options).start() else { return nil }

        let maxDays = Double(cities.map(\.days).max() ?? 1)
        return UIGraphicsImageRenderer(size: size).image { renderer in
            snapshot.image.draw(at: .zero)
            let context = renderer.cgContext

            // Routes: a soft glow under a fine line.
            for line in routes where line.coordinates.count > 1 {
                let path = UIBezierPath()
                for (index, coordinate) in line.coordinates.enumerated() {
                    let point = snapshot.point(for: coordinate.onMap)
                    index == 0 ? path.move(to: point) : path.addLine(to: point)
                }
                path.lineCapStyle = .round
                path.lineJoinStyle = .round
                context.saveGState()
                context.setShadow(offset: .zero, blur: 6, color: UIColor.white.withAlphaComponent(0.6).cgColor)
                UIColor.white.withAlphaComponent(0.85).setStroke()
                path.lineWidth = 1.4
                path.stroke()
                context.restoreGState()
            }

            // Cities: brighter and larger with more days there.
            let colors = [UIColor(red: 1, green: 0.62, blue: 0.25, alpha: 0.85).cgColor,
                          UIColor(red: 1, green: 0.45, blue: 0.2, alpha: 0).cgColor] as CFArray
            let gradient = CGGradient(colorsSpace: CGColorSpaceCreateDeviceRGB(), colors: colors, locations: [0, 1])!
            for city in cities.reversed() {
                let point = snapshot.point(for: city.center)
                let weight = sqrt(Double(city.days) / maxDays)
                let radius = CGFloat(14 + 34 * weight)
                context.drawRadialGradient(gradient, startCenter: point, startRadius: 0, endCenter: point, endRadius: radius, options: [])
                let core = CGFloat(3 + 3 * weight)
                UIColor(red: 1, green: 0.93, blue: 0.8, alpha: 1).setFill()
                UIBezierPath(ovalIn: CGRect(x: point.x - core, y: point.y - core, width: core * 2, height: core * 2)).fill()
            }
        }
    }
}

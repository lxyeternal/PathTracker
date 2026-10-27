import SwiftUI
import SwiftData
import CoreLocation

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
            StoryPage { AnyView(DistancePage(report: r, isActive: $0)) },
        ]
        if r.steps > 0 { pages.append(StoryPage { AnyView(StepsPage(report: r, isActive: $0)) }) }
        if !r.countries.isEmpty { pages.append(StoryPage { AnyView(PlacesPage(data: data, isActive: $0)) }) }
        if r.longestDay != nil, !data.longestDayRoutes.isEmpty { pages.append(StoryPage { AnyView(LongestDayPage(data: data, isActive: $0)) }) }
        if r.favoritePlace != nil || r.farthestPlace != nil { pages.append(StoryPage { AnyView(FavoritePage(report: r, isActive: $0)) }) }
        if data.photos.count >= 3 { pages.append(StoryPage { AnyView(PhotosPage(photos: data.photos, isActive: $0)) }) }
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
            RouteArt(lines: data.routes, color: .white.opacity(0.85), lineWidth: 1.2, progress: drawn)
                .padding(.top, 110)
                .padding(.bottom, 370)
                .opacity(0.9)
            VStack(alignment: .leading, spacing: 6) {
                Spacer()
                Text(verbatim: String(data.report.year))
                    .font(.system(size: 96, weight: .black, design: .rounded))
                    .reveal(isActive, after: 0.2)
                Text("我的年度足迹").font(.system(size: 30, weight: .bold)).reveal(isActive, after: 0.35)
                Text("这一年记录了 \(data.report.daysRecorded) 天，每一条线都是你走过的路。")
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

private struct DistancePage: View {
    let report: YearReport
    let isActive: Bool

    var body: some View {
        PageLayout(colors: Palette.ocean) {
            Text("这一年你移动了").font(.title2.weight(.semibold)).reveal(isActive)
            CountUp(value: isActive ? report.distance / 1000 : 0) { "\(Int($0).formatted(.number.locale(appLocale)))" }
                .font(.system(size: 88, weight: .black, design: .rounded))
                .minimumScaleFactor(0.5).lineLimit(1)
                .animation(.easeOut(duration: 1.6).delay(0.2), value: isActive)
            Text("公里").font(.title.bold()).foregroundStyle(.white.opacity(0.8)).reveal(isActive, after: 0.3)
            HStack(spacing: 18) {
                ZStack {
                    Circle().stroke(.white.opacity(0.2), lineWidth: 10)
                    Circle()
                        .trim(from: 0, to: isActive ? max(0.02, min(1, report.shareOfEquator)) : 0)
                        .stroke(.white, style: StrokeStyle(lineWidth: 10, lineCap: .round))
                        .rotationEffect(.degrees(-90))
                        .animation(.easeOut(duration: 1.8).delay(0.6), value: isActive)
                    Image(systemName: "globe.asia.australia.fill").font(.system(size: 34))
                }
                .frame(width: 92, height: 92)
                Text("地面上的路程相当于绕赤道 \(report.shareOfEquator.formatted(.percent.precision(.fractionLength(0...1)).locale(appLocale)))")
                    .font(.title3.weight(.semibold))
            }
            .padding(.top, 20)
            .reveal(isActive, after: 0.6)
            if report.flightDistance > 0 {
                Label("其中飞行 \(Format.distance(report.flightDistance))", systemImage: "airplane")
                    .font(.headline).foregroundStyle(.white.opacity(0.75))
                    .reveal(isActive, after: 0.9)
            }
        }
    }
}

private struct StepsPage: View {
    let report: YearReport
    let isActive: Bool

    var body: some View {
        PageLayout(colors: Palette.forest) {
            Text("一步一步，走了").font(.title2.weight(.semibold)).reveal(isActive)
            CountUp(value: isActive ? report.steps : 0) { Int($0).formatted(.number.locale(appLocale)) }
                .font(.system(size: 76, weight: .black, design: .rounded))
                .minimumScaleFactor(0.4).lineLimit(1)
                .animation(.easeOut(duration: 1.6).delay(0.2), value: isActive)
            Text("步").font(.title.bold()).foregroundStyle(.white.opacity(0.8)).reveal(isActive, after: 0.3)
            let marathons = Int(report.marathons.rounded(.down))
            VStack(alignment: .leading, spacing: 10) {
                Text("步行 \(Format.distance(report.walkingDistance))，相当于 \(report.marathons.formatted(.number.precision(.fractionLength(0...1)).locale(appLocale))) 个全程马拉松")
                    .font(.title3.weight(.semibold))
                LazyVGrid(columns: Array(repeating: GridItem(.fixed(26), spacing: 6), count: 10), alignment: .leading, spacing: 6) {
                    ForEach(0..<min(max(marathons, 1), 50), id: \.self) { index in
                        Image(systemName: "figure.run")
                            .font(.system(size: 18, weight: .bold))
                            .foregroundStyle(.white)
                            .opacity(isActive ? 1 : 0)
                            .scaleEffect(isActive ? 1 : 0.3)
                            .animation(.spring(response: 0.4, dampingFraction: 0.6).delay(0.8 + Double(index) * 0.03), value: isActive)
                    }
                }
            }
            .padding(.top, 18)
            .reveal(isActive, after: 0.6)
        }
    }
}

private struct PlacesPage: View {
    let data: YearReportView.StoryData
    let isActive: Bool

    var body: some View {
        let r = data.report
        PageLayout(colors: Palette.sunset) {
            Text("去过的地方").font(.title2.weight(.semibold)).reveal(isActive)
            HStack(alignment: .firstTextBaseline, spacing: 12) {
                count(r.countries.count, "国家和地区", delay: 0.1)
                count(r.cities.count, "座城市", delay: 0.2)
                if !r.provinces.isEmpty { count(r.provinces.count, "个省份", delay: 0.3) }
            }
            if !r.provinces.isEmpty {
                ProvinceTileMap(insights: data.lightUp)
                    .allowsHitTesting(false)
                    .padding(14)
                    .background(.black.opacity(0.22), in: .rect(cornerRadius: 22, style: .continuous))
                    .overlay(RoundedRectangle(cornerRadius: 22, style: .continuous).stroke(.white.opacity(0.15), lineWidth: 1))
                    .padding(.top, 12)
                    .reveal(isActive, after: 0.5)
            }
            Text(r.countries.prefix(16).map { String.flag(for: $0) }.joined(separator: " "))
                .font(.system(size: 34))
                .reveal(isActive, after: 0.7)
            if !r.newCities.isEmpty {
                Text("新去的城市：\(r.newCities.prefix(6).joined(separator: "、"))")
                    .font(.headline).foregroundStyle(.white.opacity(0.8))
                    .reveal(isActive, after: 0.85)
            }
        }
    }

    private func count(_ value: Int, _ label: LocalizedStringKey, delay: Double) -> some View {
        VStack(alignment: .leading, spacing: 0) {
            CountUp(value: isActive ? Double(value) : 0) { "\(Int($0.rounded()))" }
                .font(.system(size: 58, weight: .black, design: .rounded))
                .animation(.easeOut(duration: 1.0).delay(delay), value: isActive)
            Text(label).font(.subheadline.weight(.semibold)).foregroundStyle(.white.opacity(0.75))
                .lineLimit(2).fixedSize(horizontal: false, vertical: true)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
    }
}

private struct LongestDayPage: View {
    let data: YearReportView.StoryData
    let isActive: Bool
    @State private var drawn: CGFloat = 0

    var body: some View {
        let r = data.report
        ZStack {
            StoryBackground(colors: Palette.violet)
            VStack(alignment: .leading, spacing: 10) {
                Spacer(minLength: 90)
                Text("移动最远的一天").font(.title2.weight(.semibold)).reveal(isActive)
                if let longest = r.longestDay {
                    Text(longest.date.formatted(.dateTime.month(.wide).day().weekday(.wide).locale(appLocale)))
                        .font(.title3).foregroundStyle(.white.opacity(0.75)).reveal(isActive, after: 0.1)
                    CountUp(value: isActive ? longest.distance / 1000 : 0) { $0.formatted(.number.precision(.fractionLength(1)).locale(appLocale)) + " km" }
                        .font(.system(size: 70, weight: .black, design: .rounded))
                        .animation(.easeOut(duration: 1.4).delay(0.2), value: isActive)
                }
                RouteArt(lines: data.longestDayRoutes, color: .white, lineWidth: 3, progress: drawn)
                    .frame(maxWidth: .infinity, minHeight: 260)
                    .background(.white.opacity(0.08), in: .rect(cornerRadius: 28, style: .continuous))
                if let month = r.busiestMonth {
                    Label("最常在路上的月份：\(month.month.formatted(.dateTime.month(.wide).locale(appLocale)))，共 \(Format.distance(month.distance))",
                          systemImage: "calendar")
                        .font(.headline).foregroundStyle(.white.opacity(0.8))
                        .reveal(isActive, after: 1.2)
                }
                Spacer(minLength: 60)
            }
            .foregroundStyle(.white)
            .padding(.horizontal, 28)
        }
        .onChange(of: isActive, initial: true) { _, active in
            drawn = 0
            if active { withAnimation(.easeInOut(duration: 2).delay(0.4)) { drawn = 1 } }
        }
    }
}

private struct FavoritePage: View {
    let report: YearReport
    let isActive: Bool

    var body: some View {
        PageLayout(colors: Palette.sunset.reversed()) {
            if let favorite = report.favoritePlace {
                Text("除了家，你最常去").font(.title2.weight(.semibold)).reveal(isActive)
                if let stay = favorite.stay {
                    PlacePicture(stay: stay)
                        .frame(height: 220)
                        .clipShape(.rect(cornerRadius: 28, style: .continuous))
                        .overlay(RoundedRectangle(cornerRadius: 28, style: .continuous).stroke(.white.opacity(0.3), lineWidth: 1))
                        .shadow(color: .black.opacity(0.3), radius: 20, y: 10)
                        .rotationEffect(.degrees(isActive ? -2 : 4))
                        .reveal(isActive, after: 0.2)
                }
                Text(favorite.name).font(.system(size: 40, weight: .black)).lineLimit(2).minimumScaleFactor(0.6)
                    .reveal(isActive, after: 0.4)
                Text("去了 \(favorite.visits) 次").font(.title3.weight(.semibold)).foregroundStyle(.white.opacity(0.8))
                    .reveal(isActive, after: 0.5)
            }
            if let farthest = report.farthestPlace {
                Label("离家最远到过\(farthest.name)，\(Format.distance(farthest.distance))", systemImage: "location.north.line.fill")
                    .font(.headline).foregroundStyle(.white.opacity(0.85))
                    .padding(.top, 16)
                    .reveal(isActive, after: 0.8)
            }
        }
    }
}

private struct PhotosPage: View {
    let photos: [TripPhoto]
    let isActive: Bool

    var body: some View {
        PageLayout(colors: Palette.night) {
            Text("这一年留下的画面").font(.title2.weight(.semibold)).reveal(isActive)
            Text("\(photos.count) 张照片").font(.title3).foregroundStyle(.white.opacity(0.75)).reveal(isActive, after: 0.1)
            let shown = Array(photos.shuffledStably.prefix(9))
            LazyVGrid(columns: Array(repeating: GridItem(.flexible(), spacing: 6), count: 3), spacing: 6) {
                ForEach(Array(shown.enumerated()), id: \.element.id) { index, photo in
                    PhotoThumbnail(photo: photo, cornerRadius: 14)
                        .rotationEffect(.degrees(isActive ? 0 : Double(index % 3 - 1) * 8))
                        .scaleEffect(isActive ? 1 : 0.6)
                        .opacity(isActive ? 1 : 0)
                        .animation(.spring(response: 0.5, dampingFraction: 0.7).delay(0.2 + Double(index) * 0.06), value: isActive)
                }
            }
            .padding(.top, 10)
        }
    }
}

private extension Array where Element == TripPhoto {
    /// A mix across the year that doesn't change every time the page draws.
    var shuffledStably: [TripPhoto] {
        guard count > 9 else { return self }
        let step = Double(count) / 9
        return (0..<9).map { self[Int(Double($0) * step)] }
    }
}

private struct SharePage: View {
    let data: YearReportView.StoryData
    let image: Image?

    var body: some View {
        ZStack {
            StoryBackground(colors: Palette.night)
            VStack(spacing: 22) {
                Spacer(minLength: 80)
                YearPoster(data: data)
                    .frame(width: 300, height: 492)
                    .clipShape(.rect(cornerRadius: 30, style: .continuous))
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
            LinearGradient(colors: [Color(red: 0.08, green: 0.07, blue: 0.25), Color(red: 0.35, green: 0.12, blue: 0.45), Color(red: 0.95, green: 0.45, blue: 0.3)],
                           startPoint: .top, endPoint: .bottom)
            RouteArt(lines: data.routes, color: .white.opacity(0.7), lineWidth: 1.1)
                .padding(.top, 150).padding(.bottom, 170)
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

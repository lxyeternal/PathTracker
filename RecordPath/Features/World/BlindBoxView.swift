import SwiftUI
import MapKit
import WeatherKit

struct BlindBoxRoute: Hashable {}

private let night = Color(red: 0.05, green: 0.05, blue: 0.14)
private let gold = LinearGradient(colors: [Color(red: 1, green: 0.88, blue: 0.55), Color(red: 1, green: 0.62, blue: 0.22)], startPoint: .top, endPoint: .bottom)
/// The gold as one colour, for outlines and tints.
private let amber = Color(red: 1, green: 0.76, blue: 0.40)

// MARK: - The sky

/// A night going warm towards the horizon, stars that twinkle, a violet glow high up and an
/// amber one low down that brightens while the box is opening.
private struct BlindBoxSky: View {
    var glow: Double
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    private struct Star { let x, y, size, phase: Double }

    private static let stars: [Star] = {
        var seed: UInt64 = 2026
        func next() -> Double {
            seed = seed &* 6_364_136_223_846_793_005 &+ 1_442_695_040_888_963_407
            return Double(seed >> 11) / Double(1 << 53)
        }
        return (0..<90).map { _ in Star(x: next(), y: next() * 0.8, size: 0.6 + next() * 1.7, phase: next() * 2 * .pi) }
    }()

    var body: some View {
        ZStack {
            LinearGradient(colors: [Color(red: 0.03, green: 0.03, blue: 0.11), night, Color(red: 0.10, green: 0.06, blue: 0.20), Color(red: 0.20, green: 0.09, blue: 0.21)],
                           startPoint: .top, endPoint: .bottom)
            TimelineView(.animation(minimumInterval: 1 / 15, paused: reduceMotion)) { timeline in
                let time = timeline.date.timeIntervalSinceReferenceDate
                Canvas { context, size in
                    for star in Self.stars {
                        let twinkle = reduceMotion ? 0.6 : 0.35 + 0.65 * (0.5 + 0.5 * sin(time * 1.2 + star.phase))
                        let rect = CGRect(x: star.x * size.width, y: star.y * size.height, width: star.size, height: star.size)
                        context.fill(Path(ellipseIn: rect), with: .color(.white.opacity(0.75 * twinkle)))
                    }
                }
            }
            GeometryReader { geo in
                Ellipse()
                    .fill(Color(red: 0.46, green: 0.32, blue: 0.98).opacity(0.24))
                    .frame(width: geo.size.width * 1.1, height: 300)
                    .blur(radius: 90)
                    .position(x: geo.size.width * 0.2, y: geo.size.height * 0.08)
                Ellipse()
                    .fill(Color(red: 1, green: 0.55, blue: 0.28).opacity(0.12 + glow * 0.28))
                    .frame(width: geo.size.width * 1.3, height: 340)
                    .blur(radius: 110)
                    .position(x: geo.size.width * 0.7, y: geo.size.height * 0.95)
            }
        }
        .ignoresSafeArea()
        .allowsHitTesting(false)
        .animation(.easeInOut(duration: 0.8), value: glow)
    }
}

/// Chips that wrap onto the next line instead of running off the side.
private struct WrappingLayout: Layout {
    var spacing: CGFloat = 8

    func sizeThatFits(proposal: ProposedViewSize, subviews: Subviews, cache: inout ()) -> CGSize {
        let width = proposal.width ?? .infinity
        var x: CGFloat = 0, y: CGFloat = 0, row: CGFloat = 0, widest: CGFloat = 0
        for subview in subviews {
            let size = subview.sizeThatFits(.unspecified)
            if x > 0, x + size.width > width {
                y += row + spacing
                x = 0
                row = 0
            }
            x += size.width + spacing
            row = max(row, size.height)
            widest = max(widest, x - spacing)
        }
        return CGSize(width: proposal.width ?? widest, height: y + row)
    }

    func placeSubviews(in bounds: CGRect, proposal: ProposedViewSize, subviews: Subviews, cache: inout ()) {
        var x = bounds.minX, y = bounds.minY, row: CGFloat = 0
        for subview in subviews {
            let size = subview.sizeThatFits(.unspecified)
            if x > bounds.minX, x + size.width > bounds.maxX {
                y += row + spacing
                x = bounds.minX
                row = 0
            }
            subview.place(at: CGPoint(x: x, y: y), proposal: ProposedViewSize(size))
            x += size.width + spacing
            row = max(row, size.height)
        }
    }
}

/// Gold sparks thrown out of the ticket as it turns over.
private struct RevealBurst: View {
    let start: Date
    private static let length = 1.6

    var body: some View {
        TimelineView(.animation(paused: Date().timeIntervalSince(start) > Self.length)) { timeline in
            let time = timeline.date.timeIntervalSince(start)
            Canvas { context, size in
                guard time < Self.length else { return }
                let center = CGPoint(x: size.width / 2, y: size.height * 0.32)
                let fade = max(0, 1 - time / Self.length)
                for index in 0..<34 {
                    let angle = Double(index) / 34 * 2 * .pi + Double(index % 3) * 0.17
                    let speed = 150 + Double((index * 37) % 120)
                    let distance = speed * time * (1 - time / 3.4)
                    let point = CGPoint(x: center.x + cos(angle) * distance, y: center.y + sin(angle) * distance + 60 * time * time)
                    let size = 2 + Double(index % 4) * 1.2
                    let rect = CGRect(x: point.x - size / 2, y: point.y - size / 2, width: size, height: size)
                    let colour = index % 5 == 0 ? Color.white : Color(red: 1, green: 0.82 - Double(index % 3) * 0.08, blue: 0.45)
                    context.fill(index % 2 == 0 ? Path(ellipseIn: rect) : Path(roundedRect: rect, cornerRadius: 1), with: .color(colour.opacity(fade)))
                }
            }
        }
        .allowsHitTesting(false)
        .accessibilityHidden(true)
    }
}

// MARK: - What's around the person

/// The live part of a draw: what Apple Maps knows nearby, the drive and the weather.
enum BlindBoxPlanner {
    struct Forecast: Equatable {
        let date: Date
        let symbol: String
        let high: Double
        let low: Double

        var isWet: Bool { ["rain", "drizzle", "bolt", "snow", "sleet", "hail"].contains { symbol.contains($0) } }
    }

    struct Plan: Equatable {
        var drive: TimeInterval?
        var forecast: Forecast?
    }

    /// What the box knows when it opens. Uses where the person is now if that's recent,
    /// otherwise home.
    @MainActor
    static func context(visited: Set<String>) -> BlindBox.Context {
        let summaries = PlaceSummaries.shared
        var context = BlindBox.Context(visited: visited)
        context.wishes = Set((UserDefaults.standard.string(forKey: "mustSee.wishes") ?? "").split(separator: ",").map(String.init))
        context.recent = BlindBoxStore.shared.recent
        let latest = summaries.stays.first { !$0.isFromPhotos }
        if let latest, Date().timeIntervalSince(latest.departure ?? .now) < 3 * 86_400 {
            context.here = latest.location
        } else {
            context.here = summaries.home?.location
        }
        if let here = context.here {
            context.farthest = summaries.stays.map { $0.location.distance(from: here) }.max() ?? 0
        }
        for document in TravelDocuments.shared.all where document.kind != .passport && document.daysLeft() >= 30 {
            for country in document.coveredCountries {
                if let held = context.visas[country], held.until >= document.expires { continue }
                context.visas[country] = (document.countryName, document.expires)
            }
        }
        return context
    }

    /// Places worth a day out, away from the everyday and not yet visited.
    @MainActor
    static func nearby(around here: CLLocation, mood: BlindBox.Mood) async -> [BlindBox.Place] {
        let stays = PlaceSummaries.shared.stays.map(\.location)
        let center = here.coordinate.onMap
        let origin = CLLocation(latitude: center.latitude, longitude: center.longitude)
        var found: [BlindBox.Place] = []
        await withTaskGroup(of: [MKMapItem].self) { group in
            for term in terms(for: mood, chinese: ChinaCoordinates.isInMainland(here.coordinate) || MustSee.isChinese) {
                group.addTask {
                    let request = MKLocalSearch.Request()
                    request.naturalLanguageQuery = term.query
                    request.resultTypes = .pointOfInterest
                    request.region = MKCoordinateRegion(center: center, latitudinalMeters: 300_000, longitudinalMeters: 300_000)
                    return (try? await MKLocalSearch(request: request).start().mapItems) ?? []
                }
            }
            for await items in group {
                for item in items {
                    let distance = item.location.distance(from: origin) / 1000
                    guard let name = item.name, BlindBox.Span.day.range.contains(distance), !isErrand(name, category: item.pointOfInterestCategory) else { continue }
                    let coordinate = item.location.coordinate
                    let id = String(format: "nearby-%.3f-%.3f", coordinate.latitude, coordinate.longitude)
                    guard !found.contains(where: { $0.id == id }) else { continue }
                    // Within a kilometre and a half of a past stay: already been.
                    let location = item.location
                    guard !stays.contains(where: { $0.distance(from: location) < 1_500 }) else { continue }
                    found.append(BlindBox.Place(id: id, name: name, region: item.addressRepresentations?.cityName ?? "",
                                                latitude: coordinate.latitude, longitude: coordinate.longitude,
                                                kind: kind(of: item.pointOfInterestCategory, query: mood)))
                }
            }
        }
        return found
    }

    private static func terms(for mood: BlindBox.Mood, chinese: Bool) -> [(query: String, unused: Void)] {
        let words: [String] = switch mood {
        case .quiet: chinese ? ["湖", "湿地公园", "海滩", "水库"] : ["lake", "beach", "nature reserve"]
        case .climb: chinese ? ["森林公园", "国家公园", "登山", "山风景区"] : ["hiking trail", "national park", "mountain"]
        case .history: chinese ? ["古镇", "古迹", "博物馆", "古村"] : ["historic site", "old town", "museum"]
        case .city: chinese ? ["老街", "历史街区", "美术馆"] : ["old town", "art museum", "historic district"]
        case .any: chinese ? ["风景区", "古镇", "森林公园", "湖"] : ["scenic area", "national park", "historic site", "lake"]
        }
        return words.map { ($0, ()) }
    }

    /// Shops, gates and car parks turn up in any search, and nobody takes a day out to one.
    private static func isErrand(_ name: String, category: MKPointOfInterestCategory?) -> Bool {
        let words = ["停车", "出口", "入口", "售票", "游客中心", "服务区", "公交", "地铁", "酒店", "宾馆", "民宿", "餐", "超市", "管理处", "检票", "公厕", "洗手间",
                     "Parking", "Entrance", "Exit", "Hotel", "Visitor Center"]
        if words.contains(where: { name.localizedCaseInsensitiveContains($0) }) { return true }
        guard let category else { return false }
        return [.hotel, .restaurant, .cafe, .store, .parking, .gasStation, .publicTransport, .airport, .bank, .atm, .hospital, .pharmacy, .school, .university].contains(category)
    }

    private static func kind(of category: MKPointOfInterestCategory?, query mood: BlindBox.Mood) -> MustSeePlace.Kind {
        switch category {
        case .beach: .water
        case .nationalPark, .park: mood == .climb ? .mountain : .wild
        case .museum, .castle, .fortress, .landmark, .nationalMonument: .heritage
        default:
            switch mood {
            case .quiet: .water
            case .climb: .mountain
            case .history: .heritage
            case .city: .city
            case .any: .wild
            }
        }
    }

    static func drive(from here: CLLocation, to place: BlindBox.Place) async -> TimeInterval? {
        let coordinate = place.mapCoordinate
        let start = here.coordinate.onMap
        let request = MKDirections.Request()
        request.source = MKMapItem(location: CLLocation(latitude: start.latitude, longitude: start.longitude), address: nil)
        request.destination = MKMapItem(location: CLLocation(latitude: coordinate.latitude, longitude: coordinate.longitude), address: nil)
        request.transportType = .automobile
        return try? await MKDirections(request: request).calculateETA().expectedTravelTime
    }

    /// The day's forecast, for days close enough to mean something. Asked at about 1 km, like
    /// the rest of the weather in the app.
    static func forecast(on day: Date, at place: BlindBox.Place) async -> Forecast? {
        let start = Calendar.current.startOfDay(for: day)
        guard let end = Calendar.current.date(byAdding: .day, value: 1, to: start),
              start.timeIntervalSinceNow < 9 * 86_400 else { return nil }
        let rough = CLLocation(latitude: (place.latitude * 100).rounded() / 100, longitude: (place.longitude * 100).rounded() / 100)
        guard let weather = try? await WeatherService.shared.weather(for: rough, including: .daily(startDate: start, endDate: end)).first else { return nil }
        return Forecast(date: start, symbol: weather.symbolName, high: weather.highTemperature.converted(to: .celsius).value,
                        low: weather.lowTemperature.converted(to: .celsius).value)
    }

    /// The day the trip's weather is worth looking up: the day out, or the coming Saturday.
    static func tripDay(for span: BlindBox.Span, from now: Date = .now) -> Date? {
        switch span {
        case .day: BlindBox.dayOut(from: now)
        case .weekend: Calendar.current.nextDate(after: now, matching: DateComponents(weekday: 7), matchingPolicy: .nextTime)
        case .holiday, .long: nil
        }
    }
}

// MARK: - The box

/// A plain cardboard-coloured mystery: a lid, a ribbon, and a light from inside as it opens.
private struct MysteryBox: View {
    /// 0 shut, 1 lid gone.
    var open: Double
    var glow: Double

    var body: some View {
        ZStack {
            Circle()
                .fill(RadialGradient(colors: [Color.orange.opacity(0.7), .clear], center: .center, startRadius: 4, endRadius: 150))
                .frame(width: 300, height: 300)
                .scaleEffect(0.6 + glow * 0.7)
                .opacity(0.25 + glow * 0.75)
                .offset(y: -20)
            RoundedRectangle(cornerRadius: 14, style: .continuous)
                .fill(LinearGradient(colors: [Color(red: 0.30, green: 0.22, blue: 0.56), Color(red: 0.14, green: 0.11, blue: 0.34)], startPoint: .top, endPoint: .bottom))
                .frame(width: 156, height: 112)
                .overlay { Rectangle().fill(gold).frame(width: 22) }
                .overlay {
                    RoundedRectangle(cornerRadius: 14, style: .continuous).strokeBorder(.white.opacity(0.12), lineWidth: 1)
                }
                .offset(y: 30)
            lid
                .rotationEffect(.degrees(open * -28), anchor: .leading)
                .offset(x: open * 40, y: -34 - open * 160)
                .opacity(1 - open)
        }
        .frame(width: 200, height: 200)
        .accessibilityHidden(true)
    }

    private var lid: some View {
        ZStack(alignment: .top) {
            RoundedRectangle(cornerRadius: 10, style: .continuous)
                .fill(LinearGradient(colors: [Color(red: 0.40, green: 0.30, blue: 0.68), Color(red: 0.25, green: 0.18, blue: 0.50)], startPoint: .top, endPoint: .bottom))
                .frame(width: 176, height: 38)
                .overlay { Rectangle().fill(gold).frame(width: 22) }
                .clipShape(.rect(cornerRadius: 10, style: .continuous))
            Image(systemName: "sparkle")
                .font(.system(size: 30, weight: .bold))
                .foregroundStyle(gold)
                .offset(y: -28)
        }
    }
}

// MARK: - The ticket

/// A ticket with a notch either side of the tear line.
private struct BoardingPassShape: Shape {
    let tear: CGFloat

    func path(in rect: CGRect) -> Path {
        var path = Path(roundedRect: rect, cornerRadius: 22, style: .continuous)
        let radius: CGFloat = 10
        path.addEllipse(in: CGRect(x: rect.minX - radius, y: tear - radius, width: radius * 2, height: radius * 2))
        path.addEllipse(in: CGRect(x: rect.maxX - radius, y: tear - radius, width: radius * 2, height: radius * 2))
        return path
    }
}

/// The boarding pass: the place's picture, from here to there, when it's at its best and why
/// this place. A postmark goes across it once the person gets there.
struct BoardingPass: View {
    let draw: BlindBox.Draw
    var from: String?
    var arrived: Date?
    var stamped = true
    @State private var cover: UIImage?

    private let paper = Color(red: 0.98, green: 0.96, blue: 0.91)
    private let ink = Color(red: 0.14, green: 0.13, blue: 0.20)
    private let imageHeight: CGFloat = 150
    private let routeHeight: CGFloat = 112

    private var place: BlindBox.Place { draw.place }
    private var story: MustSeeStory? { place.mustSeeID.flatMap(MustSee.story) }

    var body: some View {
        VStack(spacing: 0) {
            picture.frame(height: imageHeight).clipped()
            route.frame(height: routeHeight)
            details
        }
        .foregroundStyle(ink)
        .background(paper)
        .clipShape(BoardingPassShape(tear: imageHeight + routeHeight), style: FillStyle(eoFill: true))
        .overlay(alignment: .topTrailing) {
            if let arrived, stamped { BlindBoxPostmark(date: arrived).rotationEffect(.degrees(-14)).padding(.top, imageHeight - 50).padding(.trailing, 16) }
        }
        .shadow(color: .black.opacity(0.35), radius: 18, y: 10)
        .task(id: place.id) {
            if let id = place.mustSeeID {
                let image = await MustSeePhotos.cover(id)
                withAnimation(.easeOut(duration: 0.4)) { cover = image }
            }
        }
        .accessibilityElement(children: .combine)
    }

    private var picture: some View {
        ZStack(alignment: .topLeading) {
            if let cover {
                GeometryReader { geo in
                    Image(uiImage: cover).resizable().scaledToFill().frame(width: geo.size.width, height: geo.size.height).clipped()
                }
            } else if place.mustSeeID == nil {
                Map(initialPosition: .camera(MapCamera(centerCoordinate: place.mapCoordinate, distance: 6_000))) { }
                    .mapStyle(.hybrid(elevation: .flat, pointsOfInterest: .excludingAll))
                    .allowsHitTesting(false)
            } else {
                LinearGradient(colors: [Color(red: 0.2, green: 0.17, blue: 0.42), Color(red: 0.45, green: 0.3, blue: 0.5)], startPoint: .top, endPoint: .bottom)
            }
            LinearGradient(colors: [.black.opacity(0.5), .clear], startPoint: .top, endPoint: .center)
            HStack {
                Text(verbatim: "WAYTRACE").font(.caption2.weight(.heavy)).tracking(3)
                Spacer()
                Label(draw.span.title, systemImage: draw.span.symbol).font(.caption2.weight(.bold))
            }
            .foregroundStyle(.white)
            .padding(14)
        }
    }

    private var route: some View {
        VStack(alignment: .leading, spacing: 4) {
            if let from, !from.isEmpty {
                Text("从\(from)出发").font(.caption.weight(.semibold)).foregroundStyle(ink.opacity(0.55))
            } else {
                Text("下一站").font(.caption.weight(.semibold)).foregroundStyle(ink.opacity(0.55))
            }
            Text(verbatim: place.localizedName)
                .font(.system(size: 28, weight: .bold, design: .serif))
                .lineLimit(2).minimumScaleFactor(0.6)
            if !place.localizedRegion.isEmpty {
                Text(verbatim: place.localizedRegion).font(.subheadline).foregroundStyle(ink.opacity(0.6))
            }
        }
        .padding(.horizontal, 18)
        .frame(maxWidth: .infinity, alignment: .leading)
    }

    private var details: some View {
        VStack(alignment: .leading, spacing: 14) {
            Line().stroke(ink.opacity(0.22), style: StrokeStyle(lineWidth: 1, dash: [5, 5])).frame(height: 1)
            HStack(alignment: .top, spacing: 16) {
                if let distance = draw.distance {
                    field("距离", value: String(localized: "约 \(Format.distance(distance))", bundle: .appLanguage))
                }
                if let season = story?.localizedSeason {
                    field("最好的时候", value: season)
                }
            }
            Text(verbatim: draw.reason.text(for: place))
                .font(.system(.body, design: .serif, weight: .medium))
                .fixedSize(horizontal: false, vertical: true)
        }
        .padding(.horizontal, 18)
        .padding(.bottom, 18)
    }

    private func field(_ title: LocalizedStringKey, value: String) -> some View {
        VStack(alignment: .leading, spacing: 2) {
            Text(title).font(.caption2.weight(.semibold)).foregroundStyle(ink.opacity(0.5))
            Text(verbatim: value).font(.footnote.weight(.semibold)).fixedSize(horizontal: false, vertical: true)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
    }

    private struct Line: Shape {
        func path(in rect: CGRect) -> Path {
            Path { $0.move(to: CGPoint(x: rect.minX, y: rect.midY)); $0.addLine(to: CGPoint(x: rect.maxX, y: rect.midY)) }
        }
    }
}

/// Inked across the ticket on arrival.
struct BlindBoxPostmark: View {
    let date: Date
    private let red = Color(red: 0.76, green: 0.13, blue: 0.13)

    var body: some View {
        VStack(spacing: 1) {
            if MustSee.isChinese { Text("已到达").font(.system(size: 14, weight: .heavy)) }
            Text(verbatim: "ARRIVED").font(.system(size: 8, weight: .heavy)).tracking(1.5)
            Text(verbatim: date.formatted(.dateTime.year().month(.twoDigits).day(.twoDigits).locale(Locale(identifier: "en_GB"))))
                .font(.system(size: 9, weight: .bold, design: .monospaced))
        }
        .foregroundStyle(red)
        .frame(width: 90, height: 90)
        .background(Circle().fill(Color(red: 0.98, green: 0.96, blue: 0.91).opacity(0.85)))
        .overlay(Circle().strokeBorder(red, lineWidth: 2.5))
        .overlay(Circle().strokeBorder(red.opacity(0.7), lineWidth: 1).padding(5))
    }
}

/// What the ticket means in practice: when to leave, how long it takes and the weather for a
/// day out; which days go where on a longer trip.
private struct BlindBoxPlanView: View {
    let draw: BlindBox.Draw
    let here: CLLocation?
    @State private var plan = BlindBoxPlanner.Plan()
    @State private var attribution: (light: URL, dark: URL, legal: URL)?
    @Environment(\.colorScheme) private var colorScheme
    private var portrait: TravellerPortrait { PlaceSummaries.shared.portrait }

    var body: some View {
        VStack(spacing: 12) {
            card {
                if draw.span == .day { dayOut } else { daysAway }
                if let forecast = plan.forecast {
                    Divider().overlay(.white.opacity(0.12))
                    weather(forecast)
                }
            }
            card { playIdeas }
            mission
        }
        .foregroundStyle(.white)
        .task(id: draw.id) {
            if draw.span == .day, let here { plan.drive = await BlindBoxPlanner.drive(from: here, to: draw.place) }
            if let day = BlindBoxPlanner.tripDay(for: draw.span) {
                plan.forecast = await BlindBoxPlanner.forecast(on: day, at: draw.place)
                if plan.forecast != nil { attribution = await PastWeather.attribution() }
            }
        }
    }

    private func card(@ViewBuilder _ content: () -> some View) -> some View {
        VStack(alignment: .leading, spacing: 14, content: content)
            .padding(18)
            .frame(maxWidth: .infinity, alignment: .leading)
            .background(.white.opacity(0.07), in: .rect(cornerRadius: 22, style: .continuous))
            .overlay(RoundedRectangle(cornerRadius: 22, style: .continuous).strokeBorder(.white.opacity(0.08), lineWidth: 1))
    }

    private func heading(_ title: LocalizedStringKey, _ symbol: String) -> some View {
        Label { Text(title) } icon: { Image(systemName: symbol).foregroundStyle(gold) }
            .font(.subheadline.weight(.bold))
    }

    /// What to do once there: a little useful.
    private var playIdeas: some View {
        let ideas = BlindBoxIdeas.ideas(for: draw.place)
        return VStack(alignment: .leading, spacing: 12) {
            heading("到了可以这样玩", "sparkles")
            ForEach(ideas.tips, id: \.self) { tip in
                HStack(alignment: .top, spacing: 12) {
                    Image(systemName: draw.place.placeKind.symbol)
                        .font(.caption.weight(.semibold)).foregroundStyle(amber)
                        .frame(width: 28, height: 28)
                        .background(amber.opacity(0.14), in: .circle)
                    Text(verbatim: tip).font(.subheadline).foregroundStyle(.white.opacity(0.88))
                        .fixedSize(horizontal: false, vertical: true)
                        .padding(.top, 4)
                }
            }
        }
    }

    /// One small thing to do there, for the fun of it, set apart like a note tucked in the ticket.
    private var mission: some View {
        let ideas = BlindBoxIdeas.ideas(for: draw.place)
        let title: LocalizedStringKey = draw.span == .day ? "今天的小任务" : "这一趟的小任务"
        return HStack(alignment: .top, spacing: 14) {
            Image(systemName: "flag.fill")
                .font(.subheadline.weight(.bold)).foregroundStyle(night)
                .frame(width: 36, height: 36)
                .background(gold, in: .circle)
            VStack(alignment: .leading, spacing: 4) {
                Text(title).font(.caption.weight(.bold)).foregroundStyle(amber)
                Text(verbatim: ideas.mission)
                    .font(.system(.body, design: .serif, weight: .semibold))
                    .fixedSize(horizontal: false, vertical: true)
            }
            Spacer(minLength: 0)
        }
        .padding(18)
        .background(amber.opacity(0.08), in: .rect(cornerRadius: 22, style: .continuous))
        .overlay(RoundedRectangle(cornerRadius: 22, style: .continuous).strokeBorder(amber.opacity(0.55), style: StrokeStyle(lineWidth: 1.2, dash: [6, 5])))
    }

    private var dayOut: some View {
        let day = BlindBox.dayOut()
        let minutes = BlindBox.departure(early: portrait.early, night: portrait.night)
        let time = String(format: "%d:%02d", minutes / 60, minutes % 60)
        let date = day.formatted(.dateTime.month().day().weekday().locale(appLocale))
        let calendar = Calendar.current
        let now = calendar.component(.hour, from: .now) * 60 + calendar.component(.minute, from: .now)
        let underway = calendar.isDateInToday(day) && now >= minutes
        return VStack(alignment: .leading, spacing: 14) {
            heading("怎么去", "map.fill")
            if underway {
                row("clock.fill", String(localized: "现在出发就正好", bundle: .appLanguage), detail: String(localized: "今天还长，天黑前能回来", bundle: .appLanguage))
            } else {
                row("clock.fill", String(localized: "\(date) \(time) 出发", bundle: .appLanguage), detail: departureNote)
            }
            if let drive = plan.drive {
                row("car.fill", String(localized: "开车约 \(Format.duration(drive))", bundle: .appLanguage),
                    detail: drive < 3 * 3600 ? String(localized: "当天能回来", bundle: .appLanguage)
                                             : String(localized: "有点远，住一晚也不错", bundle: .appLanguage))
            }
        }
    }

    private var departureNote: String {
        if portrait.early >= 0.2 { return String(localized: "你习惯早起，这个时间刚好", bundle: .appLanguage) }
        if portrait.night >= 0.2 { return String(localized: "你是夜里才精神的人，不用起太早", bundle: .appLanguage) }
        return String(localized: "不赶，吃完早饭再走", bundle: .appLanguage)
    }

    private var daysAway: some View {
        let places = [draw.place] + draw.stops.compactMap(BlindBox.mustSee(id:)).map(BlindBox.Place.init)
        let ranges = BlindBox.itinerary(days: draw.span.days, places: places.count)
        let stops = Array(zip(places, ranges))
        return VStack(alignment: .leading, spacing: 14) {
            heading("可以这样走", "point.bottomleft.forward.to.point.topright.scurvepath.fill")
            VStack(alignment: .leading, spacing: 0) {
                ForEach(Array(stops.enumerated()), id: \.element.0.id) { index, stop in
                    let (place, range) = stop
                    let last = index == stops.count - 1
                    HStack(alignment: .top, spacing: 14) {
                        // A dot for each stop, joined by the road between them.
                        VStack(spacing: 0) {
                            Circle()
                                .fill(index == 0 ? AnyShapeStyle(gold) : AnyShapeStyle(night))
                                .overlay(Circle().strokeBorder(amber, lineWidth: 2))
                                .frame(width: 14, height: 14)
                                .padding(.top, 3)
                            if !last {
                                Rectangle().fill(amber.opacity(0.35)).frame(width: 2).frame(maxHeight: .infinity)
                            }
                        }
                        .frame(width: 14)
                        VStack(alignment: .leading, spacing: 3) {
                            Text(verbatim: label(range))
                                .font(.caption2.weight(.heavy)).foregroundStyle(amber)
                            Text(verbatim: place.localizedName).font(.body.weight(.semibold))
                            if let season = place.mustSeeID.flatMap(MustSee.story)?.localizedSeason {
                                Text(verbatim: season).font(.caption).foregroundStyle(.white.opacity(0.6))
                            }
                        }
                        .padding(.bottom, last ? 0 : 18)
                        Spacer(minLength: 0)
                    }
                }
            }
            Text("只是个建议。到了那里，想多待就多待。")
                .font(.caption).foregroundStyle(.white.opacity(0.55))
        }
    }

    private func label(_ range: ClosedRange<Int>) -> String {
        range.count == 1 ? String(localized: "第 \(range.lowerBound) 天", bundle: .appLanguage)
                         : String(localized: "第 \(range.lowerBound)–\(range.upperBound) 天", bundle: .appLanguage)
    }

    private func row(_ symbol: String, _ title: String, detail: String) -> some View {
        HStack(alignment: .top, spacing: 12) {
            Image(systemName: symbol)
                .font(.caption.weight(.semibold)).foregroundStyle(amber)
                .frame(width: 28, height: 28)
                .background(amber.opacity(0.14), in: .circle)
            VStack(alignment: .leading, spacing: 2) {
                Text(verbatim: title).font(.subheadline.weight(.semibold))
                Text(verbatim: detail).font(.caption).foregroundStyle(.white.opacity(0.6))
            }
            .padding(.top, 2)
        }
    }

    private func weather(_ forecast: BlindBoxPlanner.Forecast) -> some View {
        let date = forecast.date.formatted(.dateTime.month().day().weekday().locale(appLocale))
        return VStack(alignment: .leading, spacing: 8) {
            HStack(alignment: .top, spacing: 12) {
                Image(systemName: forecast.symbol).symbolRenderingMode(.multicolor)
                    .frame(width: 28, height: 28)
                    .background(.white.opacity(0.1), in: .circle)
                VStack(alignment: .leading, spacing: 2) {
                    Text(verbatim: "\(date) · \(temperature(forecast.low)) – \(temperature(forecast.high))").font(.subheadline.weight(.semibold))
                    Text(forecast.isWet ? "可能有雨雪，带好伞。不想淋雨，再抽一次也行" : "是个适合出门的日子")
                        .font(.caption).foregroundStyle(.white.opacity(0.6))
                }
            }
            if let attribution {
                HStack(spacing: 6) {
                    AsyncImage(url: colorScheme == .dark ? attribution.dark : attribution.light) { image in
                        image.resizable().scaledToFit()
                    } placeholder: { EmptyView() }
                    .frame(height: 11)
                    Link("数据来源", destination: attribution.legal).font(.caption2)
                }
            }
        }
    }

    private func temperature(_ celsius: Double) -> String {
        // Rounded first, or a tenth of a degree of frost reads as "-0°".
        Measurement(value: celsius.rounded() + 0, unit: UnitTemperature.celsius)
            .formatted(.measurement(width: .narrow, usage: .weather, numberFormatStyle: .number.precision(.fractionLength(0))).locale(appLocale))
    }
}

// MARK: - The screen

struct BlindBoxView: View {
    private enum Phase: Equatable { case choosing, opening, revealed(BlindBox.Draw), kept(BlindBox.Draw) }

    private var store = BlindBoxStore.shared
    private var summaries = PlaceSummaries.shared
    private var progress = MustSeeProgress.shared
    @State private var phase = Phase.choosing
    @State private var span = BlindBox.Span.weekend
    @AppStorage("blindBox.mood") private var moodRaw = BlindBox.Mood.any.rawValue
    @State private var moment = BlindBoxMoment(line: "", span: .weekend)
    @State private var holdProgress: CGFloat = 0
    @State private var holdStart: Date?
    @State private var lidOpen = 0.0
    @State private var flipped = false
    @State private var nothing: LocalizedStringKey?
    @State private var viewing: BlindBox.Ticket?
    @State private var here: CLLocation?
    @State private var burst: Date?
    @State private var floating = false
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    private static let holdDuration = 1.2
    private var mood: BlindBox.Mood { BlindBox.Mood(rawValue: moodRaw) ?? .any }
    private var startCity: String? { summaries.stays.first { !$0.isFromPhotos }?.city ?? summaries.home?.city }

    var body: some View {
        ScrollView {
            VStack(spacing: 22) {
                switch phase {
                case .choosing, .opening: chooser
                case let .revealed(draw): revealed(draw)
                case let .kept(draw): kept(draw)
                }
                if phase == .choosing, !store.tickets.isEmpty { ticketList }
            }
            .padding(.horizontal)
            .padding(.bottom, 40)
        }
        .scrollIndicators(.hidden)
        .background { BlindBoxSky(glow: phase == .opening ? 1 : holdProgress) }
        .navigationTitle("旅行盲盒")
        .navigationBarTitleDisplayMode(.inline)
        .toolbarColorScheme(.dark, for: .navigationBar)
        .environment(\.colorScheme, .dark)
        .onAppear(perform: setUp)
        .sheet(item: $viewing) { TicketSheet(ticket: $0, here: here) }
    }

    private func setUp() {
        let now = Date.now
        let chinese = summaries.home?.countryCode == "CN" || (summaries.home == nil && MustSee.isChinese)
        moment = BlindBoxMoment.at(now, holiday: chinese ? Holiday.next(after: now) : nil)
        if phase == .choosing { span = moment.span }
        here = BlindBoxPlanner.context(visited: []).here
        if let open = store.open, phase == .choosing {
            flipped = true
            lidOpen = 1
            phase = .revealed(open)
        }
    }

    // MARK: Choosing

    private var chooser: some View {
        VStack(spacing: 20) {
            VStack(spacing: 8) {
                Text(verbatim: Date.now.formatted(.dateTime.month().day().weekday(.wide).locale(appLocale)))
                    .font(.caption.weight(.bold)).tracking(1.5)
                    .foregroundStyle(amber)
                Text(verbatim: moment.line)
                    .font(.system(.title2, design: .serif, weight: .bold))
                    .foregroundStyle(.white)
                    .multilineTextAlignment(.center)
                    .fixedSize(horizontal: false, vertical: true)
            }
            .padding(.top, 4)
            .frame(maxWidth: .infinity)
            spanPicker
            moodPicker
            box
        }
    }

    private func section(_ title: LocalizedStringKey) -> some View {
        Text(title).font(.footnote.weight(.semibold)).foregroundStyle(.white.opacity(0.6))
    }

    /// Chosen: a gold outline and a warm tint. The solid gold is kept for the one thing to press.
    private func choice(_ selected: Bool, in shape: some InsettableShape) -> some View {
        shape.fill(selected ? amber.opacity(0.16) : .white.opacity(0.06))
            .overlay(shape.strokeBorder(selected ? amber : .white.opacity(0.08), lineWidth: selected ? 1.5 : 1))
    }

    private var spanPicker: some View {
        VStack(alignment: .leading, spacing: 10) {
            section("你有多少时间")
            LazyVGrid(columns: [GridItem(.flexible(), spacing: 10), GridItem(.flexible(), spacing: 10)], spacing: 10) {
                ForEach(BlindBox.Span.allCases) { option in
                    let selected = option == span
                    Button {
                        withAnimation(.snappy) { span = option; nothing = nil }
                    } label: {
                        HStack(spacing: 10) {
                            Image(systemName: option.symbol).font(.body)
                                .foregroundStyle(selected ? AnyShapeStyle(gold) : AnyShapeStyle(.white.opacity(0.55)))
                                .frame(width: 24)
                            VStack(alignment: .leading, spacing: 1) {
                                Text(verbatim: option.title).font(.subheadline.weight(.semibold)).foregroundStyle(.white)
                                    .lineLimit(1).minimumScaleFactor(0.75)
                                Text(verbatim: option.detail).font(.caption2).foregroundStyle(.white.opacity(selected ? 0.75 : 0.5))
                                    .lineLimit(1).minimumScaleFactor(0.8)
                            }
                            Spacer(minLength: 0)
                        }
                        .padding(.horizontal, 12).padding(.vertical, 11)
                        .background { choice(selected, in: RoundedRectangle(cornerRadius: 16, style: .continuous)) }
                    }
                    .buttonStyle(PressableStyle())
                    .accessibilityAddTraits(selected ? .isSelected : [])
                }
            }
        }
        .sensoryFeedback(.selection, trigger: span)
    }

    private var moodPicker: some View {
        VStack(alignment: .leading, spacing: 10) {
            section("想要什么感觉")
            WrappingLayout(spacing: 8) {
                ForEach(BlindBox.Mood.allCases) { option in
                    let selected = option == mood
                    Button {
                        withAnimation(.snappy) { moodRaw = option.rawValue; nothing = nil }
                    } label: {
                        Label {
                            Text(verbatim: option.title).foregroundStyle(.white)
                        } icon: {
                            Image(systemName: option.symbol)
                                .foregroundStyle(selected ? AnyShapeStyle(gold) : AnyShapeStyle(.white.opacity(0.55)))
                        }
                        .font(.subheadline.weight(.medium))
                        .padding(.horizontal, 13).padding(.vertical, 8)
                        .background { choice(selected, in: Capsule()) }
                    }
                    .buttonStyle(.plain)
                    .accessibilityAddTraits(selected ? .isSelected : [])
                }
            }
        }
        .sensoryFeedback(.selection, trigger: moodRaw)
    }

    private var box: some View {
        let canOpen = store.remainingToday > 0
        return VStack(spacing: 14) {
            ZStack {
                // How far the hold has got, drawn round the box.
                Circle().strokeBorder(.white.opacity(0.06), lineWidth: 1).frame(width: 214, height: 214)
                Circle()
                    .trim(from: 0, to: holdProgress)
                    .stroke(gold, style: StrokeStyle(lineWidth: 3, lineCap: .round))
                    .rotationEffect(.degrees(-90))
                    .frame(width: 211, height: 211)
                    .opacity(phase == .choosing ? 1 : 0)
                Ellipse()
                    .fill(.black.opacity(0.45))
                    .frame(width: floating ? 120 : 140, height: 16)
                    .blur(radius: 7)
                    .offset(y: 92)
                TimelineView(.animation(paused: holdStart == nil && phase != .opening)) { timeline in
                    let amount = shake(at: timeline.date)
                    MysteryBox(open: lidOpen, glow: phase == .opening ? 1 : max(amount, 0.25))
                        .rotationEffect(.degrees(reduceMotion ? 0 : sin(timeline.date.timeIntervalSinceReferenceDate * 48) * amount * 5))
                        .scaleEffect(1 + amount * 0.06)
                }
                .offset(y: floating && holdStart == nil && phase == .choosing ? -8 : 0)
            }
            .frame(height: 224)
            .onAppear {
                guard !reduceMotion else { return }
                withAnimation(.easeInOut(duration: 2.2).repeatForever(autoreverses: true)) { floating = true }
            }
            .contentShape(.rect)
            .holdToLight(isLit: !canOpen || phase != .choosing, progress: $holdProgress, duration: Self.holdDuration) { open() }
            .onChange(of: holdProgress) { holdStart = holdProgress > 0 ? (holdStart ?? .now) : nil }
            .accessibilityElement()
            .accessibilityLabel(Text("盲盒"))
            .accessibilityHint(Text("长按拆开"))
            .accessibilityAddTraits(.isButton)
            .accessibilityAction { if canOpen, phase == .choosing { open() } }

            if let nothing {
                Text(nothing).font(.subheadline).foregroundStyle(.white.opacity(0.85)).multilineTextAlignment(.center)
                    .padding(.horizontal, 18).padding(.vertical, 12)
                    .background(.white.opacity(0.07), in: .rect(cornerRadius: 16, style: .continuous))
            } else if phase == .opening {
                Text("正在替你想…").font(.subheadline).foregroundStyle(.white.opacity(0.7))
            } else if canOpen {
                VStack(spacing: 10) {
                    Label("长按拆开", systemImage: "hand.tap.fill")
                        .font(.subheadline.weight(.semibold)).foregroundStyle(.white)
                        .padding(.horizontal, 16).padding(.vertical, 9)
                        .background(.white.opacity(0.1), in: .capsule)
                        .overlay(Capsule().strokeBorder(.white.opacity(0.1), lineWidth: 1))
                    HStack(spacing: 6) {
                        ForEach(0..<BlindBoxStore.dailyLimit, id: \.self) { index in
                            Capsule()
                                .fill(index < store.remainingToday ? AnyShapeStyle(gold) : AnyShapeStyle(.white.opacity(0.15)))
                                .frame(width: 16, height: 4)
                        }
                        Text("今天还能拆 \(store.remainingToday) 次")
                            .font(.caption).foregroundStyle(.white.opacity(0.55)).monospacedDigit()
                            .padding(.leading, 4)
                    }
                }
            } else {
                VStack(spacing: 4) {
                    Image(systemName: "moon.stars.fill").font(.title3).foregroundStyle(gold)
                    Text("今天的盒子拆完了，明天再来").font(.subheadline).foregroundStyle(.white.opacity(0.75))
                }
            }
        }
    }

    private func shake(at date: Date) -> Double {
        guard let holdStart else { return 0 }
        return min(max(date.timeIntervalSince(holdStart) / Self.holdDuration, 0), 1)
    }

    /// Thinks, then the lid goes and the ticket comes out sealed, then turns over.
    private func open() {
        guard phase == .choosing, store.remainingToday > 0 else { return }
        nothing = nil
        phase = .opening
        holdStart = nil
        UIImpactFeedbackGenerator(style: .heavy).impactOccurred()
        withAnimation(.spring(response: 0.55, dampingFraction: 0.72)) { lidOpen = 1 }
        Task { @MainActor in
            await progress.update(from: summaries.stays)
            let context = BlindBoxPlanner.context(visited: Set(progress.firstVisits.keys))
            here = context.here
            guard let draw = await bestDraw(context) else {
                withAnimation(.smooth) {
                    lidOpen = 0
                    holdProgress = 0
                    phase = .choosing
                    nothing = span == .day ? "这附近一天能到的地方，暂时没找到。换个长一点的时间试试。"
                                           : "两百处地方，你都走到了。接下来的路，你自己定。"
                }
                return
            }
            try? await Task.sleep(for: .seconds(0.5))
            store.record(draw)
            flipped = false
            withAnimation(.spring(response: 0.6, dampingFraction: 0.85)) {
                holdProgress = 0
                phase = .revealed(draw)
            }
            try? await Task.sleep(for: .seconds(0.7))
            UINotificationFeedbackGenerator().notificationOccurred(.success)
            if !reduceMotion { burst = .now }
            withAnimation(reduceMotion ? .easeInOut(duration: 0.2) : .spring(response: 0.75, dampingFraction: 0.78)) { flipped = true }
        }
    }

    /// A day out that turns out to be over three hours' drive isn't one: try for a closer one.
    private func bestDraw(_ context: BlindBox.Context) async -> BlindBox.Draw? {
        var generator = SystemRandomNumberGenerator()
        guard span == .day else { return BlindBox.draw(span: span, mood: mood, context: context, using: &generator) }
        guard let here = context.here else { return nil }
        var nearby = await BlindBoxPlanner.nearby(around: here, mood: mood)
        // Asking for a day's worth of a thing the area hasn't got: take anything worth the trip.
        if nearby.isEmpty, mood != .any { nearby = await BlindBoxPlanner.nearby(around: here, mood: .any) }
        for _ in 0..<3 {
            guard let draw = BlindBox.draw(span: .day, mood: mood, context: context, nearby: nearby, using: &generator) else { return nil }
            guard let drive = await BlindBoxPlanner.drive(from: here, to: draw.place), drive > 3 * 3600 else { return draw }
            nearby.removeAll { $0.id == draw.id }
        }
        return BlindBox.draw(span: .day, mood: mood, context: context, nearby: nearby, using: &generator)
    }

    // MARK: Revealed

    private func revealed(_ draw: BlindBox.Draw) -> some View {
        VStack(spacing: 18) {
            sealable(draw)
            if flipped {
                Group {
                    BlindBoxPlanView(draw: draw, here: here)
                    decision(draw)
                    footnote(draw)
                }
                .transition(.opacity.combined(with: .move(edge: .bottom)))
            }
        }
        .padding(.top, 8)
    }

    /// The back of the ticket, then the front, turning over like a card.
    private func sealable(_ draw: BlindBox.Draw) -> some View {
        ZStack {
            BoardingPass(draw: draw, from: startCity)
                .opacity(flipped ? 1 : 0)
                .rotation3DEffect(.degrees(flipped ? 0 : -180), axis: (0, 1, 0), perspective: 0.5)
            sealed
                .opacity(flipped ? 0 : 1)
                .rotation3DEffect(.degrees(flipped ? 180 : 0), axis: (0, 1, 0), perspective: 0.5)
        }
        .overlay {
            if let burst { RevealBurst(start: burst).padding(-60) }
        }
    }

    /// The back of the ticket: same notches, a starry envelope, nothing given away.
    private var sealed: some View {
        LinearGradient(colors: [Color(red: 0.32, green: 0.23, blue: 0.60), Color(red: 0.12, green: 0.10, blue: 0.30)], startPoint: .topLeading, endPoint: .bottomTrailing)
            .frame(height: 400)
            .overlay {
                VStack(spacing: 14) {
                    Image(systemName: "sparkle").font(.system(size: 54, weight: .bold)).foregroundStyle(gold)
                    Text(verbatim: "WAYTRACE").font(.caption.weight(.heavy)).tracking(5).foregroundStyle(.white.opacity(0.7))
                    Text(verbatim: "BOARDING PASS").font(.caption2.weight(.semibold)).tracking(3).foregroundStyle(.white.opacity(0.4))
                }
            }
            .overlay(alignment: .bottom) {
                Rectangle().fill(.white.opacity(0.18)).frame(height: 1).padding(.horizontal, 18).padding(.bottom, 138)
            }
            .clipShape(BoardingPassShape(tear: 262), style: FillStyle(eoFill: true))
    }

    private func decision(_ draw: BlindBox.Draw) -> some View {
        let left = store.remainingToday
        return VStack(spacing: 10) {
            Button {
                if store.keep() != nil {
                    UINotificationFeedbackGenerator().notificationOccurred(.success)
                    withAnimation(.spring(response: 0.55, dampingFraction: 0.82)) { phase = .kept(draw) }
                }
            } label: {
                Text("收下这张登机牌").font(.headline).foregroundStyle(.black)
                    .frame(maxWidth: .infinity).frame(height: 54)
                    .background(gold, in: .capsule)
            }
            .buttonStyle(PressableStyle())
            HStack(spacing: 10) {
                if let must = draw.place.mustSee {
                    NavigationLink { MustSeePlaceView(place: must) } label: { secondary("看看这里", "info.circle") }
                } else {
                    Button { BlindBoxView.directions(to: draw.place) } label: { secondary("导航过去", "arrow.triangle.turn.up.right.diamond") }
                }
                Button {
                    store.putBack()
                    lidOpen = 0
                    holdProgress = 0
                    burst = nil
                    withAnimation(.smooth) { phase = .choosing }
                } label: {
                    if left > 0 {
                        secondary("再抽一次（还有 \(left) 次）", "arrow.clockwise")
                    } else {
                        secondary("放回去", "arrow.uturn.backward")
                    }
                }
            }
            .buttonStyle(PressableStyle())
        }
    }

    private func secondary(_ title: LocalizedStringKey, _ symbol: String) -> some View {
        Label(title, systemImage: symbol)
            .font(.subheadline.weight(.semibold)).foregroundStyle(.white)
            .lineLimit(1).minimumScaleFactor(0.7)
            .padding(.horizontal, 10)
            .frame(maxWidth: .infinity).frame(height: 48)
            .background(.white.opacity(0.08), in: .capsule)
            .overlay(Capsule().strokeBorder(.white.opacity(0.1), lineWidth: 1))
    }

    /// Entry rules only when there's a border to cross from where the person is.
    private func crossesBorder(_ draw: BlindBox.Draw) -> Bool {
        let there = BlindBox.countries(of: draw.place)
        guard !there.isEmpty else { return false }
        guard let home = summaries.stays.first(where: { !$0.isFromPhotos })?.countryCode ?? summaries.home?.countryCode else { return true }
        return !there.contains(home)
    }

    private func footnote(_ draw: BlindBox.Draw) -> some View {
        VStack(spacing: 6) {
            if let id = draw.place.mustSeeID, let credit = MustSeePhotos.credit(id) {
                Link(destination: credit.page) {
                    Text("封面照片：\(credit.artist)，\(credit.license)，来自 Wikimedia Commons")
                }
                .font(.caption2).foregroundStyle(.white.opacity(0.4))
            }
            if crossesBorder(draw) {
                Text("出发前，请查看当地的入境要求、天气和安全提示。")
                    .font(.caption2).foregroundStyle(.white.opacity(0.4))
            } else {
                Text("出发前，看一眼当地的天气和开放时间。")
                    .font(.caption2).foregroundStyle(.white.opacity(0.4))
            }
        }
        .multilineTextAlignment(.center)
    }

    /// Apple Maps, with the route from here already asked for.
    static func directions(to place: BlindBox.Place) {
        let coordinate = place.mapCoordinate
        let item = MKMapItem(location: CLLocation(latitude: coordinate.latitude, longitude: coordinate.longitude), address: nil)
        item.name = place.localizedName
        item.openInMaps(launchOptions: [MKLaunchOptionsDirectionsModeKey: MKLaunchOptionsDirectionsModeDefault])
    }

    // MARK: Kept

    private func kept(_ draw: BlindBox.Draw) -> some View {
        VStack(spacing: 20) {
            BoardingPass(draw: draw, from: startCity)
                .scaleEffect(0.86)
                .padding(.vertical, -24)
            VStack(spacing: 8) {
                Image(systemName: "checkmark.seal.fill")
                    .font(.system(size: 34)).foregroundStyle(gold)
                    .symbolEffect(.bounce, options: .nonRepeating, value: draw.id)
                Text("收好了").font(.system(.title2, design: .serif, weight: .bold)).foregroundStyle(.white)
                Text("它不会过期，也不会催你。\n等你真的走到那里，漫迹会认出来。")
                    .font(.subheadline).foregroundStyle(.white.opacity(0.75))
                    .multilineTextAlignment(.center)
                if draw.place.mustSee != nil {
                    Label("也放进了此生必去的“想去”", systemImage: "heart.fill")
                        .font(.caption.weight(.medium)).foregroundStyle(amber)
                        .padding(.top, 4)
                }
            }
            HStack(spacing: 10) {
                Button { BlindBoxView.directions(to: draw.place) } label: { secondary("导航过去", "arrow.triangle.turn.up.right.diamond") }
                Button {
                    lidOpen = 0
                    holdProgress = 0
                    burst = nil
                    withAnimation(.smooth) { phase = .choosing }
                } label: { secondary("好", "checkmark") }
            }
            .buttonStyle(PressableStyle())
        }
        .padding(.top, 8)
    }

    // MARK: Kept tickets

    private var ticketList: some View {
        VStack(alignment: .leading, spacing: 14) {
            Text("你的登机牌").font(.system(.title3, design: .serif, weight: .bold)).foregroundStyle(.white)
            if !store.waiting.isEmpty { tickets(store.waiting, title: "在等你") }
            if !store.arrived.isEmpty { tickets(store.arrived, title: "已经到了") }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(.top, 10)
    }

    private func tickets(_ list: [BlindBox.Ticket], title: LocalizedStringKey) -> some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack(spacing: 6) {
                section(title)
                Text(verbatim: "\(list.count)").font(.caption2.weight(.bold)).foregroundStyle(.white.opacity(0.5))
                    .padding(.horizontal, 6).padding(.vertical, 1)
                    .background(.white.opacity(0.1), in: .capsule)
            }
            VStack(spacing: 0) {
                ForEach(list) { ticket in
                    Button { viewing = ticket } label: { ticketRow(ticket) }
                        .buttonStyle(.plain)
                    if ticket.id != list.last?.id { Divider().overlay(.white.opacity(0.06)).padding(.leading, 82) }
                }
            }
            .background(.white.opacity(0.07), in: .rect(cornerRadius: 22, style: .continuous))
            .overlay(RoundedRectangle(cornerRadius: 22, style: .continuous).strokeBorder(.white.opacity(0.08), lineWidth: 1))
        }
    }

    private func ticketRow(_ ticket: BlindBox.Ticket) -> some View {
        let place = ticket.draw.place
        return HStack(spacing: 14) {
            if let must = place.mustSee {
                MustSeeThumb(place: must, lit: ticket.arrived != nil)
            } else {
                Image(systemName: place.placeKind.symbol)
                    .foregroundStyle(gold)
                    .frame(width: 54, height: 54)
                    .background(.white.opacity(0.1), in: .rect(cornerRadius: 12, style: .continuous))
            }
            VStack(alignment: .leading, spacing: 3) {
                Text(verbatim: place.localizedName).font(.body.weight(.semibold)).foregroundStyle(.white)
                Label(ticket.draw.span.title, systemImage: ticket.draw.span.symbol)
                    .font(.caption2.weight(.semibold)).foregroundStyle(.white.opacity(0.5))
                Text(verbatim: status(ticket)).font(.caption).foregroundStyle(ticket.arrived != nil ? AnyShapeStyle(gold) : AnyShapeStyle(.white.opacity(0.65)))
            }
            Spacer(minLength: 0)
            Image(systemName: "chevron.forward").font(.footnote.weight(.semibold)).foregroundStyle(.white.opacity(0.35))
        }
        .padding(.horizontal, 14).padding(.vertical, 10)
        .contentShape(.rect)
    }

    private func status(_ ticket: BlindBox.Ticket) -> String {
        if let arrived = ticket.arrived {
            let days = BlindBoxDays.between(ticket.kept, arrived)
            return days == 0 ? String(localized: "当天就到了", bundle: .appLanguage) : String(localized: "\(days) 天后，你到了这里", bundle: .appLanguage)
        }
        let days = BlindBoxDays.between(ticket.kept, .now)
        return days == 0 ? String(localized: "今天收下的", bundle: .appLanguage) : String(localized: "还在等你 · 收下 \(days) 天了", bundle: .appLanguage)
    }
}

enum BlindBoxDays {
    static func between(_ start: Date, _ end: Date) -> Int {
        let calendar = Calendar.current
        return calendar.dateComponents([.day], from: calendar.startOfDay(for: start), to: calendar.startOfDay(for: end)).day ?? 0
    }
}

/// One kept ticket, up close.
private struct TicketSheet: View {
    let ticket: BlindBox.Ticket
    let here: CLLocation?
    @Environment(\.dismiss) private var dismiss
    @State private var confirming = false

    private var place: BlindBox.Place { ticket.draw.place }

    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(spacing: 18) {
                    BoardingPass(draw: ticket.draw, arrived: ticket.arrived)
                    if ticket.arrived == nil {
                        Button { BlindBoxView.directions(to: place) } label: {
                            Label("导航过去", systemImage: "arrow.triangle.turn.up.right.diamond.fill")
                                .font(.headline).foregroundStyle(night)
                                .frame(maxWidth: .infinity).frame(height: 54)
                                .background(gold, in: .capsule)
                        }
                        .buttonStyle(PressableStyle())
                    }
                    HStack(spacing: 10) {
                        if let must = place.mustSee {
                            NavigationLink { MustSeePlaceView(place: must) } label: { action("看看这里", "info.circle") }
                        } else if ticket.arrived != nil {
                            Button { BlindBoxView.directions(to: place) } label: { action("在地图里看看", "map") }
                        }
                        if ticket.arrived == nil {
                            Button { confirming = true } label: { action("撕掉这张", "scissors") }
                        }
                    }
                    .buttonStyle(PressableStyle())
                    if ticket.arrived == nil { BlindBoxPlanView(draw: ticket.draw, here: here) }
                }
                .padding()
            }
            .background { BlindBoxSky(glow: 0.2) }
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("关闭", systemImage: "xmark") { dismiss() }
                }
            }
            .confirmationDialog("撕掉这张登机牌？", isPresented: $confirming, titleVisibility: .visible) {
                Button("撕掉", role: .destructive) {
                    BlindBoxStore.shared.remove(ticket)
                    dismiss()
                }
            } message: {
                Text("没关系，想去的心情可以变。")
            }
        }
        .environment(\.colorScheme, .dark)
    }

    private func action(_ title: LocalizedStringKey, _ symbol: String) -> some View {
        Label(title, systemImage: symbol)
            .font(.subheadline.weight(.semibold)).foregroundStyle(.white)
            .frame(maxWidth: .infinity).frame(height: 48)
            .background(.white.opacity(0.08), in: .capsule)
            .overlay(Capsule().strokeBorder(.white.opacity(0.1), lineWidth: 1))
    }
}

// MARK: - The way in

/// On the Places tab.
struct BlindBoxCard: View {
    private var store = BlindBoxStore.shared

    var body: some View {
        HStack(spacing: 16) {
            MysteryBox(open: 0, glow: 0.2)
                .scaleEffect(0.42)
                .frame(width: 84, height: 84)
            VStack(alignment: .leading, spacing: 3) {
                Text("旅行盲盒").font(.title3.bold()).foregroundStyle(.white)
                if store.waiting.isEmpty {
                    Text("不知道去哪儿？这次让它替你选。").font(.subheadline).foregroundStyle(.white.opacity(0.75))
                } else {
                    Text("有 \(store.waiting.count) 张登机牌在等你").font(.subheadline).foregroundStyle(.white.opacity(0.75))
                }
            }
            Spacer(minLength: 0)
            Image(systemName: "chevron.forward").font(.footnote.weight(.semibold)).foregroundStyle(.white.opacity(0.5))
        }
        .padding(.horizontal, 14).padding(.vertical, 10)
        .background(
            LinearGradient(colors: [Color(red: 0.42, green: 0.20, blue: 0.40), Color(red: 0.78, green: 0.38, blue: 0.28)], startPoint: .topLeading, endPoint: .bottomTrailing),
            in: .rect(cornerRadius: 26, style: .continuous)
        )
    }
}

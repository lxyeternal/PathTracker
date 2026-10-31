import Foundation
import CoreLocation

/// Where the person lives, as the history tells it: the place they called home, or else the
/// place they spent the most time at.
struct HomeBase: Sendable {
    let latitude: Double
    let longitude: Double
    let countryCode: String?
    let city: String?

    var location: CLLocation { CLLocation(latitude: latitude, longitude: longitude) }

    /// Home's city under the same name `CityNames.canonical` gives the stays, so "Shanghai"
    /// and "上海" are the same place when they're compared.
    func cityName(in names: [String: String]) -> String? {
        city.map { names["\(countryCode ?? "")|\($0)"] ?? $0 }
    }

    static func find(in stays: [Stay]) -> HomeBase? {
        if let home = stays.first(where: { $0.categoryRaw == "home" }) {
            return HomeBase(latitude: home.latitude, longitude: home.longitude, countryCode: home.countryCode, city: home.city)
        }
        // ~200 m cells, weighted by time spent; photo visits have no length and don't count.
        var time: [Int64: (TimeInterval, Stay)] = [:]
        for stay in stays where !stay.isFromPhotos {
            let key = Int64((stay.latitude / 0.002).rounded(.down)) &* 1_000_003 &+ Int64((stay.longitude / 0.002).rounded(.down))
            let duration = min(stay.duration, 3 * 86_400)
            time[key] = ((time[key]?.0 ?? 0) + duration, time[key]?.1 ?? stay)
        }
        guard let best = time.values.max(by: { $0.0 < $1.0 })?.1 else { return nil }
        return HomeBase(latitude: best.latitude, longitude: best.longitude, countryCode: best.countryCode, city: best.city)
    }
}

// MARK: Firsts

/// A first in the person's life as the app has seen it: the first time abroad, the first night
/// away, the first time in a city or at a place worth a lifetime.
struct LifeFirst: Identifiable, Sendable {
    enum Kind: String, Sendable {
        case beginning, abroad, country, city, mustSee, flight, longWalk, lateNight, nightAway

        var symbol: String {
            switch self {
            case .beginning: "sparkles"
            case .abroad: "airplane.departure"
            case .country: "flag.fill"
            case .city: "building.2.fill"
            case .mustSee: "star.fill"
            case .flight: "airplane"
            case .longWalk: "figure.walk"
            case .lateNight: "moon.stars.fill"
            case .nightAway: "bed.double.fill"
            }
        }
    }

    let kind: Kind
    let date: Date
    let title: String
    let place: String?
    /// For a place worth a lifetime, which one, for its photograph.
    var mustSeeID: String? = nil
    var id: String { "\(kind.rawValue)|\(title)|\(date.timeIntervalSince1970)" }
}

/// The furthest places in each direction, and from home.
struct LifeExtremes: Sendable {
    struct Point: Sendable {
        let name: String
        /// The country, with its flag.
        let detail: String
        let latitude: Double
        let longitude: Double
        let date: Date
        var coordinate: CLLocationCoordinate2D { CLLocationCoordinate2D(latitude: latitude, longitude: longitude) }
    }

    var north: Point?
    var south: Point?
    var east: Point?
    var west: Point?
    var farthest: Point?
    var farthestDistance: Double = 0
}

enum LifeFirsts {
    /// `country` is the person's own: going anywhere else is going abroad.
    static func find(stays: [Stay], chunks: [TrackChunk], home: HomeBase?, country: String?) -> (firsts: [LifeFirst], extremes: LifeExtremes) {
        let ordered = stays.sorted { $0.arrival < $1.arrival }
        var firsts: [LifeFirst] = []
        var extremes = LifeExtremes()
        guard let first = ordered.first else { return ([], extremes) }
        let calendar = Calendar.current
        func name(_ stay: Stay) -> String { [stay.displayName, stay.city].compactMap { $0 }.removingDuplicates().joined(separator: " · ") }

        firsts.append(LifeFirst(kind: .beginning, date: first.arrival,
                                title: String(localized: "故事从这里开始", bundle: .appLanguage), place: name(first)))

        // Countries and cities, in the order they first happened.
        let homeCountry = country ?? home?.countryCode
        var countries = Set<String>(), cities = Set<String>()
        var wentAbroad = false
        let cityNames = CityNames.canonical(for: stays)
        let homeCity = home?.cityName(in: cityNames)
        for stay in ordered {
            if let code = stay.countryCode, countries.insert(code).inserted, code != homeCountry, homeCountry != nil {
                let country = appLocale.localizedString(forRegionCode: code) ?? stay.country ?? code
                let title = wentAbroad
                    ? String(localized: "第一次到\(country)", bundle: .appLanguage)
                    : String(localized: "第一次出国，去了\(country)", bundle: .appLanguage)
                firsts.append(LifeFirst(kind: wentAbroad ? .country : .abroad, date: stay.arrival, title: title, place: stay.city))
                wentAbroad = true
            }
            if let key = CityNames.key(stay), let city = cityNames[key], city != homeCity,
               cities.insert("\(stay.countryCode ?? "")|\(city)").inserted, stay.countryCode == homeCountry || homeCountry == nil {
                firsts.append(LifeFirst(kind: .city, date: stay.arrival,
                                        title: String(localized: "第一次到\(city)", bundle: .appLanguage), place: nil))
            }
        }

        // Places worth a lifetime.
        let visits = stays.map { MustSee.Visit(latitude: $0.latitude, longitude: $0.longitude, arrival: $0.arrival, countryCode: $0.countryCode) }
        let places = MustSee.china + MustSee.world
        for (id, date) in MustSee.firstVisits(places, visits: visits) {
            guard let place = places.first(where: { $0.id == id }) else { continue }
            firsts.append(LifeFirst(kind: .mustSee, date: date,
                                    title: String(localized: "第一次到\(place.localizedName)", bundle: .appLanguage),
                                    place: place.localizedRegion, mustSeeID: place.id))
        }

        // Moving: the first flight, the first long walk, the first time out in the small hours.
        let byDate = chunks.sorted { $0.startDate < $1.startDate }
        if let flight = byDate.first(where: { $0.mode == .flying }) {
            let km = Int(flight.distance / 1000).formatted(.number.locale(appLocale))
            firsts.append(LifeFirst(kind: .flight, date: flight.startDate,
                                    title: String(localized: "记下的第一段飞行", bundle: .appLanguage),
                                    place: String(localized: "飞了 \(km) 公里", bundle: .appLanguage)))
        }
        var onFoot: [Date: Double] = [:]
        for chunk in byDate where chunk.mode == .walking || chunk.mode == .running {
            onFoot[calendar.startOfDay(for: chunk.startDate), default: 0] += chunk.distance
        }
        for threshold in [10, 20] {
            if let day = onFoot.filter({ $0.value >= Double(threshold) * 1000 }).keys.min() {
                firsts.append(LifeFirst(kind: .longWalk, date: day,
                                        title: String(localized: "第一次一天走了 \(threshold) 公里", bundle: .appLanguage), place: nil))
            }
        }
        if let late = byDate.first(where: { $0.mode != .flying && (1..<4).contains(calendar.component(.hour, from: $0.startDate)) }) {
            let hour = calendar.component(.hour, from: late.startDate)
            firsts.append(LifeFirst(kind: .lateNight, date: late.startDate,
                                    title: String(localized: "第一次凌晨 \(hour) 点还在路上", bundle: .appLanguage), place: nil))
        }
        if let home {
            let away = ordered.first { stay in
                guard !stay.isFromPhotos, let departure = stay.departure, stay.location.distance(from: home.location) > 30_000 else { return false }
                guard let three = calendar.date(bySettingHour: 3, minute: 0, second: 0, of: stay.arrival) else { return false }
                let night = three > stay.arrival ? three : three.addingTimeInterval(86_400)
                return departure > night
            }
            if let away {
                firsts.append(LifeFirst(kind: .nightAway, date: away.arrival,
                                        title: String(localized: "第一次在外过夜", bundle: .appLanguage), place: name(away)))
            }
        }

        // The ends of the map.
        // A sight by its name, anywhere else by its town: a street number says nothing here.
        func point(_ stay: Stay) -> LifeExtremes.Point {
            let title = (stay.isLandmark ? stay.placeName : nil) ?? stay.customName ?? stay.city ?? stay.displayName
            let country = stay.countryCode.map { appLocale.localizedString(forRegionCode: $0) ?? $0 } ?? stay.country ?? ""
            return LifeExtremes.Point(name: title, detail: "\(String.flag(for: stay.countryCode)) \(country)".trimmingCharacters(in: .whitespaces),
                                      latitude: stay.latitude, longitude: stay.longitude, date: stay.arrival)
        }
        if let s = stays.max(by: { $0.latitude < $1.latitude }) { extremes.north = point(s) }
        if let s = stays.min(by: { $0.latitude < $1.latitude }) { extremes.south = point(s) }
        if let s = stays.max(by: { $0.longitude < $1.longitude }) { extremes.east = point(s) }
        if let s = stays.min(by: { $0.longitude < $1.longitude }) { extremes.west = point(s) }
        if let home, let far = stays.max(by: { $0.location.distance(from: home.location) < $1.location.distance(from: home.location) }) {
            extremes.farthest = point(far)
            extremes.farthestDistance = far.location.distance(from: home.location)
        }
        return (firsts.sorted { $0.date < $1.date }, extremes)
    }
}

// MARK: Portrait

/// What kind of traveller the past year says the person is, with the numbers behind it.
struct TravellerPortrait: Sendable {
    enum Archetype: String, CaseIterable, Sendable {
        case nightWalker, earlyRiser, cityCollector, globetrotter, explorer, homebody, rider, wanderer, commuter, slowWalker

        var title: String {
            switch self {
            case .nightWalker: String(localized: "夜行的散步者", bundle: .appLanguage)
            case .earlyRiser: String(localized: "早起的人", bundle: .appLanguage)
            case .cityCollector: String(localized: "城市收藏家", bundle: .appLanguage)
            case .globetrotter: String(localized: "世界旅人", bundle: .appLanguage)
            case .explorer: String(localized: "好奇的探索者", bundle: .appLanguage)
            case .homebody: String(localized: "恋家的人", bundle: .appLanguage)
            case .rider: String(localized: "风一样的骑行者", bundle: .appLanguage)
            case .wanderer: String(localized: "用双脚丈量的人", bundle: .appLanguage)
            case .commuter: String(localized: "城市的通勤者", bundle: .appLanguage)
            case .slowWalker: String(localized: "慢慢走的人", bundle: .appLanguage)
            }
        }

        var symbol: String {
            switch self {
            case .nightWalker: "moon.stars.fill"
            case .earlyRiser: "sunrise.fill"
            case .cityCollector: "building.2.crop.circle.fill"
            case .globetrotter: "globe.asia.australia.fill"
            case .explorer: "binoculars.fill"
            case .homebody: "house.fill"
            case .rider: "bicycle"
            case .wanderer: "figure.walk"
            case .commuter: "tram.fill"
            case .slowWalker: "leaf.fill"
            }
        }

        /// Gradient for the card, top to bottom.
        var colors: [(Double, Double, Double)] {
            switch self {
            case .nightWalker: [(0.16, 0.14, 0.42), (0.45, 0.28, 0.66)]
            case .earlyRiser: [(1.0, 0.62, 0.38), (1.0, 0.84, 0.55)]
            case .cityCollector: [(0.36, 0.30, 0.86), (0.62, 0.52, 1.0)]
            case .globetrotter: [(0.05, 0.42, 0.78), (0.32, 0.74, 0.95)]
            case .explorer: [(0.09, 0.55, 0.45), (0.45, 0.82, 0.6)]
            case .homebody: [(0.85, 0.42, 0.35), (1.0, 0.72, 0.55)]
            case .rider: [(0.0, 0.55, 0.62), (0.32, 0.86, 0.80)]
            case .wanderer: [(0.18, 0.55, 0.28), (0.55, 0.82, 0.42)]
            case .commuter: [(0.15, 0.32, 0.62), (0.42, 0.6, 0.9)]
            case .slowWalker: [(0.42, 0.5, 0.36), (0.72, 0.78, 0.58)]
            }
        }
    }

    /// Shares of the year's ground travel, 0…1.
    var night = 0.0
    var early = 0.0
    var onFoot = 0.0
    var cycling = 0.0
    var riding = 0.0
    /// Share of places first seen in the past three months.
    var newPlaces = 0.0
    /// Share of the past three months' time spent at home.
    var atHome = 0.0
    var cities = 0
    var countries = 0
    var distance = 0.0

    var ranked: [Archetype] {
        let scores: [(Archetype, Double)] = [
            (.nightWalker, night / 0.3), (.earlyRiser, early / 0.2), (.cityCollector, Double(cities) / 15),
            (.globetrotter, Double(countries) / 8), (.explorer, newPlaces / 0.4), (.homebody, atHome / 0.7),
            (.rider, cycling / 0.3), (.wanderer, onFoot / 0.5), (.commuter, riding / 0.65),
        ]
        let fitting = scores.filter { $0.1 >= 1 }.sorted { $0.1 > $1.1 }.map(\.0)
        return fitting.isEmpty ? [.slowWalker] : fitting
    }

    var archetype: Archetype { ranked[0] }
    var traits: [Archetype] { Array(ranked.dropFirst().prefix(2)) }

    /// One line on why, in the person's own numbers.
    var reason: String {
        func percent(_ value: Double) -> String { value.formatted(.percent.precision(.fractionLength(0)).locale(appLocale)) }
        return switch archetype {
        case .nightWalker: String(localized: "过去一年 \(percent(night)) 的路，是晚上九点以后走的。", bundle: .appLanguage)
        case .earlyRiser: String(localized: "过去一年 \(percent(early)) 的路，是早上八点以前走的。", bundle: .appLanguage)
        case .cityCollector: String(localized: "过去一年去了 \(cities) 座城市，每一座都留下了你的名字。", bundle: .appLanguage)
        case .globetrotter: String(localized: "过去一年走过 \(countries) 个国家和地区，世界在你脚下变小了。", bundle: .appLanguage)
        case .explorer: String(localized: "最近三个月去的地方，\(percent(newPlaces)) 是第一次去。", bundle: .appLanguage)
        case .homebody: String(localized: "最近三个月，\(percent(atHome)) 的时间在家。家是最好的地方。", bundle: .appLanguage)
        case .rider: String(localized: "过去一年 \(percent(cycling)) 的路是骑车走的，风一直在你身边。", bundle: .appLanguage)
        case .wanderer: String(localized: "过去一年 \(percent(onFoot)) 的路是一步一步走出来的。", bundle: .appLanguage)
        case .commuter: String(localized: "过去一年 \(percent(riding)) 的路在车上和地铁里，城市在窗外流过。", bundle: .appLanguage)
        case .slowWalker: String(localized: "不急不忙，每一段路都慢慢走。", bundle: .appLanguage)
        }
    }

    init() {}

    init(stays: [Stay], chunks: [TrackChunk], home: HomeBase?, now: Date = Date()) {
        let calendar = Calendar.current
        let yearAgo = now.addingTimeInterval(-365 * 86_400)
        let ground = chunks.filter { $0.startDate >= yearAgo && $0.mode != .flying }
        let total = ground.reduce(0) { $0 + $1.distance }
        distance = total
        if total > 0 {
            func share(_ include: (TrackChunk) -> Bool) -> Double { ground.filter(include).reduce(0) { $0 + $1.distance } / total }
            night = share { let h = calendar.component(.hour, from: $0.startDate); return h >= 21 || h < 4 }
            early = share { (4..<8).contains(calendar.component(.hour, from: $0.startDate)) }
            onFoot = share { $0.mode == .walking || $0.mode == .running }
            cycling = share { $0.mode == .cycling }
            riding = share { $0.mode == .automotive || $0.mode == .subway }
        }
        let year = stays.filter { $0.arrival >= yearAgo }
        let cityNames = CityNames.canonical(for: stays)
        cities = Set(year.compactMap { CityNames.key($0).flatMap { cityNames[$0] } }).count
        countries = Set(year.compactMap(\.countryCode)).count

        let quarterAgo = now.addingTimeInterval(-90 * 86_400)
        let recent = stays.filter { $0.arrival >= quarterAgo && !$0.isFromPhotos }
        if !recent.isEmpty {
            func cell(_ stay: Stay) -> Int64 {
                Int64((stay.latitude / 0.002).rounded(.down)) &* 1_000_003 &+ Int64((stay.longitude / 0.002).rounded(.down))
            }
            let before = Set(stays.filter { $0.arrival < quarterAgo }.map(cell))
            // Without history from before the past three months, everything looks new.
            if !before.isEmpty {
                let places = Set(recent.map(cell))
                newPlaces = Double(places.subtracting(before).count) / Double(places.count)
            }
            if let home {
                let time = recent.reduce(0) { $0 + min($1.duration, 3 * 86_400) }
                let homeTime = recent.filter { $0.location.distance(from: home.location) < 200 }.reduce(0) { $0 + min($1.duration, 3 * 86_400) }
                atHome = time > 0 ? homeTime / time : 0
            }
        }
    }
}

// MARK: Echoes

/// A quiet pattern in the person's life, said once: coming back to a city at the same time of
/// year, or a place they used to go to often and haven't for a while.
struct Echo: Identifiable, Sendable, Equatable {
    let id: String
    let title: String
    let detail: String
    let symbol: String
    /// A day to open for the memory behind it.
    let day: Date?
}

enum Echoes {
    static func find(stays: [Stay], home: HomeBase?, now: Date = Date()) -> [Echo] {
        var echoes: [Echo] = []
        let calendar = Calendar.current
        let cityNames = CityNames.canonical(for: stays)
        func city(_ stay: Stay) -> String? { CityNames.key(stay).flatMap { cityNames[$0] } ?? stay.city }

        // Back in a city at the same time of year.
        if let today = stays.first(where: { calendar.isDate($0.arrival, inSameDayAs: now) || ($0.departure == nil && !$0.isFromPhotos) }),
           let here = city(today), here != home?.cityName(in: cityNames) {
            let year = calendar.component(.year, from: now)
            var years: [Int] = []
            var memory: Date?
            for back in 1...20 {
                guard let then = calendar.date(byAdding: .year, value: -back, to: now) else { break }
                let window = DateInterval(start: then.addingTimeInterval(-20 * 86_400), end: then.addingTimeInterval(20 * 86_400))
                guard let visit = stays.first(where: { window.contains($0.arrival) && city($0) == here }) else { break }
                years.append(year - back)
                memory = memory ?? visit.arrival
            }
            if let memory, !years.isEmpty {
                let title = years.count == 1
                    ? String(localized: "去年的这个时候，你也在\(here)", bundle: .appLanguage)
                    : String(localized: "这是你连续第 \(years.count + 1) 年在这个时节来\(here)", bundle: .appLanguage)
                echoes.append(Echo(id: "return|\(here)|\(year)", title: title,
                                   detail: String(localized: "有些地方，会在每年差不多的时候把你叫回来。", bundle: .appLanguage),
                                   symbol: "arrow.trianglehead.2.clockwise.rotate.90", day: calendar.startOfDay(for: memory)))
            }
        }

        // A place often visited, then not for a while.
        func cell(_ stay: Stay) -> Int64 {
            Int64((stay.latitude / 0.002).rounded(.down)) &* 1_000_003 &+ Int64((stay.longitude / 0.002).rounded(.down))
        }
        var byPlace: [Int64: [Stay]] = [:]
        for stay in stays where !stay.isFromPhotos { byPlace[cell(stay), default: []].append(stay) }
        let candidates = byPlace.values.compactMap { visits -> (Stay, Int, Date)? in
            guard visits.count >= 6, let last = visits.map(\.arrival).max() else { return nil }
            let months = Set(visits.map { calendar.dateComponents([.year, .month], from: $0.arrival) })
            guard months.count >= 3, now.timeIntervalSince(last) > 90 * 86_400, now.timeIntervalSince(last) < 730 * 86_400 else { return nil }
            let place = visits.max { $0.arrival < $1.arrival }!
            if let home, place.location.distance(from: home.location) < 300 { return nil }
            return (place, visits.count, last)
        }
        if let (place, count, last) = candidates.max(by: { $0.1 < $1.1 }) {
            let months = max(3, calendar.dateComponents([.month], from: last, to: now).month ?? 3)
            let lastText = last.formatted(.dateTime.year().month().day().locale(appLocale))
            echoes.append(Echo(id: "absence|\(cell(place))|\(Int(last.timeIntervalSince1970))",
                               title: String(localized: "你已经 \(months) 个月没去\(place.displayName)了", bundle: .appLanguage),
                               detail: String(localized: "以前你常去，一共去过 \(count) 次。最后一次是 \(lastText)。", bundle: .appLanguage),
                               symbol: "hourglass", day: calendar.startOfDay(for: last)))
        }
        return echoes
    }
}

/// Decides which echo, if any, to say: at most one a week, each only once, gone once dismissed.
@MainActor
enum EchoSchedule {
    private static let currentKey = "echo.current", shownKey = "echo.shownAt", seenKey = "echo.seen"

    static func pick(from echoes: [Echo], now: Date = Date()) -> Echo? {
        let defaults = UserDefaults.standard
        let seen = Set(defaults.stringArray(forKey: seenKey) ?? [])
        let shownAt = defaults.object(forKey: shownKey) as? Date
        // Today's echo stays for the day until it's closed.
        if let current = defaults.string(forKey: currentKey), let shownAt, Calendar.current.isDate(shownAt, inSameDayAs: now) {
            return echoes.first { $0.id == current }
        }
        if let shownAt, now.timeIntervalSince(shownAt) < 7 * 86_400 { return nil }
        guard let echo = echoes.first(where: { !seen.contains($0.id) }) else { return nil }
        defaults.set(echo.id, forKey: currentKey)
        defaults.set(now, forKey: shownKey)
        defaults.set(Array(seen.union([echo.id])).suffix(200), forKey: seenKey)
        return echo
    }

    static func dismiss() {
        UserDefaults.standard.removeObject(forKey: currentKey)
    }
}

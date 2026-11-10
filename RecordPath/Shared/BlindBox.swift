import Foundation
import CoreLocation
import Observation

/// The travel blind box: for someone who knows where they've been and not where to go next.
/// It weighs how much time they have, how they want to feel, where they are, what their
/// footprints say they like and what they haven't seen, then gives one place and a true reason
/// for it. Everything is worked out on the device.
enum BlindBox {
    /// How much time there is, which decides how far the box may reach.
    enum Span: String, Codable, CaseIterable, Identifiable, Sendable {
        case day, weekend, holiday, long

        var id: String { rawValue }

        /// How far away the place may be, in kilometres, in a straight line.
        var range: ClosedRange<Double> {
            switch self {
            case .day: 10...150
            case .weekend: 60...700
            case .holiday: 200...2_500
            case .long: 800...25_000
            }
        }

        var days: Int {
            switch self {
            case .day: 1
            case .weekend: 2
            case .holiday: 4
            case .long: 7
            }
        }

        /// Other places to take in on the way, for the days there are.
        var stopCount: Int {
            switch self {
            case .day: 0
            case .weekend: 1
            case .holiday: 2
            case .long: 3
            }
        }

        /// How far from the main place the others may be, in kilometres.
        var stopReach: Double { self == .weekend ? 120 : 350 }

        var symbol: String {
            switch self {
            case .day: "sun.max.fill"
            case .weekend: "tent.fill"
            case .holiday: "suitcase.rolling.fill"
            case .long: "airplane"
            }
        }

        var title: String {
            switch self {
            case .day: String(localized: "周边一天", bundle: .appLanguage)
            case .weekend: String(localized: "一个周末", bundle: .appLanguage)
            case .holiday: String(localized: "小长假", bundle: .appLanguage)
            case .long: String(localized: "长假", bundle: .appLanguage)
            }
        }

        var detail: String {
            switch self {
            case .day: String(localized: "当天来回", bundle: .appLanguage)
            case .weekend: String(localized: "两天，不用走太远", bundle: .appLanguage)
            case .holiday: String(localized: "三到五天", bundle: .appLanguage)
            case .long: String(localized: "一周左右，走远一点", bundle: .appLanguage)
            }
        }
    }

    /// How the person wants the trip to feel.
    enum Mood: String, Codable, CaseIterable, Identifiable, Sendable {
        case any, quiet, climb, history, city

        var id: String { rawValue }

        var kinds: Set<MustSeePlace.Kind> {
            switch self {
            case .any: [.heritage, .mountain, .water, .city, .wild]
            case .quiet: [.water, .wild]
            case .climb: [.mountain, .wild]
            case .history: [.heritage]
            case .city: [.city]
            }
        }

        var symbol: String {
            switch self {
            case .any: "sparkles"
            case .quiet: "water.waves"
            case .climb: "mountain.2.fill"
            case .history: "building.columns.fill"
            case .city: "cup.and.saucer.fill"
            }
        }

        var title: String {
            switch self {
            case .any: String(localized: "都行", bundle: .appLanguage)
            case .quiet: String(localized: "放空", bundle: .appLanguage)
            case .climb: String(localized: "出点汗", bundle: .appLanguage)
            case .history: String(localized: "看老东西", bundle: .appLanguage)
            case .city: String(localized: "人间烟火", bundle: .appLanguage)
            }
        }
    }

    /// A place the box can give: one of the two hundred, or somewhere nearby from Apple Maps.
    struct Place: Codable, Hashable, Identifiable, Sendable {
        let id: String
        let name: String
        let region: String
        let latitude: Double
        let longitude: Double
        let kind: String
        var mustSeeID: String?
        /// How close a stay must be to count as having arrived, in kilometres.
        var radius = 1.5
        var countryCode: String?

        init(id: String, name: String, region: String, latitude: Double, longitude: Double, kind: MustSeePlace.Kind) {
            self.id = id
            self.name = name
            self.region = region
            self.latitude = latitude
            self.longitude = longitude
            self.kind = kind.rawValue
        }

        init(_ place: MustSeePlace) {
            self.init(id: place.id, name: place.name, region: place.region, latitude: place.latitude, longitude: place.longitude, kind: place.kind)
            mustSeeID = place.id
            radius = place.radius
            countryCode = place.countryCode
        }

        var mustSee: MustSeePlace? { mustSeeID.flatMap(BlindBox.mustSee(id:)) }
        var localizedName: String { mustSee?.localizedName ?? name }
        var localizedRegion: String { mustSee?.localizedRegion ?? region }
        var placeKind: MustSeePlace.Kind { MustSeePlace.Kind(rawValue: kind) ?? .wild }
        var location: CLLocation { CLLocation(latitude: latitude, longitude: longitude) }
        /// Results from Apple Maps are already map coordinates; the lists hold GPS ones.
        var mapCoordinate: CLLocationCoordinate2D {
            let coordinate = CLLocationCoordinate2D(latitude: latitude, longitude: longitude)
            return mustSeeID == nil ? coordinate : ChinaCoordinates.mapCoordinate(for: coordinate)
        }
    }

    /// Why this place. Always true of the person's own data, never a guess about them.
    enum Reason: Codable, Hashable, Sendable {
        case wished
        case visa(name: String, until: Date)
        case mood(Mood)
        case nearby(Double)
        case weekendAway(Double)
        case farther(Double)
        case newKind(String, lit: Int)
        case favourite(String)
        case untouchedRegion
        case none

        func text(for place: Place) -> String {
            switch self {
            case .wished:
                return String(localized: "这是你亲手收进想去清单的地方。它等你很久了。", bundle: .appLanguage)
            case let .visa(name, until):
                let year = until.formatted(.dateTime.year().locale(appLocale))
                return String(localized: "你的卡包里有一张\(name)签证，到\(year)都有效。别让它白白等着。", bundle: .appLanguage)
            case .mood(.quiet):
                return String(localized: "你说想放空。这里有足够大的风景，装得下你的心事。", bundle: .appLanguage)
            case .mood(.climb):
                return String(localized: "你说想出点汗。走到这里，脑子就安静了。", bundle: .appLanguage)
            case .mood(.history):
                return String(localized: "你想看老东西。这里的时间，比所有烦恼都长。", bundle: .appLanguage)
            case .mood(.city):
                return String(localized: "你想要点人间烟火。那就去热闹里走走。", bundle: .appLanguage)
            case .mood(.any):
                return String(localized: "你说都行。那这次，就听盲盒的。", bundle: .appLanguage)
            case let .nearby(metres):
                return String(localized: "离你只有 \(Format.distance(metres))，可你还从没来过。最近的远方，常常就在这里。", bundle: .appLanguage)
            case let .weekendAway(metres):
                return String(localized: "只有 \(Format.distance(metres))，一个周末刚刚好。", bundle: .appLanguage)
            case let .farther(metres):
                return String(localized: "这里比你到过最远的地方，还要再远 \(Format.distance(metres))。该刷新一下纪录了。", bundle: .appLanguage)
            case let .newKind(kind, lit):
                return Self.newKindText(MustSeePlace.Kind(rawValue: kind) ?? .wild, lit: lit)
            case let .favourite(kind):
                return Self.favouriteText(MustSeePlace.Kind(rawValue: kind) ?? .wild)
            case .untouchedRegion:
                let region = place.localizedRegion
                return String(localized: "\(region)的必去之地，你一处都还没点亮。就从这里开始吧。", bundle: .appLanguage)
            case .none:
                return String(localized: "没有理由。这就是盲盒。", bundle: .appLanguage)
            }
        }

        private static func newKindText(_ kind: MustSeePlace.Kind, lit: Int) -> String {
            switch kind {
            case .mountain: String(localized: "你点亮了 \(lit) 处地方，里面还没有一座山。", bundle: .appLanguage)
            case .water: String(localized: "你点亮了 \(lit) 处地方，里面还没有一片水。", bundle: .appLanguage)
            case .heritage: String(localized: "你点亮了 \(lit) 处地方，里面还没有一处古迹。", bundle: .appLanguage)
            case .city: String(localized: "你点亮了 \(lit) 处地方，里面还没有一座城。", bundle: .appLanguage)
            case .wild: String(localized: "你点亮了 \(lit) 处地方，里面还没有一片荒野。", bundle: .appLanguage)
            }
        }

        private static func favouriteText(_ kind: MustSeePlace.Kind) -> String {
            switch kind {
            case .mountain: String(localized: "你点亮最多的是山。这一座，大概也会喜欢你。", bundle: .appLanguage)
            case .water: String(localized: "你点亮最多的是水。这里的水，你应该也会喜欢。", bundle: .appLanguage)
            case .heritage: String(localized: "你点亮最多的是古迹。这一处，你应该也会喜欢。", bundle: .appLanguage)
            case .city: String(localized: "你点亮最多的是城市。这一座，你应该也会喜欢。", bundle: .appLanguage)
            case .wild: String(localized: "你点亮最多的是荒野。这一片，你应该也会喜欢。", bundle: .appLanguage)
            }
        }
    }

    /// What one opening gave.
    struct Draw: Codable, Hashable, Identifiable, Sendable {
        var id: String { place.id }
        let place: Place
        let reason: Reason
        let span: Span
        /// From where the person was, in metres; nil if that isn't known.
        let distance: Double?
        /// Must-see ids to take in on the way.
        var stops: [String] = []
    }

    /// A draw the person kept, waiting for them to get there.
    struct Ticket: Codable, Identifiable, Hashable, Sendable {
        var id: String { draw.place.id }
        let draw: Draw
        let kept: Date
        var arrived: Date?
    }

    /// What the box knows about the person when it opens.
    struct Context: Sendable {
        var visited: Set<String> = []
        var wishes: Set<String> = []
        /// Where the person is now, or home if that's all there is.
        var here: CLLocation?
        /// How far they have ever been from there, in metres.
        var farthest: Double = 0
        /// Countries with a visa valid for a while yet, and the name and end of that visa.
        var visas: [String: (name: String, until: Date)] = [:]
        /// Must-see places opened recently, not to be given again straight away.
        var recent: Set<String> = []

        func lit(_ kind: MustSeePlace.Kind) -> Int { litByKind[kind, default: 0] }
        var litTotal: Int { visited.count }
        var favourite: MustSeePlace.Kind? {
            let top = litByKind.max { $0.value < $1.value }
            return (top?.value ?? 0) >= 3 ? top?.key : nil
        }

        private var litByKind: [MustSeePlace.Kind: Int] {
            var counts: [MustSeePlace.Kind: Int] = [:]
            for id in visited { if let place = BlindBox.mustSee(id: id) { counts[place.kind, default: 0] += 1 } }
            return counts
        }
    }

    /// Places left out for now because going there would be unwise or impossible for most
    /// travellers, whatever a random draw says. They stay on the must-see lists.
    static let leftOut: Set<String> = ["jerusalem", "red-square", "baikal", "bagan"]

    nonisolated(unsafe) private static let byID: [String: MustSeePlace] = Dictionary((MustSee.china + MustSee.world).map { ($0.id, $0) }, uniquingKeysWith: { first, _ in first })

    static func mustSee(id: String) -> MustSeePlace? { byID[id] }

    /// The countries a place is in, from the list's English region ("Canada / United States").
    static func countries(of place: MustSeePlace) -> Set<String> {
        if let code = place.countryCode { return [code] }
        return Set(place.regionEn.components(separatedBy: " / ").compactMap { regionCodes[$0] })
    }

    /// The countries a ticket crosses into, for whether entry rules are worth a mention. Empty for
    /// somewhere nearby from Apple Maps, which is never more than a day away.
    static func countries(of place: Place) -> Set<String> {
        guard let must = place.mustSee else { return [] }
        guard MustSee.china.contains(where: { $0.id == must.id }) else { return countries(of: must) }
        return switch must.regionEn {
        case "Hong Kong": ["HK"]
        case "Macao": ["MO"]
        case "Taiwan": ["TW"]
        default: ["CN"]
        }
    }

    private static let regionCodes: [String: String] = {
        let english = Locale(identifier: "en")
        var codes: [String: String] = ["UAE": "AE", "Czechia": "CZ", "Türkiye": "TR", "Vatican City": "VA", "South Korea": "KR",
                                       "United States": "US", "United Kingdom": "GB", "Myanmar": "MM"]
        for region in Locale.Region.isoRegions where region.identifier.count == 2 {
            if let name = english.localizedString(forRegionCode: region.identifier), codes[name] == nil { codes[name] = region.identifier }
        }
        return codes
    }()

    // MARK: Drawing

    /// One place for the time and mood, or nil if nothing fits at all. `nearby` is what
    /// Apple Maps found around the person, for a day out.
    static func draw(span: Span, mood: Mood, context: Context, nearby: [Place] = [],
                     using generator: inout some RandomNumberGenerator) -> Draw? {
        let unseen = (MustSee.china + MustSee.world)
            .filter { !context.visited.contains($0.id) && !leftOut.contains($0.id) }
            .map(Place.init)
        var pool = unseen + nearby
        if let here = context.here {
            let reachable = pool.filter { span.range.contains(here.distance(from: $0.location) / 1000) }
            if !reachable.isEmpty {
                pool = reachable
            } else if span == .day {
                // Nothing within a day's reach: better to say so than to send them far away.
                return nil
            } else {
                // Somewhere remote: the closest few that are left.
                pool = Array(pool.sorted { here.distance(from: $0.location) < here.distance(from: $1.location) }.prefix(6))
            }
        }
        let suited = pool.filter { mood.kinds.contains($0.placeKind) }
        if !suited.isEmpty { pool = suited }
        let fresh = pool.filter { !context.recent.contains($0.id) }
        if !fresh.isEmpty { pool = fresh }
        guard let place = weightedPick(pool, mood: mood, context: context, using: &generator) else { return nil }
        let distance = context.here.map { $0.distance(from: place.location) }
        let reason = reason(for: place, span: span, mood: mood, distance: distance, context: context, using: &generator)
        return Draw(place: place, reason: reason, span: span, distance: distance, stops: stops(around: place, span: span, context: context))
    }

    private static func weightedPick(_ pool: [Place], mood: Mood, context: Context, using generator: inout some RandomNumberGenerator) -> Place? {
        let favourite = context.favourite
        let weights = pool.map { place -> Double in
            var weight = 1.0
            if let id = place.mustSeeID, context.wishes.contains(id) { weight *= 6 }
            if visa(for: place, context: context) != nil { weight *= 3 }
            if mood == .any {
                if place.placeKind == favourite { weight *= 2 }
                if context.litTotal >= 3, context.lit(place.placeKind) == 0 { weight *= 1.5 }
            }
            return weight
        }
        let total = weights.reduce(0, +)
        guard total > 0 else { return nil }
        var roll = Double.random(in: 0..<total, using: &generator)
        for (place, weight) in zip(pool, weights) {
            roll -= weight
            if roll < 0 { return place }
        }
        return pool.last
    }

    private static func visa(for place: Place, context: Context) -> (name: String, until: Date)? {
        guard let mustSee = place.mustSee else { return nil }
        return countries(of: mustSee).lazy.compactMap { context.visas[$0] }.first
    }

    /// The truest things that can be said, most personal first; one of the top two, so the
    /// box doesn't keep saying the same thing.
    private static func reason(for place: Place, span: Span, mood: Mood, distance: Double?, context: Context,
                               using generator: inout some RandomNumberGenerator) -> Reason {
        var options: [Reason] = []
        if let id = place.mustSeeID, context.wishes.contains(id) { options.append(.wished) }
        if let visa = visa(for: place, context: context) { options.append(.visa(name: visa.name, until: visa.until)) }
        if mood != .any, mood.kinds.contains(place.placeKind) { options.append(.mood(mood)) }
        if let distance {
            if span == .day { options.append(.nearby(distance)) }
            if span == .weekend { options.append(.weekendAway(distance)) }
            if context.farthest > 0, distance > context.farthest + 100_000 { options.append(.farther(distance - context.farthest)) }
        }
        if context.litTotal >= 3, context.lit(place.placeKind) == 0 { options.append(.newKind(place.placeKind.rawValue, lit: context.litTotal)) }
        if place.placeKind == context.favourite { options.append(.favourite(place.placeKind.rawValue)) }
        if let mustSee = place.mustSee, context.litTotal > 0,
           !MustSee.List.allCases.flatMap(\.places).contains(where: { $0.region == mustSee.region && context.visited.contains($0.id) }) {
            options.append(.untouchedRegion)
        }
        if mood == .any, options.isEmpty, Bool.random(using: &generator) { options.append(.mood(.any)) }
        guard !options.isEmpty else { return .none }
        return options[Int.random(in: 0..<min(2, options.count), using: &generator)]
    }

    /// Other places not yet seen close to this one, each next to the last, for a longer trip.
    static func stops(around place: Place, span: Span, context: Context) -> [String] {
        guard span.stopCount > 0, place.mustSeeID != nil else { return [] }
        // Close by on the map isn't close by if there's a border between: a stop is in the same
        // country or region as the place itself.
        let side = countries(of: place)
        var left = (MustSee.china + MustSee.world).filter {
            $0.id != place.id && $0.countryCode == nil && !context.visited.contains($0.id) && !leftOut.contains($0.id)
                && place.location.distance(from: CLLocation(latitude: $0.latitude, longitude: $0.longitude)) <= span.stopReach * 1000
                && !countries(of: Place($0)).isDisjoint(with: side)
        }
        var result: [String] = []
        var from = place.location
        while result.count < span.stopCount, !left.isEmpty {
            guard let index = left.indices.min(by: {
                from.distance(from: CLLocation(latitude: left[$0].latitude, longitude: left[$0].longitude))
                    < from.distance(from: CLLocation(latitude: left[$1].latitude, longitude: left[$1].longitude))
            }) else { break }
            let next = left.remove(at: index)
            result.append(next.id)
            from = CLLocation(latitude: next.latitude, longitude: next.longitude)
        }
        return result
    }

    /// The days shared out among the places, with more for the main one: for four days and
    /// three places, 2, 1, 1.
    static func itinerary(days: Int, places: Int) -> [ClosedRange<Int>] {
        guard places > 0, days >= places else { return places > 0 ? [1...max(days, 1)] : [] }
        var result: [ClosedRange<Int>] = []
        var next = 1
        let each = days / places, extra = days % places
        for index in 0..<places {
            let length = each + (index == 0 ? extra : 0)
            result.append(next...(next + length - 1))
            next += length
        }
        return result
    }

    /// When a day out should begin: today if the morning's still young, otherwise tomorrow.
    static func dayOut(from now: Date = .now, calendar: Calendar = .current) -> Date {
        let start = calendar.startOfDay(for: now)
        return calendar.component(.hour, from: now) < 11 ? start : (calendar.date(byAdding: .day, value: 1, to: start) ?? start)
    }

    /// When to set off, in minutes after midnight, going by when the person usually gets moving.
    static func departure(early: Double, night: Double) -> Int {
        if early >= 0.2 { return 7 * 60 + 30 }
        if night >= 0.2 { return 10 * 60 }
        return 8 * 60 + 30
    }

    /// Whether the person has reached this ticket's place since keeping it, and when.
    static func arrival(of ticket: Ticket, in visits: [MustSee.Visit]) -> Date? {
        let place = ticket.draw.place
        return visits.lazy.filter { visit in
            guard visit.arrival >= ticket.kept else { return false }
            if let code = place.countryCode { return visit.countryCode == code }
            return CLLocation(latitude: visit.latitude, longitude: visit.longitude).distance(from: place.location) <= place.radius * 1000
        }.map(\.arrival).min()
    }
}

// MARK: - Holidays

/// China's public holidays by the festivals they keep. The days actually off are announced
/// each year, so the box only ever speaks of the festival's own date.
struct Holiday: Equatable, Sendable {
    let name: String
    let date: Date
    let span: BlindBox.Span

    func daysAway(from now: Date, calendar: Calendar = .current) -> Int {
        calendar.dateComponents([.day], from: calendar.startOfDay(for: now), to: calendar.startOfDay(for: date)).day ?? 0
    }

    static func next(after now: Date, calendar: Calendar = .current) -> Holiday? {
        let today = calendar.startOfDay(for: now)
        func solar(_ month: Int, _ day: Int) -> Date? {
            calendar.nextDate(after: today.addingTimeInterval(-1), matching: DateComponents(month: month, day: day), matchingPolicy: .nextTime)
        }
        func lunar(_ month: Int, _ day: Int) -> Date? {
            var chinese = Calendar(identifier: .chinese)
            chinese.timeZone = calendar.timeZone
            var parts = DateComponents(month: month, day: day)
            parts.isLeapMonth = false
            return chinese.nextDate(after: today.addingTimeInterval(-1), matching: parts, matchingPolicy: .nextTime)
        }
        let all: [(String, Date?, BlindBox.Span)] = [
            (String(localized: "元旦", bundle: .appLanguage), solar(1, 1), .holiday),
            (String(localized: "春节", bundle: .appLanguage), lunar(1, 1), .long),
            (String(localized: "清明", bundle: .appLanguage), solar(4, 5), .holiday),
            (String(localized: "五一", bundle: .appLanguage), solar(5, 1), .holiday),
            (String(localized: "端午", bundle: .appLanguage), lunar(5, 5), .holiday),
            (String(localized: "中秋", bundle: .appLanguage), lunar(8, 15), .holiday),
            (String(localized: "国庆", bundle: .appLanguage), solar(10, 1), .long),
        ]
        return all.compactMap { name, date, span in date.map { Holiday(name: name, date: $0, span: span) } }
            .min { $0.date < $1.date }
    }
}

/// What the box says when it's opened, and which length of trip it offers first: the week as
/// the person is living it right now.
struct BlindBoxMoment: Equatable {
    let line: String
    let span: BlindBox.Span

    /// How soon a holiday has to be before the box brings it up.
    private static let holidayHorizon = 21

    static func at(_ now: Date, holiday: Holiday?, calendar: Calendar = .current) -> BlindBoxMoment {
        if let holiday {
            let days = holiday.daysAway(from: now, calendar: calendar)
            if days == 0 {
                return BlindBoxMoment(line: String(localized: "今天就是\(holiday.name)。出门走走吧，别辜负了。", bundle: .appLanguage), span: .day)
            }
            if days <= holidayHorizon {
                return BlindBoxMoment(line: String(localized: "离\(holiday.name)还有 \(days) 天。去哪儿，现在想正好。", bundle: .appLanguage), span: holiday.span)
            }
        }
        let weekday = calendar.component(.weekday, from: now)
        let hour = calendar.component(.hour, from: now)
        switch weekday {
        case 7 where hour < 11, 1 where hour < 11:
            return BlindBoxMoment(line: String(localized: "今天有空。不如现在就出门。", bundle: .appLanguage), span: .day)
        case 7:
            return BlindBoxMoment(line: String(localized: "今天有点晚了，明天还来得及。", bundle: .appLanguage), span: .day)
        case 1:
            return BlindBoxMoment(line: String(localized: "这个周末快过完了。下一个，交给盲盒吧。", bundle: .appLanguage), span: .weekend)
        case 6:
            return BlindBoxMoment(line: String(localized: "快到周末了。这次，别又在家躺过去。", bundle: .appLanguage), span: .weekend)
        default:
            let left = 7 - weekday
            return BlindBoxMoment(line: String(localized: "还有 \(left) 天到周末。先给自己留个念想。", bundle: .appLanguage), span: .weekend)
        }
    }
}

/// Ways to enjoy a place once there, by the kind of place. They hold for anywhere of that kind,
/// so nothing here pretends to know a particular lake or lane.
enum BlindBoxIdeas {
    /// Two ideas and one small mission, the same for a place each time it's looked at.
    static func ideas(for place: BlindBox.Place) -> (tips: [String], mission: String) {
        let seed = place.id.unicodeScalars.reduce(0) { ($0 &* 31 &+ Int($1.value)) & 0xFFFF }
        let all = tips(place.placeKind)
        let picked = [all[seed % all.count], all[(seed + 1) % all.count]]
        let missions = missions()
        return (picked, missions[seed % missions.count])
    }

    private static func tips(_ kind: MustSeePlace.Kind) -> [String] {
        switch kind {
        case .water: [String(localized: "绕着水边慢慢走一圈，不用赶。", bundle: .appLanguage), String(localized: "带块野餐垫，找片草地坐一下午。", bundle: .appLanguage), String(localized: "日落前一小时到，水面最好看。", bundle: .appLanguage)]
        case .mountain: [String(localized: "早点上山，人少，空气也好。", bundle: .appLanguage), String(localized: "不用登顶，走到舒服的地方就够了。", bundle: .appLanguage), String(localized: "带点吃的，在山上吃什么都香。", bundle: .appLanguage)]
        case .wild: [String(localized: "手机调成静音，听一会儿风。", bundle: .appLanguage), String(localized: "穿双好走的鞋，往人少的地方多走几步。", bundle: .appLanguage), String(localized: "留到天黑，抬头看看星星。", bundle: .appLanguage)]
        case .heritage: [String(localized: "找个角落坐下，想想几百年前这里的人在做什么。", bundle: .appLanguage), String(localized: "别跳过讲解牌，一个小故事就够记很久。", bundle: .appLanguage), String(localized: "早点到，或者晚点走，就能躲开人潮。", bundle: .appLanguage)]
        case .city: [String(localized: "先不看攻略，拐进第一条让你好奇的小巷。", bundle: .appLanguage), String(localized: "问问路边的店家，他们自己常去哪家吃。", bundle: .appLanguage), String(localized: "找家老店坐坐，看街上的人来人往。", bundle: .appLanguage)]
        }
    }

    private static func missions() -> [String] {
        [
            String(localized: "拍一张只有你知道在哪儿的照片。", bundle: .appLanguage),
            String(localized: "带一样这里才有的小东西回家。", bundle: .appLanguage),
            String(localized: "给很久没联系的人寄一张明信片。", bundle: .appLanguage),
            String(localized: "记下今天听到的最有意思的一句话。", bundle: .appLanguage),
            String(localized: "吃一样你从没吃过的东西。", bundle: .appLanguage),
        ]
    }
}

// MARK: - Store

/// Kept tickets and today's openings. Tickets follow the person between devices through
/// iCloud; three openings a day, so that each one means something.
@MainActor
@Observable
final class BlindBoxStore {
    static let shared = BlindBoxStore()
    static let dailyLimit = 3

    private static let ticketsKey = "blindBox.tickets"
    private static let openKey = "blindBox.open"
    private static let dayKey = "blindBox.day"
    private static let countKey = "blindBox.count"
    private static let recentKey = "blindBox.recent"

    private(set) var tickets: [BlindBox.Ticket] = []
    /// What's been opened and not yet kept or put back. It stays until the person decides.
    private(set) var open: BlindBox.Draw?
    private(set) var openedToday = 0

    private init() {
        let defaults = UserDefaults.standard
        tickets = Self.decode(NSUbiquitousKeyValueStore.default.data(forKey: Self.ticketsKey) ?? defaults.data(forKey: Self.ticketsKey)) ?? []
        open = defaults.data(forKey: Self.openKey).flatMap { try? JSONDecoder().decode(BlindBox.Draw.self, from: $0) }
        openedToday = defaults.string(forKey: Self.dayKey) == Self.today ? defaults.integer(forKey: Self.countKey) : 0
        NotificationCenter.default.addObserver(forName: NSUbiquitousKeyValueStore.didChangeExternallyNotification,
                                               object: NSUbiquitousKeyValueStore.default, queue: .main) { note in
            let keys = note.userInfo?[NSUbiquitousKeyValueStoreChangedKeysKey] as? [String] ?? []
            guard keys.contains(Self.ticketsKey) else { return }
            MainActor.assumeIsolated {
                let store = BlindBoxStore.shared
                if let synced = Self.decode(NSUbiquitousKeyValueStore.default.data(forKey: Self.ticketsKey)), synced != store.tickets {
                    store.tickets = synced
                }
            }
        }
    }

    private static func decode(_ data: Data?) -> [BlindBox.Ticket]? {
        data.flatMap { try? JSONDecoder().decode([BlindBox.Ticket].self, from: $0) }
    }

    private static var today: String {
        let parts = Calendar.current.dateComponents([.year, .month, .day], from: .now)
        return "\(parts.year ?? 0)-\(parts.month ?? 0)-\(parts.day ?? 0)"
    }

    var waiting: [BlindBox.Ticket] { tickets.filter { $0.arrived == nil }.sorted { $0.kept > $1.kept } }
    var arrived: [BlindBox.Ticket] { tickets.filter { $0.arrived != nil }.sorted { ($0.arrived ?? .distantPast) > ($1.arrived ?? .distantPast) } }

    var remainingToday: Int {
        refreshDay()
        return max(Self.dailyLimit - openedToday, 0)
    }

    private func refreshDay() {
        if UserDefaults.standard.string(forKey: Self.dayKey) != Self.today, openedToday != 0 { openedToday = 0 }
    }

    /// Recently opened places, which the box won't offer again for a while.
    var recent: Set<String> { Set(UserDefaults.standard.stringArray(forKey: Self.recentKey) ?? []).union(tickets.map(\.id)) }

    /// A new draw replaces whatever was open, and uses up one of the day's openings.
    func record(_ draw: BlindBox.Draw) {
        refreshDay()
        openedToday += 1
        let defaults = UserDefaults.standard
        defaults.set(Self.today, forKey: Self.dayKey)
        defaults.set(openedToday, forKey: Self.countKey)
        defaults.set(Array(([draw.id] + (defaults.stringArray(forKey: Self.recentKey) ?? [])).prefix(20)), forKey: Self.recentKey)
        open = draw
        saveOpen()
    }

    /// Keeps what's open as a ticket, and puts a must-see place on the wish list too.
    @discardableResult
    func keep() -> BlindBox.Ticket? {
        guard let draw = open else { return nil }
        let ticket = BlindBox.Ticket(draw: draw, kept: .now)
        tickets.removeAll { $0.id == ticket.id }
        tickets.append(ticket)
        saveTickets()
        if let id = draw.place.mustSeeID {
            let defaults = UserDefaults.standard
            var wishes = Set((defaults.string(forKey: "mustSee.wishes") ?? "").split(separator: ",").map(String.init))
            wishes.insert(id)
            defaults.set(wishes.sorted().joined(separator: ","), forKey: "mustSee.wishes")
        }
        open = nil
        saveOpen()
        return ticket
    }

    func putBack() {
        open = nil
        saveOpen()
    }

    func remove(_ ticket: BlindBox.Ticket) {
        tickets.removeAll { $0.id == ticket.id }
        saveTickets()
    }

    /// Marks tickets whose place has been reached, queues their moment, and returns them.
    @discardableResult
    func settle(visits: [MustSee.Visit]) -> [BlindBox.Ticket] {
        var reached: [BlindBox.Ticket] = []
        for index in tickets.indices where tickets[index].arrived == nil {
            guard let date = BlindBox.arrival(of: tickets[index], in: visits) else { continue }
            tickets[index].arrived = date
            reached.append(tickets[index])
            let place = tickets[index].draw.place
            Celebrations.shared.add(Celebrations.Item(id: "blindBox.\(place.id)", kind: .blindBox, title: place.localizedName, subtitle: place.localizedRegion,
                                                      latitude: place.latitude, longitude: place.longitude, date: date,
                                                      firstVisit: tickets[index].kept, code: place.id))
        }
        if !reached.isEmpty { saveTickets() }
        return reached
    }

    func ticket(id: String?) -> BlindBox.Ticket? { tickets.first { $0.id == id } }

    /// When all the data is deleted.
    func removeAll() {
        tickets = []
        open = nil
        openedToday = 0
        saveTickets()
        saveOpen()
        for key in [Self.dayKey, Self.countKey, Self.recentKey] { UserDefaults.standard.removeObject(forKey: key) }
    }

    private func saveTickets() {
        let data = try? JSONEncoder().encode(tickets)
        UserDefaults.standard.set(data, forKey: Self.ticketsKey)
        NSUbiquitousKeyValueStore.default.set(data, forKey: Self.ticketsKey)
    }

    private func saveOpen() {
        UserDefaults.standard.set(open.flatMap { try? JSONEncoder().encode($0) }, forKey: Self.openKey)
    }

    #if DEBUG
    /// Today's openings back, for trying things out: `-blindBoxReset`.
    func resetToday() {
        openedToday = 0
        open = nil
        saveOpen()
        for key in [Self.dayKey, Self.countKey, Self.recentKey] { UserDefaults.standard.removeObject(forKey: key) }
    }

    /// A kept ticket, for trying the arrival out: `-blindBoxSample`.
    func addSample() {
        guard let place = BlindBox.mustSee(id: "zhangjiajie") ?? MustSee.china.first else { return }
        let draw = BlindBox.Draw(place: .init(place), reason: .none, span: .holiday, distance: 1_100_000)
        let kept = Date.now.addingTimeInterval(-73 * 86_400)
        tickets.removeAll { $0.id == draw.id }
        tickets.append(BlindBox.Ticket(draw: draw, kept: kept, arrived: nil))
        settle(visits: [MustSee.Visit(latitude: place.latitude, longitude: place.longitude, arrival: .now, countryCode: "CN")])
    }
    #endif
}

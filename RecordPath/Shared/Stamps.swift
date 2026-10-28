import Foundation
import CoreLocation

/// One stamp in the passport or the stamp book. Nothing is stored: stamps are read off the
/// stays, so they're the same on every device and appear for visits imported from photos too.
struct Stamp: Identifiable, Hashable {
    enum Kind: String { case entry, exit, province, city, special, set }

    let id: String
    let kind: Kind
    let date: Date
    var countryCode: String?
    /// Entry and exit: where the border was crossed, an airport or the first town.
    var port: String?
    var byAir = false
    /// Exit: days in the country on that visit.
    var days = 0
    var provinceID: String?
    var city: String?
    var latitude = 0.0
    var longitude = 0.0
    /// Special stamps: which one ("equator", "newyear.2026", "record.north"); sets: the set's id.
    var code: String?
    /// What the special stamp prints big: "45°48′N", "2026", "1,523 m".
    var value: String?

    var coordinate: CLLocationCoordinate2D { CLLocationCoordinate2D(latitude: latitude, longitude: longitude) }
    var province: Province? { provinceID.flatMap { id in Province.all.first { $0.id == id } } }

    /// A stable number for the small irregularities of a hand-pressed stamp: tilt, wear, ink.
    var seed: UInt64 { StampSeed.of(id) }
    /// Tilted a few degrees, the way a stamp lands when someone presses it in a hurry.
    var tilt: Double { Double(seed % 1300) / 100 - 6.5 }
}

enum StampSeed {
    /// FNV-1a: stable across launches, unlike `hashValue`.
    static func of(_ text: String) -> UInt64 {
        var hash: UInt64 = 0xcbf29ce484222325
        for byte in text.utf8 {
            hash ^= UInt64(byte)
            hash = hash &* 0x100000001b3
        }
        return hash
    }
}

/// Every stamp earned so far, oldest first in each list.
struct StampBook {
    /// Entry and exit stamps, interleaved in the order they happened.
    var passport: [Stamp] = []
    var provinces: [Stamp] = []
    var cities: [Stamp] = []
    /// Once-in-a-lifetime crossings, each New Year's Eve, and the farthest you've been.
    var specials: [Stamp] = []
    /// Groups of cities, and how far along each one is.
    var sets: [StampSet.Progress] = []
    /// The country lived in, which issues the passport rather than stamping it.
    var home: String?
    var since: Date?

    init() {}

    init(stays: [Stay]) {
        let sorted = stays.filter { $0.countryCode != nil }.sorted { $0.arrival < $1.arrival }
        guard let first = sorted.first else { return }
        since = first.arrival

        let runs = Self.countryRuns(sorted)
        var time: [String: TimeInterval] = [:]
        for run in runs { time[run.code, default: 0] += run.end.timeIntervalSince(run.start) }
        home = time.max { $0.value < $1.value }?.key

        for visit in Self.visits(runs, home: home) {
            passport.append(Stamp(id: "entry.\(visit.code).\(Int(visit.start.timeIntervalSince1970))", kind: .entry, date: visit.start,
                                  countryCode: visit.code, port: Self.port(visit.first), byAir: visit.arrivedByAir,
                                  latitude: visit.first.latitude, longitude: visit.first.longitude))
            // Still there: no exit stamp yet.
            guard let next = visit.next else { continue }
            let days = Calendar.current.days(in: DateInterval(start: visit.start, end: max(visit.end, visit.start))).count
            passport.append(Stamp(id: "exit.\(visit.code).\(Int(visit.start.timeIntervalSince1970))", kind: .exit, date: visit.end,
                                  countryCode: visit.code, port: Self.port(visit.last),
                                  byAir: visit.last.category == .airport || visit.last.location.distance(from: next.location) > 400_000,
                                  days: days, latitude: visit.last.latitude, longitude: visit.last.longitude))
        }

        var seenProvinces = Set<String>()
        let names = CityNames.canonical(for: sorted)
        var seenCities = Set<String>()
        for stay in sorted {
            if let province = Province.containing(countryCode: stay.countryCode, region: stay.region, city: stay.city),
               seenProvinces.insert(province.id).inserted {
                provinces.append(Stamp(id: "province.\(province.id)", kind: .province, date: stay.arrival, countryCode: stay.countryCode,
                                       provinceID: province.id, latitude: stay.latitude, longitude: stay.longitude))
            }
            if let key = CityNames.key(stay), let name = names[key] {
                let id = "\(stay.countryCode ?? "")|\(name)"
                if seenCities.insert(id).inserted {
                    cities.append(Stamp(id: "city.\(id)", kind: .city, date: stay.arrival, countryCode: stay.countryCode,
                                        city: name, latitude: stay.latitude, longitude: stay.longitude))
                }
            }
        }
        specials = Self.specials(stays.sorted { $0.arrival < $1.arrival })
        sets = StampSet.progress(cities: cities)
    }

    /// Special stamps and completed sets: the ones worth a ceremony when they're new.
    var earnedOnce: [Stamp] {
        specials.filter { !($0.code ?? "").hasPrefix("record.") } + sets.compactMap(\.stamp)
    }

    // MARK: Special stamps

    static let arcticCircle = 66.5634

    static func specials(_ sorted: [Stay]) -> [Stamp] {
        var result: [Stamp] = []
        func add(_ code: String, _ stay: Stay, value: String? = nil) {
            result.append(Stamp(id: "special.\(code)", kind: .special, date: stay.arrival, countryCode: stay.countryCode,
                                city: stay.city ?? stay.country ?? stay.placeName, latitude: stay.latitude, longitude: stay.longitude,
                                code: code, value: value))
        }
        var crossedEquator = false, crossedDateLine = false, arctic = false, antarctic = false
        for (previous, stay) in zip(sorted, sorted.dropFirst()) {
            // Well clear of the line on both sides, so wobbling near it doesn't count.
            if !crossedEquator, previous.latitude * stay.latitude < 0, abs(previous.latitude) > 0.2 || abs(stay.latitude) > 0.2 {
                crossedEquator = true
                add("equator", stay, value: "0°00′")
            }
            // The short way between them runs across the Pacific's 180th meridian.
            if !crossedDateLine, abs(previous.longitude - stay.longitude) > 180 {
                crossedDateLine = true
                add("dateline", stay, value: "180°")
            }
        }
        for stay in sorted {
            if !arctic, stay.latitude >= arcticCircle { arctic = true; add("arctic", stay, value: "66°33′N") }
            if !antarctic, stay.latitude <= -arcticCircle { antarctic = true; add("antarctic", stay, value: "66°33′S") }
        }

        // Where each New Year began: the place you were at midnight, or the nearest to it
        // within a couple of hours, out celebrating between places.
        let calendar = Calendar.current
        if let first = sorted.first?.arrival {
            let firstYear = calendar.component(.year, from: first), thisYear = calendar.component(.year, from: Date())
            for year in max(firstYear, thisYear - 40)...thisYear {
                guard let midnight = calendar.date(from: DateComponents(year: year, month: 1, day: 1)), midnight <= Date() else { continue }
                func gap(_ stay: Stay) -> TimeInterval {
                    let end = stay.departure ?? Date()
                    return stay.arrival > midnight ? stay.arrival.timeIntervalSince(midnight) : max(0, midnight.timeIntervalSince(end))
                }
                guard let stay = sorted.filter({ gap($0) < 2 * 3600 }).min(by: { gap($0) < gap($1) }) else { continue }
                result.append(Stamp(id: "special.newyear.\(year)", kind: .special, date: midnight, countryCode: stay.countryCode,
                                    city: stay.displayName, latitude: stay.latitude, longitude: stay.longitude,
                                    code: "newyear.\(year)", value: String(year)))
            }
        }

        // The four corners of everywhere you've been: 四至.
        let named = sorted.filter { $0.city != nil }
        let corners: [(String, (Stay, Stay) -> Bool, (Stay) -> String)] = [
            ("north", { $0.latitude < $1.latitude }, { Self.degrees($0.latitude, "N", "S") }),
            ("south", { $0.latitude > $1.latitude }, { Self.degrees($0.latitude, "N", "S") }),
            ("east", { $0.longitude < $1.longitude }, { Self.degrees($0.longitude, "E", "W") }),
            ("west", { $0.longitude > $1.longitude }, { Self.degrees($0.longitude, "E", "W") }),
        ]
        if named.count > 1 {
            for (code, isLess, label) in corners {
                if let best = named.max(by: isLess) { add("record.\(code)", best, value: label(best)) }
            }
        }
        return result
    }

    /// 45.803 → "45°48′N".
    static func degrees(_ value: Double, _ positive: String, _ negative: String) -> String {
        let whole = Int(abs(value)), minutes = Int((abs(value) - Double(whole)) * 60)
        return "\(whole)°\(String(format: "%02d", minutes))′\(value >= 0 ? positive : negative)"
    }

    /// Stamps for one country: its entries and exits.
    func passport(for code: String) -> [Stamp] { passport.filter { $0.countryCode == code } }
    func cities(in code: String) -> [Stamp] { cities.filter { $0.countryCode == code } }

    // MARK: Visits to a country

    struct Run {
        let code: String
        var first: Stay
        var last: Stay
        var start: Date
        var end: Date
        var time: TimeInterval
        var count: Int
        var fromPhotos: Bool
    }

    struct Visit {
        let code: String
        var first: Stay
        var last: Stay
        var start: Date
        var end: Date
        var arrivedByAir: Bool
        /// The first stay after leaving; nil while still there.
        var next: Stay?
    }

    /// Trips abroad, one entry and one exit each. Going back within a few days, like living on
    /// one side of a border and working on the other, continues the same visit rather than
    /// stamping the passport twice a day.
    static func visits(_ runs: [Run], home: String?, rejoin: TimeInterval = 3 * 86_400) -> [Visit] {
        var visits: [Visit] = []
        for (index, run) in runs.enumerated() where run.code != home {
            let next = index + 1 < runs.count ? runs[index + 1].first : nil
            if let open = visits.lastIndex(where: { $0.code == run.code }), run.start.timeIntervalSince(visits[open].end) < rejoin,
               open == visits.count - 1 {
                visits[open].last = run.last
                visits[open].end = max(visits[open].end, run.end)
                visits[open].next = next
                continue
            }
            let previous = index > 0 ? runs[index - 1].last : nil
            let byAir = run.first.category == .airport || previous.map { $0.location.distance(from: run.first.location) > 400_000 } ?? false
            visits.append(Visit(code: run.code, first: run.first, last: run.last, start: run.start, end: run.end,
                                arrivedByAir: byAir, next: next))
        }
        return visits
    }

    /// Back-to-back stays in one country make one visit. Brief blips, like a place across the
    /// border named by mistake or a layover, are dropped, so they don't stamp the passport.
    static func countryRuns(_ sorted: [Stay]) -> [Run] {
        var raw: [Run] = []
        for stay in sorted {
            guard let code = stay.countryCode else { continue }
            let end = max(stay.departure ?? stay.arrival, stay.arrival)
            if raw.last?.code == code {
                raw[raw.count - 1].last = stay
                raw[raw.count - 1].end = max(raw[raw.count - 1].end, end)
                raw[raw.count - 1].time += end.timeIntervalSince(stay.arrival)
                raw[raw.count - 1].count += 1
                raw[raw.count - 1].fromPhotos = raw[raw.count - 1].fromPhotos || stay.isFromPhotos
            } else {
                raw.append(Run(code: code, first: stay, last: stay, start: stay.arrival, end: end,
                               time: end.timeIntervalSince(stay.arrival), count: 1, fromPhotos: stay.isFromPhotos))
            }
        }
        let kept = raw.filter { $0.time >= 45 * 60 || $0.count >= 3 || $0.fromPhotos }
        var merged: [Run] = []
        for run in kept {
            if merged.last?.code == run.code {
                merged[merged.count - 1].last = run.last
                merged[merged.count - 1].end = max(merged[merged.count - 1].end, run.end)
                merged[merged.count - 1].time += run.time
                merged[merged.count - 1].count += run.count
            } else {
                merged.append(run)
            }
        }
        return merged
    }

    /// An airport by its name, anywhere else by its town.
    private static func port(_ stay: Stay) -> String? {
        stay.category == .airport ? stay.displayName : (stay.city ?? stay.placeName)
    }
}

// MARK: - Reunions

/// Coming back to a place after a long time away.
struct Reunion: Equatable {
    let lastVisit: Date
    let firstVisit: Date
    let visits: Int

    /// A year away counts. Shorter gaps are just life.
    static let minimumGap: TimeInterval = 365 * 86_400

    /// "2 年 7 个月", "1 年": how long it's been, in the words people use.
    static func away(since date: Date, now: Date = Date()) -> String {
        let parts = Calendar.current.dateComponents([.year, .month], from: date, to: now)
        let years = parts.year ?? 0, months = parts.month ?? 0
        if years > 0, months > 0 { return String(localized: "\(years) 年 \(months) 个月", bundle: .appLanguage) }
        if years > 0 { return String(localized: "\(years) 年", bundle: .appLanguage) }
        return String(localized: "\(months) 个月", bundle: .appLanguage)
    }

    /// The last time the person was within a stone's throw of this stay, if it was long enough ago.
    static func find(_ stay: Stay, after others: [Stay]) -> Reunion? {
        guard !stay.isFromPhotos else { return nil }
        let near = others.filter {
            $0.arrival < stay.arrival && abs($0.latitude - stay.latitude) < 0.003
                && $0.location.distance(from: stay.location) < 150
        }
        guard let last = near.max(by: { $0.arrival < $1.arrival }), let first = near.min(by: { $0.arrival < $1.arrival }) else { return nil }
        let left = last.departure ?? last.arrival
        guard stay.arrival.timeIntervalSince(left) >= minimumGap else { return nil }
        return Reunion(lastVisit: last.arrival, firstVisit: first.arrival, visits: near.count + 1)
    }
}

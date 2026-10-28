import Foundation
import CoreLocation

/// One stamp in the passport or the stamp book. Nothing is stored: stamps are read off the
/// stays, so they're the same on every device and appear for visits imported from photos too.
struct Stamp: Identifiable, Hashable {
    enum Kind: String { case entry, exit, province, city }

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

        for (index, run) in runs.enumerated() where run.code != home {
            let previous = index > 0 ? runs[index - 1].last : nil
            let byAir = run.first.category == .airport
                || previous.map { $0.location.distance(from: run.first.location) > 400_000 } ?? false
            passport.append(Stamp(id: "entry.\(run.code).\(Int(run.start.timeIntervalSince1970))", kind: .entry, date: run.start,
                                  countryCode: run.code, port: Self.port(run.first), byAir: byAir,
                                  latitude: run.first.latitude, longitude: run.first.longitude))
            // Still there: no exit stamp yet.
            guard index < runs.count - 1 else { continue }
            let next = runs[index + 1].first
            let days = Calendar.current.days(in: DateInterval(start: run.start, end: max(run.end, run.start))).count
            passport.append(Stamp(id: "exit.\(run.code).\(Int(run.start.timeIntervalSince1970))", kind: .exit, date: run.end,
                                  countryCode: run.code, port: Self.port(run.last),
                                  byAir: run.last.category == .airport || run.last.location.distance(from: next.location) > 400_000,
                                  days: days, latitude: run.last.latitude, longitude: run.last.longitude))
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

    var daysAway: Int {
        Calendar.current.dateComponents([.day], from: Calendar.current.startOfDay(for: lastVisit),
                                        to: Calendar.current.startOfDay(for: Date())).day ?? 0
    }

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

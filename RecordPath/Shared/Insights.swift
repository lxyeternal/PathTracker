import Foundation
import SwiftData
import CoreLocation

// MARK: - Day timeline

struct Move: Identifiable {
    let chunks: [TrackChunk]
    var id: Date { start }
    var start: Date { chunks.first?.startDate ?? .distantPast }
    var end: Date { chunks.last?.endDate ?? .distantPast }
    var distance: Double { chunks.reduce(0) { $0 + $1.distance } }
    var duration: TimeInterval { end.timeIntervalSince(start) }

    var mode: MovementMode {
        Dictionary(grouping: chunks, by: \.mode)
            .max { $0.value.reduce(0) { $0 + $1.distance } < $1.value.reduce(0) { $0 + $1.distance } }?.key ?? .unknown
    }
}

enum TimelineEntry: Identifiable {
    case stay(Stay)
    case move(Move)

    var id: String {
        switch self {
        case .stay(let stay): "stay-\(stay.id)"
        case .move(let move): "move-\(move.start.timeIntervalSince1970)"
        }
    }

    var start: Date {
        switch self {
        case .stay(let stay): stay.arrival
        case .move(let move): move.start
        }
    }
}

enum Timeline {
    /// Interleaves stays with the movement between them, newest last.
    static func entries(stays: [Stay], chunks: [TrackChunk]) -> [TimelineEntry] {
        let stays = stays.sorted { $0.arrival < $1.arrival }
        let chunks = chunks.sorted { $0.startDate < $1.startDate }
        var entries: [TimelineEntry] = stays.map { .stay($0) }

        var group: [TrackChunk] = []
        func closeGroup() {
            if !group.isEmpty, group.reduce(0, { $0 + $1.distance }) > 50 { entries.append(.move(Move(chunks: group))) }
            group = []
        }
        for chunk in chunks {
            if let last = group.last {
                let gap = chunk.startDate.timeIntervalSince(last.endDate)
                let stayBetween = stays.contains { $0.arrival >= last.endDate.addingTimeInterval(-60) && $0.arrival <= chunk.startDate }
                if gap > 10 * 60 || stayBetween { closeGroup() }
            }
            group.append(chunk)
        }
        closeGroup()
        return entries.sorted { $0.start < $1.start }
    }
}

// MARK: - World

struct CountrySummary: Identifiable, Hashable {
    let code: String
    let name: String
    var days: Set<Date> = []
    var cities: [String: Int] = [:]
    var landmarks: [String] = []
    var firstVisit: Date = .distantFuture
    var lastVisit: Date = .distantPast

    var id: String { code }
    var flag: String { .flag(for: code) }

    static func == (lhs: Self, rhs: Self) -> Bool { lhs.code == rhs.code && lhs.days == rhs.days }
    func hash(into hasher: inout Hasher) { hasher.combine(code) }
}

struct FrequentPlace: Identifiable {
    let representative: Stay
    let visits: Int
    let totalTime: TimeInterval
    var id: UUID { representative.id }
}

struct WorldInsights {
    var countries: [CountrySummary] = []
    var cityCount = 0
    var landmarks: [Stay] = []
    var frequentPlaces: [FrequentPlace] = []
    var trackedDays = 0
    var firstDay: Date?

    init() {}

    init(stays: [Stay]) {
        let calendar = Calendar.current
        var byCountry: [String: CountrySummary] = [:]
        var cities = Set<String>()
        var days = Set<Date>()
        var landmarkNames = Set<String>()
        let cityNames = CityNames.canonical(for: stays)

        for stay in stays {
            let interval = DateInterval(start: stay.arrival, end: max(stay.departure ?? Date(), stay.arrival))
            let stayDays = calendar.days(in: interval)
            days.formUnion(stayDays)
            guard let code = stay.countryCode else { continue }
            var summary = byCountry[code] ?? CountrySummary(code: code, name: Self.countryName(code: code, fallback: stay.country))
            summary.days.formUnion(stayDays)
            summary.firstVisit = min(summary.firstVisit, stay.arrival)
            summary.lastVisit = max(summary.lastVisit, stay.departure ?? Date())
            if let key = CityNames.key(stay), let city = cityNames[key] {
                summary.cities[city, default: 0] += 1
                cities.insert("\(code)|\(city)")
            }
            if stay.isLandmark, let name = stay.placeName, landmarkNames.insert(name).inserted {
                summary.landmarks.append(name)
                landmarks.append(stay)
            }
            byCountry[code] = summary
        }

        countries = byCountry.values.sorted { $0.days.count > $1.days.count }
        cityCount = cities.count
        trackedDays = days.count
        firstDay = days.min()
        landmarks.sort { $0.arrival > $1.arrival }
        frequentPlaces = Self.clusters(of: stays)
    }

    /// The same insights pointing at another context's copies of the places.
    func rehomed(in context: ModelContext) -> WorldInsights {
        var copy = self
        copy.landmarks = landmarks.compactMap { context.model(for: $0.persistentModelID) as? Stay }
        copy.frequentPlaces = frequentPlaces.compactMap { place in
            (context.model(for: place.representative.persistentModelID) as? Stay).map {
                FrequentPlace(representative: $0, visits: place.visits, totalTime: place.totalTime)
            }
        }
        return copy
    }

    static func countryName(code: String, fallback: String?) -> String {
        appLocale.localizedString(forRegionCode: code) ?? fallback ?? code
    }

    /// Groups stays within 150 m of each other; places visited at least three times. Cluster
    /// centres sit in a grid of 150 m cells, so each stay only looks at the cells around it.
    private static func clusters(of stays: [Stay]) -> [FrequentPlace] {
        var clusters: [(center: Stay, location: CLLocation, members: [Stay])] = []
        var grid: [Int64: [Int]] = [:]
        let cell = KnownPlaces.radius
        func coordinates(_ stay: Stay) -> (Int64, Int64) {
            // Metres east and north, near enough for picking neighbouring cells.
            let y = stay.latitude * 111_320
            let x = stay.longitude * 111_320 * cos(stay.latitude * .pi / 180)
            return (Int64((x / cell).rounded(.down)), Int64((y / cell).rounded(.down)))
        }
        func key(_ x: Int64, _ y: Int64) -> Int64 { x &* 1_000_003 &+ y }
        let durations = stays.map(\.duration)
        for index in stays.indices.sorted(by: { durations[$0] > durations[$1] }) {
            let stay = stays[index]
            let location = stay.location
            let (x, y) = coordinates(stay)
            var found: Int?
            search: for dx in -1...1 {
                for dy in -1...1 {
                    for candidate in grid[key(x + Int64(dx), y + Int64(dy))] ?? []
                    where clusters[candidate].location.distance(from: location) <= KnownPlaces.radius {
                        found = candidate
                        break search
                    }
                }
            }
            if let found {
                clusters[found].members.append(stay)
            } else {
                grid[key(x, y), default: []].append(clusters.count)
                clusters.append((stay, location, [stay]))
            }
        }
        return clusters
            .filter { $0.members.count >= 3 }
            .map { cluster in
                let named = cluster.members.first { $0.customName != nil } ?? cluster.center
                return FrequentPlace(representative: named, visits: cluster.members.count,
                                     totalTime: cluster.members.reduce(0) { $0 + $1.duration })
            }
            .sorted { $0.totalTime > $1.totalTime }
            .prefix(12)
            .map { $0 }
    }
}

// MARK: - City names

/// The same city can be stored under two names ("上海" and "Shanghai") when places were named
/// while the device used different languages. Names in one country whose places lie within
/// 25 km are one city, shown under the name that fits the app's language.
enum CityNames {
    static func key(_ stay: Stay) -> String? {
        stay.city.map { "\(stay.countryCode ?? "")|\($0)" }
    }

    /// Maps each `key(_:)` to the city name to show.
    static func canonical(for stays: [Stay]) -> [String: String] {
        struct Name { var name: String; var country: String; var lat = 0.0; var lon = 0.0; var count = 0 }
        var names: [String: Name] = [:]
        for stay in stays {
            guard let key = key(stay), let city = stay.city else { continue }
            var entry = names[key] ?? Name(name: city, country: stay.countryCode ?? "")
            entry.lat += stay.latitude
            entry.lon += stay.longitude
            entry.count += 1
            names[key] = entry
        }
        let keys = Array(names.keys)
        let centers = keys.map { key in
            let n = names[key]!
            return (country: n.country, location: CLLocation(latitude: n.lat / Double(n.count), longitude: n.lon / Double(n.count)))
        }

        // Union names that are the same city.
        var parent = Dictionary(uniqueKeysWithValues: keys.map { ($0, $0) })
        func root(_ k: String) -> String { var k = k; while let p = parent[k], p != k { k = p }; return k }
        for i in keys.indices {
            for j in (i + 1)..<keys.count where centers[i].country == centers[j].country {
                // Cheap check first: 25 km is well under 0.3° of latitude.
                guard abs(centers[i].location.coordinate.latitude - centers[j].location.coordinate.latitude) < 0.3 else { continue }
                if centers[i].location.distance(from: centers[j].location) < 25_000 { parent[root(keys[j])] = root(keys[i]) }
            }
        }

        let prefersChinese = appLocale.language.languageCode == .chinese
        var result: [String: String] = [:]
        for group in Dictionary(grouping: keys, by: root).values {
            let members = group.compactMap { names[$0] }
            let fitting = members.filter { hasHan($0.name) == prefersChinese }
            let best = (fitting.isEmpty ? members : fitting).max { $0.count < $1.count }?.name ?? members[0].name
            for key in group { result[key] = best }
        }
        return result
    }

    private static func hasHan(_ text: String) -> Bool {
        text.unicodeScalars.contains { (0x4E00...0x9FFF).contains($0.value) || (0x3400...0x4DBF).contains($0.value) }
    }
}

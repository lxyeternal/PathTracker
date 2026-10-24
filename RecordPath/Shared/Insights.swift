import Foundation
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
    var sortedCities: [String] { cities.sorted { $0.value > $1.value }.map(\.key) }

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

        for stay in stays {
            let interval = DateInterval(start: stay.arrival, end: max(stay.departure ?? Date(), stay.arrival))
            let stayDays = calendar.days(in: interval)
            days.formUnion(stayDays)
            guard let code = stay.countryCode else { continue }
            var summary = byCountry[code] ?? CountrySummary(code: code, name: Self.countryName(code: code, fallback: stay.country))
            summary.days.formUnion(stayDays)
            summary.firstVisit = min(summary.firstVisit, stay.arrival)
            summary.lastVisit = max(summary.lastVisit, stay.departure ?? Date())
            if let city = stay.city {
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

    static func countryName(code: String, fallback: String?) -> String {
        Locale.current.localizedString(forRegionCode: code) ?? fallback ?? code
    }

    /// Groups stays within 150 m of each other; places visited at least three times.
    private static func clusters(of stays: [Stay]) -> [FrequentPlace] {
        var clusters: [(center: Stay, members: [Stay])] = []
        for stay in stays.sorted(by: { $0.duration > $1.duration }) {
            if let index = clusters.firstIndex(where: { $0.center.location.distance(from: stay.location) <= KnownPlaces.radius }) {
                clusters[index].members.append(stay)
            } else {
                clusters.append((stay, [stay]))
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

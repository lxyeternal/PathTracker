import Foundation
import CoreLocation

/// Finds the trips already in your history: runs of days spent well away from where you lived
/// that year. Most come from imported photos ("杭州 · 2020年8月21日–23日"), so they can be kept as
/// trips with one tap instead of being rebuilt by hand.
enum TripFinder {
    struct Found: Identifiable, Hashable, Sendable {
        let start: Date
        let end: Date
        let title: String
        let cities: [String]
        let countryCode: String?
        let places: Int
        let latitude: Double
        let longitude: Double

        var id: String { "\(Int(start.timeIntervalSince1970))-\(Int(end.timeIntervalSince1970))" }
        var interval: DateInterval { DateInterval(start: start, end: max(end, start)) }
        var center: CLLocation { CLLocation(latitude: latitude, longitude: longitude) }

        var days: Int {
            let calendar = Calendar.current
            // The end is midnight after the last day.
            let last = max(start, end.addingTimeInterval(-1))
            return (calendar.dateComponents([.day], from: calendar.startOfDay(for: start), to: calendar.startOfDay(for: last)).day ?? 0) + 1
        }
    }

    /// A stay reduced to what finding trips needs.
    struct Visit: Sendable {
        let arrival: Date
        let departure: Date
        let latitude: Double
        let longitude: Double
        let city: String?
        let countryCode: String?
        var location: CLLocation { CLLocation(latitude: latitude, longitude: longitude) }
    }

    static let awayDistance: CLLocationDistance = 80_000

    static func find(_ visits: [Visit], calendar: Calendar = .current) -> [Found] {
        guard !visits.isEmpty else { return [] }
        let homes = homes(visits, calendar: calendar)

        // The days spent away, with what happened on each.
        var awayDays: [Date: [Visit]] = [:]
        for visit in visits {
            let year = calendar.component(.year, from: visit.arrival)
            guard let home = homes[year] ?? homes.values.first,
                  visit.location.distance(from: home) > awayDistance else { continue }
            awayDays[calendar.startOfDay(for: visit.arrival), default: []].append(visit)
        }
        // Days at home end a trip; a single quiet day in between doesn't.
        var homeDays = Set<Date>()
        for visit in visits {
            let year = calendar.component(.year, from: visit.arrival)
            if let home = homes[year] ?? homes.values.first, visit.location.distance(from: home) <= awayDistance {
                homeDays.insert(calendar.startOfDay(for: visit.arrival))
            }
        }

        var found: [Found] = []
        var run: [Date] = []
        func close() {
            defer { run = [] }
            guard let first = run.first, let last = run.last else { return }
            let members = run.flatMap { awayDays[$0] ?? [] }
            let farthest = members.map { visit -> CLLocationDistance in
                let year = calendar.component(.year, from: visit.arrival)
                return (homes[year] ?? homes.values.first).map { visit.location.distance(from: $0) } ?? 0
            }.max() ?? 0
            // A day out nearby isn't a trip; a day somewhere far is.
            guard run.count >= 2 || farthest > 300_000 else { return }
            let cities = Dictionary(grouping: members.compactMap(\.city), by: { $0 })
                .sorted { $0.value.count > $1.value.count }.map(\.key)
            let countries = Dictionary(grouping: members.compactMap(\.countryCode), by: { $0 })
                .sorted { $0.value.count > $1.value.count }.map(\.key)
            let lat = members.map(\.latitude).reduce(0, +) / Double(members.count)
            let lon = members.map(\.longitude).reduce(0, +) / Double(members.count)
            let end = calendar.date(byAdding: .day, value: 1, to: last) ?? last
            found.append(Found(start: first, end: end, title: title(cities: cities, countries: countries),
                               cities: Array(cities.prefix(4)), countryCode: countries.first, places: members.count,
                               latitude: lat, longitude: lon))
        }
        for day in awayDays.keys.sorted() {
            if let previous = run.last {
                let gap = calendar.dateComponents([.day], from: previous, to: day).day ?? 99
                let wentHome = (1..<max(gap, 1)).contains { offset in
                    calendar.date(byAdding: .day, value: offset, to: previous).map(homeDays.contains) ?? false
                }
                // A jump to another part of the world is another trip, even on the next day.
                let jumped = centre(of: awayDays[previous] ?? []).distance(from: centre(of: awayDays[day] ?? [])) > 2_500_000
                if gap > 2 || wentHome || jumped { close() }
            }
            run.append(day)
        }
        close()
        return found.sorted { $0.start > $1.start }
    }

    private static func centre(of visits: [Visit]) -> CLLocation {
        guard !visits.isEmpty else { return CLLocation(latitude: 0, longitude: 0) }
        return CLLocation(latitude: visits.map(\.latitude).reduce(0, +) / Double(visits.count),
                          longitude: visits.map(\.longitude).reduce(0, +) / Double(visits.count))
    }

    /// Where home was each year: the ~20 km area with the most distinct days.
    static func homes(_ visits: [Visit], calendar: Calendar = .current) -> [Int: CLLocation] {
        var cells: [Int: [String: (days: Set<Date>, lat: Double, lon: Double, count: Int)]] = [:]
        for visit in visits {
            let year = calendar.component(.year, from: visit.arrival)
            let key = "\(Int((visit.latitude * 5).rounded()))|\(Int((visit.longitude * 5).rounded()))"
            var cell = cells[year]?[key] ?? ([], 0, 0, 0)
            cell.days.insert(calendar.startOfDay(for: visit.arrival))
            cell.lat += visit.latitude
            cell.lon += visit.longitude
            cell.count += 1
            cells[year, default: [:]][key] = cell
        }
        return cells.compactMapValues { yearCells in
            guard let best = yearCells.values.max(by: { $0.days.count < $1.days.count }), best.days.count >= 5 else { return nil }
            return CLLocation(latitude: best.lat / Double(best.count), longitude: best.lon / Double(best.count))
        }
    }

    /// "杭州之旅", or the country for a trip across several of its cities abroad.
    private static func title(cities: [String], countries: [String]) -> String {
        if let code = countries.first, code != "CN", cities.count >= 3 || countries.count > 1 {
            let name = WorldInsights.countryName(code: code, fallback: nil)
            return String(localized: "\(name)之旅", bundle: .appLanguage)
        }
        if let city = cities.first { return String(localized: "\(city)之旅", bundle: .appLanguage) }
        return String(localized: "一次出行", bundle: .appLanguage)
    }
}

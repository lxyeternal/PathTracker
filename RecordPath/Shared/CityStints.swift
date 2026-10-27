import Foundation
import CoreLocation

/// Time spent in one city in one go: consecutive days there become one entry, so three
/// days in Hangzhou read as "杭州 · 8月21日–23日" rather than dozens of separate stops.
struct CityStint: Identifiable, Hashable {
    let city: String
    let countryCode: String?
    let stays: [Stay]
    let start: Date
    let end: Date

    var id: String { "\(countryCode ?? "")|\(city)|\(start.timeIntervalSince1970)" }

    static func == (lhs: Self, rhs: Self) -> Bool { lhs.id == rhs.id && lhs.stays.count == rhs.stays.count }
    func hash(into hasher: inout Hasher) { hasher.combine(id) }

    var interval: DateInterval { DateInterval(start: start, end: max(end, start)) }

    var days: Int {
        let calendar = Calendar.current
        return (calendar.dateComponents([.day], from: calendar.startOfDay(for: start), to: calendar.startOfDay(for: end)).day ?? 0) + 1
    }

    /// Photos and videos taken there, counted when the visits came from the library.
    var photoCount: Int { stays.filter(\.isFromPhotos).reduce(0) { $0 + max($1.sampleCount, 1) } }

    /// The stop that best stands for the stint: a sight, a named place, else the longest.
    var representative: Stay {
        stays.first(where: \.isLandmark) ?? stays.first(where: { $0.customName != nil })
            ?? stays.max { $0.duration < $1.duration } ?? stays[0]
    }

    var center: CLLocation {
        let lat = stays.map(\.latitude).reduce(0, +) / Double(stays.count)
        let lon = stays.map(\.longitude).reduce(0, +) / Double(stays.count)
        return CLLocation(latitude: lat, longitude: lon)
    }

    /// Groups stays by city into runs of consecutive days, newest first. A run breaks after
    /// a day away, and at a month so home doesn't become one entry spanning years.
    static func group(_ stays: [Stay], calendar: Calendar = .current) -> [CityStint] {
        let names = CityNames.canonical(for: stays)
        var open: [String: (city: String, code: String?, members: [Stay], start: Date, end: Date)] = [:]
        var finished: [CityStint] = []
        func close(_ key: String) {
            guard let run = open.removeValue(forKey: key) else { return }
            finished.append(CityStint(city: run.city, countryCode: run.code, stays: run.members.reversed(), start: run.start, end: run.end))
        }
        for stay in stays.sorted(by: { $0.arrival < $1.arrival }) {
            let city = CityNames.key(stay).flatMap { names[$0] } ?? stay.city
                ?? String(localized: "未识别的地方", bundle: .appLanguage)
            let key = "\(stay.countryCode ?? "")|\(city)"
            let end = max(stay.departure ?? stay.arrival, stay.arrival)
            if let run = open[key] {
                let gap = calendar.dateComponents([.day], from: calendar.startOfDay(for: run.end), to: calendar.startOfDay(for: stay.arrival)).day ?? 0
                let sameMonth = calendar.isDate(run.start, equalTo: stay.arrival, toGranularity: .month)
                if gap <= 1, sameMonth || run.end.timeIntervalSince(run.start) < 7 * 86_400 {
                    open[key]?.members.append(stay)
                    open[key]?.end = max(run.end, end)
                    continue
                }
                close(key)
            }
            open[key] = (city, stay.countryCode, [stay], stay.arrival, end)
        }
        for key in Array(open.keys) { close(key) }
        return finished.sorted { $0.start > $1.start }
    }
}

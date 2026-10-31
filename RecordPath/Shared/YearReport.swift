import Foundation
import CoreLocation

/// A year in footprints: how far, how many places, which were new, the standout days.
struct YearReport {
    struct Movement {
        let start: Date
        let distance: Double
        let mode: MovementMode
    }

    struct Place {
        let name: String
        let detail: String?
        let visits: Int
        let distance: Double
        /// One visit there, for its picture.
        var stay: Stay?
    }

    let year: Int
    var daysRecorded = 0
    /// Everything moved, flights included.
    var distance: Double = 0
    var flightDistance: Double = 0
    /// Distance on the ground: the year's headline number, with flights said separately.
    var groundDistance: Double { distance - flightDistance }
    var steps: Double = 0
    var walkingDistance: Double = 0
    var countries: [String] = []
    var newCountries: [String] = []
    var cities: [String] = []
    var newCities: [String] = []
    var provinces: [String] = []
    var newProvinces: [String] = []
    var longestDay: (date: Date, distance: Double)?
    var busiestMonth: (month: Date, distance: Double)?
    var favoritePlace: Place?
    var farthestPlace: Place?
    var trips = 0
    var recordings = 0

    var isEmpty: Bool { daysRecorded == 0 }

    /// Ground distance as a share of the way round the equator.
    var shareOfEquator: Double { groundDistance / 40_075_000 }
    var marathons: Double { walkingDistance / 42_195 }

    static func years(in stays: [Stay]) -> [Int] {
        let calendar = Calendar.current
        let years = Set(stays.map { calendar.component(.year, from: $0.arrival) })
        let current = calendar.component(.year, from: Date())
        return (years.isEmpty ? [current] : years.sorted(by: >))
    }

    static func make(year: Int, stays: [Stay], movements: [Movement], steps: [DailyActivity], trips: [Trip],
                     calendar: Calendar = .current) -> YearReport {
        var report = YearReport(year: year)
        guard let start = calendar.date(from: DateComponents(year: year, month: 1, day: 1)),
              let end = calendar.date(byAdding: .year, value: 1, to: start) else { return report }
        let year = DateInterval(start: start, end: end)
        let inYear = stays.filter { year.contains($0.arrival) }
        let before = stays.filter { $0.arrival < start }
        let cityNames = CityNames.canonical(for: stays)
        // "First time" only means something when there are earlier years to compare with.
        let hasHistory = !before.isEmpty

        // Days and distance.
        var days = Set<Date>()
        for stay in inYear {
            days.formUnion(calendar.days(in: DateInterval(start: stay.arrival, end: max(stay.departure ?? Date(), stay.arrival))))
        }
        let moves = movements.filter { year.contains($0.start) }
        days.formUnion(moves.map { calendar.startOfDay(for: $0.start) })
        report.daysRecorded = days.filter { year.contains($0) }.count
        report.distance = moves.reduce(0) { $0 + $1.distance }
        report.flightDistance = moves.filter { $0.mode == .flying }.reduce(0) { $0 + $1.distance }
        let yearSteps = steps.filter { year.contains($0.day) }
        report.steps = yearSteps.reduce(0) { $0 + $1.steps }
        report.walkingDistance = yearSteps.reduce(0) { $0 + $1.walkingDistance }

        // Standout days and months, on the ground.
        let ground = moves.filter { $0.mode != .flying }
        let byDay = Dictionary(grouping: ground) { calendar.startOfDay(for: $0.start) }.mapValues { $0.reduce(0) { $0 + $1.distance } }
        report.longestDay = byDay.max { $0.value < $1.value }.map { ($0.key, $0.value) }
        let byMonth = Dictionary(grouping: ground) { calendar.dateInterval(of: .month, for: $0.start)?.start ?? $0.start }
            .mapValues { $0.reduce(0) { $0 + $1.distance } }
        report.busiestMonth = byMonth.max { $0.value < $1.value }.map { ($0.key, $0.value) }

        // Places, and which were seen for the first time.
        func codes(_ stays: [Stay]) -> [String] {
            Dictionary(grouping: stays.compactMap(\.countryCode), by: { $0 }).sorted { $0.value.count > $1.value.count }.map(\.key)
        }
        func cityKeys(_ stays: [Stay]) -> [String] { stays.compactMap { CityNames.key($0).flatMap { cityNames[$0] } }.removingDuplicates() }
        func provinceIDs(_ stays: [Stay]) -> [String] {
            stays.compactMap { Province.containing(countryCode: $0.countryCode, region: $0.region, city: $0.city)?.id }.removingDuplicates()
        }
        report.countries = codes(inYear)
        report.cities = cityKeys(inYear)
        report.provinces = provinceIDs(inYear)
        if hasHistory {
            // Worked out once, not once per place.
            let seenCountries = Set(before.compactMap(\.countryCode)), seenCities = Set(cityKeys(before)), seenProvinces = Set(provinceIDs(before))
            report.newCountries = report.countries.filter { !seenCountries.contains($0) }
            report.newCities = report.cities.filter { !seenCities.contains($0) }
            report.newProvinces = report.provinces.filter { !seenProvinces.contains($0) }
        }

        // Home is where the most time went; the favourite is where you went most, apart from home.
        let clusters = cluster(inYear)
        if let home = clusters.max(by: { $0.time < $1.time }) {
            let others = clusters.filter { $0.center !== home.center }
            if let favorite = others.max(by: { ($0.members.count, $0.time) < ($1.members.count, $1.time) }), favorite.members.count >= 2 {
                report.favoritePlace = Place(name: favorite.name, detail: favorite.center.subtitle, visits: favorite.members.count,
                                             distance: favorite.center.location.distance(from: home.center.location),
                                             stay: favorite.center)
            }
            if let farthest = inYear.max(by: { $0.location.distance(from: home.center.location) < $1.location.distance(from: home.center.location) }) {
                let distance = farthest.location.distance(from: home.center.location)
                if distance > 50_000 {
                    report.farthestPlace = Place(name: CityNames.key(farthest).flatMap { cityNames[$0] } ?? farthest.displayName,
                                                 detail: farthest.country, visits: 1, distance: distance, stay: farthest)
                }
            }
        }

        let yearTrips = trips.filter { year.contains($0.startDate) }
        report.trips = yearTrips.filter { !$0.isRecording }.count
        report.recordings = yearTrips.filter(\.isRecording).count
        return report
    }

    private struct Cluster {
        let center: Stay
        var members: [Stay]
        var time: TimeInterval { members.reduce(0) { $0 + $1.duration } }
        var name: String { (members.first { $0.customName != nil } ?? center).displayName }
    }

    /// Groups stays within 150 m of the longest stay near them. Centres sit in a grid of
    /// 150 m cells, so each stay only looks at the cells around it, not every cluster.
    private static func cluster(_ stays: [Stay]) -> [Cluster] {
        var clusters: [Cluster] = []
        var centers: [CLLocation] = []
        var grid: [Int64: [Int]] = [:]
        let cell = KnownPlaces.radius
        func coordinates(_ stay: Stay) -> (Int64, Int64) {
            let y = stay.latitude * 111_320
            let x = stay.longitude * 111_320 * cos(stay.latitude * .pi / 180)
            return (Int64((x / cell).rounded(.down)), Int64((y / cell).rounded(.down)))
        }
        func key(_ x: Int64, _ y: Int64) -> Int64 { x &* 1_000_003 &+ y }
        for stay in stays.sorted(by: { $0.duration > $1.duration }) {
            let location = stay.location
            let (x, y) = coordinates(stay)
            // The earliest cluster in reach, as a scan through all of them would find.
            var found: Int?
            for dx in -1...1 {
                for dy in -1...1 {
                    for candidate in grid[key(x + Int64(dx), y + Int64(dy))] ?? []
                    where candidate < (found ?? .max) && centers[candidate].distance(from: location) <= KnownPlaces.radius {
                        found = candidate
                    }
                }
            }
            if let found {
                clusters[found].members.append(stay)
            } else {
                grid[key(x, y), default: []].append(clusters.count)
                clusters.append(Cluster(center: stay, members: [stay]))
                centers.append(location)
            }
        }
        return clusters
    }
}

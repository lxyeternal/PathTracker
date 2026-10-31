import Foundation
import CoreLocation
import CryptoKit

/// One day of someone's footprints, reduced to what comparing with a friend needs and no
/// more: the ~20 km areas they were in, and the ~1 km cells they were in hour by hour. No
/// names, routes or exact places; nothing within 2 km of home, work or a privacy zone.
struct FootprintDay: Hashable, Sendable {
    /// ~20 km (0.2°) square, enough to say "the same city".
    struct Area: Hashable, Sendable {
        var lat: Int16
        var lon: Int16
    }

    /// A ~1 km (0.01°) square during one hour (hours since 1970, UTC).
    struct Slot: Hashable, Sendable {
        var hour: Int32
        var lat: Int32
        var lon: Int32
    }

    /// The local date where they were, "2019-05-03".
    var day: String
    var areas: Set<Area> = []
    var slots: Set<Slot> = []

    // MARK: Bytes, as stored in iCloud

    var areasData: Data {
        var data = Data()
        for area in areas.sorted(by: { ($0.lat, $0.lon) < ($1.lat, $1.lon) }) {
            data.append(area.lat)
            data.append(area.lon)
        }
        return data
    }

    var slotsData: Data {
        var data = Data()
        for slot in slots.sorted(by: { ($0.hour, $0.lat, $0.lon) < ($1.hour, $1.lat, $1.lon) }) {
            data.append(slot.hour)
            data.append(slot.lat)
            data.append(slot.lon)
        }
        return data
    }

    /// Changes whenever anything in the day does, to upload only what changed.
    var fingerprint: String {
        SHA256.hash(data: Data(day.utf8) + areasData + slotsData).prefix(12).map { String(format: "%02x", $0) }.joined()
    }

    init(day: String, areas: Set<Area> = [], slots: Set<Slot> = []) {
        self.day = day
        self.areas = areas
        self.slots = slots
    }

    init(day: String, areasData: Data, slotsData: Data) {
        self.day = day
        var reader = ByteReader(areasData)
        while let lat: Int16 = reader.next(), let lon: Int16 = reader.next() { areas.insert(Area(lat: lat, lon: lon)) }
        reader = ByteReader(slotsData)
        while let hour: Int32 = reader.next(), let lat: Int32 = reader.next(), let lon: Int32 = reader.next() {
            slots.insert(Slot(hour: hour, lat: lat, lon: lon))
        }
    }
}

private extension Data {
    mutating func append<T: FixedWidthInteger>(_ value: T) {
        Swift.withUnsafeBytes(of: value.littleEndian) { append(contentsOf: $0) }
    }
}

private struct ByteReader {
    private let data: Data
    private var offset = 0

    init(_ data: Data) { self.data = data }

    mutating func next<T: FixedWidthInteger>() -> T? {
        let size = MemoryLayout<T>.size
        guard offset + size <= data.count else { return nil }
        var value: T = 0
        withUnsafeMutableBytes(of: &value) { $0.copyBytes(from: data[data.startIndex + offset ..< data.startIndex + offset + size]) }
        offset += size
        return T(littleEndian: value)
    }
}

/// Turns the history into footprint days.
enum FootprintDigest {
    /// Nothing this close to home, work, school or a privacy zone is shared.
    static let privateRadius: CLLocationDistance = 2_000
    /// A long stay (a hotel for a fortnight) counts for at most this long.
    static let longestStay: TimeInterval = 14 * 86_400

    /// Something seen somewhere: a stay from its arrival to departure, or a track point.
    struct Sighting: Sendable {
        var latitude: Double
        var longitude: Double
        var start: Date
        var end: Date
        var timeZone: TimeZone
    }

    static func area(latitude: Double, longitude: Double) -> FootprintDay.Area {
        FootprintDay.Area(lat: Int16((latitude * 5).rounded(.down)), lon: Int16((longitude * 5).rounded(.down)))
    }

    static func cell(latitude: Double, longitude: Double) -> (lat: Int32, lon: Int32) {
        (Int32((latitude * 100).rounded(.down)), Int32((longitude * 100).rounded(.down)))
    }

    /// The middle of a ~1 km cell or a ~20 km area.
    static func center(lat: Int32, lon: Int32) -> CLLocationCoordinate2D {
        CLLocationCoordinate2D(latitude: (Double(lat) + 0.5) / 100, longitude: (Double(lon) + 0.5) / 100)
    }

    static func center(of area: FootprintDay.Area) -> CLLocationCoordinate2D {
        CLLocationCoordinate2D(latitude: (Double(area.lat) + 0.5) / 5, longitude: (Double(area.lon) + 0.5) / 5)
    }

    static func dayString(_ date: Date, in zone: TimeZone) -> String {
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = zone
        let parts = calendar.dateComponents([.year, .month, .day], from: date)
        return String(format: "%04d-%02d-%02d", parts.year ?? 0, parts.month ?? 0, parts.day ?? 0)
    }

    static func date(of day: String) -> Date? {
        let parts = day.split(separator: "-").compactMap { Int($0) }
        guard parts.count == 3 else { return nil }
        return Calendar.current.date(from: DateComponents(year: parts[0], month: parts[1], day: parts[2]))
    }

    /// Every day something was seen, keyed by its date.
    static func days(from sightings: [Sighting], excluding hidden: [CLLocation]) -> [String: FootprintDay] {
        var days: [String: FootprintDay] = [:]
        for sighting in sightings {
            let place = CLLocation(latitude: sighting.latitude, longitude: sighting.longitude)
            let isPrivate = hidden.contains { $0.distance(from: place) <= privateRadius }
            let area = area(latitude: sighting.latitude, longitude: sighting.longitude)
            let cell = cell(latitude: sighting.latitude, longitude: sighting.longitude)
            let end = min(max(sighting.end, sighting.start), sighting.start.addingTimeInterval(longestStay))
            var hour = Int32(sighting.start.timeIntervalSince1970 / 3600)
            let last = Int32(end.timeIntervalSince1970 / 3600)
            while hour <= last {
                let moment = max(Date(timeIntervalSince1970: TimeInterval(hour) * 3600), sighting.start)
                let key = dayString(moment, in: sighting.timeZone)
                var day = days[key] ?? FootprintDay(day: key)
                day.areas.insert(area)
                if !isPrivate { day.slots.insert(FootprintDay.Slot(hour: hour, lat: cell.lat, lon: cell.lon)) }
                days[key] = day
                hour += 1
            }
        }
        return days
    }
}

/// Where two people's footprints met.
struct ParallelResult: Sendable {
    /// Within ~1 km of each other in the same hour.
    struct Moment: Identifiable, Hashable, Sendable {
        var hour: Int32
        var lat: Int32
        var lon: Int32
        var id: String { "\(hour)-\(lat)-\(lon)" }
        var date: Date { Date(timeIntervalSince1970: TimeInterval(hour) * 3600) }
        var coordinate: CLLocationCoordinate2D { FootprintDigest.center(lat: lat, lon: lon) }
    }

    /// The same ~20 km area on the same day.
    struct SameDay: Identifiable, Hashable, Sendable {
        var day: String
        var area: FootprintDay.Area
        var id: String { day }
        var date: Date? { FootprintDigest.date(of: day) }
    }

    /// The same ~1 km place, at different times: each one's latest time there.
    struct Echo: Identifiable, Hashable, Sendable {
        var lat: Int32
        var lon: Int32
        var mine: Date
        var theirs: Date
        var id: String { "\(lat)-\(lon)" }
        var coordinate: CLLocationCoordinate2D { FootprintDigest.center(lat: lat, lon: lon) }
    }

    var passedBy: [Moment] = []
    var sameDays: [SameDay] = []
    var samePlaces: [Echo] = []
    var sharedAreas: Set<FootprintDay.Area> = []

    var isEmpty: Bool { passedBy.isEmpty && sameDays.isEmpty && samePlaces.isEmpty }
}

enum ParallelMatch {
    static func compare(mine: [FootprintDay], theirs: [FootprintDay]) -> ParallelResult {
        var result = ParallelResult()

        // Passing by: the same hour, the same or a neighbouring cell. A run of such hours in
        // one place is one moment.
        var theirCells: [Int32: [(Int32, Int32)]] = [:]
        for day in theirs { for slot in day.slots { theirCells[slot.hour, default: []].append((slot.lat, slot.lon)) } }
        let mySlots = mine.flatMap(\.slots).sorted { ($0.hour, $0.lat, $0.lon) < ($1.hour, $1.lat, $1.lon) }
        var moments: [ParallelResult.Moment] = []
        for slot in mySlots {
            guard let cells = theirCells[slot.hour],
                  cells.contains(where: { abs($0.0 - slot.lat) <= 1 && abs($0.1 - slot.lon) <= 1 }) else { continue }
            if let last = moments.last, slot.hour - last.hour <= 3, abs(last.lat - slot.lat) <= 1, abs(last.lon - slot.lon) <= 1 { continue }
            moments.append(ParallelResult.Moment(hour: slot.hour, lat: slot.lat, lon: slot.lon))
        }
        result.passedBy = moments.reversed()

        // The same city on the same day: the same area or the one next to it, since a city
        // can straddle the grid.
        let theirAreas = Dictionary(theirs.map { ($0.day, $0.areas) }, uniquingKeysWith: { $0.union($1) })
        for day in mine {
            guard let others = theirAreas[day.day],
                  let area = day.areas.first(where: { mine in others.contains { abs(Int($0.lat) - Int(mine.lat)) <= 1 && abs(Int($0.lon) - Int(mine.lon)) <= 1 } })
            else { continue }
            result.sameDays.append(ParallelResult.SameDay(day: day.day, area: area))
        }
        result.sameDays.sort { $0.day > $1.day }
        result.sharedAreas = Set(mine.flatMap(\.areas)).intersection(theirs.flatMap(\.areas))

        // The same place at different times. Places are grouped ~3 km wide so one
        // neighbourhood reads once; times within a few hours were passing by instead.
        func latest(_ days: [FootprintDay]) -> [Int64: (hour: Int32, lat: Int32, lon: Int32)] {
            var found: [Int64: (hour: Int32, lat: Int32, lon: Int32)] = [:]
            for slot in days.flatMap(\.slots) {
                let key = Int64(slot.lat.floorDivided(by: 3)) << 32 | Int64(UInt32(bitPattern: slot.lon.floorDivided(by: 3)))
                if (found[key]?.hour ?? .min) < slot.hour { found[key] = (slot.hour, slot.lat, slot.lon) }
            }
            return found
        }
        let myPlaces = latest(mine), theirPlaces = latest(theirs)
        let passedCells = Set(moments.map { Int64($0.lat.floorDivided(by: 3)) << 32 | Int64(UInt32(bitPattern: $0.lon.floorDivided(by: 3))) })
        for (key, me) in myPlaces {
            guard let them = theirPlaces[key], !passedCells.contains(key), abs(me.hour - them.hour) > 3 else { continue }
            result.samePlaces.append(ParallelResult.Echo(lat: me.lat, lon: me.lon,
                                                         mine: Date(timeIntervalSince1970: TimeInterval(me.hour) * 3600),
                                                         theirs: Date(timeIntervalSince1970: TimeInterval(them.hour) * 3600)))
        }
        result.samePlaces.sort { max($0.mine, $0.theirs) > max($1.mine, $1.theirs) }
        return result
    }
}

private extension Int32 {
    /// Division that rounds down for negatives too, so cells west of Greenwich group evenly.
    func floorDivided(by divisor: Int32) -> Int32 {
        let quotient = self / divisor
        return (self % divisor != 0 && (self < 0) != (divisor < 0)) ? quotient - 1 : quotient
    }
}

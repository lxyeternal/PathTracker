import Foundation
import SwiftData
import CoreLocation

// CloudKit-backed SwiftData rules: every attribute has a default or is optional,
// no unique constraints, and every relationship is optional with an inverse.

/// An immutable slice of recorded movement. Points are packed into one blob so a day
/// of all-day tracking is a few dozen CloudKit records instead of thousands.
@Model
final class TrackChunk {
    var startDate: Date = Date.distantPast
    var endDate: Date = Date.distantPast
    var distance: Double = 0
    var pointCount: Int = 0
    var minLatitude: Double = 0
    var maxLatitude: Double = 0
    var minLongitude: Double = 0
    var maxLongitude: Double = 0
    var modeRaw: String = MovementMode.unknown.rawValue
    /// Set while a trip was recording, so trip tracks can be told apart from all-day ones.
    var tripID: UUID?
    @Attribute(.externalStorage) var pointsData: Data?

    init(points: [TrackPoint], mode: MovementMode, tripID: UUID?) {
        self.startDate = points.first?.timestamp ?? Date()
        self.endDate = points.last?.timestamp ?? Date()
        self.pointCount = points.count
        self.distance = TrackPoint.distance(of: points)
        self.modeRaw = mode.rawValue
        self.tripID = tripID
        self.minLatitude = points.map(\.latitude).min() ?? 0
        self.maxLatitude = points.map(\.latitude).max() ?? 0
        self.minLongitude = points.map(\.longitude).min() ?? 0
        self.maxLongitude = points.map(\.longitude).max() ?? 0
        self.pointsData = TrackCodec.encode(points)
    }

    var mode: MovementMode { MovementMode(rawValue: modeRaw) ?? .unknown }

    var points: [TrackPoint] {
        guard let pointsData else { return [] }
        return TrackCodec.decode(pointsData)
    }
}

/// A place the user stayed at for a while: home, school, a café, a landmark.
@Model
final class Stay {
    var id: UUID = UUID()
    var arrival: Date = Date.distantPast
    /// nil while the user is still there.
    var departure: Date?
    var latitude: Double = 0
    var longitude: Double = 0
    var sampleCount: Int = 0

    var placeName: String?
    var categoryRaw: String?
    var street: String?
    var city: String?
    var region: String?
    var country: String?
    var countryCode: String?
    var isLandmark: Bool = false
    var tagStateRaw: Int = TagState.pending.rawValue

    /// What the user called this place ("家", "学校"); wins over everything else.
    var customName: String?
    var note: String?

    init(arrival: Date, coordinate: CLLocationCoordinate2D) {
        self.arrival = arrival
        self.latitude = coordinate.latitude
        self.longitude = coordinate.longitude
        self.sampleCount = 1
    }

    var coordinate: CLLocationCoordinate2D {
        CLLocationCoordinate2D(latitude: latitude, longitude: longitude)
    }

    var location: CLLocation { CLLocation(latitude: latitude, longitude: longitude) }

    var tagState: TagState {
        get { TagState(rawValue: tagStateRaw) ?? .pending }
        set { tagStateRaw = newValue.rawValue }
    }

    var displayName: String {
        customName ?? placeName ?? street ?? city ?? String(localized: "未知地点")
    }

    var subtitle: String? {
        let parts = [city, country].compactMap { $0 }.removingDuplicates()
        return parts.isEmpty ? nil : parts.joined(separator: " · ")
    }

    var duration: TimeInterval { (departure ?? Date()).timeIntervalSince(arrival) }

    var category: PlaceCategory { PlaceCategory(rawValue: categoryRaw) }
}

enum TagState: Int {
    case pending = 0, tagged = 1, failed = 2
}

/// A named journey ("日本 7 日"). Its track is every chunk inside its time range.
@Model
final class Trip {
    var id: UUID = UUID()
    var title: String = ""
    var startDate: Date = Date()
    var endDate: Date?
    var notes: String = ""
    var coverEmoji: String = "🧭"
    @Relationship(deleteRule: .cascade, inverse: \TripPhoto.trip) var photos: [TripPhoto]? = []

    init(title: String, startDate: Date = Date()) {
        self.title = title
        self.startDate = startDate
    }

    var isActive: Bool { endDate == nil }
    var interval: DateInterval { DateInterval(start: startDate, end: max(endDate ?? Date(), startDate)) }

    /// "2026年10月5日" for one day, "2026年9月22日至25日" for several. A trip ending exactly at
    /// midnight doesn't count the next day.
    var dateRangeText: String {
        let calendar = Calendar.current
        let lastMoment = max(interval.start, interval.end.addingTimeInterval(-1))
        if calendar.isDate(interval.start, inSameDayAs: lastMoment) {
            return interval.start.formatted(.dateTime.year().month().day())
        }
        return (interval.start..<lastMoment).formatted(.interval.year().month().day())
    }
}

@Model
final class TripPhoto {
    var id: UUID = UUID()
    @Attribute(.externalStorage) var imageData: Data?
    var takenAt: Date = Date()
    var latitude: Double?
    var longitude: Double?
    var caption: String?
    var trip: Trip?

    init(imageData: Data, takenAt: Date, coordinate: CLLocationCoordinate2D?) {
        self.imageData = imageData
        self.takenAt = takenAt
        self.latitude = coordinate?.latitude
        self.longitude = coordinate?.longitude
    }
}

enum MovementMode: String, CaseIterable {
    case walking, running, cycling, automotive, flying, unknown

    var title: String {
        switch self {
        case .walking: String(localized: "步行")
        case .running: String(localized: "跑步")
        case .cycling: String(localized: "骑行")
        case .automotive: String(localized: "乘车")
        case .flying: String(localized: "飞行")
        case .unknown: String(localized: "移动")
        }
    }

    var symbol: String {
        switch self {
        case .walking: "figure.walk"
        case .running: "figure.run"
        case .cycling: "bicycle"
        case .automotive: "car.fill"
        case .flying: "airplane"
        case .unknown: "location.north.line.fill"
        }
    }
}

extension Array where Element: Hashable {
    func removingDuplicates() -> [Element] {
        var seen = Set<Element>()
        return filter { seen.insert($0).inserted }
    }
}

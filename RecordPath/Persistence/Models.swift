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
    /// The words of a post about this visit.
    var note: String?
    /// Where this visit came from: nil when recorded, "photos" when found in the photo library.
    var sourceRaw: String?
    /// The place's own time zone ("Asia/Tokyo"), so its times read as they were there.
    var timeZoneID: String?
    /// Photos posted for this visit.
    @Relationship(deleteRule: .cascade, inverse: \TripPhoto.stay) var photos: [TripPhoto]? = []

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
        customName ?? placeName ?? street ?? city ?? String(localized: "未知地点", bundle: .appLanguage)
    }

    var subtitle: String? {
        let parts = [city, country].compactMap { $0 }.removingDuplicates()
        return parts.isEmpty ? nil : parts.joined(separator: " · ")
    }

    var duration: TimeInterval { (departure ?? Date()).timeIntervalSince(arrival) }

    /// The place's time zone when its clock differs from this device's at the time of the
    /// visit; nil when they read the same.
    var localTimeZone: TimeZone? {
        guard let zone = timeZoneID.flatMap(TimeZone.init(identifier:)),
              zone.secondsFromGMT(for: arrival) != TimeZone.current.secondsFromGMT(for: arrival) else { return nil }
        return zone
    }

    var category: PlaceCategory { PlaceCategory(rawValue: categoryRaw) }
    var isFromPhotos: Bool { sourceRaw == PhotoFootprints.source }
}

enum TagState: Int {
    case pending = 0, tagged = 1, failed = 2
}

/// Either a trip ("日本 7 日"), days of travel gathered from all-day recording, or a recording
/// ("徒步 · 10月25日"), one activity recorded on its own at higher precision. Its track is every
/// chunk inside its time range.
@Model
final class Trip {
    var id: UUID = UUID()
    var title: String = ""
    var startDate: Date = Date()
    var endDate: Date?
    var notes: String = ""
    var coverEmoji: String = "🧭"
    /// Set for a recording (hiking, running…); nil for a trip.
    var activityRaw: String?
    @Relationship(deleteRule: .cascade, inverse: \TripPhoto.trip) var photos: [TripPhoto]? = []

    init(title: String, startDate: Date = Date()) {
        self.title = title
        self.startDate = startDate
    }

    var isActive: Bool { endDate == nil }
    var activity: ActivityType? { activityRaw.flatMap(ActivityType.init(rawValue:)) }
    var isRecording: Bool { activityRaw != nil }
    var interval: DateInterval { DateInterval(start: startDate, end: max(endDate ?? Date(), startDate)) }

    /// "2026年10月5日" for one day, "2026年9月22日至25日" for several. A trip ending exactly at
    /// midnight doesn't count the next day.
    var dateRangeText: String {
        let calendar = Calendar.current
        let lastMoment = max(interval.start, interval.end.addingTimeInterval(-1))
        if calendar.isDate(interval.start, inSameDayAs: lastMoment) {
            return interval.start.formatted(.dateTime.year().month().day().locale(appLocale))
        }
        return (interval.start..<lastMoment).formatted(.interval.year().month().day().locale(appLocale))
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
    /// The place visit it was posted for, if any.
    var stay: Stay?

    init(imageData: Data, takenAt: Date, coordinate: CLLocationCoordinate2D?) {
        self.imageData = imageData
        self.takenAt = takenAt
        self.latitude = coordinate?.latitude
        self.longitude = coordinate?.longitude
    }
}

enum MovementMode: String, CaseIterable {
    case walking, running, cycling, automotive, subway, flying, unknown

    var title: String {
        switch self {
        case .walking: String(localized: "步行", bundle: .appLanguage)
        case .running: String(localized: "跑步", bundle: .appLanguage)
        case .cycling: String(localized: "骑行", bundle: .appLanguage)
        case .automotive: String(localized: "乘车", bundle: .appLanguage)
        case .subway: String(localized: "地铁", bundle: .appLanguage)
        case .flying: String(localized: "飞行", bundle: .appLanguage)
        case .unknown: String(localized: "移动", bundle: .appLanguage)
        }
    }

    var symbol: String {
        switch self {
        case .walking: "figure.walk"
        case .running: "figure.run"
        case .cycling: "bicycle"
        case .automotive: "car.fill"
        case .subway: "tram.fill.tunnel"
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

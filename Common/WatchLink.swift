import Foundation
import CoreLocation
import HealthKit

// Shared by the iPhone and Watch apps. The iPhone does the all-day recording; the Watch shows
// where you are and today's route, and records on its own when you start a recording there.

/// What the iPhone sends the Watch: just enough to draw "where am I, and where have I been today".
struct WatchSnapshot: Codable, Equatable {
    struct Coordinate: Codable, Equatable {
        var lat: Double
        var lon: Double
        var clCoordinate: CLLocationCoordinate2D { CLLocationCoordinate2D(latitude: lat, longitude: lon) }
    }

    struct Place: Codable, Equatable {
        var name: String
        var detail: String?
        var coordinate: Coordinate
        var arrival: Date
        /// nil while the user is still there.
        var departure: Date?
    }

    var generatedAt = Date()
    /// AppLanguage raw value, so the Watch speaks the language chosen on the iPhone.
    var language = "system"
    /// Today's movement, one array per continuous stretch so gaps aren't drawn as straight lines.
    var segments: [[Coordinate]] = []
    var places: [Place] = []
    var distance: Double = 0
    var steps: Double = 0
    /// All-day recording is on and not paused.
    var isRecording = false
    var pausedUntil: Date?
    var isEnabled = true
    /// Watch recordings the iPhone has filed away; the Watch keeps each one until it's listed here.
    var receivedRecordings: [UUID] = []
    /// A manual recording running on the iPhone right now.
    var activeRecording: ActiveRecording?

    /// The place the user is at right now, if the iPhone thinks they are staying somewhere.
    var currentPlace: Place? { places.last { $0.departure == nil } }

    static let key = "snapshot"

    init() {}

    /// Missing fields fall back to defaults, so an iPhone and Watch on different app versions
    /// (mid-update) still understand each other.
    init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        generatedAt = try c.decodeIfPresent(Date.self, forKey: .generatedAt) ?? .distantPast
        language = try c.decodeIfPresent(String.self, forKey: .language) ?? "system"
        segments = try c.decodeIfPresent([[Coordinate]].self, forKey: .segments) ?? []
        places = try c.decodeIfPresent([Place].self, forKey: .places) ?? []
        distance = try c.decodeIfPresent(Double.self, forKey: .distance) ?? 0
        steps = try c.decodeIfPresent(Double.self, forKey: .steps) ?? 0
        isRecording = try c.decodeIfPresent(Bool.self, forKey: .isRecording) ?? false
        pausedUntil = try c.decodeIfPresent(Date.self, forKey: .pausedUntil)
        isEnabled = try c.decodeIfPresent(Bool.self, forKey: .isEnabled) ?? true
        receivedRecordings = try c.decodeIfPresent([UUID].self, forKey: .receivedRecordings) ?? []
        activeRecording = try c.decodeIfPresent(ActiveRecording.self, forKey: .activeRecording)
    }

    func encoded() -> Data? { try? JSONEncoder().encode(self) }
    static func decode(_ data: Data?) -> WatchSnapshot? {
        data.flatMap { try? JSONDecoder().decode(WatchSnapshot.self, from: $0) }
    }
}

/// A manual recording started on the iPhone, as the Watch sees it.
struct ActiveRecording: Codable, Equatable {
    var tripID: UUID
    var title: String
    var emoji: String
    var start: Date
    /// Set when the user asked for the Watch to record along (heart rate, a workout in Fitness).
    var watchActivity: WatchActivity?
}

/// Requests the Watch sends to the iPhone.
enum WatchCommand: String {
    case pause, resume, refresh, endRecording

    static let key = "command"
    static let untilKey = "until"
    static let tripKey = "trip"
}

/// Kinds of recording the Watch can start, matching the workout types in the Fitness app.
enum WatchActivity: String, CaseIterable, Identifiable, Codable {
    case hiking, walking, running, cycling

    var id: String { rawValue }

    var title: String {
        switch self {
        case .hiking: String(localized: "徒步", bundle: .appLanguage)
        case .walking: String(localized: "步行", bundle: .appLanguage)
        case .running: String(localized: "跑步", bundle: .appLanguage)
        case .cycling: String(localized: "骑行", bundle: .appLanguage)
        }
    }

    var symbol: String {
        switch self {
        case .hiking: "figure.hiking"
        case .walking: "figure.walk"
        case .running: "figure.run"
        case .cycling: "figure.outdoor.cycle"
        }
    }

    var emoji: String {
        switch self {
        case .hiking: "🥾"
        case .walking: "🚶"
        case .running: "🏃"
        case .cycling: "🚴"
        }
    }

    /// What the Watch records for a trip with this icon, or nil for trips that aren't a workout
    /// (driving, flying, taking the train).
    static func forTripEmoji(_ emoji: String) -> WatchActivity? {
        switch emoji {
        case "✈️", "🚗", "🚆": nil
        case "🚲": .cycling
        case "🥾", "🏔️", "🗻", "🏕️", "🎒": .hiking
        default: .walking
        }
    }
}

extension WatchActivity {
    var workoutType: HKWorkoutActivityType {
        switch self {
        case .hiking: .hiking
        case .walking: .walking
        case .running: .running
        case .cycling: .cycling
        }
    }

    init(workoutType: HKWorkoutActivityType) {
        switch workoutType {
        case .hiking: self = .hiking
        case .running: self = .running
        case .cycling: self = .cycling
        default: self = .walking
        }
    }
}

/// Metadata sent along with a track file recorded on the Watch.
struct WatchRecordingInfo: Codable, Equatable {
    var id: UUID
    var activity: WatchActivity
    var start: Date
    var end: Date
    var distance: Double
    /// The iPhone trip this was recorded alongside, if it was started from the iPhone.
    var tripID: UUID?

    static let key = "recording"
    static let trackKey = "track"
    /// Recordings up to this size also go straight over as a message when the iPhone is in
    /// reach; bigger ones only travel as a file transfer.
    static let messageLimit = 60_000

    var metadata: [String: Any] {
        guard let data = try? JSONEncoder().encode(self) else { return [:] }
        return [Self.key: data]
    }

    init(id: UUID, activity: WatchActivity, start: Date, end: Date, distance: Double, tripID: UUID? = nil) {
        self.id = id
        self.activity = activity
        self.start = start
        self.end = end
        self.distance = distance
        self.tripID = tripID
    }

    init?(metadata: [String: Any]?) {
        guard let data = metadata?[Self.key] as? Data,
              let info = try? JSONDecoder().decode(WatchRecordingInfo.self, from: data) else { return nil }
        self = info
    }
}

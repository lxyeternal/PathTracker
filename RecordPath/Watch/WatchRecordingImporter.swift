import Foundation
import SwiftData

/// Files a recording made on the Watch as a finished trip, so it shows in Trips with its map
/// and in that day's timeline.
enum WatchRecordingImporter {
    @MainActor
    @discardableResult
    static func importRecording(points: [TrackPoint], info: WatchRecordingInfo, into context: ModelContext) -> Trip? {
        // The Watch resends until it hears back, so the same recording can arrive twice.
        let id = info.id
        defer { markReceived(id) }
        if receivedIDs.contains(id) { return nil }
        if let existing = try? context.fetch(FetchDescriptor<Trip>(predicate: #Predicate { $0.id == id })).first {
            return existing
        }
        guard info.end > info.start else { return nil }

        // Recorded alongside an iPhone recording: it belongs to that trip, not a new one.
        let trip: Trip
        if let linked = info.tripID,
           let existing = try? context.fetch(FetchDescriptor<Trip>(predicate: #Predicate { $0.id == linked })).first {
            trip = existing
        } else {
            trip = Trip(title: defaultTitle(for: info), startDate: info.start)
            trip.id = info.id
            trip.endDate = info.end
            trip.coverEmoji = info.activity.emoji
            trip.activityRaw = info.activity.rawValue
            context.insert(trip)
        }

        // If the iPhone was along, it recorded the same route; a trip's track is every chunk in
        // its time range, so only add the Watch's points where the iPhone has none.
        let recorded = ((try? context.fetch(FetchDescriptor<TrackChunk>())) ?? [])
            .map { DateInterval(start: $0.startDate, end: max($0.endDate, $0.startDate)) }
        let span = DateInterval(start: info.start, end: info.end)
        if points.count > 1, !GPXImporter.isAlreadyRecorded(span, in: recorded) {
            for start in stride(from: 0, to: points.count, by: 400) {
                let slice = Array(points[max(0, start - 1)..<min(start + 400, points.count)])
                guard slice.count > 1 else { continue }
                context.insert(TrackChunk(points: slice, mode: mode(for: info.activity), tripID: trip.id))
            }
        }
        try? context.save()
        return trip
    }

    private static let receivedKey = "watch.receivedRecordings"

    /// The most recent recordings filed away, reported back to the Watch so it can delete its copy.
    static var receivedIDs: [UUID] {
        (UserDefaults.standard.stringArray(forKey: receivedKey) ?? []).compactMap(UUID.init(uuidString:))
    }

    private static func markReceived(_ id: UUID) {
        let ids = ([id] + receivedIDs.filter { $0 != id }).prefix(50)
        UserDefaults.standard.set(ids.map(\.uuidString), forKey: receivedKey)
    }

    static func mode(for activity: ActivityType) -> MovementMode {
        switch activity {
        case .hiking, .walking: .walking
        case .running: .running
        case .cycling: .cycling
        }
    }

    static func defaultTitle(for info: WatchRecordingInfo) -> String {
        let day = info.start.formatted(.dateTime.month().day().locale(appLocale))
        return "\(info.activity.title) · \(day)"
    }
}

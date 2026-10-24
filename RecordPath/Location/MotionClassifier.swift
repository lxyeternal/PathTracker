import Foundation
import CoreMotion

/// Works out how a stretch of track was travelled, using the motion coprocessor when
/// available and falling back to speed.
final class MotionClassifier {
    private let manager = CMMotionActivityManager()

    func mode(from start: Date, to end: Date, points: [TrackPoint]) async -> MovementMode {
        let speedMode = Self.mode(forSpeeds: points.map(\.speed))
        guard CMMotionActivityManager.isActivityAvailable(),
              CMMotionActivityManager.authorizationStatus() != .denied else { return speedMode }

        let activities: [CMMotionActivity] = await withCheckedContinuation { continuation in
            manager.queryActivityStarting(from: start, to: end, to: .main) { activities, _ in
                continuation.resume(returning: activities ?? [])
            }
        }
        guard !activities.isEmpty else { return speedMode }

        var weights: [MovementMode: TimeInterval] = [:]
        for (activity, next) in zip(activities, activities.dropFirst().map(Optional.some) + [nil]) {
            guard activity.confidence != .low else { continue }
            let span = (next?.startDate ?? end).timeIntervalSince(max(activity.startDate, start))
            let mode: MovementMode? =
                activity.automotive ? .automotive :
                activity.cycling ? .cycling :
                activity.running ? .running :
                activity.walking ? .walking : nil
            if let mode, span > 0 { weights[mode, default: 0] += span }
        }
        guard var best = weights.max(by: { $0.value < $1.value })?.key else { return speedMode }
        if speedMode == .flying { best = .flying }
        return best
    }

    static func mode(forSpeeds speeds: [Double]) -> MovementMode {
        let moving = speeds.filter { $0 > 0.3 }.sorted()
        guard !moving.isEmpty else { return .walking }
        let median = moving[moving.count / 2]
        switch median {
        case 60...: return .flying
        case 7..<60: return .automotive
        case 2.6..<7: return .cycling
        default: return .walking
        }
    }
}

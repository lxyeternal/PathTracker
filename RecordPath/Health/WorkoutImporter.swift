import Foundation
import HealthKit
import SwiftData
import CoreLocation

/// Brings the routes of past workouts in Health (an Apple Watch's, or any app that saves its
/// routes there) in as tracks, so the years before the app was installed have distance too.
enum WorkoutImporter {
    struct Result: Equatable {
        /// Workouts whose route became tracks.
        var imported = 0
        /// Workouts whose time is already recorded.
        var alreadyRecorded = 0
        /// Workouts with no route in Health: indoor ones, or saved by an app that keeps its route.
        var withoutRoute = 0
        var distance: Double = 0

        var total: Int { imported + alreadyRecorded + withoutRoute }
    }

    static var isAvailable: Bool { HKHealthStore.isHealthDataAvailable() }

    /// How a workout counts in the statistics. Anything that isn't on foot or by bike (skiing,
    /// rowing, skating…) is just "moving": its speed would otherwise pass for a car.
    static func mode(for activity: HKWorkoutActivityType) -> MovementMode {
        switch activity {
        case .walking, .hiking: .walking
        case .running: .running
        case .cycling, .handCycling: .cycling
        default: .unknown
        }
    }

    /// A route as the app stores one: oldest first, a point about every five metres rather than
    /// the Watch's one a second, and cut wherever the workout paused so a pause isn't drawn as
    /// a straight line.
    static func segments(of points: [TrackPoint], spacing: Double = 5, pause: TimeInterval = 120) -> [[TrackPoint]] {
        var segments: [[TrackPoint]] = []
        var current: [TrackPoint] = []
        var previous: TrackPoint?
        for point in points.sorted(by: { $0.timestamp < $1.timestamp }) {
            if let previous, point.timestamp.timeIntervalSince(previous.timestamp) > pause {
                // The last point before a pause is where the line ends, however close to the one kept.
                if current.last != previous { current.append(previous) }
                segments.append(current)
                current = []
            }
            if let kept = current.last {
                if kept.location.distance(from: point.location) >= spacing { current.append(point) }
            } else {
                current.append(point)
            }
            previous = point
        }
        if let previous, current.last != previous { current.append(previous) }
        segments.append(current)
        return segments.filter { $0.count > 1 }
    }

    /// Asks for workouts and their routes, then files every route that isn't recorded yet.
    /// Running it again only adds what is new.
    @MainActor
    static func importAll(into context: ModelContext, progress: @MainActor (Int, Int) -> Void = { _, _ in }) async -> Result {
        guard isAvailable else { return Result() }
        let store = HKHealthStore()
        try? await store.requestAuthorization(toShare: [], read: [HKObjectType.workoutType(), HKSeriesType.workoutRoute()])

        let query = HKSampleQueryDescriptor(predicates: [.workout()], sortDescriptors: [SortDescriptor(\.startDate)])
        let workouts = (try? await query.result(for: store)) ?? []
        var recorded = ((try? context.fetch(FetchDescriptor<TrackChunk>())) ?? [])
            .map { DateInterval(start: $0.startDate, end: max($0.endDate, $0.startDate)) }

        var result = Result()
        for (index, workout) in workouts.enumerated() {
            if Task.isCancelled { break }
            progress(index, workouts.count)
            let span = DateInterval(start: workout.startDate, end: max(workout.endDate, workout.startDate))
            // The same hour can't be travelled twice: the phone was along, the Watch app already
            // sent this recording, or two apps saved the same workout.
            if GPXImporter.isAlreadyRecorded(span, in: recorded) {
                result.alreadyRecorded += 1
                continue
            }
            let parts = segments(of: await route(of: workout, in: store))
            guard !parts.isEmpty else {
                result.withoutRoute += 1
                continue
            }
            let mode = mode(for: workout.workoutActivityType)
            for part in parts {
                for start in stride(from: 0, to: part.count, by: 400) {
                    let slice = Array(part[max(0, start - 1)..<min(start + 400, part.count)])
                    guard slice.count > 1 else { continue }
                    let chunk = TrackChunk(points: slice, mode: mode, tripID: nil)
                    context.insert(chunk)
                    result.distance += chunk.distance
                }
            }
            recorded.append(span)
            result.imported += 1
            if result.imported.isMultiple(of: 25) { try? context.save() }
        }
        progress(workouts.count, workouts.count)
        try? context.save()
        return result
    }

    /// Every location of a workout's route, or none when Health has no route for it.
    private static func route(of workout: HKWorkout, in store: HKHealthStore) async -> [TrackPoint] {
        let query = HKSampleQueryDescriptor(
            predicates: [.workoutRoute(HKQuery.predicateForObjects(from: workout))], sortDescriptors: [])
        let routes = (try? await query.result(for: store)) ?? []
        var points: [TrackPoint] = []
        for route in routes {
            do {
                for try await location in HKWorkoutRouteQueryDescriptor(route).results(for: store)
                where location.horizontalAccuracy >= 0 && location.horizontalAccuracy <= 100 {
                    points.append(TrackPoint(location))
                }
            } catch {
                continue
            }
        }
        return points
    }

    #if DEBUG
    /// Two outdoor workouts with routes and an indoor one without, written to the simulator's
    /// Health so the import has something to read.
    static func seedSamples() async {
        let store = HKHealthStore()
        let types: Set<HKSampleType> = [HKObjectType.workoutType(), HKSeriesType.workoutRoute()]
        try? await store.requestAuthorization(toShare: types, read: types)
        let samples: [(HKWorkoutActivityType, Int, Double, Bool)] = [(.cycling, 400, 6, true), (.hiking, 380, 1.3, true), (.cycling, 370, 0, false)]
        for (activity, daysAgo, speed, outdoors) in samples {
            let start = Calendar.current.startOfDay(for: Date()).addingTimeInterval(Double(-daysAgo) * 86_400 + 9 * 3_600)
            let seconds = 3_600
            let configuration = HKWorkoutConfiguration()
            configuration.activityType = activity
            configuration.locationType = outdoors ? .outdoor : .indoor
            let builder = HKWorkoutBuilder(healthStore: store, configuration: configuration, device: .local())
            do {
                try await builder.beginCollection(at: start)
                try await builder.endCollection(at: start.addingTimeInterval(Double(seconds)))
                guard let workout = try await builder.finishWorkout(), outdoors else { continue }
                // Along the West Lake shore, with a ten-minute stop halfway.
                let locations = (0...seconds).filter { $0 < 1_500 || $0 > 2_100 }.map { second -> CLLocation in
                    let moved = Double(second < 1_500 ? second : second - 600) * speed
                    return CLLocation(coordinate: CLLocationCoordinate2D(latitude: 30.23 + moved / 111_000 * 0.8,
                                                                         longitude: 120.14 + sin(moved / 900) * 0.01),
                                      altitude: 10, horizontalAccuracy: 5, verticalAccuracy: 5,
                                      timestamp: start.addingTimeInterval(Double(second)))
                }
                let route = HKWorkoutRouteBuilder(healthStore: store, device: .local())
                try await route.insertRouteData(locations)
                try await route.finishRoute(with: workout, metadata: nil)
            } catch {
                print("Sample workout failed: \(error)")
            }
        }
    }
    #endif
}

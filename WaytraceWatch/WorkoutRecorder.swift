import Foundation
import HealthKit
import CoreLocation
import os

/// Records a route on the Watch by itself, the way hiking apps do: a workout session keeps the
/// app running with the wrist down, GPS draws the route, and the result is saved to Health (so
/// it appears in Fitness) and sent to the iPhone.
@MainActor
@Observable
final class WorkoutRecorder: NSObject {
    static let shared = WorkoutRecorder()

    enum State: Equatable { case idle, starting, running, paused, saving, finished }

    struct Summary: Equatable {
        var activity: ActivityType
        var distance: Double
        var duration: TimeInterval
    }

    private(set) var state: State = .idle
    private(set) var activity: ActivityType = .walking
    private(set) var points: [TrackPoint] = []
    private(set) var heartRate: Double?
    private(set) var startDate: Date?
    private(set) var summary: Summary?
    private(set) var errorMessage: String?
    private(set) var locationAuthorization: CLAuthorizationStatus
    /// Recording along with a manual recording on the iPhone (started from there).
    private(set) var isLinkedToPhone = false
    /// That iPhone recording, once the iPhone has said which one it is.
    private(set) var linkedTripID: UUID?

    /// The activity chosen last time, offered first.
    var lastActivity: ActivityType {
        ActivityType(rawValue: UserDefaults.standard.string(forKey: "watch.lastActivity") ?? "") ?? .walking
    }

    var isActive: Bool { state != .idle && state != .finished }

    private let store = HKHealthStore()
    private let manager = CLLocationManager()
    private var session: HKWorkoutSession?
    private var builder: HKLiveWorkoutBuilder?
    private var routeBuilder: HKWorkoutRouteBuilder?
    private var builderDistance: Double = 0
    private var routeDistance: Double = 0
    private let log = Logger(subsystem: "PathTracker", category: "WorkoutRecorder")

    private override init() {
        locationAuthorization = manager.authorizationStatus
        super.init()
        manager.delegate = self
        manager.desiredAccuracy = kCLLocationAccuracyBest
        manager.activityType = .fitness
    }

    /// GPS distance is what the map shows; the workout's own distance (from steps and GPS
    /// together) is used once it has something, since it handles poor signal better.
    var distance: Double { builderDistance > 0 ? builderDistance : routeDistance }

    func elapsed(at date: Date) -> TimeInterval { builder?.elapsedTime(at: date) ?? 0 }

    func requestLocationPermission() {
        if manager.authorizationStatus == .notDetermined { manager.requestWhenInUseAuthorization() }
    }

    // MARK: Control

    func start(_ activity: ActivityType, linkedToPhone: Bool = false) async {
        guard state == .idle || state == .finished else { return }
        self.activity = activity
        isLinkedToPhone = linkedToPhone
        // On a cold launch the last snapshot may be from an earlier recording: only trust one
        // that began moments ago; the iPhone's next snapshot says for sure (see `link(to:)`).
        let cached = PhoneLink.shared.snapshot?.activeRecording
        linkedTripID = linkedToPhone && cached.map { Date().timeIntervalSince($0.start) < 5 * 60 } == true ? cached?.tripID : nil
        UserDefaults.standard.set(activity.rawValue, forKey: "watch.lastActivity")
        state = .starting
        errorMessage = nil
        summary = nil
        points = []
        heartRate = nil
        builderDistance = 0
        routeDistance = 0

        do {
            try await store.requestAuthorization(toShare: Self.shareTypes, read: Self.readTypes)
            let configuration = HKWorkoutConfiguration()
            configuration.activityType = activity.workoutType
            configuration.locationType = .outdoor
            let session = try HKWorkoutSession(healthStore: store, configuration: configuration)
            let builder = session.associatedWorkoutBuilder()
            builder.dataSource = HKLiveWorkoutDataSource(healthStore: store, workoutConfiguration: configuration)
            session.delegate = self
            builder.delegate = self
            self.session = session
            self.builder = builder
            routeBuilder = HKWorkoutRouteBuilder(healthStore: store, device: nil)

            let start = Date()
            startDate = start
            session.startActivity(with: start)
            try await builder.beginCollection(at: start)
            requestLocationPermission()
            manager.allowsBackgroundLocationUpdates = true
            manager.startUpdatingLocation()
            state = .running
        } catch {
            log.error("Couldn't start workout: \(error.localizedDescription)")
            errorMessage = String(localized: "无法开始记录。请在 iPhone 的“健康”App 中允许漫迹记录体能训练。", bundle: .appLanguage)
            reset()
        }
    }

    /// The iPhone said which recording this goes with. It replaces a guess from a cached snapshot.
    func link(to tripID: UUID) {
        guard isLinkedToPhone, linkedTripID != tripID else { return }
        linkedTripID = tripID
    }

    func pause() { session?.pause() }
    func resume() { session?.resume() }

    /// Ends the recording. Ended on the Watch, a linked iPhone recording ends too; ended because
    /// the iPhone recording ended, there's nothing to tell it.
    func end(becauseIPhoneEnded: Bool = false) async {
        guard let session, let builder, let startDate, isActive else { return }
        if isLinkedToPhone, !becauseIPhoneEnded, let linkedTripID { PhoneLink.shared.endIPhoneRecording(linkedTripID) }
        state = .saving
        manager.stopUpdatingLocation()
        let end = Date()
        let duration = builder.elapsedTime(at: end)
        session.end()
        do {
            try await builder.endCollection(at: end)
            if let workout = try await builder.finishWorkout(), let routeBuilder, points.count > 1 {
                _ = try? await routeBuilder.finishRoute(with: workout, metadata: nil)
            }
        } catch {
            // Health couldn't save it; the route itself is still kept and sent to the iPhone.
            log.error("Couldn't save workout: \(error.localizedDescription)")
        }

        let info = WatchRecordingInfo(id: UUID(), activity: activity, start: startDate, end: end, distance: distance,
                                      tripID: linkedTripID)
        if points.count > 1 { PhoneLink.shared.deliver(points: points, info: info) }
        summary = Summary(activity: activity, distance: distance, duration: duration)
        reset()
        state = .finished
    }

    func clearError() { errorMessage = nil }

    /// Leaves the summary screen.
    func dismissSummary() {
        summary = nil
        state = .idle
    }

    private func reset() {
        isLinkedToPhone = false
        linkedTripID = nil
        session = nil
        builder = nil
        routeBuilder = nil
        startDate = nil
        if state != .saving { state = .idle }
    }

    // MARK: Data

    private func add(_ locations: [CLLocation]) {
        guard state == .running else { return }
        let good = locations.filter { $0.horizontalAccuracy > 0 && $0.horizontalAccuracy <= 50 }
        guard !good.isEmpty else { return }
        for location in good {
            if let last = points.last?.location {
                // Ignore jitter while standing still.
                let step = location.distance(from: last)
                guard step >= 3 else { continue }
                routeDistance += step
            }
            points.append(TrackPoint(location))
        }
        routeBuilder?.insertRouteData(good) { _, _ in }
    }

    private func update(from statistics: [HKQuantityType: HKStatistics]) {
        for (type, stats) in statistics {
            switch type {
            case HKQuantityType(.heartRate):
                heartRate = stats.mostRecentQuantity()?.doubleValue(for: .count().unitDivided(by: .minute()))
            case HKQuantityType(.distanceWalkingRunning), HKQuantityType(.distanceCycling):
                builderDistance = stats.sumQuantity()?.doubleValue(for: .meter()) ?? builderDistance
            default:
                break
            }
        }
    }

    private static let shareTypes: Set<HKSampleType> = [.workoutType(), HKSeriesType.workoutRoute()]
    private static let readTypes: Set<HKObjectType> = [
        HKQuantityType(.heartRate), HKQuantityType(.distanceWalkingRunning),
        HKQuantityType(.distanceCycling), HKQuantityType(.activeEnergyBurned),
    ]
}

extension WorkoutRecorder: HKWorkoutSessionDelegate {
    nonisolated func workoutSession(_ workoutSession: HKWorkoutSession, didChangeTo toState: HKWorkoutSessionState,
                                    from fromState: HKWorkoutSessionState, date: Date) {
        Task { @MainActor in
            switch toState {
            case .running where self.state == .paused: self.state = .running
            case .paused where self.state == .running: self.state = .paused
            default: break
            }
        }
    }

    nonisolated func workoutSession(_ workoutSession: HKWorkoutSession, didFailWithError error: Error) {
        Task { @MainActor in self.log.error("Workout session failed: \(error.localizedDescription)") }
    }
}

extension WorkoutRecorder: HKLiveWorkoutBuilderDelegate {
    nonisolated func workoutBuilder(_ workoutBuilder: HKLiveWorkoutBuilder, didCollectDataOf collectedTypes: Set<HKSampleType>) {
        let statistics = Dictionary(uniqueKeysWithValues: collectedTypes.compactMap { type -> (HKQuantityType, HKStatistics)? in
            guard let type = type as? HKQuantityType, let stats = workoutBuilder.statistics(for: type) else { return nil }
            return (type, stats)
        })
        let sendable = SendableStatistics(value: statistics)
        Task { @MainActor in self.update(from: sendable.value) }
    }

    nonisolated func workoutBuilderDidCollectEvent(_ workoutBuilder: HKLiveWorkoutBuilder) {}
}

extension WorkoutRecorder: CLLocationManagerDelegate {
    nonisolated func locationManager(_ manager: CLLocationManager, didUpdateLocations locations: [CLLocation]) {
        Task { @MainActor in self.add(locations) }
    }

    nonisolated func locationManagerDidChangeAuthorization(_ manager: CLLocationManager) {
        let status = manager.authorizationStatus
        Task { @MainActor in self.locationAuthorization = status }
    }

    nonisolated func locationManager(_ manager: CLLocationManager, didFailWithError error: Error) {}
}

/// HealthKit statistics are immutable snapshots; this only moves them to the main actor.
private struct SendableStatistics: @unchecked Sendable { let value: [HKQuantityType: HKStatistics] }

import ActivityKit
import Foundation
import HealthKit
import SwiftData
import os

/// Ties a manual recording on the iPhone to the wrist: a Live Activity (which iOS also shows in
/// the Apple Watch Smart Stack) for as long as it runs, and, when asked for, the Watch app
/// opening by itself to record along.
@MainActor
final class LiveRecording {
    private let context: ModelContext
    private let engine: LocationEngine
    private let health = HKHealthStore()
    private var activity: Activity<RecordingAttributes>?
    private var updateTask: Task<Void, Never>?
    private var saveObserver: NSObjectProtocol?
    private var lastSentDistance: Double = -1
    private let log = Logger(subsystem: "PathTracker", category: "LiveRecording")

    init(context: ModelContext, engine: LocationEngine) {
        self.context = context
        self.engine = engine
    }

    func activate() {
        saveObserver = NotificationCenter.default.addObserver(forName: ModelContext.didSave, object: nil, queue: .main) { [weak self] _ in
            Task { @MainActor in self?.scheduleUpdate() }
        }
        observeEngine()
        sync()
    }

    private func observeEngine() {
        withObservationTracking {
            _ = engine.activeTripID
        } onChange: { [weak self] in
            Task { @MainActor in
                self?.sync()
                self?.observeEngine()
            }
        }
    }

    // MARK: Watch

    /// Whether the Watch should record along with this trip, chosen when it was started.
    static func watchActivity(for tripID: UUID) -> WatchActivity? {
        UserDefaults.standard.string(forKey: watchKey(tripID)).flatMap(WatchActivity.init(rawValue:))
    }

    static func setWatchActivity(_ activity: WatchActivity?, for tripID: UUID) {
        UserDefaults.standard.set(activity?.rawValue, forKey: watchKey(tripID))
    }

    private static func watchKey(_ id: UUID) -> String { "recording.watch.\(id.uuidString)" }

    /// Opens the Watch app straight into a recording, the way workout apps do.
    private func startWatchApp(_ activity: WatchActivity) {
        let configuration = HKWorkoutConfiguration()
        configuration.activityType = activity.workoutType
        configuration.locationType = .outdoor
        health.startWatchApp(with: configuration) { [log] success, error in
            if !success { log.info("Watch app didn't start: \(error?.localizedDescription ?? "no Watch nearby")") }
        }
    }

    // MARK: Live Activity

    /// Starts, keeps or ends the Live Activity so it matches the recording.
    private func sync() {
        let trip = activeTrip()
        for running in Activity<RecordingAttributes>.activities where running.attributes.tripID != trip?.id {
            Task { await running.end(nil, dismissalPolicy: .default) }
        }
        activity = Activity<RecordingAttributes>.activities.first { $0.attributes.tripID == trip?.id }
        guard let trip else {
            activity = nil
            return
        }
        guard activity == nil else { return scheduleUpdate() }

        let watch = Self.watchActivity(for: trip.id)
        // Only a just-started recording opens the Watch app; reopening the iPhone app later shouldn't.
        if let watch, Date().timeIntervalSince(trip.startDate) < 60 { startWatchApp(watch) }
        guard ActivityAuthorizationInfo().areActivitiesEnabled else { return }
        let attributes = RecordingAttributes(tripID: trip.id, title: trip.title, emoji: trip.coverEmoji, start: trip.startDate)
        let state = RecordingAttributes.ContentState(distance: distance(of: trip), watchRecording: watch != nil)
        do {
            activity = try Activity.request(attributes: attributes, content: .init(state: state, staleDate: nil))
            lastSentDistance = state.distance
        } catch {
            // Starting needs the app in the foreground; it's retried the next time it is.
            log.info("Live Activity not started: \(error.localizedDescription)")
        }
    }

    /// Distance changes with every GPS fix; the card only needs it every half minute.
    private func scheduleUpdate() {
        guard activity != nil, updateTask == nil else { return }
        updateTask = Task { [weak self] in
            try? await Task.sleep(for: .seconds(30))
            self?.updateTask = nil
            await self?.update()
        }
    }

    private func update() async {
        guard let activity, let trip = activeTrip(), trip.id == activity.attributes.tripID else { return }
        let distance = distance(of: trip)
        guard abs(distance - lastSentDistance) >= 10 else { return }
        lastSentDistance = distance
        let state = RecordingAttributes.ContentState(distance: distance, watchRecording: Self.watchActivity(for: trip.id) != nil)
        await activity.update(.init(state: state, staleDate: nil))
    }

    func refreshNow() {
        sync()
        Task { await update() }
    }

    private func activeTrip() -> Trip? {
        guard let id = engine.activeTripID else { return nil }
        return try? context.fetch(FetchDescriptor<Trip>(predicate: #Predicate { $0.id == id && $0.endDate == nil })).first
    }

    private func distance(of trip: Trip) -> Double {
        let id: UUID? = trip.id
        let chunks = (try? context.fetch(FetchDescriptor<TrackChunk>(predicate: #Predicate { $0.tripID == id }))) ?? []
        return chunks.reduce(0) { $0 + $1.distance } + TrackPoint.distance(of: engine.pendingPoints)
    }
}

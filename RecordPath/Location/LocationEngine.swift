import Foundation
import CoreLocation
import SwiftData
import UIKit
import os

/// The always-on recorder. It listens to Core Location's live updates (which pause by
/// themselves when the phone is still, so battery use follows how much you move),
/// writes the path into `TrackChunk`s and detects `Stay`s along the way. During a long stay
/// it turns GPS off and waits on a geofence around the stay instead.
@MainActor
@Observable
final class LocationEngine {
    enum Activity: Equatable { case off, starting, moving, stationary, unavailable }

    /// How hard to work for track detail. Manual recordings always use `.precise`.
    enum Precision: String, CaseIterable, Identifiable {
        case battery, balanced, precise
        var id: String { rawValue }
    }

    private(set) var authorization: CLAuthorizationStatus
    private(set) var isPreciseLocation = true
    private(set) var activity: Activity = .off
    private(set) var currentLocation: CLLocation?
    /// Points recorded since the last chunk was written; drawn live on the map.
    private(set) var pendingPoints: [TrackPoint] = []
    private(set) var openStay: Stay?
    private(set) var activeTripID: UUID?

    /// All-day automatic recording. A manually started recording runs on its own and is not
    /// affected by this switch.
    var isEnabled: Bool {
        didSet {
            UserDefaults.standard.set(isEnabled, forKey: Keys.enabled)
            guard activeTripID == nil else { return }
            isEnabled ? start() : stop()
        }
    }

    var precision: Precision {
        didSet {
            UserDefaults.standard.set(precision.rawValue, forKey: Keys.precision)
            if activeTripID == nil, isRecording { restart() }
        }
    }

    /// All-day recording is paused until this moment, e.g. for an hour at a private place.
    private(set) var pausedUntil: Date?

    var isPaused: Bool { pausedUntil.map { $0 > Date() } ?? false }

    /// Whether location is being recorded right now, automatically or manually.
    var isRecording: Bool { (isEnabled && !isPaused) || activeTripID != nil }

    private let context: ModelContext
    private let tagger: PlaceTagger
    private let classifier = MotionClassifier()
    private let manager = CLLocationManager()
    private let delegate = AuthorizationDelegate()
    private var updatesTask: Task<Void, Never>?
    private var backgroundSession: CLBackgroundActivitySession?
    private var anchor: (location: CLLocation, since: Date, latSum: Double, lonSum: Double, count: Int)?
    private var lastAcceptedLocation: CLLocation?
    private var rejectedJumps = 0
    private var dwellTask: Task<Void, Never>?
    private var resumeTask: Task<Void, Never>?
    /// Settled: a long stay where GPS is off and a geofence around the stay wakes us on leaving.
    private var isSettled = false
    private var settleTask: Task<Void, Never>?
    private var fenceMonitor: Task<CLMonitor, Never>?
    private var fenceWork: Task<Void, Never>?
    private let log = Logger(subsystem: "PathTracker", category: "LocationEngine")

    private enum Keys {
        static let enabled = "tracking.enabled"
        static let tripID = "tracking.activeTripID"
        static let precision = "tracking.precision"
        static let pausedUntil = "tracking.pausedUntil"
    }

    private enum Tuning {
        static let maxAccuracy: CLLocationAccuracy = 65
        static let minStepDistance: CLLocationDistance = 8
        static let stayRadius: CLLocationDistance = 120
        static let stayMinimumDwell: TimeInterval = 5 * 60
        static let stayMinimumDuration: TimeInterval = 3 * 60
        static let stayMergeGap: TimeInterval = 15 * 60
        static let chunkMaxPoints = 400
        static let chunkMaxDuration: TimeInterval = 20 * 60
        static let gapBreak: TimeInterval = 10 * 60
        /// Faster than this between two fixes, outside of a plane, is a GPS jump.
        static let maxGroundSpeed: CLLocationSpeed = 75
        static let coarseAccuracy: CLLocationAccuracy = 250
        /// How long a stay lasts before GPS hands over to the geofence. Shorter stops (a red
        /// light, a shop) keep live updates so the next stretch of path starts on time.
        static let settleAfter: TimeInterval = 10 * 60
        static let fenceRadius: CLLocationDistance = 150
    }

    private static let fenceID = "stay"

    init(context: ModelContext, tagger: PlaceTagger) {
        self.context = context
        self.tagger = tagger
        self.authorization = manager.authorizationStatus
        self.isEnabled = UserDefaults.standard.bool(forKey: Keys.enabled)
        self.activeTripID = UserDefaults.standard.string(forKey: Keys.tripID).flatMap(UUID.init)
        self.isPreciseLocation = manager.accuracyAuthorization == .fullAccuracy
        self.precision = Precision(rawValue: UserDefaults.standard.string(forKey: Keys.precision) ?? "") ?? .balanced
        let paused = UserDefaults.standard.object(forKey: Keys.pausedUntil) as? Date
        self.pausedUntil = paused.flatMap { $0 > Date() ? $0 : nil }

        manager.delegate = delegate
        delegate.onChange = { [weak self] manager in
            Task { @MainActor in self?.authorizationChanged(manager) }
        }
        delegate.onLocations = { [weak self] locations in
            Task { @MainActor in self?.handleCoarse(locations) }
        }
        delegate.onVisit = { [weak self] visit in
            Task { @MainActor in self?.handleVisit(visit) }
        }
        if isPaused { schedulePauseEnd() }
        pendingPoints = PendingTrackStore.load()
        restoreOpenStay()
        validateActiveTrip()
        if isRecording { start() }
    }

    // MARK: Permissions

    var hasAlwaysPermission: Bool { authorization == .authorizedAlways }
    var hasAnyPermission: Bool { authorization == .authorizedAlways || authorization == .authorizedWhenInUse }

    func requestWhenInUse() { manager.requestWhenInUseAuthorization() }
    /// Asks for "Always". iOS shows that prompt only once per install; after that the request is
    /// silently ignored, so later taps open the app's page in Settings instead.
    func requestAlways() {
        let key = "location.alwaysRequested"
        if UserDefaults.standard.bool(forKey: key) {
            Diagnostics.record("requestAlways -> open Settings")
            if let url = URL(string: UIApplication.openSettingsURLString) { UIApplication.shared.open(url) }
            return
        }
        UserDefaults.standard.set(true, forKey: key)
        Diagnostics.record("requestAlways prompt")
        manager.requestAlwaysAuthorization()
        // If iOS shows nothing (it already asked before this version tracked it), go to Settings.
        Task { [weak self] in
            try? await Task.sleep(for: .seconds(1.5))
            guard let self, self.authorization == .authorizedWhenInUse,
                  UIApplication.shared.applicationState == .active else { return }
            if let url = URL(string: UIApplication.openSettingsURLString) { await UIApplication.shared.open(url) }
        }
    }

    private func authorizationChanged(_ manager: CLLocationManager) {
        authorization = manager.authorizationStatus
        isPreciseLocation = manager.accuracyAuthorization == .fullAccuracy
        Diagnostics.record("authorization status=\(authorization.rawValue) precise=\(isPreciseLocation)")
        if isRecording, hasAnyPermission, updatesTask == nil, !isSettled { start() }
        if !hasAnyPermission { activity = .unavailable }
    }

    // MARK: Lifecycle

    private var usesLiveUpdates: Bool { activeTripID != nil || precision != .battery }

    private func start() {
        guard isRecording else { return }
        guard hasAnyPermission else {
            activity = authorization == .notDetermined ? .off : .unavailable
            return
        }
        updatesTask?.cancel()
        updatesTask = nil
        unsettle()
        Diagnostics.record("start precision=\(precision.rawValue) trip=\(activeTripID != nil) live=\(usesLiveUpdates) \(Diagnostics.battery)")
        // Lets iOS relaunch the app after it was terminated while the user moves on.
        manager.startMonitoringSignificantLocationChanges()
        activity = .starting
        guard usesLiveUpdates else {
            // Battery saver: system visits for places, significant changes for a rough path.
            backgroundSession?.invalidate()
            backgroundSession = nil
            manager.startMonitoringVisits()
            activity = .stationary
            return
        }
        manager.stopMonitoringVisits()
        backgroundSession = CLBackgroundActivitySession()
        // A phone lying still may get no fix at all; don't say "starting" forever.
        Task { [weak self] in
            try? await Task.sleep(for: .seconds(15))
            if self?.activity == .starting { self?.activity = .stationary }
        }
        let configuration: CLLocationUpdate.LiveConfiguration =
            activeTripID != nil || precision == .precise ? .fitness : .default
        updatesTask = Task { [weak self] in
            do {
                for try await update in CLLocationUpdate.liveUpdates(configuration) {
                    guard let self, !Task.isCancelled else { return }
                    self.handle(update)
                }
            } catch {
                self?.log.error("Live updates ended: \(error.localizedDescription)")
                Diagnostics.record("liveUpdates ended error=\(error.localizedDescription)")
            }
        }
    }

    private func stop() {
        Diagnostics.record("stop paused=\(isPaused)")
        updatesTask?.cancel()
        updatesTask = nil
        unsettle()
        backgroundSession?.invalidate()
        backgroundSession = nil
        manager.stopMonitoringVisits()
        // While paused, keep the cheap significant-change wake-ups so recording can resume on time.
        if !isPaused { manager.stopMonitoringSignificantLocationChanges() }
        flushChunk(carryOver: false)
        if let openStay { close(openStay, at: Date()) }
        anchor = nil
        dwellTask?.cancel()
        activity = .off
    }

    private func restart() {
        guard isRecording else { return }
        flushChunk(carryOver: true)
        start()
    }

    /// Called when the app moves to the background so nothing is lost if iOS kills it.
    func persistNow() {
        PendingTrackStore.save(pendingPoints)
        try? context.save()
    }

    /// Re-reads state after stays were deleted or replaced outside the engine (wiping data,
    /// deleting a visit), so it never holds on to a deleted model.
    func reloadAfterDataChange(discardPending: Bool) {
        openStay = nil
        anchor = nil
        if discardPending {
            lastAcceptedLocation = nil
            pendingPoints = []
            PendingTrackStore.save([])
        }
        restoreOpenStay()
        validateActiveTrip()
    }

    /// The recording trip can disappear underneath us (deleted here, or on another device
    /// and synced over). Without this the app would say "recording" with nothing to stop.
    private func validateActiveTrip() {
        guard let id = activeTripID else { return }
        let descriptor = FetchDescriptor<Trip>(predicate: #Predicate { $0.id == id && $0.endDate == nil })
        guard ((try? context.fetchCount(descriptor)) ?? 0) == 0 else { return }
        activeTripID = nil
        UserDefaults.standard.removeObject(forKey: Keys.tripID)
        if isRecording { restart() } else { stop() }
    }

    // MARK: Pause

    func pause(until date: Date) {
        Diagnostics.record("pause until=\(date.formatted(.iso8601))")
        pausedUntil = date
        UserDefaults.standard.set(date, forKey: Keys.pausedUntil)
        if activeTripID == nil { stop() }
        schedulePauseEnd()
    }

    func resume() {
        Diagnostics.record("resume")
        resumeTask?.cancel()
        pausedUntil = nil
        UserDefaults.standard.removeObject(forKey: Keys.pausedUntil)
        if isRecording, updatesTask == nil || !usesLiveUpdates { start() }
    }

    /// Resumes when the pause ends while the app is running; otherwise the next wake-up
    /// (a significant location change or opening the app) notices and resumes.
    private func schedulePauseEnd() {
        resumeTask?.cancel()
        guard let pausedUntil else { return }
        resumeTask = Task { [weak self] in
            try? await Task.sleep(for: .seconds(max(0, pausedUntil.timeIntervalSinceNow)))
            guard !Task.isCancelled else { return }
            self?.resume()
        }
    }

    /// Called whenever the app becomes active.
    func refreshState() {
        validateActiveTrip()
        if pausedUntil != nil, !isPaused { resume() }
        if isRecording, activity == .off { start() }
    }

    // MARK: Trips

    func beginTrip(_ trip: Trip) {
        activeTripID = trip.id
        UserDefaults.standard.set(trip.id.uuidString, forKey: Keys.tripID)
        if updatesTask == nil { start() } else { restart() }
    }

    func endTrip(_ trip: Trip) {
        trip.endDate = Date()
        // A trip gathers all-day tracks and doesn't drive recording; only a recording does.
        guard activeTripID == trip.id else {
            try? context.save()
            return
        }
        activeTripID = nil
        UserDefaults.standard.removeObject(forKey: Keys.tripID)
        // Back to all-day recording if it is on; otherwise a manual recording simply stops.
        if isEnabled { restart() } else { stop() }
        try? context.save()
    }

    // MARK: Updates

    private func handle(_ update: CLLocationUpdate) {
        if update.authorizationDenied || update.authorizationDeniedGlobally {
            if activity != .unavailable { Diagnostics.record("update authorizationDenied") }
            activity = .unavailable
            return
        }
        if update.stationary {
            if activity != .stationary { Diagnostics.record("stationary") }
            activity = .stationary
            if let location = update.location ?? currentLocation { promoteAnchorIfStill(at: location) }
            flushChunk(carryOver: true)
            scheduleSettle()
            return
        }
        guard let location = update.location else { return }
        currentLocation = location
        // Any fix ends "starting"; a slow one reads as still until movement is confirmed.
        if activity == .starting { activity = location.speed > 0.5 ? .moving : .stationary }
        Diagnostics.count("fix")
        guard location.horizontalAccuracy > 0, location.horizontalAccuracy <= Tuning.maxAccuracy else { return Diagnostics.count("inaccurate") }
        guard abs(location.timestamp.timeIntervalSinceNow) < 60 else { return Diagnostics.count("stale") }
        guard !isJump(location) else {
            Diagnostics.record("jump rejected \(Diagnostics.describe(location))")
            return
        }
        Diagnostics.count("accepted")
        activity = location.speed >= 0 && location.speed < 0.5 && openStay != nil ? .stationary : .moving
        record(location)
        detectStay(with: location)
    }

    /// Drops fixes that imply an impossible speed (a fix from the wrong tower in a subway, a
    /// reflection between towers). Several in a row are accepted: we really did move that far.
    private func isJump(_ location: CLLocation) -> Bool {
        guard let last = lastAcceptedLocation else { return false }
        let elapsed = location.timestamp.timeIntervalSince(last.timestamp)
        guard elapsed > 0, elapsed < Tuning.gapBreak else { rejectedJumps = 0; return false }
        let implied = location.distance(from: last) / elapsed
        let reported = max(location.speed, 0)
        let flying = reported > 50
        if !flying, implied > Tuning.maxGroundSpeed, implied > reported * 3 + 10, rejectedJumps < 3 {
            rejectedJumps += 1
            return true
        }
        rejectedJumps = 0
        return false
    }

    // MARK: Battery saver

    /// Significant-change locations: wake-ups while paused, and a rough path in battery mode.
    private func handleCoarse(_ locations: [CLLocation]) {
        if let last = locations.last { Diagnostics.record("significantChange \(Diagnostics.describe(last))") }
        if pausedUntil != nil, !isPaused { resume() }
        // A backup for the geofence: a coarse fix well away from the stay also wakes GPS.
        if isSettled, let stay = openStay, let last = locations.last,
           last.distance(from: stay.location) > Tuning.fenceRadius + last.horizontalAccuracy {
            leftFence()
        }
        guard !usesLiveUpdates, isRecording else { return }
        for location in locations where location.horizontalAccuracy > 0 && location.horizontalAccuracy <= Tuning.coarseAccuracy {
            currentLocation = location
            lastAcceptedLocation = nil
            // Visit departures can arrive late or not at all; clearly being elsewhere ends the stay.
            if let stay = openStay,
               location.distance(from: stay.location) > Tuning.stayRadius + location.horizontalAccuracy {
                close(stay, at: location.timestamp)
                activity = .moving
            }
            pendingPoints.append(TrackPoint(location))
        }
        // Coarse points are sparse; collect them into fewer, longer chunks.
        if let first = pendingPoints.first, pendingPoints.count >= 2,
           pendingPoints.count >= 30 || Date().timeIntervalSince(first.timestamp) >= 30 * 60 {
            flushChunk(carryOver: true)
        }
    }

    /// System-detected visits: arrival opens a stay, departure closes it.
    private func handleVisit(_ visit: CLVisit) {
        Diagnostics.record("visit arrival=\(visit.arrivalDate.formatted(.iso8601)) departure=\(visit.departureDate == .distantFuture ? "-" : visit.departureDate.formatted(.iso8601))")
        guard !usesLiveUpdates, isRecording else { return }
        let arrived = visit.arrivalDate != .distantPast ? visit.arrivalDate : Date()
        if visit.departureDate == .distantFuture {
            guard openStay == nil else { return }
            let location = CLLocation(latitude: visit.coordinate.latitude, longitude: visit.coordinate.longitude)
            beginStay(from: (location, arrived, visit.coordinate.latitude, visit.coordinate.longitude, 1))
        } else if let stay = openStay {
            close(stay, at: visit.departureDate)
        }
    }

    private func record(_ location: CLLocation) {
        if let last = lastAcceptedLocation ?? pendingPoints.last?.location {
            let gap = location.timestamp.timeIntervalSince(last.timestamp)
            if gap > Tuning.gapBreak { flushChunk(carryOver: false) }
            let step = location.distance(from: last)
            guard step >= max(Tuning.minStepDistance, location.horizontalAccuracy * 0.5) || gap > Tuning.gapBreak else { return }
        }
        lastAcceptedLocation = location
        pendingPoints.append(TrackPoint(location))
        if pendingPoints.count % 10 == 0 { PendingTrackStore.save(pendingPoints) }

        if let first = pendingPoints.first,
           pendingPoints.count >= Tuning.chunkMaxPoints || location.timestamp.timeIntervalSince(first.timestamp) >= Tuning.chunkMaxDuration {
            flushChunk(carryOver: true)
        }
    }

    /// Writes the pending points as a new chunk. With `carryOver`, the last point starts the
    /// next chunk so the line on the map stays continuous.
    private func flushChunk(carryOver: Bool) {
        let points = pendingPoints
        pendingPoints = carryOver ? Array(points.suffix(1)) : []
        if !carryOver { lastAcceptedLocation = nil }
        PendingTrackStore.save(pendingPoints)
        guard points.count >= 2, TrackPoint.distance(of: points) > 15 else { return }

        let tripID = activeTripID
        Task {
            let mode = await classifier.mode(from: points[0].timestamp, to: points[points.count - 1].timestamp, points: points)
            Diagnostics.record("chunk points=\(points.count) distance=\(Int(TrackPoint.distance(of: points)))m mode=\(mode.rawValue)")
            context.insert(TrackChunk(points: points, mode: mode, tripID: tripID))
            try? context.save()
        }
    }

    // MARK: Stays

    private func detectStay(with location: CLLocation) {
        if let stay = openStay {
            if location.distance(from: stay.location) <= Tuning.stayRadius + location.horizontalAccuracy {
                refine(stay, with: location)
            } else {
                close(stay, at: location.timestamp)
                setAnchor(location)
            }
            return
        }

        guard var current = anchor, location.distance(from: current.location) <= Tuning.stayRadius else {
            setAnchor(location)
            return
        }
        current.latSum += location.coordinate.latitude
        current.lonSum += location.coordinate.longitude
        current.count += 1
        anchor = current
        if location.timestamp.timeIntervalSince(current.since) >= Tuning.stayMinimumDwell {
            beginStay(from: current)
        }
    }

    /// Starts watching a possible stay. A phone lying still may stop reporting fixes
    /// altogether, so the stay is confirmed by a timer rather than by the next fix.
    private func setAnchor(_ location: CLLocation) {
        anchor = (location, location.timestamp, location.coordinate.latitude, location.coordinate.longitude, 1)
        dwellTask?.cancel()
        let since = location.timestamp
        dwellTask = Task { [weak self] in
            let wait = Tuning.stayMinimumDwell - Date().timeIntervalSince(since)
            try? await Task.sleep(for: .seconds(max(1, wait)))
            guard let self, !Task.isCancelled, self.openStay == nil,
                  let current = self.anchor, current.since == since, self.isRecording else { return }
            self.beginStay(from: current)
            self.activity = .stationary
        }
    }

    /// Core Location says the phone has stopped: treat where we are as a stay right away.
    private func promoteAnchorIfStill(at location: CLLocation) {
        guard openStay == nil else { return }
        if let current = anchor, location.distance(from: current.location) <= Tuning.stayRadius {
            beginStay(from: current)
        } else {
            beginStay(from: (location, location.timestamp, location.coordinate.latitude, location.coordinate.longitude, 1))
        }
    }

    private func beginStay(from anchor: (location: CLLocation, since: Date, latSum: Double, lonSum: Double, count: Int)) {
        dwellTask?.cancel()
        let center = CLLocationCoordinate2D(latitude: anchor.latSum / Double(anchor.count),
                                            longitude: anchor.lonSum / Double(anchor.count))
        self.anchor = nil
        flushChunk(carryOver: true)

        // Stepping out for a few minutes (or a GPS wobble) shouldn't split one visit in two.
        if let previous = lastClosedStay(),
           let left = previous.departure, anchor.since.timeIntervalSince(left) < Tuning.stayMergeGap,
           previous.location.distance(from: CLLocation(latitude: center.latitude, longitude: center.longitude)) < Tuning.stayRadius {
            previous.departure = nil
            openStay = previous
            try? context.save()
            scheduleSettle()
            return
        }

        Diagnostics.record(String(format: "stay begin %.3f,%.3f samples=%d", center.latitude, center.longitude, anchor.count))
        let stay = Stay(arrival: anchor.since, coordinate: center)
        stay.sampleCount = anchor.count
        KnownPlaces.applyName(to: stay, in: context)
        context.insert(stay)
        openStay = stay
        try? context.save()
        tagger.enqueue()
        scheduleSettle()
    }

    private func refine(_ stay: Stay, with location: CLLocation) {
        guard location.horizontalAccuracy <= 30, stay.sampleCount < 200 else { return }
        let n = Double(stay.sampleCount)
        stay.latitude = (stay.latitude * n + location.coordinate.latitude) / (n + 1)
        stay.longitude = (stay.longitude * n + location.coordinate.longitude) / (n + 1)
        stay.sampleCount += 1
    }

    private func close(_ stay: Stay, at date: Date) {
        Diagnostics.record("stay close duration=\(Int(date.timeIntervalSince(stay.arrival) / 60))min")
        openStay = nil
        if date.timeIntervalSince(stay.arrival) < Tuning.stayMinimumDuration {
            context.delete(stay)
        } else {
            stay.departure = date
        }
        try? context.save()
    }

    // MARK: Settling

    /// Live updates pause when the phone is still but wake every time it is picked up, so a day
    /// at the office kept GPS on about half the time. Once a stay has lasted a while, hand over
    /// to a geofence around it and turn GPS off until we leave.
    private func scheduleSettle() {
        guard let stay = openStay, activeTripID == nil, usesLiveUpdates, !isSettled else { return }
        settleTask?.cancel()
        let wait = Tuning.settleAfter - Date().timeIntervalSince(stay.arrival)
        settleTask = Task { [weak self] in
            try? await Task.sleep(for: .seconds(max(0, wait)))
            guard let self, !Task.isCancelled, self.openStay === stay, self.activity == .stationary else { return }
            self.settle()
        }
    }

    private func settle() {
        guard let stay = openStay, isRecording, activeTripID == nil, usesLiveUpdates, !isSettled else { return }
        isSettled = true
        updatesTask?.cancel()
        updatesTask = nil
        flushChunk(carryOver: false)
        Diagnostics.record("settle radius=\(Int(Tuning.fenceRadius))m \(Diagnostics.battery)")
        updateFence(around: stay.location.coordinate)
    }

    private func unsettle() {
        settleTask?.cancel()
        settleTask = nil
        guard isSettled else {
            // After a relaunch the monitor may still hold a fence from before; clear it.
            if fenceMonitor == nil, isRecording { updateFence(around: nil) }
            return
        }
        isSettled = false
        updateFence(around: nil)
    }

    private func leftFence() {
        guard isSettled else { return }
        Diagnostics.record("fence exit \(Diagnostics.battery)")
        if isRecording { start() } else { unsettle() }
    }

    /// Adds or removes the stay geofence, one change at a time and in order.
    private func updateFence(around center: CLLocationCoordinate2D?) {
        let previous = fenceWork
        let monitor = monitorTask()
        fenceWork = Task {
            await previous?.value
            let monitor = await monitor.value
            if let center {
                let condition = CLMonitor.CircularGeographicCondition(center: center, radius: Tuning.fenceRadius)
                await monitor.add(condition, identifier: Self.fenceID, assuming: .satisfied)
            } else {
                await monitor.remove(Self.fenceID)
            }
        }
    }

    /// One monitor for the app's lifetime; its events also arrive when iOS relaunches us for them.
    private func monitorTask() -> Task<CLMonitor, Never> {
        if let fenceMonitor { return fenceMonitor }
        let task = Task { [weak self] in
            let monitor = await CLMonitor("StayFence")
            Task {
                do {
                    for try await event in await monitor.events
                    where event.identifier == Self.fenceID && event.state == .unsatisfied {
                        self?.leftFence()
                    }
                } catch {
                    Diagnostics.record("fence ended error=\(error.localizedDescription)")
                }
            }
            return monitor
        }
        fenceMonitor = task
        return task
    }

    private func lastClosedStay() -> Stay? {
        // Visits found in photos aren't reopened by live recording.
        var descriptor = FetchDescriptor<Stay>(predicate: #Predicate { $0.departure != nil && $0.sourceRaw == nil },
                                               sortBy: [SortDescriptor(\.arrival, order: .reverse)])
        descriptor.fetchLimit = 1
        return try? context.fetch(descriptor).first
    }

    private func restoreOpenStay() {
        let descriptor = FetchDescriptor<Stay>(predicate: #Predicate { $0.departure == nil },
                                               sortBy: [SortDescriptor(\.arrival, order: .reverse)])
        let open = (try? context.fetch(descriptor)) ?? []
        openStay = open.first
        // Another device or an old crash may have left extra open stays behind.
        for stale in open.dropFirst() { stale.departure = stale.arrival.addingTimeInterval(Tuning.stayMinimumDuration) }
        if !isRecording, let stay = openStay {
            close(stay, at: Date())
        }
    }
}

private final class AuthorizationDelegate: NSObject, CLLocationManagerDelegate {
    var onChange: ((CLLocationManager) -> Void)?
    var onLocations: (([CLLocation]) -> Void)?
    var onVisit: ((CLVisit) -> Void)?

    func locationManagerDidChangeAuthorization(_ manager: CLLocationManager) {
        onChange?(manager)
    }

    func locationManager(_ manager: CLLocationManager, didUpdateLocations locations: [CLLocation]) {
        onLocations?(locations)
    }

    func locationManager(_ manager: CLLocationManager, didVisit visit: CLVisit) {
        onVisit?(visit)
    }

    func locationManager(_ manager: CLLocationManager, didFailWithError error: Error) {}
}

/// Points not yet written as a chunk, kept on disk so a terminated app loses nothing.
enum PendingTrackStore {
    private static var url: URL {
        URL.applicationSupportDirectory.appending(path: "pending-track.bin")
    }

    static func save(_ points: [TrackPoint]) {
        try? FileManager.default.createDirectory(at: URL.applicationSupportDirectory, withIntermediateDirectories: true)
        try? TrackCodec.encode(points).write(to: url, options: [.atomic, .completeFileProtectionUntilFirstUserAuthentication])
    }

    static func load() -> [TrackPoint] {
        guard let data = try? Data(contentsOf: url) else { return [] }
        return TrackCodec.decode(data)
    }
}

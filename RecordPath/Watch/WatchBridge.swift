import Foundation
import SwiftData
import WatchConnectivity
import os

/// Keeps the Watch app up to date with today's route and where the user is, carries out the
/// Watch's requests (pause, resume), and files recordings made on the Watch into the timeline.
@MainActor
final class WatchBridge: NSObject {
    private let context: ModelContext
    private let engine: LocationEngine
    private let activity: ActivityProvider
    private let session: WCSession? = WCSession.isSupported() ? .default : nil
    private var pushTask: Task<Void, Never>?
    private var lastPush = Date.distantPast
    private var lastSent: WatchSnapshot?
    private var saveObserver: NSObjectProtocol?
    private let log = Logger(subsystem: "PathTracker", category: "WatchBridge")

    /// The Watch only needs to look current, not be live to the second; this keeps the
    /// all-day recorder from waking the Watch for every GPS fix.
    private static let minimumInterval: TimeInterval = 30
    /// Plenty for a day's route on a 46 mm screen, and well under the transfer size limit.
    nonisolated private static let maximumPoints = 600

    init(context: ModelContext, engine: LocationEngine, activity: ActivityProvider) {
        self.context = context
        self.engine = engine
        self.activity = activity
        super.init()
    }

    func activate() {
        guard let session else { return }
        session.delegate = self
        session.activate()
        saveObserver = NotificationCenter.default.addObserver(forName: ModelContext.didSave, object: nil, queue: .main) { [weak self] _ in
            Task { @MainActor in self?.scheduleUpdate() }
        }
        observeEngine()
    }

    /// Pause, resume and language changes show on the Watch right away.
    private func observeEngine() {
        withObservationTracking {
            _ = engine.pausedUntil
            _ = engine.isEnabled
            _ = engine.openStay
            _ = engine.activeTripID
            _ = activity.today
            _ = LanguageSettings.shared.language
        } onChange: { [weak self] in
            Task { @MainActor in
                self?.scheduleUpdate(immediately: true)
                self?.observeEngine()
            }
        }
    }

    func scheduleUpdate(immediately: Bool = false) {
        guard let session, session.activationState == .activated, session.isPaired, session.isWatchAppInstalled else { return }
        let wait = immediately ? 0.3 : max(0.3, Self.minimumInterval - Date().timeIntervalSince(lastPush))
        pushTask?.cancel()
        pushTask = Task { [weak self] in
            try? await Task.sleep(for: .seconds(wait))
            guard !Task.isCancelled else { return }
            self?.push()
        }
    }

    private func push() {
        guard let session else { return }
        let snapshot = makeSnapshot()
        lastPush = Date()
        guard snapshot.withoutTimestamp != lastSent?.withoutTimestamp, let data = snapshot.encoded() else { return }
        do {
            try session.updateApplicationContext([WatchSnapshot.key: data])
            lastSent = snapshot
        } catch {
            log.error("Watch context update failed: \(error.localizedDescription)")
        }
    }

    func makeSnapshot(now: Date = Date()) -> WatchSnapshot {
        let day = Calendar.current.dayInterval(for: now)
        let start = day.start, end = day.end
        let chunks = (try? context.fetch(FetchDescriptor<TrackChunk>(
            predicate: #Predicate { $0.startDate < end && $0.endDate > start },
            sortBy: [SortDescriptor(\.startDate)]))) ?? []
        // Optional comparisons don't translate to a store query, so the departure check runs here.
        let stays = ((try? context.fetch(FetchDescriptor<Stay>(
            predicate: #Predicate { $0.arrival < end },
            sortBy: [SortDescriptor(\.arrival)]))) ?? [])
            .filter { ($0.departure ?? .distantFuture) > start }

        var snapshot = WatchSnapshot()
        snapshot.language = LanguageSettings.shared.language.rawValue
        snapshot.segments = Self.segments(from: chunks.map { ($0.startDate, $0.endDate, $0.points) } + [pendingStretch()])
        snapshot.places = stays.map {
            WatchSnapshot.Place(name: $0.displayName, detail: $0.subtitle,
                                coordinate: .init(lat: $0.latitude, lon: $0.longitude),
                                arrival: $0.arrival, departure: $0.departure)
        }
        snapshot.distance = chunks.reduce(0) { $0 + $1.distance } + TrackPoint.distance(of: engine.pendingPoints)
        snapshot.steps = activity.today.steps
        snapshot.isEnabled = engine.isEnabled
        snapshot.isRecording = engine.isRecording
        snapshot.pausedUntil = engine.isPaused ? engine.pausedUntil : nil
        snapshot.receivedRecordings = WatchRecordingImporter.receivedIDs
        if let id = engine.activeTripID,
           let trip = try? context.fetch(FetchDescriptor<Trip>(predicate: #Predicate { $0.id == id && $0.endDate == nil })).first {
            snapshot.activeRecording = ActiveRecording(tripID: trip.id, title: trip.title, emoji: trip.coverEmoji,
                                                       start: trip.startDate, watchActivity: LiveRecording.watchActivity(for: trip))
        }
        return snapshot
    }

    private func pendingStretch() -> (Date, Date, [TrackPoint]) {
        let points = engine.pendingPoints
        return (points.first?.timestamp ?? .distantPast, points.last?.timestamp ?? .distantPast, points)
    }

    /// Joins chunks into continuous stretches and thins them so the whole day fits the budget.
    nonisolated static func segments(from stretches: [(start: Date, end: Date, points: [TrackPoint])]) -> [[WatchSnapshot.Coordinate]] {
        var joined: [[TrackPoint]] = []
        var lastEnd = Date.distantPast
        for stretch in stretches where stretch.points.count > 1 {
            if !joined.isEmpty, stretch.start.timeIntervalSince(lastEnd) < 10 * 60 {
                joined[joined.count - 1].append(contentsOf: stretch.points)
            } else {
                joined.append(stretch.points)
            }
            lastEnd = stretch.end
        }
        var tolerance = 5.0
        var thinned = joined.map { $0.simplified(tolerance: tolerance) }
        while thinned.reduce(0, { $0 + $1.count }) > maximumPoints, tolerance < 2000 {
            tolerance *= 2
            thinned = joined.map { $0.simplified(tolerance: tolerance) }
        }
        return thinned.map { $0.map { WatchSnapshot.Coordinate(lat: $0.latitude, lon: $0.longitude) } }
    }

    // MARK: Requests from the Watch

    fileprivate func handle(_ message: [String: Any]) -> [String: Any] {
        if let track = message[WatchRecordingInfo.trackKey] as? Data, let info = WatchRecordingInfo(metadata: message) {
            receiveRecording(track, info: info)
        }
        switch message[WatchCommand.key].flatMap({ WatchCommand(rawValue: $0 as? String ?? "") }) {
        case .pause:
            if let until = message[WatchCommand.untilKey] as? Date { engine.pause(until: until) }
        case .resume:
            engine.resume()
        case .endRecording:
            // Ended on the Watch: end it here too, but only the recording the Watch was part of.
            if let id = (message[WatchCommand.tripKey] as? String).flatMap(UUID.init(uuidString:)), engine.activeTripID == id,
               let trip = try? context.fetch(FetchDescriptor<Trip>(predicate: #Predicate { $0.id == id })).first {
                engine.endTrip(trip)
            }
        case .refresh, nil:
            break
        }
        let snapshot = makeSnapshot()
        return snapshot.encoded().map { [WatchSnapshot.key: $0] } ?? [:]
    }

    fileprivate func receiveRecording(_ data: Data, info: WatchRecordingInfo) {
        let points = TrackCodec.decode(data)
        WatchRecordingImporter.importRecording(points: points, info: info, into: context)
        engine.reloadAfterDataChange(discardPending: false)
        scheduleUpdate(immediately: true)
    }
}

private extension WatchSnapshot {
    /// Equal snapshots made a few seconds apart shouldn't be resent.
    var withoutTimestamp: WatchSnapshot {
        var copy = self
        copy.generatedAt = .distantPast
        return copy
    }
}

extension WatchBridge: WCSessionDelegate {
    nonisolated func session(_ session: WCSession, activationDidCompleteWith activationState: WCSessionActivationState, error: Error?) {
        Task { @MainActor in self.scheduleUpdate(immediately: true) }
    }

    nonisolated func sessionDidBecomeInactive(_ session: WCSession) {}

    nonisolated func sessionDidDeactivate(_ session: WCSession) {
        // The user switched to another Watch; talk to that one instead.
        session.activate()
    }

    nonisolated func sessionReachabilityDidChange(_ session: WCSession) {
        Task { @MainActor in self.scheduleUpdate(immediately: true) }
    }

    nonisolated func sessionWatchStateDidChange(_ session: WCSession) {
        Task { @MainActor in self.scheduleUpdate(immediately: true) }
    }

    nonisolated func session(_ session: WCSession, didReceiveMessage message: [String: Any],
                             replyHandler: @escaping ([String: Any]) -> Void) {
        let message = SendableDictionary(value: message)
        let reply = SendableReply(handler: replyHandler)
        Task { @MainActor in reply.handler(self.handle(message.value)) }
    }

    nonisolated func session(_ session: WCSession, didReceiveUserInfo userInfo: [String: Any] = [:]) {
        let message = SendableDictionary(value: userInfo)
        Task { @MainActor in _ = self.handle(message.value) }
    }

    nonisolated func session(_ session: WCSession, didReceive file: WCSessionFile) {
        // The file is removed once this method returns, so read it now.
        guard let data = try? Data(contentsOf: file.fileURL), let info = WatchRecordingInfo(metadata: file.metadata) else { return }
        Task { @MainActor in self.receiveRecording(data, info: info) }
    }
}

/// WatchConnectivity hands over plain property-list dictionaries; these only cross to the main actor.
private struct SendableDictionary: @unchecked Sendable { let value: [String: Any] }
private struct SendableReply: @unchecked Sendable { let handler: ([String: Any]) -> Void }

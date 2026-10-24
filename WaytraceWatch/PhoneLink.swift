import Foundation
import WatchConnectivity
import WidgetKit
import os

/// The Watch's side of the link: receives today's snapshot from the iPhone, sends requests
/// back, and hands over recordings made on the Watch. Recordings are kept on the Watch until
/// the iPhone has them, so nothing is lost while the phone is away.
@MainActor
@Observable
final class PhoneLink: NSObject {
    static let shared = PhoneLink()

    private(set) var snapshot: WatchSnapshot?
    private(set) var isReachable = false
    /// Recordings waiting for the iPhone.
    private(set) var pendingRecordings = 0

    private let session: WCSession? = WCSession.isSupported() ? .default : nil
    private let log = Logger(subsystem: "PathTracker", category: "PhoneLink")
    private var lastFileAttempt: [String: Date] = [:]
    private var lastMessageAttempt: [String: Date] = [:]

    private static var recordingsFolder: URL {
        let url = URL.documentsDirectory.appending(path: "Recordings", directoryHint: .isDirectory)
        try? FileManager.default.createDirectory(at: url, withIntermediateDirectories: true)
        return url
    }

    private override init() {
        // Show the last known route straight away, even before the iPhone answers.
        snapshot = SharedSnapshot.load()
        super.init()
        if let snapshot { applyLanguage(of: snapshot) }
    }

    func activate() {
        guard let session else { return }
        session.delegate = self
        session.activate()
    }

    /// How old the snapshot is when the iPhone is out of reach, so stale data doesn't pass as live.
    var isStale: Bool {
        guard let snapshot else { return true }
        return !isReachable && Date().timeIntervalSince(snapshot.generatedAt) > 5 * 60
    }

    // MARK: Requests

    func refresh() { send(.refresh) }

    func pause(until date: Date) {
        // Show the change at once; the iPhone's reply confirms it.
        snapshot?.pausedUntil = date
        snapshot?.isRecording = false
        send(.pause, until: date)
    }

    func resume() {
        // Read before writing: `snapshot?.x = snapshot?.y` is an overlapping access and traps.
        let isEnabled = snapshot?.isEnabled ?? true
        snapshot?.pausedUntil = nil
        snapshot?.isRecording = isEnabled
        send(.resume)
    }

    private func send(_ command: WatchCommand, until: Date? = nil) {
        guard let session, session.activationState == .activated else { return }
        var message: [String: Any] = [WatchCommand.key: command.rawValue]
        if let until { message[WatchCommand.untilKey] = until }
        if session.isReachable {
            session.sendMessage(message, replyHandler: { reply in
                let data = reply[WatchSnapshot.key] as? Data
                Task { @MainActor in self.receive(WatchSnapshot.decode(data)) }
            }, errorHandler: { [weak self] _ in
                // Lost the iPhone mid-request; queue it so it still happens.
                guard command != .refresh else { return }
                Task { @MainActor in self?.session?.transferUserInfo(message) }
            })
        } else if command != .refresh {
            session.transferUserInfo(message)
        }
    }

    // MARK: Recordings

    /// Stores the recording and queues it for the iPhone.
    func deliver(points: [TrackPoint], info: WatchRecordingInfo) {
        let file = Self.recordingsFolder.appending(path: "\(info.id.uuidString).track")
        do {
            try TrackCodec.encode(points).write(to: file)
            try JSONEncoder().encode(info).write(to: file.deletingPathExtension().appendingPathExtension("json"))
        } catch {
            log.error("Couldn't save recording: \(error.localizedDescription)")
        }
        transferPending()
    }

    /// Sends every saved recording the iPhone hasn't confirmed yet. A transfer that "finishes"
    /// isn't proof the iPhone filed it, so copies are only deleted once the iPhone lists them as
    /// received; until then they're resent now and then. Safe to call repeatedly.
    private func transferPending() {
        let acknowledged = Set(snapshot?.receivedRecordings ?? [])
        var tracks = (try? FileManager.default.contentsOfDirectory(at: Self.recordingsFolder, includingPropertiesForKeys: nil)) ?? []
        tracks = tracks.filter { $0.pathExtension == "track" }
        for track in tracks where UUID(uuidString: track.deletingPathExtension().lastPathComponent).map(acknowledged.contains) == true {
            try? FileManager.default.removeItem(at: track)
            try? FileManager.default.removeItem(at: track.deletingPathExtension().appendingPathExtension("json"))
        }
        tracks = tracks.filter { FileManager.default.fileExists(atPath: $0.path) }
        pendingRecordings = tracks.count

        guard let session, session.activationState == .activated else { return }
        let inFlight = Set(session.outstandingFileTransfers.map(\.file.fileURL.lastPathComponent))
        let now = Date()
        for track in tracks {
            let name = track.lastPathComponent
            let infoURL = track.deletingPathExtension().appendingPathExtension("json")
            guard let infoData = try? Data(contentsOf: infoURL),
                  let info = try? JSONDecoder().decode(WatchRecordingInfo.self, from: infoData) else { continue }
            // The file transfer is the dependable route, even with the app closed on both ends.
            if !inFlight.contains(name), now.timeIntervalSince(lastFileAttempt[name] ?? .distantPast) > 120 {
                lastFileAttempt[name] = now
                session.transferFile(track, metadata: info.metadata)
            }
            // When the iPhone is right there, a small recording also goes over directly, so it
            // shows up in Trips at once.
            if session.isReachable, now.timeIntervalSince(lastMessageAttempt[name] ?? .distantPast) > 30,
               let data = try? Data(contentsOf: track), data.count <= WatchRecordingInfo.messageLimit {
                lastMessageAttempt[name] = now
                var message = info.metadata
                message[WatchRecordingInfo.trackKey] = data
                session.sendMessage(message, replyHandler: { reply in
                    let snapshot = reply[WatchSnapshot.key] as? Data
                    Task { @MainActor in self.receive(WatchSnapshot.decode(snapshot)) }
                }, errorHandler: nil)
            }
        }
    }

    // MARK: Receiving

    private func receive(_ snapshot: WatchSnapshot?) {
        guard let snapshot else { return }
        let previous = self.snapshot
        self.snapshot = snapshot
        SharedSnapshot.save(snapshot)
        applyLanguage(of: snapshot)
        if previous.map(ComplicationContent.init) != ComplicationContent(snapshot) {
            WidgetCenter.shared.reloadAllTimelines()
        }
        transferPending()
    }

    private func applyLanguage(of snapshot: WatchSnapshot) {
        LanguageSettings.shared.set(AppLanguage(rawValue: snapshot.language) ?? .system)
    }
}

/// What the complications show; they're only reloaded when this changes, since watchOS
/// budgets complication updates.
private struct ComplicationContent: Equatable {
    var tenthsOfKilometre: Int
    var place: String?
    var isPaused: Bool
    var language: String

    init(_ snapshot: WatchSnapshot) {
        tenthsOfKilometre = Int(snapshot.distance / 100)
        place = snapshot.currentPlace?.name
        isPaused = snapshot.pausedUntil != nil
        language = snapshot.language
    }
}

extension PhoneLink: WCSessionDelegate {
    nonisolated func session(_ session: WCSession, activationDidCompleteWith activationState: WCSessionActivationState, error: Error?) {
        let data = session.receivedApplicationContext[WatchSnapshot.key] as? Data
        let reachable = session.isReachable
        Task { @MainActor in
            self.isReachable = reachable
            if let snapshot = WatchSnapshot.decode(data), snapshot.generatedAt > (self.snapshot?.generatedAt ?? .distantPast) {
                self.receive(snapshot)
            }
            self.transferPending()
            self.refresh()
        }
    }

    nonisolated func sessionReachabilityDidChange(_ session: WCSession) {
        let reachable = session.isReachable
        Task { @MainActor in
            self.isReachable = reachable
            if reachable {
                self.refresh()
                self.transferPending()
            }
        }
    }

    nonisolated func session(_ session: WCSession, didReceiveApplicationContext applicationContext: [String: Any]) {
        let data = applicationContext[WatchSnapshot.key] as? Data
        Task { @MainActor in self.receive(WatchSnapshot.decode(data)) }
    }

    nonisolated func session(_ session: WCSession, didFinish fileTransfer: WCSessionFileTransfer, error: Error?) {
        // Nothing to delete yet: that waits for the iPhone to confirm (see transferPending).
        // Ask for its latest state so the confirmation arrives promptly.
        Task { @MainActor in self.refresh() }
    }
}

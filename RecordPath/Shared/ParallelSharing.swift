import Foundation
import CloudKit
import SwiftData
import CoreLocation
import os

/// 平行足迹 between friends. Each person keeps their footprint days in a zone of their own
/// iCloud, apart from the synced history, and shares that zone with the friends they invite.
/// Friends read each other's days and compare them on their own phones; nothing goes to a
/// server of ours. Only friends who share both ways see each other.
@MainActor
@Observable
final class ParallelSharing {
    static let shared = ParallelSharing()

    /// Someone the person shares footprints with, or who shares with them.
    struct Friend: Identifiable, Hashable {
        enum State { case mutual, theyShared, waitingForThem, invited }
        /// Their iCloud user record name, the same on both sides.
        let id: String
        var name: String
        var state: State
        /// Their zone in the shared database, once they share with this person.
        var zoneID: CKRecordZone.ID?
    }

    private(set) var friends: [Friend] = []
    private(set) var isLoading = false
    private(set) var lastError: String?
    /// Who just shared with this person, to offer sharing back.
    var justAccepted: Friend?

    /// The person agreed to share their footprints (asked once, before the first invite).
    var hasConsented: Bool {
        get { UserDefaults.standard.bool(forKey: "parallel.consented") }
        set { UserDefaults.standard.set(newValue, forKey: "parallel.consented") }
    }

    /// Footprints are being shared with somebody, so new days should be uploaded.
    private var isSharing: Bool {
        get { UserDefaults.standard.bool(forKey: "parallel.sharing") }
        set { UserDefaults.standard.set(newValue, forKey: "parallel.sharing") }
    }

    let container = CKContainer.default()
    private var privateDB: CKDatabase { container.privateCloudDatabase }
    private var sharedDB: CKDatabase { container.sharedCloudDatabase }
    private let zoneID = CKRecordZone.ID(zoneName: "ParallelFootprints", ownerName: CKCurrentUserDefaultName)
    private static let recordType = "FootprintDay"
    private let log = Logger(subsystem: "PathTracker", category: "Parallel")
    @ObservationIgnored private var modelContainer: ModelContainer?
    @ObservationIgnored private var lastUpload = Date.distantPast

    private init() {}

    func attach(_ container: ModelContainer) { modelContainer = container }

    // MARK: Sharing mine

    /// The share of this person's footprint zone, made the first time; the days are uploaded
    /// before anyone is invited.
    func prepareShare() async throws -> CKShare {
        do {
            // Each zone and record reports its own result; a failure there doesn't throw by itself.
            let zones = try await privateDB.modifyRecordZones(saving: [CKRecordZone(zoneID: zoneID)], deleting: [])
            _ = try zones.saveResults[zoneID]?.get()
            let share: CKShare
            if let existing = try? await privateDB.record(for: CKRecord.ID(recordName: CKRecordNameZoneWideShare, zoneID: zoneID)) as? CKShare {
                share = existing
            } else {
                let made = CKShare(recordZoneID: zoneID)
                made[CKShare.SystemFieldKey.title] = String(localized: "漫迹 · 平行足迹", bundle: .appLanguage)
                made.publicPermission = .none
                let saved = try await privateDB.modifyRecords(saving: [made], deleting: [])
                // The share as the server keeps it, with the link the invitation needs.
                guard let result = saved.saveResults[made.recordID], let stored = try result.get() as? CKShare else {
                    throw CKError(.internalError)
                }
                share = stored
            }
            isSharing = true
            try await upload(force: true)
            return share
        } catch {
            log.error("Couldn't prepare the share: \(error.localizedDescription)")
            lastError = Self.describe(error)
            throw error
        }
    }

    /// Uploads the days that changed since last time. Cheap to call: at most every few hours
    /// unless forced.
    func upload(force: Bool = false) async throws {
        guard isSharing, let modelContainer, force || Date().timeIntervalSince(lastUpload) > 6 * 3600 else { return }
        lastUpload = Date()
        let hidden = PrivacyZones.shared.zones.map(\.location)
        let days = await Task.detached(priority: .utility) { Self.myDays(in: modelContainer, hiddenZones: hidden) }.value

        var uploaded = Self.uploadedFingerprints
        let changed = days.values.filter { uploaded[$0.day] != $0.fingerprint }
        let gone = Set(uploaded.keys).subtracting(days.keys)
        let records = changed.map { day -> CKRecord in
            let record = CKRecord(recordType: Self.recordType, recordID: CKRecord.ID(recordName: "day-\(day.day)", zoneID: zoneID))
            record["day"] = day.day
            record["areas"] = day.areasData
            record["slots"] = day.slotsData
            return record
        }
        let deletions = gone.map { CKRecord.ID(recordName: "day-\($0)", zoneID: zoneID) }
        // CloudKit takes a few hundred at a time.
        var savedIDs = Set<CKRecord.ID>(), deletedIDs = Set<CKRecord.ID>()
        var firstError: Error?
        for start in stride(from: 0, to: max(records.count, deletions.count), by: 300) {
            let saving = Array(records.dropFirst(start).prefix(300))
            let deleting = Array(deletions.dropFirst(start).prefix(300))
            let results = try await privateDB.modifyRecords(saving: saving, deleting: deleting, savePolicy: .allKeys)
            for (id, result) in results.saveResults {
                switch result {
                case .success: savedIDs.insert(id)
                case .failure(let error): firstError = firstError ?? error
                }
            }
            for (id, result) in results.deleteResults {
                switch result {
                case .success: deletedIDs.insert(id)
                case .failure(let error): firstError = firstError ?? error
                }
            }
        }
        // Only what made it is remembered, so the rest goes again next time.
        for day in changed where savedIDs.contains(CKRecord.ID(recordName: "day-\(day.day)", zoneID: zoneID)) {
            uploaded[day.day] = day.fingerprint
        }
        for day in gone where deletedIDs.contains(CKRecord.ID(recordName: "day-\(day)", zoneID: zoneID)) {
            uploaded[day] = nil
        }
        Self.uploadedFingerprints = uploaded
        log.info("Uploaded \(savedIDs.count) days, removed \(deletedIDs.count)")
        if let firstError { throw firstError }
    }

    /// This person's footprint days, from the store.
    nonisolated static func myDays(in container: ModelContainer, hiddenZones: [CLLocation]) -> [String: FootprintDay] {
        let context = ModelContext(container)
        let stays = (try? context.fetch(FetchDescriptor<Stay>())) ?? []
        let chunks = (try? context.fetch(FetchDescriptor<TrackChunk>())) ?? []
        var hidden = hiddenZones
        hidden += stays.filter { ["home", "work", "school"].contains($0.categoryRaw ?? "") }.map(\.location)
        if let home = HomeBase.find(in: stays) { hidden.append(home.location) }

        var sightings = stays.map { stay in
            FootprintDigest.Sighting(latitude: stay.latitude, longitude: stay.longitude, start: stay.arrival,
                                     end: stay.departure ?? Date(),
                                     timeZone: stay.timeZoneID.flatMap(TimeZone.init(identifier:)) ?? .current)
        }
        for chunk in chunks where chunk.mode != .flying {
            // A point every ten minutes is plenty for hour-long cells.
            var lastKept = Date.distantPast
            for point in chunk.points where point.timestamp.timeIntervalSince(lastKept) >= 600 {
                lastKept = point.timestamp
                sightings.append(FootprintDigest.Sighting(latitude: point.latitude, longitude: point.longitude,
                                                          start: point.timestamp, end: point.timestamp, timeZone: .current))
            }
        }
        return FootprintDigest.days(from: sightings, excluding: hidden)
    }

    private static var fingerprintsFile: URL {
        URL.applicationSupportDirectory.appending(path: "parallel-uploaded.json")
    }

    private static var uploadedFingerprints: [String: String] {
        get { (try? Data(contentsOf: fingerprintsFile)).flatMap { try? JSONDecoder().decode([String: String].self, from: $0) } ?? [:] }
        set {
            try? FileManager.default.createDirectory(at: URL.applicationSupportDirectory, withIntermediateDirectories: true)
            try? JSONEncoder().encode(newValue).write(to: fingerprintsFile, options: .atomic)
        }
    }

    // MARK: Friends

    /// Works out who shares with whom: the people on this person's share, and the people
    /// whose footprint zones were shared with them.
    func refresh() async {
        isLoading = true
        defer { isLoading = false }
        lastError = nil
        var byID: [String: Friend] = [:]

        if let share = try? await privateDB.record(for: CKRecord.ID(recordName: CKRecordNameZoneWideShare, zoneID: zoneID)) as? CKShare {
            for participant in share.participants where participant.role != .owner {
                guard let id = participant.userIdentity.userRecordID?.recordName else { continue }
                byID[id] = Friend(id: id, name: Self.name(of: participant.userIdentity),
                                  state: participant.acceptanceStatus == .accepted ? .waitingForThem : .invited)
            }
        }
        do {
            for zone in try await sharedDB.allRecordZones() where zone.zoneID.zoneName == zoneID.zoneName {
                let ownerID = zone.zoneID.ownerName
                let owner = (try? await sharedDB.record(for: CKRecord.ID(recordName: CKRecordNameZoneWideShare, zoneID: zone.zoneID)) as? CKShare)?.owner
                var friend = byID[ownerID] ?? Friend(id: ownerID, name: owner.map { Self.name(of: $0.userIdentity) } ?? "", state: .theyShared)
                if friend.name.isEmpty, let owner { friend.name = Self.name(of: owner.userIdentity) }
                switch byID[ownerID]?.state {
                case .waitingForThem: friend.state = .mutual
                case .invited: friend.state = .invited
                default: friend.state = .theyShared
                }
                friend.zoneID = zone.zoneID
                byID[ownerID] = friend
            }
        } catch {
            lastError = Self.describe(error)
        }
        friends = byID.values.sorted { ($0.state == .mutual ? 0 : 1, $0.name) < ($1.state == .mutual ? 0 : 1, $1.name) }
        try? await upload()
    }

    /// A friend's footprint days, fetched from what they share. The last copy is kept on the
    /// phone, so the page opens at once and works offline.
    func days(of friend: Friend) async -> [FootprintDay] {
        let cached = Self.cachedDays(friend.id)
        guard let zoneID = friend.zoneID else { return cached }
        var days: [FootprintDay] = []
        var token: CKServerChangeToken?
        do {
            repeat {
                let changes = try await sharedDB.recordZoneChanges(inZoneWith: zoneID, since: token)
                for (_, result) in changes.modificationResultsByID {
                    guard let record = try? result.get().record, record.recordType == Self.recordType,
                          let day = record["day"] as? String else { continue }
                    days.append(FootprintDay(day: day, areasData: record["areas"] as? Data ?? Data(),
                                             slotsData: record["slots"] as? Data ?? Data()))
                }
                token = changes.changeToken
                if !changes.moreComing { break }
            } while true
        } catch {
            lastError = Self.describe(error)
            return cached
        }
        Self.cache(days, for: friend.id)
        return days
    }

    /// Accepting an invitation someone sent.
    func accept(_ metadata: CKShare.Metadata) async {
        do {
            _ = try await container.accept(metadata)
            await refresh()
            let ownerID = metadata.ownerIdentity.userRecordID?.recordName
            if let friend = friends.first(where: { $0.id == ownerID }), friend.state == .theyShared {
                justAccepted = friend
            }
        } catch {
            lastError = Self.describe(error)
        }
    }

    /// Stops sharing with one friend, both ways: they're taken off this person's share, and
    /// this person leaves theirs.
    func stop(_ friend: Friend) async {
        do {
            if let share = try? await privateDB.record(for: CKRecord.ID(recordName: CKRecordNameZoneWideShare, zoneID: zoneID)) as? CKShare,
               let participant = share.participants.first(where: { $0.userIdentity.userRecordID?.recordName == friend.id }) {
                share.removeParticipant(participant)
                let saved = try await privateDB.modifyRecords(saving: [share], deleting: [])
                _ = try saved.saveResults[share.recordID]?.get()
            }
            if let zone = friend.zoneID { _ = try await sharedDB.modifyRecordZones(saving: [], deleting: [zone]) }
            Self.cache([], for: friend.id)
        } catch {
            lastError = Self.describe(error)
        }
        await refresh()
    }

    /// Stops sharing with everyone and deletes the footprint days from iCloud.
    func stopAll() async {
        do {
            _ = try await privateDB.modifyRecordZones(saving: [], deleting: [zoneID])
            for friend in friends {
                if let zone = friend.zoneID { _ = try? await sharedDB.modifyRecordZones(saving: [], deleting: [zone]) }
                Self.cache([], for: friend.id)
            }
        } catch {
            lastError = Self.describe(error)
        }
        isSharing = false
        Self.uploadedFingerprints = [:]
        await refresh()
    }

    // MARK: Helpers

    private static func name(of identity: CKUserIdentity) -> String {
        identity.nameComponents.map { PersonNameComponentsFormatter.localizedString(from: $0, style: .default) }
            ?? identity.lookupInfo?.emailAddress ?? identity.lookupInfo?.phoneNumber
            ?? String(localized: "一位朋友", bundle: .appLanguage)
    }

    private static func describe(_ error: Error) -> String {
        if let error = error as? CKError, error.code == .notAuthenticated {
            return String(localized: "需要登录 iCloud 才能使用平行足迹。", bundle: .appLanguage)
        }
        if let error = error as? CKError, [.networkUnavailable, .networkFailure].contains(error.code) {
            return String(localized: "网络不可用，稍后再试。", bundle: .appLanguage)
        }
        return error.localizedDescription
    }

    private static func cacheFile(_ id: String) -> URL {
        URL.cachesDirectory.appending(path: "parallel-\(id.replacingOccurrences(of: "/", with: "_")).bin")
    }

    private static func cachedDays(_ id: String) -> [FootprintDay] {
        guard let rows = (try? Data(contentsOf: cacheFile(id))).flatMap({ try? PropertyListDecoder().decode([[Data]].self, from: $0) }) else { return [] }
        return rows.compactMap { row in
            guard row.count == 3, let day = String(data: row[0], encoding: .utf8) else { return nil }
            return FootprintDay(day: day, areasData: row[1], slotsData: row[2])
        }
    }

    private static func cache(_ days: [FootprintDay], for id: String) {
        let rows = days.map { [Data($0.day.utf8), $0.areasData, $0.slotsData] }
        try? PropertyListEncoder().encode(rows).write(to: cacheFile(id), options: .atomic)
    }
}

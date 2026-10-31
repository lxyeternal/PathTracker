import Foundation
import SwiftData
import CoreLocation
import Photos

/// Finds where you've been from the photos and videos in your library: shots taken close
/// together on the same day become one visit, which then lights up its city, province and
/// country like a recorded one. Nothing leaves the device but the coordinates Apple's map
/// service needs to name each place.
enum PhotoFootprints {
    static let source = "photos"

    /// A photo's time and place, all the import needs.
    struct Shot: Equatable {
        var date: Date
        var latitude: Double
        var longitude: Double
        var location: CLLocation { CLLocation(latitude: latitude, longitude: longitude) }
    }

    struct Visit: Equatable {
        var start: Date
        var end: Date
        var latitude: Double
        var longitude: Double
        var shots: Int
        var coordinate: CLLocationCoordinate2D { CLLocationCoordinate2D(latitude: latitude, longitude: longitude) }
    }

    struct Summary: Equatable {
        var scanned = 0
        var withLocation = 0
        var visits = 0
        var skippedAlreadyRecorded = 0
    }

    /// Groups shots into visits: same calendar day, within `radius` of where the visit started.
    static func visits(from shots: [Shot], radius: CLLocationDistance = 500, calendar: Calendar = .current) -> [Visit] {
        var visits: [Visit] = []
        var current: (shots: [Shot], anchor: CLLocation)?
        func close() {
            guard let group = current?.shots, let first = group.first, let last = group.last else { return }
            let lat = group.map(\.latitude).reduce(0, +) / Double(group.count)
            let lon = group.map(\.longitude).reduce(0, +) / Double(group.count)
            visits.append(Visit(start: first.date, end: last.date, latitude: lat, longitude: lon, shots: group.count))
            current = nil
        }
        for shot in shots.sorted(by: { $0.date < $1.date }) {
            if let c = current, calendar.isDate(c.shots[0].date, inSameDayAs: shot.date),
               shot.location.distance(from: c.anchor) <= radius {
                current?.shots.append(shot)
            } else {
                close()
                current = ([shot], shot.location)
            }
        }
        close()
        return visits
    }

    // MARK: Library

    static var authorization: PHAuthorizationStatus { PHPhotoLibrary.authorizationStatus(for: .readWrite) }

    /// Every photo and video with a location, oldest first.
    static func shotsInLibrary(progress: @Sendable (Int, Int) -> Void) -> (shots: [Shot], scanned: Int) {
        let options = PHFetchOptions()
        options.predicate = NSPredicate(format: "mediaType == %d OR mediaType == %d",
                                        PHAssetMediaType.image.rawValue, PHAssetMediaType.video.rawValue)
        options.sortDescriptors = [NSSortDescriptor(key: "creationDate", ascending: true)]
        let assets = PHAsset.fetchAssets(with: options)
        var shots: [Shot] = []
        shots.reserveCapacity(assets.count)
        for index in 0..<assets.count {
            let asset = assets.object(at: index)
            if let location = asset.location, let date = asset.creationDate,
               CLLocationCoordinate2DIsValid(location.coordinate), location.coordinate.latitude != 0 || location.coordinate.longitude != 0 {
                shots.append(Shot(date: date, latitude: location.coordinate.latitude, longitude: location.coordinate.longitude))
            }
            if index % 500 == 0 { progress(index, assets.count) }
        }
        return (shots, assets.count)
    }

    /// A stay reduced to what de-duplication needs, so the work can leave the main thread.
    struct Known: Sendable {
        var arrival: Date
        var departure: Date
        var latitude: Double
        var longitude: Double
    }

    /// The visits worth adding: not covered by a recorded stay, not imported before. Recorded
    /// stays are searched by time (sorted, binary search) and earlier imports by their start
    /// second, so a library of tens of thousands stays fast.
    static func newVisits(_ visits: [Visit], recorded: [Known], imported: [Known]) -> (new: [Visit], skipped: Int) {
        let byArrival = recorded.sorted { $0.arrival < $1.arrival }
        // No recorded stay is longer than this, so nothing earlier can overlap.
        let longest = byArrival.map { $0.departure.timeIntervalSince($0.arrival) }.max() ?? 0
        var importedStarts: [Int: [Known]] = [:]
        for known in imported { importedStarts[Int(known.arrival.timeIntervalSince1970), default: []].append(known) }
        let calendar = Calendar.current
        let importedByDay = Dictionary(grouping: imported) { calendar.startOfDay(for: $0.arrival) }

        var fresh: [Visit] = []
        var skipped = 0
        for visit in visits {
            let place = CLLocation(latitude: visit.latitude, longitude: visit.longitude)
            let from = visit.start.addingTimeInterval(-1800 - longest), to = visit.end.addingTimeInterval(1800)
            var low = 0, high = byArrival.count
            while low < high {
                let mid = (low + high) / 2
                if byArrival[mid].arrival < from { low = mid + 1 } else { high = mid }
            }
            var covered = false
            var i = low
            while i < byArrival.count, byArrival[i].arrival <= to {
                let stay = byArrival[i]
                if stay.departure >= visit.start.addingTimeInterval(-1800),
                   CLLocation(latitude: stay.latitude, longitude: stay.longitude).distance(from: place) < 400 {
                    covered = true
                    break
                }
                i += 1
            }
            if covered {
                skipped += 1
                continue
            }
            let second = Int(visit.start.timeIntervalSince1970)
            let seen = (second - 1...second + 1).contains { key in
                importedStarts[key]?.contains { CLLocation(latitude: $0.latitude, longitude: $0.longitude).distance(from: place) < 50 } ?? false
            }
            // Or folded into a day's visit to that city since.
            let merged = !seen && importedByDay[calendar.startOfDay(for: visit.start)]?.contains { known in
                known.arrival.addingTimeInterval(-60) <= visit.start && visit.start <= known.departure.addingTimeInterval(60)
                    && CLLocation(latitude: known.latitude, longitude: known.longitude).distance(from: place) < 40_000
            } == true
            if !seen && !merged { fresh.append(visit) }
        }
        return (fresh, skipped)
    }

    /// Once named, a day's photo visits in one city become a single visit: the timeline and
    /// lists read "嘉兴" once a day, not a dozen spots a few hundred metres apart. Visits the
    /// user named, wrote about or posted photos to are left alone. Returns how many were folded in.
    @MainActor
    static func consolidate(in context: ModelContext) async -> Int {
        let source = Self.source, tagged = TagState.tagged.rawValue
        let stays = (try? context.fetch(FetchDescriptor<Stay>(predicate: #Predicate { $0.sourceRaw == source && $0.tagStateRaw == tagged },
                                                              sortBy: [SortDescriptor(\.arrival)]))) ?? []
        let calendar = Calendar.current
        let editable = stays.filter { $0.customName == nil && ($0.note ?? "").isEmpty && ($0.photos ?? []).isEmpty && $0.city != nil }
        let groups = Dictionary(grouping: editable) { "\(calendar.startOfDay(for: $0.arrival).timeIntervalSince1970)|\($0.countryCode ?? "")|\($0.city ?? "")" }
        var removed: [Stay] = []
        for members in groups.values where members.count > 1 {
            let sorted = members.sorted { $0.arrival < $1.arrival }
            let keep = sorted[0]
            keep.departure = sorted.compactMap(\.departure).max() ?? keep.departure
            keep.sampleCount = sorted.reduce(0) { $0 + max($1.sampleCount, 1) }
            removed.append(contentsOf: sorted.dropFirst())
        }
        guard !removed.isEmpty else { return 0 }
        PlaceSummaries.shared.forget(Set(removed.map(\.persistentModelID)))
        for (index, stay) in removed.enumerated() {
            context.delete(stay)
            if index % 500 == 499 { await Task.yield() }
        }
        try? context.save()
        Diagnostics.record("photoConsolidate merged=\(removed.count) groups=\(groups.count)")
        return removed.count
    }

    /// Adds the library's visits as stays and returns what happened. Re-running only adds
    /// what's new. Reading, grouping and comparing happen off the main thread; stays are added
    /// in batches so the app stays responsive.
    @MainActor
    static func importLibrary(into context: ModelContext, progress: @escaping @Sendable (Int, Int) -> Void,
                              adding: @escaping @MainActor (Int, Int) -> Void = { _, _ in }) async -> Summary {
        let existing = (try? context.fetch(FetchDescriptor<Stay>())) ?? []
        let snapshot = existing.map { (Known(arrival: $0.arrival, departure: max($0.departure ?? Date(), $0.arrival),
                                             latitude: $0.latitude, longitude: $0.longitude), $0.isFromPhotos) }
        let recorded = snapshot.filter { !$0.1 }.map(\.0)
        // Visits deleted by hand count as imported, so scanning again doesn't bring them back.
        let imported = snapshot.filter(\.1).map(\.0) + DeletedPhotoVisits.all

        let found = await Task.detached(priority: .userInitiated) {
            let library = shotsInLibrary(progress: progress)
            let grouped = visits(from: library.shots)
            let result = newVisits(grouped, recorded: recorded, imported: imported)
            return (library.scanned, library.shots.count, result.new, result.skipped)
        }.value
        var summary = Summary(scanned: found.0, withLocation: found.1, skippedAlreadyRecorded: found.3)

        let fresh = found.2
        for (index, visit) in fresh.enumerated() {
            let stay = Stay(arrival: visit.start, coordinate: visit.coordinate)
            stay.departure = max(visit.end, visit.start.addingTimeInterval(60))
            stay.sampleCount = visit.shots
            stay.sourceRaw = source
            context.insert(stay)
            summary.visits += 1
            if index % 250 == 249 {
                try? context.save()
                adding(index + 1, fresh.count)
                await Task.yield()
            }
        }
        try? context.save()
        adding(fresh.count, fresh.count)
        Diagnostics.record("photoImport scanned=\(summary.scanned) located=\(summary.withLocation) added=\(summary.visits) skipped=\(summary.skippedAlreadyRecorded)")
        return summary
    }
}

/// Photo visits the person deleted. Scanning the library again skips them instead of adding
/// them back. Kept in iCloud so another device's scan skips them too.
enum DeletedPhotoVisits {
    private static let key = "photoImport.deleted"
    private static let limit = 3000

    static var all: [PhotoFootprints.Known] {
        stored.compactMap { row in
            guard row.count == 4 else { return nil }
            return PhotoFootprints.Known(arrival: Date(timeIntervalSince1970: row[0]), departure: Date(timeIntervalSince1970: row[1]),
                                         latitude: row[2], longitude: row[3])
        }
    }

    static func remember(_ stay: Stay) {
        guard stay.isFromPhotos else { return }
        let row = [stay.arrival.timeIntervalSince1970, max(stay.departure ?? stay.arrival, stay.arrival).timeIntervalSince1970,
                   stay.latitude, stay.longitude]
        let rows = Array((stored + [row]).suffix(limit))
        UserDefaults.standard.set(rows, forKey: key)
        NSUbiquitousKeyValueStore.default.set(rows, forKey: key)
    }

    static func clear() {
        UserDefaults.standard.removeObject(forKey: key)
        NSUbiquitousKeyValueStore.default.removeObject(forKey: key)
    }

    private static var stored: [[Double]] {
        let local = UserDefaults.standard.array(forKey: key) as? [[Double]] ?? []
        let synced = NSUbiquitousKeyValueStore.default.array(forKey: key) as? [[Double]] ?? []
        return synced.count > local.count ? synced : local
    }
}

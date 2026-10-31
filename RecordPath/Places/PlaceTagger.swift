import Foundation
import CoreLocation
import MapKit
import SwiftData
import os

/// Names each stay: country and city from reverse geocoding, and the nearest point of
/// interest from MapKit, flagging well-known landmarks. Runs one request at a time to
/// stay within Apple's geocoding limits and retries later when offline.
@MainActor
final class PlaceTagger {
    private let context: ModelContext
    private var isRunning = false
    private var needsAnotherPass = false
    /// Told about each place once it has been named.
    var onTagged: ((Stay) -> Void)?
    /// Told once a batch of photo visits has been named, since one call per photo would be thousands.
    var onPhotosTagged: (() -> Void)?
    private let log = Logger(subsystem: "PathTracker", category: "PlaceTagger")

    init(context: ModelContext) {
        self.context = context
        retagMisnamedCities()
        retryFailedIfDue()
    }

    /// A place that couldn't be named (no network abroad, Apple's limit reached during a big
    /// photo import) used to stay unnamed until the user found the button in Settings, so a
    /// trip to Thailand could leave no country and no stamp. They're tried again twice a day.
    private func retryFailedIfDue() {
        let key = "tagger.lastFailedRetry"
        let last = UserDefaults.standard.double(forKey: key)
        guard Date().timeIntervalSince1970 - last > 12 * 3600 else { return }
        UserDefaults.standard.set(Date().timeIntervalSince1970, forKey: key)
        let failed = TagState.failed.rawValue
        let stays = (try? context.fetch(FetchDescriptor<Stay>(predicate: #Predicate { $0.tagStateRaw == failed }))) ?? []
        guard !stays.isEmpty else { return }
        for stay in stays { stay.tagState = .pending }
        try? context.save()
        Diagnostics.record("tagger retry failed=\(stays.count)")
    }

    /// Earlier versions stored a whole Chinese address ("中国上海市上海") or a Hong Kong district
    /// as the city. Those places are named again, once.
    private func retagMisnamedCities() {
        let key = "tagger.retaggedCities.v1"
        guard !UserDefaults.standard.bool(forKey: key) else { return }
        let stays = (try? context.fetch(FetchDescriptor<Stay>())) ?? []
        for stay in stays where (stay.city?.hasPrefix("中国") ?? false) || stay.countryCode == "HK" || stay.countryCode == "MO" {
            stay.tagState = .pending
        }
        try? context.save()
        UserDefaults.standard.set(true, forKey: key)
    }

    func enqueue() {
        guard !isRunning else { needsAnotherPass = true; return }
        isRunning = true
        Task {
            repeat {
                needsAnotherPass = false
                await processPending()
            } while needsAnotherPass
            isRunning = false
        }
    }

    private func processPending() async {
        await processPendingPhotos()
        let pending = TagState.pending.rawValue
        var descriptor = FetchDescriptor<Stay>(predicate: #Predicate { $0.tagStateRaw == pending && $0.sourceRaw == nil },
                                               sortBy: [SortDescriptor(\.arrival, order: .reverse)])
        descriptor.fetchLimit = 120
        guard let stays = try? context.fetch(descriptor), !stays.isEmpty else {
            await fillTimeZones()
            return
        }

        for stay in stays {
            if Self.isGone(stay) { continue }
            let outcome = await tagPatiently(stay)
            try? context.save()
            if outcome != .done { return }
            if !Self.isGone(stay) { onTagged?(stay) }
            // Up to three map requests per place; stay well under Apple's rate limit.
            try? await Task.sleep(for: .milliseconds(2000))
        }
        needsAnotherPass = true
    }

    /// Places named before time zones were kept get theirs: one lookup per one-degree area,
    /// shared by every place in it, and only a few areas each time the queue is empty.
    private func fillTimeZones() async {
        let tagged = TagState.tagged.rawValue
        let missing = (try? context.fetch(FetchDescriptor<Stay>(predicate: #Predicate { $0.tagStateRaw == tagged && $0.timeZoneID == nil }))) ?? []
        guard !missing.isEmpty else { return }
        func area(_ stay: Stay) -> String { "\(Int(stay.latitude.rounded(.down))),\(Int(stay.longitude.rounded(.down)))" }
        var zones: [String: String] = [:]
        let known = (try? context.fetch(FetchDescriptor<Stay>(predicate: #Predicate { $0.timeZoneID != nil }))) ?? []
        for stay in known { if let zone = stay.timeZoneID { zones[area(stay)] = zone } }

        var lookups = 0
        for stay in missing {
            if Self.isGone(stay) { continue }
            let key = area(stay)
            if zones[key] == nil, lookups < 12, let request = MKReverseGeocodingRequest(location: stay.location) {
                lookups += 1
                do {
                    if let zone = try await request.mapItems.first?.timeZone?.identifier { zones[key] = zone }
                } catch let error as NSError where Self.isThrottled(error) {
                    break
                } catch {}
                try? await Task.sleep(for: .milliseconds(1500))
                if Self.isGone(stay) { continue }
            }
            if let zone = zones[key] { stay.timeZoneID = zone }
        }
        try? context.save()
        Diagnostics.record("timeZones filled lookups=\(lookups) missing=\(missing.count)")
    }

    /// Photo visits can number in the thousands. Named places go into a grid of ~3 km cells
    /// held in memory; a visit with a named neighbour copies its city and country, and only
    /// one visit per empty area is sent to the geocoder. Saves are batched so the screens
    /// showing places don't redraw thousands of times.
    private func processPendingPhotos() async {
        let pending = TagState.pending.rawValue, tagged = TagState.tagged.rawValue
        let waiting = (try? context.fetch(FetchDescriptor<Stay>(predicate: #Predicate { $0.tagStateRaw == pending && $0.sourceRaw != nil },
                                                                 sortBy: [SortDescriptor(\.arrival, order: .reverse)]))) ?? []
        let consolidatedKey = "photoImport.consolidated.v1"
        guard !waiting.isEmpty else {
            // Libraries imported before same-day visits were merged get merged once.
            if !UserDefaults.standard.bool(forKey: consolidatedKey) {
                _ = await PhotoFootprints.consolidate(in: context)
                UserDefaults.standard.set(true, forKey: consolidatedKey)
            }
            return
        }
        let named = (try? context.fetch(FetchDescriptor<Stay>(predicate: #Predicate { $0.tagStateRaw == tagged && $0.countryCode != nil }))) ?? []
        var grid = PhotoGrid()
        named.forEach { grid.add($0) }

        var unnamed: [Stay] = []
        for (index, stay) in waiting.enumerated() {
            if Self.isGone(stay) { continue }
            // Copies don't go back into the grid, so a name can't creep from one visit to the next.
            if let neighbour = grid.nearest(to: stay, within: 3_000) {
                stay.copyPlace(from: neighbour)
            } else {
                unnamed.append(stay)
            }
            if index % 400 == 399 {
                try? context.save()
                await Task.yield()
            }
        }
        try? context.save()
        onPhotosTagged?()

        var geocoded = 0
        for stay in unnamed {
            if Self.isGone(stay) { continue }
            if let neighbour = grid.nearest(to: stay, within: 3_000) {
                // Named by a visit geocoded a moment ago.
                stay.copyPlace(from: neighbour)
                continue
            }
            let outcome = await tagPatiently(stay, lookForNeighbour: false)
            if outcome != .done { break }
            if !Self.isGone(stay), stay.countryCode != nil { grid.add(stay) }
            geocoded += 1
            // Every save redraws whatever shows places; a dozen at a time is plenty.
            if geocoded % 12 == 0 { try? context.save() }
            try? await Task.sleep(for: .milliseconds(1300))
        }
        try? context.save()
        _ = await PhotoFootprints.consolidate(in: context)
        UserDefaults.standard.set(true, forKey: consolidatedKey)
        onPhotosTagged?()
        Diagnostics.record("photoTag named=\(waiting.count - unnamed.count) geocoded=\(unnamed.count)")
    }

    private enum Outcome { case done, offline, throttled }

    /// Apple allows about fifty lookups a minute. Past that it refuses for a while, which
    /// isn't a reason to give up on a place: wait a minute and ask again.
    private func tagPatiently(_ stay: Stay, lookForNeighbour: Bool = true) async -> Outcome {
        var outcome = await tag(stay, lookForNeighbour: lookForNeighbour)
        var attempts = 0
        while outcome == .throttled, attempts < 5 {
            attempts += 1
            try? await Task.sleep(for: .seconds(60))
            if Self.isGone(stay) { return .done }
            outcome = await tag(stay, lookForNeighbour: lookForNeighbour)
        }
        return outcome
    }

    /// A place can be deleted while a lookup for it is under way; it mustn't be touched after.
    private static func isGone(_ stay: Stay) -> Bool { stay.modelContext == nil || stay.isDeleted }

    private static func isThrottled(_ error: NSError) -> Bool {
        if error.domain == MKErrorDomain, error.code == Int(MKError.loadingThrottled.rawValue) { return true }
        if error.domain == "GEOErrorDomain", error.code == -3 { return true }
        if let underlying = error.userInfo[NSUnderlyingErrorKey] as? NSError { return isThrottled(underlying) }
        return false
    }

    /// Places that came only from photos carry just their city's name, so several frequent
    /// spots in one city would all read "新加坡". The few shown as frequent places get a real
    /// name: the point of interest there, else the street. Each is looked up once.
    func nameFrequentPlaces(_ stays: [Stay]) {
        let unnamed = stays.filter { $0.customName == nil && $0.placeName == nil && $0.street == nil }
        guard !unnamed.isEmpty, !isNamingFrequent else { return }
        isNamingFrequent = true
        Task {
            defer { isNamingFrequent = false }
            for stay in unnamed {
                if Self.isGone(stay) { continue }
                let item = await nearestPointOfInterest(around: stay.location, radius: 150, filter: .includingAll,
                                                        excluding: PlaceCategory.utilityCategories)
                if Self.isGone(stay) { continue }
                if let item {
                    stay.placeName = item.name
                    if stay.categoryRaw == nil { stay.categoryRaw = item.pointOfInterestCategory?.rawValue }
                } else if await tagPatiently(stay, lookForNeighbour: false) != .done {
                    return
                }
                try? context.save()
                try? await Task.sleep(for: .milliseconds(1500))
            }
        }
    }

    private var isNamingFrequent = false

    private func tag(_ stay: Stay, lookForNeighbour: Bool = true) async -> Outcome {
        let location = stay.location
        // Photo visits can number in the thousands: take the city from a named place close by
        // when there is one, and don't look for points of interest.
        if stay.isFromPhotos, lookForNeighbour {
            if let neighbour = nearestTagged(to: stay, within: 3_000) {
                stay.country = neighbour.country
                stay.countryCode = neighbour.countryCode
                stay.city = neighbour.city
                stay.region = neighbour.region
                stay.timeZoneID = neighbour.timeZoneID
                stay.tagState = .tagged
                return .done
            }
        }
        do {
            guard let request = MKReverseGeocodingRequest(location: location) else { return .done }
            let item = try await request.mapItems.first
            if Self.isGone(stay) { return .done }
            if let item, let address = item.addressRepresentations {
                stay.country = address.regionName
                stay.countryCode = address.region?.identifier
                stay.city = CityName.normalized(cityName: address.cityName,
                                                shortContext: address.cityWithContext(.short),
                                                countryCode: address.region?.identifier,
                                                regionName: address.regionName)
                stay.region = address.cityWithContext
                stay.street = item.address?.shortAddress ?? item.name
            }
            if let zone = item?.timeZone?.identifier { stay.timeZoneID = zone }
        } catch let error as NSError where Self.isThrottled(error) {
            Diagnostics.record("geocode throttled")
            return .throttled
        } catch let error as NSError where error.domain == NSURLErrorDomain
                    || (error.domain == MKErrorDomain && error.code == Int(MKError.serverFailure.rawValue)) {
            Diagnostics.record("geocode offline")
            return .offline
        } catch {
            log.error("Geocoding failed: \(error.localizedDescription)")
            Diagnostics.record("geocode failed \(error.localizedDescription)")
        }
        guard !Self.isGone(stay) else { return .done }

        if stay.isFromPhotos {
            stay.tagState = stay.country == nil ? .failed : .tagged
            return .done
        }

        // Home, school and overnight stays are never sightseeing, even next to a famous sight.
        let personal = ["home", "school", "work"].contains(stay.categoryRaw ?? "")
        let overnight = stay.departure.map { $0.timeIntervalSince(stay.arrival) > 6 * 3600 } ?? false
        if !personal, UserMarkedSights.contains(stay) {
            // The user called this a sight; keep it one on every visit.
            if stay.categoryRaw == nil { stay.categoryRaw = MKPointOfInterestCategory.landmark.rawValue }
            stay.isLandmark = true
        } else if !personal, !overnight, let landmark = await nearestLandmark(around: location) {
            guard !Self.isGone(stay) else { return .done }
            stay.placeName = landmark.name
            stay.categoryRaw = landmark.pointOfInterestCategory?.rawValue
            stay.isLandmark = true
        } else if let item = await nearestPointOfInterest(around: location, radius: 90, filter: .includingAll,
                                                          excluding: PlaceCategory.utilityCategories) {
            guard !Self.isGone(stay) else { return .done }
            stay.placeName = item.name
            if stay.categoryRaw == nil { stay.categoryRaw = item.pointOfInterestCategory?.rawValue }
        }
        guard !Self.isGone(stay) else { return .done }
        stay.tagState = stay.country == nil ? .failed : .tagged
        return .done
    }

    private func nearestTagged(to stay: Stay, within radius: CLLocationDistance) -> Stay? {
        let tagged = TagState.tagged.rawValue
        let candidates = (try? context.fetch(FetchDescriptor<Stay>(predicate: #Predicate { $0.tagStateRaw == tagged && $0.countryCode != nil }))) ?? []
        let near = candidates
            .map { ($0, $0.location.distance(from: stay.location)) }
            .filter { $0.1 <= radius }
        // Near a border (澳门 beside 珠海, 罗湖 beside 深圳) neighbours disagree; look it up instead.
        guard Set(near.compactMap { $0.0.countryCode }).count <= 1 else { return nil }
        return near.min { $0.1 < $1.1 }?.0
    }

    /// Nearby-POI search works well in most of the world but returns little in mainland China,
    /// where a keyword search for sights finds them. Sights there are often one point for a
    /// whole scenic area, hence the wider radius; the search can also wander to another
    /// country entirely, so results are always held to it.
    private func nearestLandmark(around location: CLLocation) async -> MKMapItem? {
        if let item = await nearestPointOfInterest(around: location, radius: 200,
                                                   filter: MKPointOfInterestFilter(including: PlaceCategory.landmarkCategories)) {
            return item
        }
        let request = MKLocalSearch.Request()
        request.naturalLanguageQuery = "景点"
        request.resultTypes = .pointOfInterest
        request.region = MKCoordinateRegion(center: location.coordinate, latitudinalMeters: 1000, longitudinalMeters: 1000)
        guard let response = try? await MKLocalSearch(request: request).start() else { return nil }
        return response.mapItems
            .filter { PlaceCategory.isSight($0.pointOfInterestCategory) }
            .map { ($0, $0.location.distance(from: location)) }
            .filter { $0.1 <= 500 }
            .min { PlaceCategory.rankingScore($0.0.pointOfInterestCategory, distance: $0.1)
                    < PlaceCategory.rankingScore($1.0.pointOfInterestCategory, distance: $1.1) }?.0
    }

    private func nearestPointOfInterest(around location: CLLocation, radius: CLLocationDistance,
                                        filter: MKPointOfInterestFilter,
                                        excluding excluded: Set<MKPointOfInterestCategory> = []) async -> MKMapItem? {
        let request = MKLocalPointsOfInterestRequest(center: location.coordinate, radius: radius)
        request.pointOfInterestFilter = filter
        guard let response = try? await MKLocalSearch(request: request).start() else { return nil }
        return response.mapItems
            .filter { item in item.pointOfInterestCategory.map { !excluded.contains($0) } ?? true }
            .map { ($0, $0.location.distance(from: location)) }
            .filter { $0.1 <= radius }
            // The tower itself beats the café or event venue inside it, unless it is much farther.
            .min { PlaceCategory.rankingScore($0.0.pointOfInterestCategory, distance: $0.1)
                    < PlaceCategory.rankingScore($1.0.pointOfInterestCategory, distance: $1.1) }?.0
    }

    /// Retries stays that failed earlier, e.g. after the user was offline abroad.
    func retryFailed() {
        let failed = TagState.failed.rawValue
        let descriptor = FetchDescriptor<Stay>(predicate: #Predicate { $0.tagStateRaw == failed })
        for stay in (try? context.fetch(descriptor)) ?? [] { stay.tagState = .pending }
        try? context.save()
        enqueue()
    }
}

/// Places the user has named ("家", "学校"). A name given once applies to every visit nearby.
enum KnownPlaces {
    static let radius: CLLocationDistance = 150

    static func applyName(to stay: Stay, in context: ModelContext) {
        let descriptor = FetchDescriptor<Stay>(predicate: #Predicate { $0.customName != nil })
        guard let named = try? context.fetch(descriptor) else { return }
        if let match = named.min(by: { $0.location.distance(from: stay.location) < $1.location.distance(from: stay.location) }),
           match.location.distance(from: stay.location) <= radius {
            stay.customName = match.customName
            if let raw = match.categoryRaw, ["home", "school", "work"].contains(raw) { stay.categoryRaw = raw }
        }
    }

    enum CategoryChange { case keep, set(String), sight, clear }

    static func rename(_ stay: Stay, to name: String?, category: CategoryChange, in context: ModelContext) {
        let trimmed = name?.trimmingCharacters(in: .whitespacesAndNewlines).nilIfEmpty
        let all = (try? context.fetch(FetchDescriptor<Stay>())) ?? []
        for other in all where other.location.distance(from: stay.location) <= radius {
            other.customName = trimmed
            switch category {
            case .keep: break
            case .set(let raw):
                other.categoryRaw = raw
                other.isLandmark = false
            case .sight:
                // Marked by hand: a sight even if MapKit has nothing famous there.
                if ["home", "school", "work"].contains(other.categoryRaw ?? "") || other.categoryRaw == nil {
                    other.categoryRaw = MKPointOfInterestCategory.landmark.rawValue
                }
                other.isLandmark = true
            case .clear:
                other.categoryRaw = nil
                other.isLandmark = false
                other.tagState = .pending
            }
        }
        try? context.save()
    }
}

extension String {
    var nilIfEmpty: String? { isEmpty ? nil : self }
}

/// Turns MapKit's city into the city people mean: "London" rather than "City of Westminster,
/// London", and "Tokyo" rather than one of its 23 wards.
enum CityName {
    private static let tokyoNames: Set<String> = ["Tokyo", "東京", "東京都", "东京", "东京都", "도쿄", "도쿄도"]

    static func normalized(cityName: String?, shortContext: String?, countryCode: String?, regionName: String? = nil) -> String? {
        // Hong Kong and Macau are one city each; geocoding reports their districts ("Central").
        if countryCode == "HK" || countryCode == "MO" {
            let chinese = (regionName ?? cityName ?? "").unicodeScalars.contains { (0x4E00...0x9FFF).contains($0.value) }
            return countryCode == "HK" ? (chinese ? "香港" : "Hong Kong") : (chinese ? "澳门" : "Macao")
        }
        // Chinese addresses run together without separators ("中国浙江杭州"); the city is at the end.
        if let cityName, let context = shortContext, !context.contains(where: { $0 == "," || $0 == "，" || $0 == "、" }),
           context != cityName, context.hasSuffix(cityName) {
            return cityName
        }
        let parts = (shortContext ?? "")
            .split(whereSeparator: { $0 == "," || $0 == "，" || $0 == "、" })
            .map { $0.trimmingCharacters(in: .whitespaces) }
            .filter { !$0.isEmpty }
        if countryCode == "JP", parts.count >= 2, tokyoNames.contains(parts[1]) {
            return parts[1].hasSuffix("都") ? String(parts[1].dropLast()) : parts[1]
        }
        return parts.first ?? cityName?.split(separator: ",").first.map { $0.trimmingCharacters(in: .whitespaces) }
    }
}

/// Named places bucketed by a ~3 km grid, for finding a neighbour without scanning them all.
private struct PhotoGrid {
    private var cells: [Int64: [Stay]] = [:]
    private let size = 0.03

    private func cell(_ lat: Double, _ lon: Double) -> (Int64, Int64) {
        (Int64((lat / size).rounded(.down)), Int64((lon / size).rounded(.down)))
    }

    private func key(_ c: (Int64, Int64)) -> Int64 { c.0 &* 100_000 &+ c.1 }

    mutating func add(_ stay: Stay) {
        cells[key(cell(stay.latitude, stay.longitude)), default: []].append(stay)
    }

    func nearest(to stay: Stay, within radius: CLLocationDistance) -> Stay? {
        let c = cell(stay.latitude, stay.longitude)
        var best: (Stay, CLLocationDistance)?
        var countries = Set<String>()
        for dy in -1...1 {
            for dx in -1...1 {
                for other in cells[key((c.0 + Int64(dy), c.1 + Int64(dx)))] ?? [] {
                    let d = other.location.distance(from: stay.location)
                    guard d <= radius else { continue }
                    if let code = other.countryCode { countries.insert(code) }
                    if d < (best?.1 ?? .infinity) { best = (other, d) }
                }
            }
        }
        // Neighbours in two countries means a border nearby: look this one up instead.
        return countries.count > 1 ? nil : best?.0
    }
}

private extension Stay {
    func copyPlace(from neighbour: Stay) {
        country = neighbour.country
        countryCode = neighbour.countryCode
        city = neighbour.city
        region = neighbour.region
        timeZoneID = neighbour.timeZoneID
        tagState = .tagged
    }
}

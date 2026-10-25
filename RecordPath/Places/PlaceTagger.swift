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
    private let log = Logger(subsystem: "PathTracker", category: "PlaceTagger")

    init(context: ModelContext) {
        self.context = context
        retagMisnamedCities()
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
        let pending = TagState.pending.rawValue
        var descriptor = FetchDescriptor<Stay>(predicate: #Predicate { $0.tagStateRaw == pending },
                                               sortBy: [SortDescriptor(\.arrival, order: .reverse)])
        descriptor.fetchLimit = 40
        guard let stays = try? context.fetch(descriptor), !stays.isEmpty else { return }

        for stay in stays {
            let outcome = await tag(stay)
            try? context.save()
            if outcome == .offline { return }
            onTagged?(stay)
            // Up to three map requests per place; stay well under Apple's rate limit.
            try? await Task.sleep(for: .seconds(2))
        }
        needsAnotherPass = true
    }

    private enum Outcome { case done, offline }

    private func tag(_ stay: Stay) async -> Outcome {
        let location = stay.location
        do {
            guard let request = MKReverseGeocodingRequest(location: location) else { return .done }
            if let item = try await request.mapItems.first, let address = item.addressRepresentations {
                stay.country = address.regionName
                stay.countryCode = address.region?.identifier
                stay.city = CityName.normalized(cityName: address.cityName,
                                                shortContext: address.cityWithContext(.short),
                                                countryCode: address.region?.identifier,
                                                regionName: address.regionName)
                stay.region = address.cityWithContext
                stay.street = item.address?.shortAddress ?? item.name
            }
        } catch let error as NSError where error.domain == NSURLErrorDomain
                    || (error.domain == MKErrorDomain && error.code == Int(MKError.serverFailure.rawValue)) {
            return .offline
        } catch {
            log.error("Geocoding failed: \(error.localizedDescription)")
        }

        // Home, school and overnight stays are never sightseeing, even next to a famous sight.
        let personal = ["home", "school", "work"].contains(stay.categoryRaw ?? "")
        let overnight = stay.departure.map { $0.timeIntervalSince(stay.arrival) > 6 * 3600 } ?? false
        if !personal, !overnight, let landmark = await nearestLandmark(around: location) {
            stay.placeName = landmark.name
            stay.categoryRaw = landmark.pointOfInterestCategory?.rawValue
            stay.isLandmark = true
        } else if let item = await nearestPointOfInterest(around: location, radius: 90, filter: .includingAll,
                                                          excluding: PlaceCategory.utilityCategories) {
            stay.placeName = item.name
            if stay.categoryRaw == nil { stay.categoryRaw = item.pointOfInterestCategory?.rawValue }
        }
        stay.tagState = stay.country == nil ? .failed : .tagged
        return .done
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

    enum CategoryChange { case keep, set(String), clear }

    static func rename(_ stay: Stay, to name: String?, category: CategoryChange, in context: ModelContext) {
        let trimmed = name?.trimmingCharacters(in: .whitespacesAndNewlines).nilIfEmpty
        let all = (try? context.fetch(FetchDescriptor<Stay>())) ?? []
        for other in all where other.location.distance(from: stay.location) <= radius {
            other.customName = trimmed
            switch category {
            case .keep: break
            case .set(let raw): other.categoryRaw = raw
            case .clear:
                other.categoryRaw = nil
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

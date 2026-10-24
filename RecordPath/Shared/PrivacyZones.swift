import Foundation
import CoreLocation

/// Places the user never wants to reveal (home, a partner's place). Tracks inside a zone are
/// cut out of shared images and exported files; nothing is removed from the user's own data.
struct PrivacyZone: Codable, Identifiable, Hashable {
    var id = UUID()
    var name: String
    var latitude: Double
    var longitude: Double
    var radius: CLLocationDistance = 300

    var location: CLLocation { CLLocation(latitude: latitude, longitude: longitude) }

    func contains(_ coordinate: CLLocationCoordinate2D) -> Bool {
        location.distance(from: CLLocation(latitude: coordinate.latitude, longitude: coordinate.longitude)) <= radius
    }
}

@MainActor
@Observable
final class PrivacyZones {
    static let shared = PrivacyZones()

    private(set) var zones: [PrivacyZone] = []
    private let key = "privacy.zones"
    private let cloud = NSUbiquitousKeyValueStore.default

    private init() {
        let data = cloud.data(forKey: key) ?? UserDefaults.standard.data(forKey: key)
        zones = data.flatMap { try? JSONDecoder().decode([PrivacyZone].self, from: $0) } ?? []
    }

    func zone(near coordinate: CLLocationCoordinate2D) -> PrivacyZone? {
        zones.first { $0.contains(coordinate) }
    }

    func add(name: String, at coordinate: CLLocationCoordinate2D) {
        guard zone(near: coordinate) == nil else { return }
        zones.append(PrivacyZone(name: name, latitude: coordinate.latitude, longitude: coordinate.longitude))
        save()
    }

    func remove(_ zone: PrivacyZone) {
        zones.removeAll { $0.id == zone.id }
        save()
    }

    /// Splits a track wherever it enters a zone, dropping the hidden part.
    func visibleSegments(of points: [TrackPoint]) -> [[TrackPoint]] {
        guard !zones.isEmpty else { return [points] }
        var segments: [[TrackPoint]] = [[]]
        for point in points {
            if zone(near: point.coordinate) != nil {
                if !(segments.last?.isEmpty ?? true) { segments.append([]) }
            } else {
                segments[segments.count - 1].append(point)
            }
        }
        return segments.filter { $0.count > 1 }
    }

    func isHidden(_ coordinate: CLLocationCoordinate2D) -> Bool { zone(near: coordinate) != nil }

    private func save() {
        guard let data = try? JSONEncoder().encode(zones) else { return }
        cloud.set(data, forKey: key)
        UserDefaults.standard.set(data, forKey: key)
        cloud.synchronize()
    }
}

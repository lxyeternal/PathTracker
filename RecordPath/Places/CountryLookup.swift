import Foundation
import CoreLocation

/// Which country a coordinate is in, from the outlines the app carries, with no network.
///
/// Apple's lookup answers with a place's country almost everywhere, but not for someone in
/// mainland China asking about a place abroad: the map data there comes from another provider
/// and often has nothing to say outside China. A library of photos from trips abroad then
/// came in with no countries at all. This is what's asked when Apple has no answer.
enum CountryLookup {
    private struct Ring {
        let code: String
        let points: [CLLocationCoordinate2D]
        let minLat, maxLat, minLon, maxLon: Double

        init(code: String, points: [CLLocationCoordinate2D]) {
            self.code = code
            self.points = points
            minLat = points.map(\.latitude).min() ?? 0
            maxLat = points.map(\.latitude).max() ?? 0
            minLon = points.map(\.longitude).min() ?? 0
            maxLon = points.map(\.longitude).max() ?? 0
        }

        /// Of its bounding box, in square degrees: only to tell small from large.
        var area: Double { (maxLat - minLat) * (maxLon - minLon) }

        func boxContains(_ point: CLLocationCoordinate2D, margin: Double = 0) -> Bool {
            point.latitude >= minLat - margin && point.latitude <= maxLat + margin
                && point.longitude >= minLon - margin && point.longitude <= maxLon + margin
        }

        func contains(_ point: CLLocationCoordinate2D) -> Bool {
            guard boxContains(point) else { return false }
            var inside = false
            var j = points.count - 1
            for i in points.indices {
                let a = points[i], b = points[j]
                if (a.latitude > point.latitude) != (b.latitude > point.latitude),
                   point.longitude < (b.longitude - a.longitude) * (point.latitude - a.latitude) / (b.latitude - a.latitude) + a.longitude {
                    inside.toggle()
                }
                j = i
            }
            return inside
        }
    }

    private static let rings: [Ring] = {
        guard let url = Bundle.main.url(forResource: "CountryBorders", withExtension: "json"),
              let data = try? Data(contentsOf: url),
              let raw = try? JSONDecoder().decode([String: [[[Double]]]].self, from: data) else { return [] }
        return raw.flatMap { code, rings in
            rings.map { ring in Ring(code: code, points: ring.map { CLLocationCoordinate2D(latitude: $0[1], longitude: $0[0]) }) }
        }
    }()

    /// A harbour or a beach can fall just outside a simplified coastline.
    private static let shoreMargin: CLLocationDistance = 25_000

    /// The outlines leave India out, so it is what's left of this box once its neighbours,
    /// which do have outlines, have been ruled out.
    private static func isInIndiaBox(_ point: CLLocationCoordinate2D) -> Bool {
        (8.0...35.5).contains(point.latitude) && (68.5...97.4).contains(point.longitude)
    }

    /// The ISO code of the country at `coordinate`, or nil at sea and where no outline is near.
    static func code(at coordinate: CLLocationCoordinate2D) -> String? {
        guard CLLocationCoordinate2DIsValid(coordinate) else { return nil }
        // The Vatican's outline is a dot a hundred metres across, far smaller than the state;
        // within half a kilometre of such a dot counts as inside it.
        if let tiny = rings.first(where: { $0.area < 0.0003 && $0.boxContains(coordinate, margin: 0.005) }) { return tiny.code }
        // An enclave lies inside two outlines; the smaller one is the country it belongs to.
        let inside = rings.filter { $0.contains(coordinate) }
        if let match = inside.min(by: { $0.area < $1.area }) {
            return match.code
        }
        let here = CLLocation(latitude: coordinate.latitude, longitude: coordinate.longitude)
        var nearest: (code: String, distance: CLLocationDistance)?
        for ring in rings where ring.boxContains(coordinate, margin: 0.4) {
            for point in ring.points {
                let distance = here.distance(from: CLLocation(latitude: point.latitude, longitude: point.longitude))
                if distance < nearest?.distance ?? shoreMargin { nearest = (ring.code, distance) }
            }
        }
        if let nearest { return nearest.code }
        return isInIndiaBox(coordinate) ? "IN" : nil
    }
}

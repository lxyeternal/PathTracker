import Foundation
import CoreLocation

/// Apple Maps in mainland China draws its map in GCJ-02, China's legally required offset of
/// GPS coordinates. GPS (WGS-84) points drawn on it land up to ~500 m off the roads, so they are
/// converted when drawn. Recorded data always stays in WGS-84.
enum ChinaCoordinates {
    /// The map coordinate for a GPS coordinate: shifted in mainland China, unchanged elsewhere
    /// (Hong Kong, Macau and Taiwan use WGS-84 maps).
    static func mapCoordinate(for gps: CLLocationCoordinate2D) -> CLLocationCoordinate2D {
        guard isInMainland(gps) else { return gps }
        return gcj02(from: gps)
    }

    static func isInMainland(_ c: CLLocationCoordinate2D) -> Bool {
        guard c.latitude > 17.8, c.latitude < 53.6, c.longitude > 73.4, c.longitude < 135.1 else { return false }
        let point = (x: c.longitude, y: c.latitude)
        guard contains(mainland, point) else { return false }
        if excludedBoxes.contains(where: { $0.contains(point) }) { return false }
        return !contains(hongKong, point) && !contains(macau, point)
    }

    /// The standard WGS-84 → GCJ-02 transform.
    static func gcj02(from wgs: CLLocationCoordinate2D) -> CLLocationCoordinate2D {
        let a = 6_378_245.0
        let ee = 0.006_693_421_622_965_943
        let x = wgs.longitude - 105.0, y = wgs.latitude - 35.0
        var dLat = -100.0 + 2.0 * x + 3.0 * y + 0.2 * y * y + 0.1 * x * y + 0.2 * abs(x).squareRoot()
        dLat += (20.0 * sin(6.0 * x * .pi) + 20.0 * sin(2.0 * x * .pi)) * 2.0 / 3.0
        dLat += (20.0 * sin(y * .pi) + 40.0 * sin(y / 3.0 * .pi)) * 2.0 / 3.0
        dLat += (160.0 * sin(y / 12.0 * .pi) + 320.0 * sin(y * .pi / 30.0)) * 2.0 / 3.0
        var dLon = 300.0 + x + 2.0 * y + 0.1 * x * x + 0.1 * x * y + 0.1 * abs(x).squareRoot()
        dLon += (20.0 * sin(6.0 * x * .pi) + 20.0 * sin(2.0 * x * .pi)) * 2.0 / 3.0
        dLon += (20.0 * sin(x * .pi) + 40.0 * sin(x / 3.0 * .pi)) * 2.0 / 3.0
        dLon += (150.0 * sin(x / 12.0 * .pi) + 300.0 * sin(x / 30.0 * .pi)) * 2.0 / 3.0
        let radLat = wgs.latitude / 180.0 * .pi
        var magic = sin(radLat)
        magic = 1 - ee * magic * magic
        let sqrtMagic = magic.squareRoot()
        dLat = (dLat * 180.0) / ((a * (1 - ee)) / (magic * sqrtMagic) * .pi)
        dLon = (dLon * 180.0) / (a / sqrtMagic * cos(radLat) * .pi)
        return CLLocationCoordinate2D(latitude: wgs.latitude + dLat, longitude: wgs.longitude + dLon)
    }

    // MARK: Boundaries

    private struct Box {
        let west, south, east, north: Double
        func contains(_ p: (x: Double, y: Double)) -> Bool { p.x >= west && p.x <= east && p.y >= south && p.y <= north }
    }

    private static func contains(_ polygon: [(Double, Double)], _ p: (x: Double, y: Double)) -> Bool {
        var inside = false
        var j = polygon.count - 1
        for i in polygon.indices {
            let (xi, yi) = polygon[i], (xj, yj) = polygon[j]
            if (yi > p.y) != (yj > p.y), p.x < (xj - xi) * (p.y - yi) / (yj - yi) + xi { inside.toggle() }
            j = i
        }
        return inside
    }

    /// Mainland China's outline (longitude, latitude), coarse along the coast and in remote
    /// border areas, closer where border cities face each other (Heihe, Dandong, Ruili…).
    private static let mainland: [(Double, Double)] = [
        (121.2, 53.35), (122.6, 53.55), (124.0, 53.4), (125.6, 53.0), (126.6, 52.0), (127.3, 50.9), (127.6, 50.3),
        (128.5, 49.6), (130.6, 48.9), (130.7, 48.5), (131.5, 47.75), (132.5, 47.75), (133.5, 48.1), (134.75, 48.4),
        (134.3, 47.6), (133.75, 46.4), (133.1, 45.1), (132.0, 45.25), (131.0, 44.9), (131.3, 44.0), (130.9, 43.0),
        (130.6, 42.45), (129.85, 42.95), (129.2, 42.42), (128.1, 42.0), (128.2, 41.45), (127.2, 41.5), (126.3, 41.2),
        (125.5, 40.7), (124.8, 40.35), (124.35, 40.0), (122.8, 39.0), (121.5, 38.65), (122.75, 37.4), (120.5, 35.9),
        (119.5, 34.6), (121.0, 32.6), (122.2, 31.4), (122.5, 30.0), (121.9, 28.8), (120.9, 27.5), (120.0, 26.6),
        (119.9, 25.4), (119.0, 24.9), (118.5, 24.3), (117.5, 23.5), (116.6, 22.85), (115.2, 22.6), (114.6, 22.4),
        (114.2, 22.1), (113.6, 21.95), (112.5, 21.6), (111.3, 21.3), (110.8, 20.4), (111.2, 19.9), (110.6, 18.1),
        (109.3, 18.1), (108.55, 18.6), (108.6, 19.3), (109.6, 21.3), (108.6, 21.55), (108.0, 21.5), (107.4, 21.6),
        (106.75, 22.0), (106.65, 22.85), (105.8, 23.0), (105.3, 23.3), (104.4, 22.8), (103.96, 22.50), (103.0, 22.6),
        (102.1, 22.4), (101.85, 21.6), (101.7, 21.15), (101.15, 21.55), (100.2, 21.45), (99.95, 21.7), (99.5, 22.1),
        (98.9, 23.2), (97.6, 23.9), (97.6, 24.8), (98.7, 26.0), (98.3, 27.5), (97.6, 28.4), (97.1, 28.3), (95.4, 29.0),
        (94.0, 28.8), (92.1, 27.8), (91.6, 27.95), (90.5, 28.1), (89.6, 28.2), (89.2, 27.9), (88.9, 27.3), (88.6, 28.1),
        (88.1, 27.9), (86.9, 28.0), (86.0, 28.05), (85.0, 28.6), (83.5, 29.3), (82.0, 30.2), (81.1, 30.1), (80.25, 30.4),
        (79.5, 30.9), (79.0, 31.3), (78.4, 32.5), (78.8, 33.5), (78.0, 35.5), (76.5, 35.9), (75.4, 36.85), (74.85, 37.2),
        (74.9, 38.4), (73.6, 39.5), (74.9, 40.5), (76.0, 40.5), (78.5, 41.5), (80.2, 42.1), (80.8, 43.2), (80.4, 44.9),
        (82.5, 45.3), (82.3, 46.2), (83.0, 47.2), (85.5, 47.0), (85.7, 48.4), (87.3, 49.1), (87.8, 49.17), (90.0, 47.9),
        (91.0, 46.6), (93.5, 44.9), (95.4, 44.3), (96.4, 42.7), (100.0, 42.6), (103.0, 41.9), (105.0, 41.6), (107.0, 42.2),
        (110.0, 42.6), (111.9, 43.65), (113.0, 44.6), (115.5, 45.4), (117.4, 46.6), (119.7, 46.6), (119.9, 47.5),
        (118.5, 48.0), (117.4, 47.7), (115.6, 47.9), (116.7, 49.8), (117.8, 49.55), (119.2, 50.3), (120.0, 51.6),
    ]

    /// Hong Kong, drawn along the Shenzhen River so Shenzhen itself stays mainland.
    private static let hongKong: [(Double, Double)] = [
        (113.82, 22.13), (113.82, 22.19), (113.84, 22.37), (113.90, 22.43), (113.97, 22.47), (114.03, 22.498),
        (114.06, 22.505), (114.09, 22.514), (114.10, 22.525), (114.12, 22.532), (114.15, 22.54), (114.22, 22.555), (114.25, 22.56),
        (114.33, 22.53), (114.40, 22.42), (114.42, 22.13),
    ]

    /// Macau, leaving Zhuhai's Gongbei and Hengqin on the mainland side.
    private static let macau: [(Double, Double)] = [
        (113.528, 22.19), (113.528, 22.215), (113.555, 22.217), (113.565, 22.19), (113.60, 22.165), (113.60, 22.11),
        (113.548, 22.11), (113.545, 22.15), (113.535, 22.18),
    ]

    /// Taiwan, Penghu, Kinmen and Matsu, which the coarse coastline would otherwise take in.
    private static let excludedBoxes = [
        Box(west: 119.30, south: 21.75, east: 122.50, north: 25.32),
        Box(west: 118.21, south: 24.37, east: 118.50, north: 24.55),
        Box(west: 119.90, south: 25.92, east: 120.55, north: 26.30),
        Box(west: 120.45, south: 26.30, east: 120.53, north: 26.40),
    ]
}

extension CLLocationCoordinate2D {
    /// Where this GPS coordinate belongs on Apple Maps (see `ChinaCoordinates`).
    var onMap: CLLocationCoordinate2D { ChinaCoordinates.mapCoordinate(for: self) }
}

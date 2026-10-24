import Foundation
import CoreLocation

/// One recorded GPS fix. A value type; chunks store arrays of these as a compressed blob.
struct TrackPoint: Codable, Hashable {
    var latitude: Double
    var longitude: Double
    var altitude: Double
    var speed: Double
    var accuracy: Double
    var timestamp: Date

    init(_ location: CLLocation) {
        latitude = location.coordinate.latitude
        longitude = location.coordinate.longitude
        altitude = location.altitude
        speed = max(location.speed, 0)
        accuracy = location.horizontalAccuracy
        timestamp = location.timestamp
    }

    init(latitude: Double, longitude: Double, altitude: Double, speed: Double, accuracy: Double, timestamp: Date) {
        self.latitude = latitude
        self.longitude = longitude
        self.altitude = altitude
        self.speed = speed
        self.accuracy = accuracy
        self.timestamp = timestamp
    }

    var coordinate: CLLocationCoordinate2D {
        CLLocationCoordinate2D(latitude: latitude, longitude: longitude)
    }

    var location: CLLocation {
        CLLocation(coordinate: coordinate, altitude: altitude, horizontalAccuracy: accuracy,
                   verticalAccuracy: -1, timestamp: timestamp)
    }

    static func distance(of points: [TrackPoint]) -> Double {
        zip(points, points.dropFirst()).reduce(0) { $0 + $1.0.location.distance(from: $1.1.location) }
    }

    /// Total climb. GPS altitude wanders by a few metres even standing still, so only changes
    /// of at least `threshold` count.
    static func elevationGain(of points: [TrackPoint], threshold: Double = 5) -> Double {
        var gain = 0.0
        var reference: Double?
        for point in points where point.altitude != 0 {
            guard let base = reference else { reference = point.altitude; continue }
            if point.altitude - base >= threshold {
                gain += point.altitude - base
                reference = point.altitude
            } else if base - point.altitude >= threshold {
                reference = point.altitude
            }
        }
        return gain
    }
}

/// Compact binary format: 8+8 bytes for the coordinate, 4 bytes each for altitude,
/// speed, accuracy and the time offset from the first point, then LZFSE-compressed.
enum TrackCodec {
    private static let version: UInt8 = 1

    static func encode(_ points: [TrackPoint]) -> Data {
        var data = Data([version])
        guard let base = points.first?.timestamp.timeIntervalSince1970 else { return data }
        data.append(value: base)
        for point in points {
            data.append(value: point.latitude)
            data.append(value: point.longitude)
            data.append(value: Float(point.altitude))
            data.append(value: Float(point.speed))
            data.append(value: Float(point.accuracy))
            data.append(value: Float(point.timestamp.timeIntervalSince1970 - base))
        }
        return (try? (data as NSData).compressed(using: .lzfse) as Data) ?? data
    }

    static func decode(_ blob: Data) -> [TrackPoint] {
        let data = (try? (blob as NSData).decompressed(using: .lzfse) as Data) ?? blob
        guard data.first == version, data.count >= 9 else { return [] }
        var reader = DataReader(data: data, offset: 1)
        guard let base: Double = reader.read() else { return [] }
        var points: [TrackPoint] = []
        points.reserveCapacity((data.count - 9) / 32)
        while let lat: Double = reader.read(), let lon: Double = reader.read(),
              let alt: Float = reader.read(), let speed: Float = reader.read(),
              let acc: Float = reader.read(), let dt: Float = reader.read() {
            points.append(TrackPoint(latitude: lat, longitude: lon, altitude: Double(alt), speed: Double(speed),
                                     accuracy: Double(acc), timestamp: Date(timeIntervalSince1970: base + Double(dt))))
        }
        return points
    }
}

private extension Data {
    mutating func append<T>(value: T) {
        Swift.withUnsafeBytes(of: value) { append(contentsOf: $0) }
    }
}

private struct DataReader {
    let data: Data
    var offset: Int

    mutating func read<T: BitwiseCopyable>() -> T? {
        let size = MemoryLayout<T>.size
        guard offset + size <= data.count else { return nil }
        let value = data.withUnsafeBytes { $0.loadUnaligned(fromByteOffset: offset, as: T.self) }
        offset += size
        return value
    }
}

extension Array where Element == TrackPoint {
    /// Douglas–Peucker simplification so long days stay smooth to render.
    func simplified(tolerance meters: Double) -> [TrackPoint] {
        guard count > 2 else { return self }
        var keep = [Bool](repeating: false, count: count)
        keep[0] = true
        keep[count - 1] = true
        var stack: [(Int, Int)] = [(0, count - 1)]
        let origin = self[0].coordinate
        let metersPerDegLat = 111_320.0
        let metersPerDegLon = 111_320.0 * cos(origin.latitude * .pi / 180)
        func xy(_ p: TrackPoint) -> (Double, Double) {
            ((p.longitude - origin.longitude) * metersPerDegLon, (p.latitude - origin.latitude) * metersPerDegLat)
        }
        while let (start, end) = stack.popLast() {
            guard end > start + 1 else { continue }
            let (x1, y1) = xy(self[start]), (x2, y2) = xy(self[end])
            let dx = x2 - x1, dy = y2 - y1
            let length = Swift.max((dx * dx + dy * dy).squareRoot(), 0.0001)
            var maxDistance = 0.0
            var index = start
            for i in (start + 1)..<end {
                let (x0, y0) = xy(self[i])
                let d = abs(dy * x0 - dx * y0 + x2 * y1 - y2 * x1) / length
                if d > maxDistance { maxDistance = d; index = i }
            }
            if maxDistance > meters {
                keep[index] = true
                stack.append((start, index))
                stack.append((index, end))
            }
        }
        return enumerated().compactMap { keep[$0.offset] ? $0.element : nil }
    }
}

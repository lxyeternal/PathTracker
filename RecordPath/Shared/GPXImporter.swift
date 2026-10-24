import Foundation
import SwiftData
import CoreLocation

/// Reads GPX files from other apps (AllTrails, Strava, Garmin…) into tracks and places.
enum GPXImporter {
    struct Result {
        var tracks = 0
        var points = 0
        var places = 0
        var skippedDuplicates = 0
        var skippedPlaces = 0
    }

    /// True when at least 80% of the span is already covered by recorded tracks.
    static func isAlreadyRecorded(_ span: DateInterval, in recorded: [DateInterval]) -> Bool {
        guard span.duration > 0 else {
            return recorded.contains { $0.contains(span.start) }
        }
        let covered = recorded.reduce(0.0) { total, interval in
            total + (span.intersection(with: interval)?.duration ?? 0)
        }
        return covered >= span.duration * 0.8
    }

    enum ImportError: LocalizedError {
        case unreadable, empty
        var errorDescription: String? {
            switch self {
            case .unreadable: String(localized: "无法读取这个文件，它可能不是 GPX 格式。", bundle: .appLanguage)
            case .empty: String(localized: "文件里没有带时间的轨迹点。", bundle: .appLanguage)
            }
        }
    }

    @MainActor
    static func importFile(at url: URL, into context: ModelContext) throws -> Result {
        let accessing = url.startAccessingSecurityScopedResource()
        defer { if accessing { url.stopAccessingSecurityScopedResource() } }
        guard let data = try? Data(contentsOf: url) else { throw ImportError.unreadable }
        let parsed = Parser(data: data)
        guard parsed.parse() else { throw ImportError.unreadable }
        guard !parsed.segments.isEmpty || !parsed.waypoints.isEmpty else { throw ImportError.empty }

        var result = Result()
        // You can't be in two places at once: time that is already recorded is a duplicate,
        // even if the file split or trimmed the tracks differently (e.g. our own export).
        let recorded = ((try? context.fetch(FetchDescriptor<TrackChunk>())) ?? [])
            .map { DateInterval(start: $0.startDate, end: max($0.endDate, $0.startDate)) }
        for segment in parsed.segments where segment.count > 1 {
            let span = DateInterval(start: segment[0].timestamp, end: max(segment[segment.count - 1].timestamp, segment[0].timestamp))
            if isAlreadyRecorded(span, in: recorded) {
                result.skippedDuplicates += 1
                continue
            }
            for start in stride(from: 0, to: segment.count, by: 400) {
                let slice = Array(segment[max(0, start - 1)..<min(start + 400, segment.count)])
                guard slice.count > 1 else { continue }
                let speeds = zip(slice, slice.dropFirst()).map { a, b in
                    a.location.distance(from: b.location) / max(b.timestamp.timeIntervalSince(a.timestamp), 1)
                }
                context.insert(TrackChunk(points: slice, mode: MotionClassifier.mode(forSpeeds: speeds), tripID: nil))
            }
            result.tracks += 1
            result.points += segment.count
        }
        let existingStays = (try? context.fetch(FetchDescriptor<Stay>())) ?? []
        for waypoint in parsed.waypoints {
            let location = CLLocation(latitude: waypoint.latitude, longitude: waypoint.longitude)
            if existingStays.contains(where: { abs($0.arrival.timeIntervalSince(waypoint.time)) < 120
                                                && $0.location.distance(from: location) < KnownPlaces.radius }) {
                result.skippedPlaces += 1
                continue
            }
            let stay = Stay(arrival: waypoint.time, coordinate: location.coordinate)
            stay.departure = waypoint.time.addingTimeInterval(10 * 60)
            stay.customName = waypoint.name
            context.insert(stay)
            result.places += 1
        }
        guard result.tracks + result.places + result.skippedDuplicates + result.skippedPlaces > 0 else { throw ImportError.empty }
        try? context.save()
        return result
    }

    private final class Parser: NSObject, XMLParserDelegate {
        struct Waypoint { var latitude: Double; var longitude: Double; var time: Date; var name: String? }

        private let parser: XMLParser
        private(set) var segments: [[TrackPoint]] = []
        private(set) var waypoints: [Waypoint] = []

        private var current: (lat: Double, lon: Double, ele: Double, time: Date?, name: String?)?
        private var inWaypoint = false
        private var text = ""
        private let iso = ISO8601DateFormatter()
        private let isoFractional: ISO8601DateFormatter = {
            let f = ISO8601DateFormatter()
            f.formatOptions = [.withInternetDateTime, .withFractionalSeconds]
            return f
        }()

        init(data: Data) {
            parser = XMLParser(data: data)
            super.init()
            parser.delegate = self
        }

        func parse() -> Bool { parser.parse() }

        func parser(_ parser: XMLParser, didStartElement name: String, namespaceURI: String?, qualifiedName: String?,
                    attributes: [String: String] = [:]) {
            text = ""
            switch name {
            case "trkseg", "rte":
                segments.append([])
            case "trkpt", "rtept", "wpt":
                guard let lat = attributes["lat"].flatMap(Double.init), let lon = attributes["lon"].flatMap(Double.init) else { return }
                current = (lat, lon, 0, nil, nil)
                inWaypoint = name == "wpt"
            default:
                break
            }
        }

        func parser(_ parser: XMLParser, foundCharacters string: String) { text += string }

        func parser(_ parser: XMLParser, didEndElement name: String, namespaceURI: String?, qualifiedName: String?) {
            let value = text.trimmingCharacters(in: .whitespacesAndNewlines)
            switch name {
            case "ele": current?.ele = Double(value) ?? 0
            case "time": current?.time = isoFractional.date(from: value) ?? iso.date(from: value)
            case "name": if current != nil { current?.name = value }
            case "trkpt", "rtept":
                if let point = current, let time = point.time {
                    if segments.isEmpty { segments.append([]) }
                    segments[segments.count - 1].append(TrackPoint(latitude: point.lat, longitude: point.lon, altitude: point.ele,
                                                                   speed: 0, accuracy: 10, timestamp: time))
                }
                current = nil
            case "wpt":
                if let point = current, let time = point.time {
                    waypoints.append(Waypoint(latitude: point.lat, longitude: point.lon, time: time, name: point.name))
                }
                current = nil
                inWaypoint = false
            default:
                break
            }
            text = ""
        }
    }
}

import Foundation
import CoreMotion
import CoreLocation

/// Works out how a stretch of track was travelled, using the motion coprocessor when
/// available and falling back to speed. A stretch can hold more than one way of travelling
/// (walk to the stop, ride the bus, walk home), so it's split where the way changes.
final class MotionClassifier {
    private let manager = CMMotionActivityManager()

    /// One part of a track travelled one way. Neighbouring legs share their boundary point,
    /// so the line on the map stays unbroken.
    struct Leg {
        let points: [TrackPoint]
        let mode: MovementMode
    }

    /// What the motion coprocessor said from a moment on; nil when it was unsure or still.
    struct Reading {
        let start: Date
        let mode: MovementMode?
        /// The chip was sure the phone wasn't moving.
        var still = false
    }

    /// A stretch of moving the motion chip saw, for a time GPS has nothing for.
    struct Journey: Equatable {
        let start: Date
        let end: Date
        /// How it mostly moved; nil when the chip only knew it was moving.
        let mode: MovementMode?
    }

    private enum Tuning {
        /// Speeds are judged over this long either side of a point, so one fast fix or a red
        /// light doesn't change the answer.
        static let window: TimeInterval = 30
        /// A leg this short in both time and distance is folded into its neighbour: crossing
        /// a car park is part of the drive, a pause at a bus stop part of the ride.
        static let minimumLegDuration: TimeInterval = 120
        static let minimumLegDistance: Double = 300
        /// Faster than this, nobody is on foot (25 km/h).
        static let notOnFoot: Double = 7
        /// Faster than this nobody walks (11 km/h), and faster than this nobody runs (20 km/h):
        /// the motion chip calling it a walk then means wheels, usually a bicycle's.
        static let notWalking: Double = 3
        static let notRunning: Double = 5.5
        /// Faster than this, nobody is on a bicycle (43 km/h).
        static let notOnBike: Double = 12
        /// A ride whose quicker moments pass this (30 km/h) was in something with an engine.
        static let bikeBursts: Double = 8.5
        /// Between two drives, a slow stretch this fast or faster (16 km/h) is traffic, not a bike.
        static let trafficPace: Double = 4.5
        /// Still for less than this between two stretches of moving is one journey.
        static let journeyPause: TimeInterval = 5 * 60
    }

    func legs(of points: [TrackPoint]) async -> [Leg] {
        guard let first = points.first, let last = points.last, points.count >= 2 else {
            return [Leg(points: points, mode: Self.mode(forSpeeds: points.map(\.speed)))]
        }
        let readings = await history(from: first.timestamp.addingTimeInterval(-120), to: last.timestamp)
        return Self.legs(of: points, readings: readings)
    }

    /// The single way a stretch was mostly travelled.
    func mode(from start: Date, to end: Date, points: [TrackPoint]) async -> MovementMode {
        let legs = await legs(of: points)
        return legs.max { TrackPoint.distance(of: $0.points) < TrackPoint.distance(of: $1.points) }?.mode
            ?? Self.mode(forSpeeds: points.map(\.speed))
    }

    /// When the phone was on the move between two moments, from the motion history iOS keeps
    /// for a week whether or not the app was running.
    func journey(from start: Date, to end: Date) async -> Journey? {
        let readings = await history(from: start.addingTimeInterval(-600), to: end)
        return Self.journey(in: readings, from: start, to: end)
    }

    /// Whether the phone is moving right now, as far as the motion chip can tell. GPS goes quiet
    /// on a train underground; the chip still feels the ride.
    func isMoving() async -> Bool {
        let readings = await history(from: Date().addingTimeInterval(-30 * 60), to: Date())
        guard let latest = readings.max(by: { $0.start < $1.start }) else { return false }
        return latest.mode != nil && latest.mode != .unknown
    }

    private func history(from start: Date, to end: Date) async -> [Reading] {
        guard CMMotionActivityManager.isActivityAvailable(),
              CMMotionActivityManager.authorizationStatus() != .denied else { return [] }
        let activities: [CMMotionActivity] = await withCheckedContinuation { continuation in
            manager.queryActivityStarting(from: start, to: end, to: .main) { activities, _ in
                continuation.resume(returning: activities ?? [])
            }
        }
        return activities.map { activity in
            let mode: MovementMode? =
                activity.confidence == .low ? nil :
                activity.automotive ? .automotive :
                activity.cycling ? .cycling :
                activity.running ? .running :
                activity.walking ? .walking : nil
            return Reading(start: activity.startDate, mode: mode, still: activity.stationary && activity.confidence != .low)
        }
    }

    // MARK: Working it out

    /// The longest stretch of moving between two moments. Stops shorter than a few minutes
    /// (a subway station, a red light) count as part of it.
    static func journey(in readings: [Reading], from start: Date, to end: Date) -> Journey? {
        let sorted = readings.sorted { $0.start < $1.start }
        var spans: [(start: Date, end: Date, modes: [MovementMode: TimeInterval])] = []
        for (index, reading) in sorted.enumerated() {
            guard let mode = reading.mode, !reading.still else { continue }
            let from = max(reading.start, start)
            let to = min(index + 1 < sorted.count ? sorted[index + 1].start : end, end)
            guard to > from else { continue }
            if let last = spans.last, from.timeIntervalSince(last.end) < Tuning.journeyPause {
                spans[spans.count - 1].end = to
                spans[spans.count - 1].modes[mode, default: 0] += to.timeIntervalSince(from)
            } else {
                spans.append((from, to, [mode: to.timeIntervalSince(from)]))
            }
        }
        guard let longest = spans.max(by: { $0.end.timeIntervalSince($0.start) < $1.end.timeIntervalSince($1.start) }),
              longest.end.timeIntervalSince(longest.start) >= Tuning.minimumLegDuration else { return nil }
        let mode = longest.modes.max { $0.value < $1.value }?.key
        return Journey(start: longest.start, end: longest.end, mode: mode)
    }

    static func legs(of points: [TrackPoint], readings: [Reading]) -> [Leg] {
        guard points.count >= 2 else { return [Leg(points: points, mode: mode(forSpeeds: points.map(\.speed)))] }
        let sorted = readings.sorted { $0.start < $1.start }
        let said = chipModes(for: points, readings: sorted)
        let speeds = windowSpeeds(points)
        let labels = labels(for: points, said: said, speeds: speeds)
        var runs = runs(of: labels)
        runs = merged(runs, points: points)
        runs = checked(runs, said: said, speeds: speeds)
        return runs.enumerated().map { index, run in
            // Each leg ends where the next begins.
            let end = index + 1 < runs.count ? runs[index + 1].range.lowerBound : points.count - 1
            return Leg(points: Array(points[run.range.lowerBound...max(end, run.range.lowerBound)]), mode: run.mode)
        }
    }

    /// A way of travelling for every point: what the motion coprocessor said at that moment,
    /// overruled where the speed makes it impossible.
    static func labels(for points: [TrackPoint], said: [MovementMode?], speeds: [Double]) -> [MovementMode] {
        points.indices.map { index in
            let speed = speeds[index]
            if speed >= 60 { return .flying }
            switch said[index] {
            case .walking?:
                return speed > Tuning.notOnFoot ? .automotive : speed > Tuning.notWalking ? .cycling : .walking
            case .running?:
                return speed > Tuning.notOnFoot ? .automotive : speed > Tuning.notRunning ? .cycling : .running
            case .cycling?:
                return speed > Tuning.notOnBike ? .automotive : .cycling
            case let mode?:
                return mode
            case nil:
                return mode(forSpeed: speed)
            }
        }
    }

    /// What the motion chip said at each point's moment, if anything.
    static func chipModes(for points: [TrackPoint], readings: [Reading]) -> [MovementMode?] {
        var reading = 0
        return points.map { point in
            let time = point.timestamp
            while reading + 1 < readings.count, readings[reading + 1].start <= time { reading += 1 }
            return readings.indices.contains(reading) && readings[reading].start <= time ? readings[reading].mode : nil
        }
    }

    /// A second look at each leg as a whole. Point by point, a car crawling through town can
    /// pass for a bicycle; over the whole leg it gives itself away by its quick moments, or by
    /// sitting between two drives. Legs the motion chip vouched for as a ride are left alone.
    static func checked(_ runs: [Run], said: [MovementMode?], speeds: [Double]) -> [Run] {
        var runs = runs
        func vouched(_ run: Run) -> Bool { said[run.range].contains(.cycling) }
        func percentile(_ run: Run, _ p: Double) -> Double {
            let sorted = speeds[run.range].sorted()
            return sorted[min(sorted.count - 1, Int(Double(sorted.count) * p))]
        }
        for index in runs.indices where runs[index].mode == .cycling && !vouched(runs[index]) {
            let before = index > 0 ? runs[index - 1].mode : nil
            let after = index + 1 < runs.count ? runs[index + 1].mode : nil
            let betweenDrives = before == .automotive && after == .automotive
            let besideDrive = before == .automotive || after == .automotive
            if percentile(runs[index], 0.85) > Tuning.bikeBursts || betweenDrives
                || (besideDrive && percentile(runs[index], 0.5) > Tuning.trafficPace) {
                runs[index].mode = .automotive
            }
        }
        var joined: [Run] = []
        for run in runs {
            if let last = joined.last, last.mode == run.mode {
                joined[joined.count - 1].range = last.range.lowerBound...run.range.upperBound
            } else {
                joined.append(run)
            }
        }
        return joined
    }

    /// The median speed within the window around each point, from the GPS's own reading where
    /// it gave one and from the distance between fixes where it didn't.
    static func windowSpeeds(_ points: [TrackPoint]) -> [Double] {
        let own: [Double] = points.indices.map { index in
            if points[index].speed > 0 { return points[index].speed }
            guard index > 0 else { return 0 }
            let elapsed = points[index].timestamp.timeIntervalSince(points[index - 1].timestamp)
            return elapsed > 0 ? points[index].location.distance(from: points[index - 1].location) / elapsed : 0
        }
        var low = 0, high = 0
        return points.indices.map { index in
            let time = points[index].timestamp
            while points[low].timestamp < time.addingTimeInterval(-Tuning.window) { low += 1 }
            while high + 1 < points.count, points[high + 1].timestamp <= time.addingTimeInterval(Tuning.window) { high += 1 }
            let window = own[low...max(high, index)].sorted()
            return window[window.count / 2]
        }
    }

    struct Run {
        var range: ClosedRange<Int>
        var mode: MovementMode
    }

    static func runs(of labels: [MovementMode]) -> [Run] {
        var runs: [Run] = []
        for (index, label) in labels.enumerated() {
            if let last = runs.last, last.mode == label {
                runs[runs.count - 1].range = last.range.lowerBound...index
            } else {
                runs.append(Run(range: index...index, mode: label))
            }
        }
        return runs
    }

    /// Folds legs too short to be a real change into a neighbour, the shortest first, until
    /// every leg left is a real one.
    static func merged(_ runs: [Run], points: [TrackPoint]) -> [Run] {
        var runs = runs
        func duration(_ run: Run) -> TimeInterval {
            let end = min(run.range.upperBound + 1, points.count - 1)
            return points[end].timestamp.timeIntervalSince(points[run.range.lowerBound].timestamp)
        }
        func distance(_ run: Run) -> Double {
            let end = min(run.range.upperBound + 1, points.count - 1)
            return TrackPoint.distance(of: Array(points[run.range.lowerBound...end]))
        }
        while runs.count > 1 {
            let minor = runs.indices.filter { duration(runs[$0]) < Tuning.minimumLegDuration || distance(runs[$0]) < Tuning.minimumLegDistance }
            guard let shortest = minor.min(by: { duration(runs[$0]) < duration(runs[$1]) }) else { break }
            // Into the longer neighbour; the same way on both sides joins all three.
            let before = shortest > 0 ? shortest - 1 : nil
            let after = shortest + 1 < runs.count ? shortest + 1 : nil
            let target: Int
            switch (before, after) {
            case let (b?, a?): target = duration(runs[b]) >= duration(runs[a]) ? b : a
            case let (b?, nil): target = b
            case let (nil, a?): target = a
            default: return runs
            }
            let lower = min(runs[shortest].range.lowerBound, runs[target].range.lowerBound)
            let upper = max(runs[shortest].range.upperBound, runs[target].range.upperBound)
            runs[target].range = lower...upper
            runs.remove(at: shortest)
            // Neighbours that now travel the same way become one.
            var joined: [Run] = []
            for run in runs {
                if let last = joined.last, last.mode == run.mode {
                    joined[joined.count - 1].range = last.range.lowerBound...run.range.upperBound
                } else {
                    joined.append(run)
                }
            }
            runs = joined
        }
        return runs
    }

    static func mode(forSpeed speed: Double) -> MovementMode {
        switch speed {
        case 60...: return .flying
        case Tuning.notOnFoot..<60: return .automotive
        case 2.6..<Tuning.notOnFoot: return .cycling
        default: return .walking
        }
    }

    static func mode(forSpeeds speeds: [Double]) -> MovementMode {
        let moving = speeds.filter { $0 > 0.3 }.sorted()
        guard !moving.isEmpty else { return .walking }
        return mode(forSpeed: moving[moving.count / 2])
    }
}

/// The line of a flight: the great circle between two airports, which reads as an arc on
/// the map, the way an airline draws its routes.
enum FlightPath {
    static func points(from: CLLocationCoordinate2D, to: CLLocationCoordinate2D, start: Date, end: Date) -> [TrackPoint] {
        func vector(_ c: CLLocationCoordinate2D) -> (Double, Double, Double) {
            let lat = c.latitude * .pi / 180, lon = c.longitude * .pi / 180
            return (cos(lat) * cos(lon), cos(lat) * sin(lon), sin(lat))
        }
        let a = vector(from), b = vector(to)
        let angle = acos(max(-1, min(1, a.0 * b.0 + a.1 * b.1 + a.2 * b.2)))
        let distance = angle * 6_371_000
        let count = max(2, min(160, Int(distance / 40_000) + 2))
        let duration = max(end.timeIntervalSince(start), 1)
        let speed = distance / duration
        return (0..<count).map { index in
            let t = Double(index) / Double(count - 1)
            var x = a.0, y = a.1, z = a.2
            if angle > 1e-9 {
                let wa = sin((1 - t) * angle) / sin(angle), wb = sin(t * angle) / sin(angle)
                x = wa * a.0 + wb * b.0; y = wa * a.1 + wb * b.1; z = wa * a.2 + wb * b.2
            }
            let lat = atan2(z, sqrt(x * x + y * y)) * 180 / .pi
            let lon = atan2(y, x) * 180 / .pi
            return TrackPoint(latitude: lat, longitude: lon, altitude: 0, speed: speed, accuracy: 1000,
                              timestamp: start.addingTimeInterval(duration * t))
        }
    }
}

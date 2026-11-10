import Foundation
import SwiftData
import CoreLocation
import Observation

/// Every road ever recorded, simplified at three levels of detail so all of it can be on one
/// map at once. Built on a background context the first time it's needed and kept in Caches;
/// later only chunks newer than the cached ones are read, since a recorded chunk never changes.
@MainActor
@Observable
final class RouteAtlas {
    static let shared = RouteAtlas()

    private(set) var lines: [AtlasLine] = []
    private(set) var isLoaded = false
    /// Set while the first, full build runs, which can take a few seconds after years of tracking.
    private(set) var isBuilding = false

    @ObservationIgnored private var container: ModelContainer?
    @ObservationIgnored private var loading: Task<Void, Never>?

    private init() {}

    func attach(_ container: ModelContainer) {
        self.container = container
    }

    /// Brings the atlas up to date: cheap when nothing new was recorded.
    func load() async {
        if let loading { return await loading.value }
        guard let container else { return }
        let known = lines.isEmpty ? nil : lines
        if known == nil { isBuilding = !FileManager.default.fileExists(atPath: Self.url.path) }
        let task = Task {
            let result = await Task.detached(priority: .userInitiated) { Self.build(container: container, known: known) }.value
            if let result { lines = result }
            isLoaded = true
            isBuilding = false
        }
        loading = task
        await task.value
        loading = nil
    }

    /// The lines inside a stretch of map, for showing what came before under a day's own route.
    func lines(near box: AtlasBox, excluding interval: DateInterval?, limit: Int) -> [AtlasLine] {
        let found = lines.filter { line in
            box.intersects(line.box) && !(interval.map { line.start >= $0.start && line.start < $0.end } ?? false)
        }
        return Array(found.suffix(limit))
    }

    // MARK: Building

    nonisolated private static func build(container: ModelContainer, known: [AtlasLine]?) -> [AtlasLine]? {
        let context = ModelContext(container)
        let total = (try? context.fetchCount(FetchDescriptor<TrackChunk>())) ?? 0
        var lines = known ?? read() ?? []
        let latest = lines.last?.start ?? .distantPast
        // Older chunks than the newest known one arrive when another device syncs its history;
        // chunks deleted with a day leave fewer. Either way the cache no longer matches.
        var fresh = FetchDescriptor<TrackChunk>(predicate: #Predicate { $0.startDate > latest },
                                                sortBy: [SortDescriptor(\.startDate)])
        fresh.includePendingChanges = false
        guard let added = try? context.fetch(fresh) else { return nil }
        if lines.count + added.count != total {
            lines = []
            var all = FetchDescriptor<TrackChunk>(sortBy: [SortDescriptor(\.startDate)])
            all.includePendingChanges = false
            // In batches, so years of points aren't all decoded in memory at once.
            let batch = 400
            var offset = 0
            while offset < total {
                all.fetchOffset = offset
                all.fetchLimit = batch
                // A context per batch lets the decoded points of the last one go.
                let fetched: Int = autoreleasepool {
                    let batchContext = ModelContext(container)
                    guard let chunks = try? batchContext.fetch(all) else { return 0 }
                    lines += chunks.compactMap(AtlasLine.init)
                    return chunks.count
                }
                guard fetched > 0 else { break }
                offset += fetched
            }
        } else if !added.isEmpty {
            lines += added.compactMap(AtlasLine.init)
        } else if known != nil {
            return nil
        }
        write(lines)
        return lines
    }

    // MARK: Cache

    nonisolated private static var url: URL { URL.cachesDirectory.appending(path: "route-atlas.bin") }
    nonisolated private static let version: UInt32 = 1

    nonisolated private static func write(_ lines: [AtlasLine]) {
        var data = Data()
        data.appendRaw(version)
        data.appendRaw(UInt32(lines.count))
        for line in lines {
            data.appendRaw(UInt8(MovementMode.allCases.firstIndex(of: line.mode) ?? 0))
            data.appendRaw(line.start.timeIntervalSinceReferenceDate)
            data.appendRaw(Float32(line.distance))
            for level in line.levels {
                data.appendRaw(UInt32(level.count))
                for point in level { data.appendRaw(point.x); data.appendRaw(point.y) }
            }
        }
        try? data.write(to: url, options: .atomic)
    }

    nonisolated private static func read() -> [AtlasLine]? {
        guard let data = try? Data(contentsOf: url, options: .mappedIfSafe) else { return nil }
        var reader = AtlasReader(data: data)
        guard reader.read(UInt32.self) == version, let count = reader.read(UInt32.self) else { return nil }
        var lines: [AtlasLine] = []
        lines.reserveCapacity(Int(count))
        for _ in 0..<count {
            guard let modeIndex = reader.read(UInt8.self), let start = reader.read(Double.self),
                  let distance = reader.read(Float32.self) else { return nil }
            var levels: [[SIMD2<Float>]] = []
            for _ in 0..<3 {
                guard let n = reader.read(UInt32.self) else { return nil }
                var level: [SIMD2<Float>] = []
                level.reserveCapacity(Int(n))
                for _ in 0..<n {
                    guard let x = reader.read(Float.self), let y = reader.read(Float.self) else { return nil }
                    level.append(SIMD2(x, y))
                }
                levels.append(level)
            }
            let mode = MovementMode.allCases[min(Int(modeIndex), MovementMode.allCases.count - 1)]
            lines.append(AtlasLine(mode: mode, start: Date(timeIntervalSinceReferenceDate: start),
                                   distance: Double(distance), levels: levels))
        }
        return lines
    }
}

/// One recorded chunk, in map coordinates (latitude, longitude) at three levels of detail.
struct AtlasLine: Sendable {
    let mode: MovementMode
    let start: Date
    let distance: Double
    /// Street level, city level and country level.
    let levels: [[SIMD2<Float>]]
    let box: AtlasBox

    enum Detail: Int { case street, city, country }

    static let tolerances: [Double] = [8, 70, 900]

    init(mode: MovementMode, start: Date, distance: Double, levels: [[SIMD2<Float>]]) {
        self.mode = mode
        self.start = start
        self.distance = distance
        self.levels = levels
        box = AtlasBox(levels[0])
    }

    init?(_ chunk: TrackChunk) {
        let points = chunk.points
        guard points.count > 1 else { return nil }
        let levels = Self.tolerances.map { tolerance in
            points.simplified(tolerance: tolerance).map { point -> SIMD2<Float> in
                let c = point.coordinate.onMap
                return SIMD2(Float(c.latitude), Float(c.longitude))
            }
        }
        self.init(mode: chunk.mode, start: chunk.startDate, distance: chunk.distance, levels: levels)
    }

    /// A stretch not saved as a chunk yet: what's being recorded right now.
    init?(points: [TrackPoint], mode: MovementMode) {
        guard points.count > 1, let first = points.first else { return nil }
        let levels = Self.tolerances.map { tolerance in
            points.simplified(tolerance: tolerance).map { point -> SIMD2<Float> in
                let c = point.coordinate.onMap
                return SIMD2(Float(c.latitude), Float(c.longitude))
            }
        }
        self.init(mode: mode, start: first.timestamp, distance: TrackPoint.distance(of: points), levels: levels)
    }

    func coordinates(_ detail: Detail) -> [CLLocationCoordinate2D] {
        levels[detail.rawValue].map { CLLocationCoordinate2D(latitude: CLLocationDegrees($0.x), longitude: CLLocationDegrees($0.y)) }
    }
}

struct AtlasBox: Sendable {
    var minLat: Float, maxLat: Float, minLon: Float, maxLon: Float

    init(minLat: Float, maxLat: Float, minLon: Float, maxLon: Float) {
        (self.minLat, self.maxLat, self.minLon, self.maxLon) = (minLat, maxLat, minLon, maxLon)
    }

    init(_ points: [SIMD2<Float>]) {
        let lats = points.map(\.x), lons = points.map(\.y)
        self.init(minLat: lats.min() ?? 0, maxLat: lats.max() ?? 0, minLon: lons.min() ?? 0, maxLon: lons.max() ?? 0)
    }

    init(_ coordinates: [CLLocationCoordinate2D], padding: Double) {
        let lats = coordinates.map(\.latitude), lons = coordinates.map(\.longitude)
        self.init(minLat: Float((lats.min() ?? 0) - padding), maxLat: Float((lats.max() ?? 0) + padding),
                  minLon: Float((lons.min() ?? 0) - padding), maxLon: Float((lons.max() ?? 0) + padding))
    }

    func intersects(_ other: AtlasBox) -> Bool {
        minLat <= other.maxLat && other.minLat <= maxLat && minLon <= other.maxLon && other.minLon <= maxLon
    }

    /// How far across it is, in degrees.
    var span: Float { max(maxLat - minLat, maxLon - minLon) }
}

private struct AtlasReader {
    let data: Data
    var offset = 0

    mutating func read<T>(_: T.Type) -> T? {
        let size = MemoryLayout<T>.size
        guard offset + size <= data.count else { return nil }
        let value = data.withUnsafeBytes { $0.loadUnaligned(fromByteOffset: offset, as: T.self) }
        offset += size
        return value
    }
}

private extension Data {
    mutating func appendRaw<T>(_ value: T) {
        Swift.withUnsafeBytes(of: value) { append(contentsOf: $0) }
    }
}

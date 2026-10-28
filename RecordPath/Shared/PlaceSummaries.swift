import Foundation
import SwiftData
import CoreLocation
import Observation

/// Everything the Places and Stats tabs say about all places — countries, cities, sights,
/// frequent places, the light-up map, milestones and map dots — worked out once per change
/// and shared. After a photo import there are thousands of places and naming them saves
/// hundreds of times a minute; computing this in each view on every save made the whole app
/// stall. Saves now collapse into at most one refresh every couple of seconds.
@MainActor
@Observable
final class PlaceSummaries {
    static let shared = PlaceSummaries()

    /// Every stay, newest first.
    private(set) var stays: [Stay] = []
    private(set) var world = WorldInsights()
    private(set) var lightUp = LightUpInsights()
    /// Passport stamps, province seals and city stamps.
    private(set) var stamps = StampBook()
    private(set) var milestones = MilestoneProgress()
    /// One dot per ~500 m area, for the maps.
    private(set) var dots: [MapDot] = []
    /// Trips found in the history, newest first.
    private(set) var foundTrips: [TripFinder.Found] = []

    @ObservationIgnored private var context: ModelContext?
    @ObservationIgnored private var pending: Task<Void, Never>?
    @ObservationIgnored private var observer: NSObjectProtocol?

    private init() {}

    func attach(_ context: ModelContext) {
        self.context = context
        observer = NotificationCenter.default.addObserver(forName: ModelContext.didSave, object: nil, queue: .main) { [weak self] _ in
            MainActor.assumeIsolated { self?.setNeedsRefresh() }
        }
        refresh()
    }

    /// Asks for a refresh soon; asking again before it runs changes nothing.
    func setNeedsRefresh() {
        guard pending == nil else { return }
        pending = Task { [weak self] in
            try? await Task.sleep(for: .seconds(1.5))
            self?.pending = nil
            self?.refresh()
        }
    }

    @ObservationIgnored private var isRefreshing = false
    @ObservationIgnored private var needsAnother = false

    /// Works everything out on a background context, then swaps the results in. Places in
    /// the results are looked up again in the main context by id, which costs nothing until
    /// a view reads them.
    func refresh() {
        guard let context else { return }
        guard !isRefreshing else { needsAnother = true; return }
        isRefreshing = true
        let container = context.container
        Task {
            let started = Date()
            let result = await Task.detached(priority: .userInitiated) { Computed(container: container) }.value
            let mainStarted = Date()
            stays = result.ids.compactMap { context.model(for: $0) as? Stay }
            world = result.world.rehomed(in: context)
            lightUp = result.lightUp
            stamps = result.stamps
            milestones = result.milestones
            dots = result.dots
            foundTrips = result.foundTrips
            #if DEBUG
            Diagnostics.record("summaries background=\(Int(mainStarted.timeIntervalSince(started) * 1000))ms main=\(Int(Date().timeIntervalSince(mainStarted) * 1000))ms")
            #endif
            let ms = Int(Date().timeIntervalSince(started) * 1000)
            if ms > 1500 { Diagnostics.record("summaries stays=\(result.ids.count) took=\(ms)ms") }
            isRefreshing = false
            if needsAnother {
                needsAnother = false
                setNeedsRefresh()
            }
        }
    }

    func stay(_ id: PersistentIdentifier) -> Stay? { context?.model(for: id) as? Stay }

    /// Drops places about to be deleted, so no screen touches them before the next refresh.
    func forget(_ ids: Set<PersistentIdentifier>) {
        stays.removeAll { ids.contains($0.persistentModelID) }
        world.landmarks.removeAll { ids.contains($0.persistentModelID) }
        world.frequentPlaces.removeAll { ids.contains($0.representative.persistentModelID) }
        dots.removeAll { ids.contains($0.id) }
        setNeedsRefresh()
    }

    /// The background half: its own context, its own copies of the places.
    private struct Computed: @unchecked Sendable {
        var ids: [PersistentIdentifier] = []
        var world = WorldInsights()
        var lightUp = LightUpInsights()
        var stamps = StampBook()
        var milestones = MilestoneProgress()
        var dots: [MapDot] = []
        var foundTrips: [TripFinder.Found] = []

        init(container: ModelContainer) {
            let context = ModelContext(container)
            let all = (try? context.fetch(FetchDescriptor<Stay>(sortBy: [SortDescriptor(\.arrival, order: .reverse)]))) ?? []
            let chunks = (try? context.fetch(FetchDescriptor<TrackChunk>())) ?? []
            ids = all.map(\.persistentModelID)
            world = WorldInsights(stays: all)
            lightUp = LightUpInsights(stays: all)
            stamps = StampBook(stays: all)
            milestones = MilestoneProgress(stays: all, movements: chunks.filter { $0.mode != .flying }.map { ($0.startDate, $0.distance) })
            dots = MapDot.dots(for: all)
            let cityNames = CityNames.canonical(for: all)
            foundTrips = TripFinder.find(all.map {
                TripFinder.Visit(arrival: $0.arrival, departure: $0.departure ?? $0.arrival, latitude: $0.latitude,
                                 longitude: $0.longitude, city: CityNames.key($0).flatMap { cityNames[$0] } ?? $0.city,
                                 countryCode: $0.countryCode)
            })
        }
    }
}

/// A place on a map, reduced to what drawing it needs.
struct MapDot: Identifiable {
    let id: PersistentIdentifier
    let coordinate: CLLocationCoordinate2D
    let countryCode: String?
    let isLandmark: Bool
    /// How many visits the dot stands for, and when the latest was.
    var visits = 1
    var last: Date = .distantPast

    /// One dot per ~500 m area, a sight winning over an ordinary place.
    static func dots(for stays: [Stay]) -> [MapDot] {
        var byCell: [Int64: MapDot] = [:]
        for stay in stays {
            let key = cellKey(stay.latitude, stay.longitude, size: 0.005)
            var dot = MapDot(id: stay.persistentModelID, coordinate: stay.coordinate.onMap,
                             countryCode: stay.countryCode, isLandmark: stay.isLandmark)
            if let existing = byCell[key] {
                dot = existing.isLandmark || !stay.isLandmark ? existing : dot
                dot.visits = existing.visits + 1
                dot.last = max(existing.last, stay.arrival)
            } else {
                dot.last = stay.arrival
            }
            byCell[key] = dot
        }
        return Array(byCell.values)
    }

    /// The part of the world the person lives in lately: the busiest stretch of the past year's
    /// places and the busy ones near it. Places spread over several continents framed together
    /// leave a map of the ocean and the continents between them.
    static func focus(_ dots: [MapDot]) -> [MapDot] {
        guard let newest = dots.map(\.last).max() else { return [] }
        let recent = dots.filter { $0.last > newest.addingTimeInterval(-365 * 86_400) }
        let pool = recent.reduce(0) { $0 + $1.visits } >= 20 ? recent : dots
        let size = 20.0
        var weight: [Int64: Int] = [:]
        for dot in pool { weight[cellKey(dot.coordinate.latitude, dot.coordinate.longitude, size: size), default: 0] += dot.visits }
        guard let busiest = weight.max(by: { $0.value < $1.value }) else { return dots }
        let centre = pool.first { cellKey($0.coordinate.latitude, $0.coordinate.longitude, size: size) == busiest.key }!.coordinate
        return pool.filter { dot in
            let key = cellKey(dot.coordinate.latitude, dot.coordinate.longitude, size: size)
            let near = abs(dot.coordinate.latitude - centre.latitude) <= 45
                && abs((dot.coordinate.longitude - centre.longitude).remainder(dividingBy: 360)) <= 45
            return key == busiest.key || (near && weight[key, default: 0] * 10 >= busiest.value)
        }
    }

    /// At most `limit` dots spread over the map: the grid coarsens until they fit.
    static func thinned(_ dots: [MapDot], cell: Double, limit: Int) -> [MapDot] {
        var size = cell
        while true {
            var byCell: [Int64: MapDot] = [:]
            for dot in dots {
                let key = cellKey(dot.coordinate.latitude, dot.coordinate.longitude, size: size)
                if let existing = byCell[key], existing.isLandmark || !dot.isLandmark { continue }
                byCell[key] = dot
            }
            if byCell.count <= limit || size > 20 { return Array(byCell.values) }
            size *= 2
        }
    }

    private static func cellKey(_ lat: Double, _ lon: Double, size: Double) -> Int64 {
        Int64((lat / size).rounded(.down)) &* 1_000_003 &+ Int64((lon / size).rounded(.down))
    }
}

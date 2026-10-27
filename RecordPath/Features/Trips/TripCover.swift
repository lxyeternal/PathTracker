import SwiftUI
import Photos
import SwiftData
import MapKit

/// A trip's picture: its first photo, else its route drawn on a quiet map.
struct TripCover: View {
    let trip: Trip
    @Environment(\.modelContext) private var context
    @Environment(\.colorScheme) private var colorScheme
    @State private var route: UIImage?
    @State private var noRoute = false
    @State private var tripStays: [Stay] = []

    var body: some View {
        GeometryReader { proxy in
            ZStack {
                LinearGradient(colors: [Color.blue.opacity(0.10), Color.teal.opacity(0.18)], startPoint: .topLeading, endPoint: .bottomTrailing)
                if let photo = (trip.photos ?? []).min(by: { $0.takenAt < $1.takenAt }) {
                    PhotoThumbnail(photo: photo, square: false)
                } else if let route {
                    Image(uiImage: route).resizable().scaledToFill().transition(.opacity)
                } else if noRoute {
                    // Nothing posted and no track (a trip from photos): its photos, else its cities.
                    TimeCover(interval: trip.interval, stays: tripStays, key: "trip-\(trip.id)")
                }
            }
            .frame(width: proxy.size.width, height: proxy.size.height)
            .task(id: "\(trip.id)-\(trip.endDate?.timeIntervalSince1970 ?? 0)-\(colorScheme)-\(Int(proxy.size.width))") {
                guard (trip.photos ?? []).isEmpty else { return }
                let image = await routeImage(size: proxy.size)
                withAnimation(.easeOut(duration: 0.25)) { route = image }
                if image == nil {
                    let start = trip.startDate, end = trip.endDate ?? Date()
                    tripStays = (try? context.fetch(FetchDescriptor<Stay>(predicate: #Predicate { $0.arrival >= start && $0.arrival < end }))) ?? []
                    noRoute = true
                }
            }
        }
        .clipped()
    }

    private func routeImage(size: CGSize) async -> UIImage? {
        let start = trip.startDate, end = trip.endDate ?? Date()
        let id: UUID? = trip.id
        let chunks = trip.isRecording
            ? (try? context.fetch(FetchDescriptor<TrackChunk>(predicate: #Predicate { $0.tripID == id }))) ?? []
            : (try? context.fetch(FetchDescriptor<TrackChunk>(predicate: #Predicate { $0.endDate >= start && $0.startDate <= end }))) ?? []
        let lines = chunks.filter { $0.mode != .flying }.sorted { $0.startDate < $1.startDate }
            .map { RouteImage.Line(coordinates: $0.points.simplified(tolerance: 20).map(\.coordinate), color: $0.mode.color) }
        return await RouteImage.render(lines, size: size, dark: colorScheme == .dark,
                                       key: "trip-\(trip.id)-\(trip.endDate?.timeIntervalSince1970 ?? 0)")
    }
}

/// The picture for a stretch of time when nothing was posted: the photos taken then, side by
/// side, else a night map with each city it touched glowing.
struct TimeCover: View {
    let interval: DateInterval
    let stays: [Stay]
    let key: String
    @State private var assets: [PHAsset] = []
    @State private var map: UIImage?
    @State private var loaded = false

    private static var maps: [String: UIImage] = [:]

    var body: some View {
        GeometryReader { proxy in
            ZStack {
                Color(red: 0.07, green: 0.08, blue: 0.16)
                if assets.count >= 3 {
                    HStack(spacing: 2) {
                        AssetThumbnail(asset: assets[0], side: proxy.size.height)
                            .frame(width: proxy.size.width * 0.5, height: proxy.size.height).clipped()
                        VStack(spacing: 2) {
                            AssetThumbnail(asset: assets[1], side: proxy.size.width * 0.5)
                                .frame(height: (proxy.size.height - 2) / 2).clipped()
                            AssetThumbnail(asset: assets[2], side: proxy.size.width * 0.5)
                                .frame(height: (proxy.size.height - 2) / 2).clipped()
                        }
                    }
                } else if let first = assets.first {
                    AssetThumbnail(asset: first, side: max(proxy.size.width, proxy.size.height))
                        .frame(width: proxy.size.width, height: proxy.size.height).clipped()
                } else if let map {
                    Image(uiImage: map).resizable().scaledToFill().transition(.opacity)
                }
            }
            .frame(width: proxy.size.width, height: proxy.size.height)
            .task(id: key) {
                guard !loaded else { return }
                loaded = true
                let interval = interval
                let found = DayPhotos.canRead
                    ? await Task.detached(priority: .userInitiated) { DayPhotos.assets(in: interval) }.value : []
                if !found.isEmpty {
                    // Favourites first, then spread over the trip.
                    let favourites = found.filter(\.isFavorite)
                    let pool = favourites.count >= 3 ? favourites : found
                    let step = max(1, pool.count / 3)
                    assets = stride(from: 0, to: pool.count, by: step).prefix(3).map { pool[$0] }
                    return
                }
                if let cached = Self.maps[key] { map = cached; return }
                let image = await YearCover.render(cities: CityGlow.glows(for: stays), routes: [], size: proxy.size)
                if let image { Self.maps[key] = image }
                withAnimation(.easeOut(duration: 0.3)) { map = image }
            }
        }
        .clipped()
    }
}

import SwiftUI
import SwiftData
import Photos
import MapKit

/// A trip in the list: a soft map of where it went with each city tagged, a calendar badge
/// that says when, a small pile of the photos taken, and how long and how far at a glance.
struct TripCard: View {
    let trip: Trip
    @Environment(\.modelContext) private var context
    @Environment(\.colorScheme) private var colorScheme
    @State private var cities: [CityGlow] = []
    @State private var map: MapBackdrop?
    @State private var photos: [PHAsset] = []
    @State private var photoCount = 0

    private static var maps: [String: MapBackdrop] = [:]
    private let height: CGFloat = 200

    var body: some View {
        VStack(spacing: 0) {
            GeometryReader { geo in
                ZStack(alignment: .topLeading) {
                    mapLayer(size: geo.size)
                    cityTags(size: geo.size)
                    DateBadge(interval: trip.interval).padding(12)
                    if !photos.isEmpty {
                        MiniPile(assets: photos)
                            .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .bottomTrailing)
                            .padding(14)
                    }
                }
            }
            .frame(height: height)
            .clipped()

            VStack(alignment: .leading, spacing: 6) {
                HStack(spacing: 8) {
                    Text(trip.coverEmoji).font(.title3)
                    Text(trip.title).font(.title3.bold()).lineLimit(1)
                }
                HStack(spacing: 6) {
                    Fact(symbol: "calendar", text: String(localized: "\(days) 天", bundle: .appLanguage))
                    if !cities.isEmpty {
                        Fact(symbol: "building.2", text: String(localized: "\(cities.count) 座城市", bundle: .appLanguage))
                    }
                    if photoCount > 0 {
                        Fact(symbol: "photo", text: String(localized: "\(photoCount) 张照片", bundle: .appLanguage))
                    }
                }
                if !cities.isEmpty {
                    Text(cities.prefix(5).map(\.name).joined(separator: " · "))
                        .font(.footnote).foregroundStyle(.secondary).lineLimit(1)
                }
            }
            .padding(.horizontal, 16).padding(.vertical, 12)
            .frame(maxWidth: .infinity, alignment: .leading)
        }
        .background(.background.secondary)
        .clipShape(.rect(cornerRadius: 24, style: .continuous))
        .contentShape(.rect(cornerRadius: 24, style: .continuous))
        .foregroundStyle(.primary)
        .task(id: "\(trip.id)-\(trip.startDate.timeIntervalSince1970)-\(trip.endDate?.timeIntervalSince1970 ?? 0)") { await load() }
    }

    private var days: Int {
        let calendar = Calendar.current
        let last = max(trip.interval.start, trip.interval.end.addingTimeInterval(-1))
        return (calendar.dateComponents([.day], from: calendar.startOfDay(for: trip.interval.start),
                                        to: calendar.startOfDay(for: last)).day ?? 0) + 1
    }

    @ViewBuilder
    private func mapLayer(size: CGSize) -> some View {
        if let map {
            Image(uiImage: map.image).resizable().scaledToFill()
                .frame(width: size.width, height: size.height)
                .transition(.opacity)
        } else {
            LinearGradient(colors: [Color.blue.opacity(0.10), Color.teal.opacity(0.16)], startPoint: .topLeading, endPoint: .bottomTrailing)
        }
    }

    /// A pin and a name for each city, the busiest first; a few at most so they stay readable.
    @ViewBuilder
    private func cityTags(size: CGSize) -> some View {
        if let map {
            ForEach(Array(placedTags(map: map, size: size).enumerated()), id: \.offset) { index, item in
                CityTag(name: item.name, prominent: index == 0)
                    .position(x: item.point.x, y: item.point.y - 14)
                    .transition(.scale(scale: 0.6, anchor: .bottom).combined(with: .opacity))
            }
        }
    }

    /// Busiest city first; a tag that would sit on another, or under the date badge, is left off.
    private func placedTags(map: MapBackdrop, size: CGSize) -> [(name: String, point: CGPoint)] {
        var placed: [(name: String, point: CGPoint)] = []
        for (city, unit) in zip(cities, map.pins) {
            let pin = CGPoint(x: unit.x * size.width, y: unit.y * size.height)
            guard pin.x > 4, pin.x < size.width - 4, pin.y > 30, pin.y < size.height - 6 else { continue }
            // The tag slides inward rather than running off the card; the dot moves with it.
            let half = CGFloat(city.name.count) * (city.name.unicodeScalars.first.map { $0.value > 0x2E80 } == true ? 7.5 : 4.2) + 14
            let point = CGPoint(x: min(max(pin.x, half + 6), size.width - half - 6), y: pin.y)
            let underBadge = point.x < 100 && point.y < 120
            let crowded = placed.contains { abs($0.point.x - point.x) < 70 && abs($0.point.y - point.y) < 34 }
            if !underBadge && !crowded { placed.append((city.name, point)) }
        }
        return placed
    }

    private func load() async {
        let start = trip.startDate, end = trip.endDate ?? Date()
        let stays = (try? context.fetch(FetchDescriptor<Stay>(predicate: #Predicate { $0.arrival >= start && $0.arrival < end }))) ?? []
        cities = CityGlow.glows(for: stays)
        photoCount = (trip.photos ?? []).count

        let key = "\(trip.id)-\(start.timeIntervalSince1970)-\(end.timeIntervalSince1970)-\(colorScheme == .dark)"
        if let cached = Self.maps[key] {
            map = cached
        } else {
            let pins = Array(cities.prefix(4).map(\.center))
            let size = CGSize(width: UIScreen.main.bounds.width - 32, height: height)
            if let region = Self.region(around: pins),
               let rendered = await MapBackdrop.render(region: region, size: size, pins: pins, dark: colorScheme == .dark) {
                Self.maps[key] = rendered
                withAnimation(.easeOut(duration: 0.35)) { map = rendered }
            }
        }

        guard DayPhotos.canRead else { return }
        let interval = trip.interval
        let found = await Task.detached(priority: .utility) { DayPhotos.assets(in: interval) }.value
        let favourites = found.filter(\.isFavorite)
        let pool = favourites.count >= 3 ? favourites : found
        let step = max(1, pool.count / 3)
        withAnimation(.spring(response: 0.5, dampingFraction: 0.8)) {
            photos = stride(from: 0, to: pool.count, by: step).prefix(3).map { pool[$0] }
            photoCount = max(photoCount, found.count)
        }
    }

    /// The cities with room around them; the right side is kept clear for the photos.
    private static func region(around coordinates: [CLLocationCoordinate2D]) -> MKCoordinateRegion? {
        let lats = coordinates.map(\.latitude)
        guard let minLat = lats.min(), let maxLat = lats.max() else { return nil }
        // Longitudes wrap: San Francisco and Shanghai are closest across the Pacific.
        let lons = coordinates.map(\.longitude).sorted()
        var widest = lons[0] + 360 - lons[lons.count - 1], west = lons[0]
        for (a, b) in zip(lons, lons.dropFirst()) where b - a > widest {
            widest = b - a
            west = b
        }
        let covered = 360 - widest
        let lonSpan = max(covered * (covered > 60 ? 1.6 : 2.0), 0.35)
        let latSpan = max((maxLat - minLat) * 2.4, lonSpan * 0.45)
        // Shifted right and down so the date badge in the top left covers nothing.
        var centerLon = west + covered / 2 - lonSpan * 0.1
        if centerLon > 180 { centerLon -= 360 }
        return MKCoordinateRegion(center: CLLocationCoordinate2D(latitude: (minLat + maxLat) / 2 + latSpan * 0.06,
                                                                 longitude: centerLon),
                                  span: MKCoordinateSpan(latitudeDelta: min(latSpan, 120), longitudeDelta: min(lonSpan, 300)))
    }
}

/// When, like a page torn from a calendar: the month on a coloured strip, the days large, the year small.
private struct DateBadge: View {
    let interval: DateInterval

    var body: some View {
        let calendar = Calendar.current
        let last = max(interval.start, interval.end.addingTimeInterval(-1))
        let sameMonth = calendar.isDate(interval.start, equalTo: last, toGranularity: .month)
        let startDay = calendar.component(.day, from: interval.start), endDay = calendar.component(.day, from: last)
        VStack(spacing: 0) {
            Text(interval.start.formatted(.dateTime.month(.abbreviated).locale(appLocale)) +
                 (sameMonth ? "" : "–" + last.formatted(.dateTime.month(.abbreviated).locale(appLocale))))
                .font(.caption2.weight(.heavy))
                .textCase(.uppercase)
                .foregroundStyle(.white)
                .frame(maxWidth: .infinity)
                .padding(.vertical, 3)
                .background(Color.red)
            Text(verbatim: startDay == endDay && sameMonth ? "\(startDay)" : "\(startDay)–\(endDay)")
                .font(.system(size: 22, weight: .bold, design: .rounded))
                .foregroundStyle(.black)
                .minimumScaleFactor(0.6)
                .lineLimit(1)
                .padding(.horizontal, 8)
                .padding(.top, 2)
            Text(verbatim: String(calendar.component(.year, from: interval.start)))
                .font(.caption2.weight(.semibold))
                .foregroundStyle(.black.opacity(0.55))
                .padding(.bottom, 4)
        }
        .frame(minWidth: 64)
        .fixedSize()
        .background(.white)
        .clipShape(.rect(cornerRadius: 12, style: .continuous))
        .shadow(color: .black.opacity(0.18), radius: 6, y: 3)
    }
}

private struct CityTag: View {
    let name: String
    let prominent: Bool

    var body: some View {
        VStack(spacing: 2) {
            Text(name)
                .font(prominent ? .footnote.weight(.bold) : .caption.weight(.semibold))
                .lineLimit(1)
                .padding(.horizontal, 9).padding(.vertical, 4)
                .background(.regularMaterial, in: .capsule)
                .shadow(color: .black.opacity(0.12), radius: 3, y: 1)
            Circle()
                .fill(prominent ? Color.orange : Color.accentColor)
                .frame(width: 10, height: 10)
                .overlay(Circle().stroke(.white, lineWidth: 2))
        }
        .fixedSize()
    }
}

/// Three photos fanned in a corner of the card.
private struct MiniPile: View {
    let assets: [PHAsset]

    var body: some View {
        ZStack {
            ForEach(Array(assets.prefix(3).enumerated()).reversed(), id: \.element.localIdentifier) { index, asset in
                AssetThumbnail(asset: asset, side: 70)
                    .frame(width: 62, height: 78)
                    .clipShape(.rect(cornerRadius: 8, style: .continuous))
                    .overlay(RoundedRectangle(cornerRadius: 8, style: .continuous).stroke(.white, lineWidth: 2.5))
                    .shadow(color: .black.opacity(0.25), radius: 4, y: 2)
                    .rotationEffect(.degrees([-8.0, 6, -2][index]))
                    .offset(x: CGFloat(index) * -22, y: CGFloat(index) * 2)
            }
        }
        .padding(.leading, 44)
    }
}

private struct Fact: View {
    let symbol: String
    let text: String

    var body: some View {
        Label(text, systemImage: symbol)
            .font(.caption.weight(.semibold))
            .padding(.horizontal, 8).padding(.vertical, 4)
            .background(.quaternary.opacity(0.6), in: .capsule)
    }
}

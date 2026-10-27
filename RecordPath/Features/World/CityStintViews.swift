import SwiftUI
import Photos
import CoreLocation

/// Photos taken during a span of time near a place, from the library on this device.
enum PlacePhotos {
    /// Remembers which photo stands for each place, so lists don't search the library twice.
    @MainActor private static var covers: [String: String?] = [:]

    static func assets(in interval: DateInterval, near location: CLLocation, within meters: CLLocationDistance) -> [PHAsset] {
        DayPhotos.assets(in: interval).filter { asset in
            // Photos without a location were probably taken there too.
            guard let place = asset.location else { return true }
            return place.distance(from: location) <= meters
        }
    }

    @MainActor
    static func cover(for key: String, interval: DateInterval, near location: CLLocation, within meters: CLLocationDistance) -> PHAsset? {
        if let known = covers[key] {
            return known.flatMap { PHAsset.fetchAssets(withLocalIdentifiers: [$0], options: nil).firstObject }
        }
        let found = assets(in: interval, near: location, within: meters)
        // The middle of the visit tends to be the picture of it, not the arrival.
        let asset = found.isEmpty ? nil : found[found.count / 2]
        covers[key] = .some(asset?.localIdentifier)
        return asset
    }
}

/// A place's picture in a list: a photo taken there when there is one, so places are told
/// apart at a glance; otherwise its icon.
struct PlaceThumb: View {
    let stay: Stay
    var size: CGFloat = 36
    @State private var asset: PHAsset?

    var body: some View {
        Group {
            if let asset {
                AssetThumbnail(asset: asset, side: size)
                    .clipShape(.circle)
                    .overlay(alignment: .bottomTrailing) {
                        if stay.isLandmark {
                            Image(systemName: "star.fill")
                                .font(.system(size: size * 0.24, weight: .bold))
                                .foregroundStyle(.white)
                                .padding(size * 0.06)
                                .background(Circle().fill(.yellow))
                                .offset(x: 2, y: 2)
                        }
                    }
            } else if stay.category == .other && !stay.isLandmark {
                Monogram(text: stay.displayName, colorKey: stay.city ?? stay.displayName, size: size, cornerRadius: size / 2)
            } else {
                PlaceIcon(category: stay.category, isLandmark: stay.isLandmark, size: size)
            }
        }
        .frame(width: size, height: size)
        .task(id: stay.id) {
            guard DayPhotos.canRead else { return }
            // Photo visits only cover first to last shot; widen a little.
            let interval = DateInterval(start: stay.arrival.addingTimeInterval(-600),
                                        end: max(stay.departure ?? Date(), stay.arrival).addingTimeInterval(600))
            asset = PlacePhotos.cover(for: stay.id.uuidString, interval: interval, near: stay.location, within: 1_500)
        }
    }
}

/// One stint in a list: its picture, the city, the dates and how much happened.
struct CityStintRow: View {
    let stint: CityStint
    @State private var cover: PHAsset?

    var body: some View {
        HStack(spacing: 14) {
            Group {
                if let cover {
                    AssetThumbnail(asset: cover, side: 56)
                } else {
                    Monogram(text: stint.city, colorKey: stint.city, size: 56, cornerRadius: 56 * 0.18)
                }
            }
            .frame(width: 56, height: 56)
            VStack(alignment: .leading, spacing: 3) {
                Text(stint.city).font(.body.weight(.semibold)).lineLimit(1)
                Text(Self.dates(stint)).font(.subheadline).foregroundStyle(.secondary).lineLimit(1)
                Text(Self.counts(stint)).font(.caption).foregroundStyle(.tertiary).lineLimit(1)
            }
            Spacer(minLength: 0)
            Image(systemName: "chevron.right").font(.caption.weight(.semibold)).foregroundStyle(.tertiary)
        }
        .padding(.horizontal, 14)
        .padding(.vertical, 8)
        .contentShape(.rect)
        .task(id: stint.id) {
            guard DayPhotos.canRead else { return }
            cover = PlacePhotos.cover(for: stint.id, interval: stint.interval, near: stint.center, within: 30_000)
        }
    }

    static func dates(_ stint: CityStint) -> String {
        let calendar = Calendar.current
        if calendar.isDate(stint.start, inSameDayAs: stint.end) {
            return stint.start.formatted(.dateTime.year().month().day().weekday(.abbreviated).locale(appLocale))
        }
        return (stint.start..<stint.end).formatted(Date.IntervalFormatStyle(date: .abbreviated, time: .omitted, locale: appLocale))
    }

    static func counts(_ stint: CityStint) -> String {
        var parts = [String(localized: "\(stint.days) 天", bundle: .appLanguage),
                     String(localized: "\(stint.stays.count) 处", bundle: .appLanguage)]
        if stint.photoCount > 0 { parts.append(String(localized: "\(stint.photoCount) 张照片", bundle: .appLanguage)) }
        return parts.joined(separator: " · ")
    }
}

/// A stint opened: where it was, its photos, and the places day by day.
struct CityStintView: View {
    let stint: CityStint
    @State private var photos: [PHAsset] = []
    @State private var viewing: PHAsset?
    @State private var showingGallery = false
    @State private var selected: Stay?

    private var byDay: [(day: Date, stays: [Stay])] {
        let calendar = Calendar.current
        return Dictionary(grouping: stint.stays) { calendar.startOfDay(for: $0.arrival) }
            .map { ($0.key, $0.value.sorted { $0.arrival < $1.arrival }) }
            .sorted { $0.day < $1.day }
    }

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 16) {
                WorldMap(dots: MapDot.dots(for: stint.stays), interactive: true, onSelect: { selected = $0 })
                    .frame(height: 220)
                    .clipShape(.rect(cornerRadius: 28, style: .continuous))

                VStack(alignment: .leading, spacing: 4) {
                    Text(CityStintRow.dates(stint)).font(.headline)
                    Text(CityStintRow.counts(stint)).font(.subheadline).foregroundStyle(.secondary)
                }

                if !photos.isEmpty {
                    // A collage, folded: the days below stay in reach. Tap for all of them.
                    Button { showingGallery = true } label: { PhotoCollage(assets: photos) }
                        .buttonStyle(PressableStyle())
                } else if !DayPhotos.canRead {
                    Label("允许访问照片后，这里会显示你在这段时间拍的照片。", systemImage: "photo.on.rectangle.angled")
                        .font(.footnote).foregroundStyle(.secondary)
                }

                ForEach(byDay, id: \.day) { day in
                    NavigationLink(value: DayRoute(day: day.day)) {
                        HStack(alignment: .firstTextBaseline) {
                            Text(day.day.formatted(.dateTime.month().day().weekday(.wide).locale(appLocale)))
                                .font(.title3.bold()).foregroundStyle(.primary)
                            Spacer()
                            Label("当天轨迹", systemImage: "chevron.right")
                                .labelStyle(TrailingIconLabelStyle())
                                .font(.subheadline.weight(.semibold))
                        }
                        .padding(.top, 8)
                    }
                    .buttonStyle(.plain)
                    LazyVStack(spacing: 0) {
                        ForEach(day.stays) { stay in
                            Button { selected = stay } label: { PlaceRow(stay: stay, timeOnly: true) }.buttonStyle(.plain)
                        }
                    }
                    .padding(.vertical, 6)
                    .background(.background.secondary, in: .rect(cornerRadius: 24, style: .continuous))
                }
            }
            .padding(.horizontal)
            .padding(.bottom, 24)
        }
        .navigationTitle("\(stint.countryCode.map { String.flag(for: $0) } ?? "") \(stint.city)")
        .navigationBarTitleDisplayMode(.inline)
        .sheet(item: $selected) { StayDetailView(stay: $0) }
        .sheet(isPresented: $showingGallery) {
            PhotoGallerySheet(title: stint.city, subtitle: CityStintRow.dates(stint), assets: photos)
        }
        .fullScreenCover(item: Binding(get: { viewing.map { AssetPagerStart(id: $0.localIdentifier) } }, set: { viewing = $0 == nil ? nil : viewing })) {
            AssetPager(assets: photos, selection: $0.id)
        }
        .task {
            guard DayPhotos.canRead else { return }
            photos = PlacePhotos.assets(in: stint.interval, near: stint.center, within: 30_000)
        }
    }
}

/// A tile with the first character of a name on a colour of its own: places without a
/// photo or a category still look different from each other, and one city keeps one colour.
struct Monogram: View {
    let text: String
    let colorKey: String
    let size: CGFloat
    let cornerRadius: CGFloat

    var body: some View {
        let hue = Self.hue(colorKey)
        RoundedRectangle(cornerRadius: cornerRadius, style: .continuous)
            .fill(LinearGradient(colors: [Color(hue: hue, saturation: 0.55, brightness: 0.95),
                                          Color(hue: (hue + 0.06).truncatingRemainder(dividingBy: 1), saturation: 0.75, brightness: 0.78)],
                                 startPoint: .topLeading, endPoint: .bottomTrailing))
            .overlay {
                Text(String(text.trimmingCharacters(in: .whitespaces).prefix(1)).uppercased())
                    .font(.system(size: size * 0.44, weight: .bold, design: .rounded))
                    .foregroundStyle(.white)
                    .shadow(color: .black.opacity(0.15), radius: 1, y: 1)
            }
            .frame(width: size, height: size)
            .accessibilityHidden(true)
    }

    /// The same name always gets the same colour, whatever the run.
    static func hue(_ key: String) -> Double {
        var hash: UInt64 = 5381
        for byte in key.utf8 { hash = (hash &* 33) &+ UInt64(byte) }
        return Double(hash % 360) / 360
    }
}

/// A day opened from Places: its map, numbers and timeline, the same as on the Today tab.
struct DayRoute: Hashable {
    let day: Date
}

struct DayPage: View {
    let day: Date

    var body: some View {
        DayContentView(day: day)
            .navigationTitle(Format.dayTitle(day))
            .navigationSubtitle(Format.daySubtitle(day))
            .navigationBarTitleDisplayMode(.inline)
    }
}

private struct TrailingIconLabelStyle: LabelStyle {
    func makeBody(configuration: Configuration) -> some View {
        HStack(spacing: 3) {
            configuration.title
            configuration.icon.font(.caption.weight(.bold))
        }
        .foregroundStyle(.tint)
    }
}

/// Five photos as one picture: a large one and four small, the last saying how many more.
struct PhotoCollage: View {
    let assets: [PHAsset]

    var body: some View {
        let shown = Array(assets.prefix(5))
        GeometryReader { geo in
            let gap: CGFloat = 4
            let big = shown.count >= 3 ? (geo.size.width - gap) * 0.58 : geo.size.width
            let small = (geo.size.height - gap) / 2
            let rest = geo.size.width - big - gap
            HStack(spacing: gap) {
                if let first = shown.first {
                    AssetThumbnail(asset: first, side: max(big, geo.size.height))
                        .frame(width: big, height: geo.size.height)
                        .clipped()
                }
                if shown.count >= 3 {
                    let tiles = Array(shown.dropFirst())
                    let columns = tiles.count >= 4 ? 2 : 1
                    let width = (rest - gap * CGFloat(columns - 1)) / CGFloat(columns)
                    LazyVGrid(columns: Array(repeating: GridItem(.fixed(width), spacing: gap), count: columns), spacing: gap) {
                        ForEach(Array(tiles.prefix(columns * 2).enumerated()), id: \.element.localIdentifier) { index, asset in
                            AssetThumbnail(asset: asset, side: max(width, small))
                                .frame(width: width, height: small)
                                .clipped()
                                .overlay {
                                    if index == min(tiles.count, columns * 2) - 1, assets.count > 5 {
                                        ZStack {
                                            Color.black.opacity(0.45)
                                            Text("+\(assets.count - 5)").font(.title2.bold()).foregroundStyle(.white)
                                        }
                                    }
                                }
                        }
                    }
                    .frame(width: rest)
                }
            }
        }
        .frame(height: 220)
        .clipShape(.rect(cornerRadius: 22, style: .continuous))
        .overlay(alignment: .bottomLeading) {
            Label("\(assets.count) 张照片", systemImage: "photo.on.rectangle.angled")
                .font(.footnote.weight(.semibold))
                .padding(.horizontal, 12).padding(.vertical, 7)
                .glassEffect(.regular, in: .capsule)
                .padding(10)
        }
    }
}

/// All the photos of a stretch of time, a grid that opens each one full screen.
struct PhotoGallerySheet: View {
    let title: String
    let subtitle: String
    let assets: [PHAsset]
    @Environment(\.dismiss) private var dismiss
    @State private var viewing: AssetPagerStart?

    private var byDay: [(day: Date, assets: [PHAsset])] {
        Dictionary(grouping: assets) { Calendar.current.startOfDay(for: $0.creationDate ?? .distantPast) }
            .map { ($0.key, $0.value) }
            .sorted { $0.day < $1.day }
    }

    var body: some View {
        NavigationStack {
            ScrollView {
                LazyVStack(alignment: .leading, spacing: 4, pinnedViews: .sectionHeaders) {
                    ForEach(byDay, id: \.day) { day in
                        Section {
                            LazyVGrid(columns: Array(repeating: GridItem(.flexible(), spacing: 3), count: 3), spacing: 3) {
                                ForEach(day.assets, id: \.localIdentifier) { asset in
                                    Button { viewing = AssetPagerStart(id: asset.localIdentifier) } label: {
                                        GeometryReader { geo in AssetThumbnail(asset: asset, side: geo.size.width) }
                                            .aspectRatio(1, contentMode: .fit)
                                    }
                                    .buttonStyle(.plain)
                                }
                            }
                        } header: {
                            HStack {
                                Text(day.day.formatted(.dateTime.month().day().weekday(.wide).locale(appLocale)))
                                    .font(.headline)
                                Spacer()
                                Text("\(day.assets.count)").font(.subheadline).foregroundStyle(.secondary)
                            }
                            .padding(.horizontal, 16).padding(.vertical, 10)
                            .background(.bar)
                        }
                    }
                }
            }
            .navigationTitle(title)
            .navigationSubtitle(subtitle)
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("关闭", systemImage: "xmark") { dismiss() }
                }
            }
            .fullScreenCover(item: $viewing) { AssetPager(assets: assets, selection: $0.id) }
        }
    }
}

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
                    PhotoStack(assets: photos) { showingGallery = true }
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

/// A trip's photos as a pile on the table: a few overlapping, turned a little, with the count.
/// Tap it and they spread out into two rows you can scroll; "All" opens every one by day.
struct PhotoStack: View {
    let assets: [PHAsset]
    let openAll: () -> Void
    @State private var expanded = false
    @State private var viewing: AssetPagerStart?
    @Namespace private var space

    private let card = CGSize(width: 116, height: 146)

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            HStack(alignment: .firstTextBaseline) {
                Text("照片").font(.title3.bold())
                Text("\(assets.count)").font(.subheadline).foregroundStyle(.secondary)
                Spacer()
                if expanded {
                    Button("全部", action: openAll).font(.subheadline.weight(.semibold))
                    Button("收起") { withAnimation(.spring(response: 0.5, dampingFraction: 0.82)) { expanded = false } }
                        .font(.subheadline.weight(.semibold))
                        .padding(.leading, 10)
                }
            }
            if expanded { spread } else { pile }
        }
        .fullScreenCover(item: $viewing) { AssetPager(assets: assets, selection: $0.id) }
        .sensoryFeedback(.impact(weight: .light), trigger: expanded)
    }

    /// Up to six, fanned from the left; the rest are counted.
    private var pile: some View {
        let shown = Array(assets.prefix(6))
        let step: CGFloat = shown.count > 1 ? min(44, (UIScreen.main.bounds.width - 40 - card.width - 90) / CGFloat(shown.count - 1)) : 0
        return Button {
            withAnimation(.spring(response: 0.55, dampingFraction: 0.78)) { expanded = true }
        } label: {
            HStack(alignment: .center, spacing: 0) {
                ZStack(alignment: .leading) {
                    ForEach(Array(shown.enumerated()).reversed(), id: \.element.localIdentifier) { index, asset in
                        thumb(asset, size: card)
                            .rotationEffect(.degrees(Double(index % 2 == 0 ? -1 : 1) * Double(min(index, 3)) * 2.5))
                            .offset(x: CGFloat(index) * step, y: CGFloat(index % 2) * 4)
                            .shadow(color: .black.opacity(0.22), radius: 6, y: 3)
                            .zIndex(Double(shown.count - index))
                    }
                }
                .frame(width: card.width + step * CGFloat(max(shown.count - 1, 0)), height: card.height + 10, alignment: .leading)
                Spacer(minLength: 12)
                VStack(spacing: 4) {
                    Image(systemName: "rectangle.expand.vertical")
                        .font(.title3.weight(.semibold))
                    Text(assets.count > shown.count ? "+\(assets.count - shown.count)" : "展开")
                        .font(.subheadline.weight(.bold))
                }
                .foregroundStyle(.tint)
                .frame(width: 64, height: 64)
                .background(.tint.opacity(0.12), in: .circle)
            }
            .contentShape(.rect)
        }
        .buttonStyle(PressableStyle())
    }

    /// Two rows across, scrolling sideways; every photo opens full screen.
    private var spread: some View {
        let side: CGFloat = 108
        return ScrollView(.horizontal) {
            LazyHGrid(rows: [GridItem(.fixed(side), spacing: 6), GridItem(.fixed(side), spacing: 6)], spacing: 6) {
                ForEach(assets, id: \.localIdentifier) { asset in
                    Button { viewing = AssetPagerStart(id: asset.localIdentifier) } label: {
                        thumb(asset, size: CGSize(width: side, height: side))
                    }
                    .buttonStyle(.plain)
                }
            }
        }
        .scrollIndicators(.hidden)
        .scrollClipDisabled()
        .frame(height: side * 2 + 6)
    }

    private func thumb(_ asset: PHAsset, size: CGSize) -> some View {
        AssetThumbnail(asset: asset, side: max(size.width, size.height))
            .frame(width: size.width, height: size.height)
            .clipShape(.rect(cornerRadius: 14, style: .continuous))
            .overlay(RoundedRectangle(cornerRadius: 14, style: .continuous).stroke(.white.opacity(0.9), lineWidth: 2))
            .matchedGeometryEffect(id: asset.localIdentifier, in: space)
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

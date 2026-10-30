import SwiftUI
import MapKit
import Photos

struct MustSeePlaceRoute: Hashable {
    let id: String
}

/// One of the hundred places, up close. Somewhere reached opens on your own photos from
/// there; somewhere not yet opens on a slow flight around it, with a few lines about why it's
/// worth the trip, how it looks from the street and what Apple Maps knows of it.
struct MustSeePlaceView: View {
    let place: MustSeePlace
    private var progress = MustSeeProgress.shared
    private var summaries = PlaceSummaries.shared
    @AppStorage("mustSee.wishes") private var wishesRaw = ""
    @State private var photos: [PHAsset] = []
    @State private var mapItem: MKMapItem?
    @State private var placeCard: MKMapItem?
    @State private var lookAround: MKLookAroundScene?
    @State private var viewing: AssetPagerStart?
    @State private var appeared = false
    @State private var burst = 0

    init(place: MustSeePlace) {
        self.place = place
    }

    private static let night = Color(red: 0.05, green: 0.06, blue: 0.11)
    private static let gold = LinearGradient(colors: [Color(red: 1, green: 0.88, blue: 0.55), .orange], startPoint: .top, endPoint: .bottom)
    private let heroHeight: CGFloat = 520

    private var firstVisit: Date? { progress.firstVisits[place.id] }
    private var story: MustSeeStory? { MustSee.story(place.id) }
    private var wishes: Set<String> { Set(wishesRaw.split(separator: ",").map(String.init)) }
    private var wished: Bool { wishes.contains(place.id) }
    private var kilometres: Int? {
        guard let here = summaries.stays.first?.location else { return nil }
        return Int((here.distance(from: CLLocation(latitude: place.latitude, longitude: place.longitude)) / 1000).rounded())
    }

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 0) {
                hero
                VStack(alignment: .leading, spacing: 28) {
                    if let story {
                        Text(verbatim: story.localizedText)
                            .font(.system(.title3, design: .serif))
                            .lineSpacing(8)
                            .foregroundStyle(.white.opacity(0.88))
                            .reveal(appeared, delay: 0.35)
                    }
                    facts.reveal(appeared, delay: 0.5)
                    if firstVisit != nil {
                        yours.reveal(appeared, delay: 0.6)
                    }
                    elsewhere.reveal(appeared, delay: 0.65)
                    if firstVisit == nil {
                        wishButton.reveal(appeared, delay: 0.7)
                    }
                    if let credit = MustSeePhotos.credit(place.id) {
                        creditLine(credit)
                    }
                }
                .padding(.horizontal, 20)
                .padding(.top, 8)
                .padding(.bottom, 48)
            }
        }
        .ignoresSafeArea(edges: .top)
        .background(Self.night.ignoresSafeArea())
        .environment(\.colorScheme, .dark)
        .navigationBarTitleDisplayMode(.inline)
        .toolbarBackground(.hidden, for: .navigationBar)
        .toolbarColorScheme(.dark, for: .navigationBar)
        .toolbar(.hidden, for: .tabBar)
        .mapItemDetailSheet(item: $placeCard)
        .fullScreenCover(item: $viewing) { AssetPager(assets: photos, selection: $0.id) }
        .sensoryFeedback(.impact(weight: .light), trigger: burst)
        .task {
            withAnimation(.smooth(duration: 0.9)) { appeared = true }
            async let mine: Void = loadPhotos()
            async let theirs: Void = findOnMaps()
            _ = await (mine, theirs)
        }
    }

    // MARK: Hero

    /// The place at its best first, then what you saw there yourself.
    private var slides: [ReelSlide] {
        (MustSeePhotos.credit(place.id) != nil ? [.cover(place.id)] : []) + photos.prefix(8).map { .asset($0) }
    }

    private var hero: some View {
        ZStack(alignment: .bottomLeading) {
            Group {
                if slides.isEmpty {
                    Flyover(place: place)
                } else {
                    PhotoReel(slides: slides)
                }
            }
            .frame(height: heroHeight)
            .frame(maxWidth: .infinity)
            .clipped()
            .overlay {
                LinearGradient(stops: [.init(color: .black.opacity(0.35), location: 0),
                                       .init(color: .clear, location: 0.22),
                                       .init(color: .clear, location: 0.5),
                                       .init(color: Self.night, location: 1)],
                               startPoint: .top, endPoint: .bottom)
            }
            .visualEffect { content, proxy in
                // Pulled down, the picture stretches to fill the gap.
                let y = proxy.frame(in: .scrollView(axis: .vertical)).minY
                return content.scaleEffect(y > 0 ? 1 + y / 520 : 1, anchor: .bottom)
            }

            VStack(alignment: .leading, spacing: 8) {
                Label {
                    Text(verbatim: place.localizedRegion)
                } icon: {
                    Image(systemName: place.kind.symbol)
                }
                .font(.footnote.weight(.semibold))
                .textCase(.uppercase)
                .tracking(1.2)
                .foregroundStyle(.white.opacity(0.75))
                .reveal(appeared, delay: 0.05)

                Text(verbatim: place.localizedName)
                    .font(.system(size: 42, weight: .bold, design: .serif))
                    .foregroundStyle(.white)
                    .shadow(color: .black.opacity(0.35), radius: 12, y: 4)
                    .minimumScaleFactor(0.6)
                    .lineLimit(2)
                    .reveal(appeared, delay: 0.12)

                Text(verbatim: MustSee.isChinese ? place.nameEn : place.name)
                    .font(.system(.subheadline, design: .serif).italic())
                    .foregroundStyle(.white.opacity(0.6))
                    .reveal(appeared, delay: 0.18)

                status.padding(.top, 6).reveal(appeared, delay: 0.26)
            }
            .padding(.horizontal, 20)
            .padding(.bottom, 18)
        }
        .frame(height: heroHeight)
    }

    @ViewBuilder
    private var status: some View {
        if let firstVisit {
            HStack(spacing: 6) {
                Image(systemName: "sparkles")
                Text("\(firstVisit.formatted(.dateTime.year().month().day().locale(appLocale))) 第一次到这里")
            }
            .font(.subheadline.weight(.semibold))
            .foregroundStyle(Self.gold)
            .padding(.horizontal, 12).padding(.vertical, 7)
            .glassEffect(.regular.tint(.orange.opacity(0.18)), in: .capsule)
        } else {
            HStack(spacing: 6) {
                Image(systemName: wished ? "heart.fill" : "star")
                Text(wished ? "在你的想去清单里" : "还在远方等你")
            }
            .font(.subheadline.weight(.semibold))
            .foregroundStyle(wished ? Color.pink : .white.opacity(0.85))
            .padding(.horizontal, 12).padding(.vertical, 7)
            .glassEffect(.regular, in: .capsule)
            .contentTransition(.symbolEffect(.replace))
        }
    }

    // MARK: Facts

    private var facts: some View {
        HStack(alignment: .top, spacing: 10) {
            if let story {
                FactTile(symbol: "calendar", title: "最好的时节", value: story.localizedSeason)
            }
            if let firstVisit {
                FactTile(symbol: "clock.arrow.circlepath", title: "第一次来", value: MustSeeView.ago(firstVisit))
            } else if let kilometres, place.countryCode == nil {
                FactTile(symbol: "location.north.line", title: "离你", value: String(localized: "约 \(kilometres.formatted()) 公里", bundle: .appLanguage))
            }
        }
        .fixedSize(horizontal: false, vertical: true)
    }

    // MARK: Yours

    @ViewBuilder
    private var yours: some View {
        VStack(alignment: .leading, spacing: 12) {
            if !photos.isEmpty {
                sectionTitle("你在这里留下的", subtitle: "\(photos.count) 张照片")
                let columns = Array(repeating: GridItem(.flexible(), spacing: 6), count: 3)
                LazyVGrid(columns: columns, spacing: 6) {
                    ForEach(photos.prefix(9), id: \.localIdentifier) { asset in
                        Button {
                            viewing = AssetPagerStart(id: asset.localIdentifier)
                        } label: {
                            Color.clear
                                .aspectRatio(1, contentMode: .fit)
                                .overlay { AssetThumbnail(asset: asset, side: 120).scaleEffect(1.01) }
                                .clipShape(.rect(cornerRadius: 14, style: .continuous))
                        }
                        .buttonStyle(PressableStyle())
                    }
                }
            }
            if let firstVisit {
                NavigationLink(value: DayRoute(day: Calendar.current.startOfDay(for: firstVisit))) {
                    HStack {
                        Image(systemName: "arrow.uturn.backward.circle.fill").font(.title3).foregroundStyle(Self.gold)
                        Text("回到第一次来的那一天").font(.headline)
                        Spacer()
                        Image(systemName: "chevron.forward").font(.footnote.weight(.semibold)).foregroundStyle(.tertiary)
                    }
                    .padding(16)
                    .background(.white.opacity(0.07), in: .rect(cornerRadius: 20, style: .continuous))
                }
                .buttonStyle(PressableStyle())
            }
        }
    }

    // MARK: Through others' eyes

    private var elsewhere: some View {
        VStack(alignment: .leading, spacing: 12) {
            sectionTitle(firstVisit == nil ? "先替你看一眼" : "再看一眼", subtitle: nil)
            if !slides.isEmpty {
                // With a photo on top, the flight around it is a view of its own.
                Flyover(place: place)
                    .frame(height: 210)
                    .clipShape(.rect(cornerRadius: 22, style: .continuous))
                    .overlay(alignment: .topLeading) {
                        Label("从空中看", systemImage: "airplane")
                            .font(.caption.weight(.semibold))
                            .padding(.horizontal, 10).padding(.vertical, 6)
                            .glassEffect(.regular, in: .capsule)
                            .padding(10)
                    }
            }
            if lookAround != nil {
                LookAroundPreview(initialScene: lookAround, allowsNavigation: true, badgePosition: .bottomTrailing)
                    .frame(height: 230)
                    .clipShape(.rect(cornerRadius: 22, style: .continuous))
                    .overlay(alignment: .topLeading) {
                        Label("街景漫步，可拖动", systemImage: "binoculars.fill")
                            .font(.caption.weight(.semibold))
                            .padding(.horizontal, 10).padding(.vertical, 6)
                            .glassEffect(.regular, in: .capsule)
                            .padding(10)
                            .allowsHitTesting(false)
                    }
            }
            if let mapItem {
                Button {
                    placeCard = mapItem
                } label: {
                    HStack(spacing: 14) {
                        ZStack {
                            RoundedRectangle(cornerRadius: 12, style: .continuous)
                                .fill(LinearGradient(colors: [.teal, .blue], startPoint: .topLeading, endPoint: .bottomTrailing))
                            Image(systemName: "photo.on.rectangle.angled").foregroundStyle(.white)
                        }
                        .frame(width: 44, height: 44)
                        VStack(alignment: .leading, spacing: 2) {
                            Text("在 Apple 地图中看看").font(.headline).foregroundStyle(.primary)
                            Text("介绍、开放时间与路线").font(.subheadline).foregroundStyle(.secondary)
                        }
                        Spacer(minLength: 0)
                        Image(systemName: "chevron.forward").font(.footnote.weight(.semibold)).foregroundStyle(.tertiary)
                    }
                    .padding(14)
                    .background(.white.opacity(0.07), in: .rect(cornerRadius: 20, style: .continuous))
                }
                .buttonStyle(PressableStyle())
            }
        }
    }

    // MARK: Wish

    private var wishButton: some View {
        VStack(spacing: 10) {
            Button {
                toggleWish()
            } label: {
                HStack(spacing: 10) {
                    Image(systemName: wished ? "heart.fill" : "heart")
                        .symbolEffect(.bounce, value: wished)
                        .contentTransition(.symbolEffect(.replace))
                    Text(wished ? "已收进想去清单" : "想去这里")
                }
                .font(.headline)
                .foregroundStyle(wished ? Color.pink : .white)
                .frame(maxWidth: .infinity)
                .padding(.vertical, 16)
                .background {
                    Capsule().fill(wished ? AnyShapeStyle(Color.pink.opacity(0.16))
                                          : AnyShapeStyle(LinearGradient(colors: [Color(red: 0.93, green: 0.33, blue: 0.5), Color(red: 0.6, green: 0.3, blue: 0.85)],
                                                                         startPoint: .leading, endPoint: .trailing)))
                }
                .overlay { HeartBurst(trigger: burst) }
            }
            .buttonStyle(PressableStyle())
            Text(wished ? "它会在夜空地图上亮成一颗粉色的星，等你出发。" : "收进清单，等一个出发的理由。")
                .font(.footnote)
                .foregroundStyle(.white.opacity(0.5))
                .contentTransition(.opacity)
        }
    }

    /// Who took the cover photo, and on what terms it may be shown.
    private func creditLine(_ credit: MustSeePhotos.Credit) -> some View {
        Link(destination: credit.page) {
            HStack(alignment: .firstTextBaseline, spacing: 6) {
                Image(systemName: "camera")
                Text("封面照片：\(credit.artist)，\(credit.license)，来自 Wikimedia Commons")
                    .multilineTextAlignment(.leading)
            }
            .font(.caption2)
            .foregroundStyle(.white.opacity(0.4))
        }
    }

    private func sectionTitle(_ title: LocalizedStringKey, subtitle: LocalizedStringKey?) -> some View {
        HStack(alignment: .firstTextBaseline) {
            Text(title).font(.system(.title3, design: .serif, weight: .bold)).foregroundStyle(.white)
            Spacer()
            if let subtitle { Text(subtitle).font(.subheadline).foregroundStyle(.white.opacity(0.5)) }
        }
    }

    // MARK: Loading

    private func toggleWish() {
        var set = wishes
        withAnimation(.spring(response: 0.4, dampingFraction: 0.7)) {
            if set.contains(place.id) { set.remove(place.id) } else { set.insert(place.id); burst += 1 }
            wishesRaw = set.sorted().joined(separator: ",")
        }
    }

    /// Your own photos from there, the best first: from every stay inside the place's radius.
    private func loadPhotos() async {
        guard firstVisit != nil, DayPhotos.canRead else { return }
        let center = CLLocation(latitude: place.latitude, longitude: place.longitude)
        let radius = place.radius * 1000
        let code = place.countryCode
        let intervals = summaries.stays
            .filter { stay in code.map { stay.countryCode == $0 } ?? (stay.location.distance(from: center) <= radius) }
            .prefix(80)
            .map { DayPhotos.interval(of: $0) }
        guard !intervals.isEmpty else { return }
        let found = await Task.detached(priority: .userInitiated) { () -> [PHAsset] in
            var seen = Set<String>()
            var assets: [PHAsset] = []
            for interval in intervals {
                for asset in DayPhotos.assets(in: interval) where seen.insert(asset.localIdentifier).inserted {
                    // A photo that says where it was taken has to have been taken here.
                    if code == nil, let location = asset.location, location.distance(from: center) > radius * 1.5 { continue }
                    assets.append(asset)
                }
                if assets.count >= 400 { break }
            }
            return assets
        }.value
        let ranked = await PhotoCurator.rank(found, limit: 36)
        withAnimation(.smooth(duration: 0.8)) { photos = Array(ranked.prefix(12)) }
    }

    /// The place on Apple Maps, for its photos and description, and a street-level look if there is one.
    private func findOnMaps() async {
        let center = ChinaCoordinates.mapCoordinate(for: place.coordinate)
        let request = MKLocalSearch.Request()
        request.naturalLanguageQuery = MustSee.china.contains(place) ? place.name : place.nameEn
        request.region = MKCoordinateRegion(center: center, latitudinalMeters: max(place.radius * 6000, 20_000),
                                            longitudinalMeters: max(place.radius * 6000, 20_000))
        request.resultTypes = place.kind == .city ? [.pointOfInterest, .address] : [.pointOfInterest]
        let here = CLLocation(latitude: center.latitude, longitude: center.longitude)
        let tolerance = max(place.radius * 3000, 15_000)
        if let items = try? await MKLocalSearch(request: request).start().mapItems,
           let best = items.filter({ $0.location.distance(from: here) <= tolerance })
               .min(by: { $0.location.distance(from: here) < $1.location.distance(from: here) }) {
            withAnimation(.smooth) { mapItem = best }
        }
        let sceneRequest = mapItem.map { MKLookAroundSceneRequest(mapItem: $0) } ?? MKLookAroundSceneRequest(coordinate: center)
        if let scene = try? await sceneRequest.scene {
            withAnimation(.smooth) { lookAround = scene }
        }
    }
}

// MARK: - Pieces

/// A slow circle around the place, high enough to see the whole of it.
private struct Flyover: View {
    let place: MustSeePlace
    @State private var lap = 0

    var body: some View {
        let center = ChinaCoordinates.mapCoordinate(for: place.coordinate)
        let distance = min(max(place.radius * 2400, 2200), 40_000)
        Map(initialPosition: .camera(MapCamera(centerCoordinate: center, distance: distance, heading: 20, pitch: 64)),
            interactionModes: [])
            .mapStyle(.imagery(elevation: .realistic))
            .mapControls { }
            .mapCameraKeyframeAnimator(trigger: lap) { camera in
                KeyframeTrack(\MapCamera.heading) {
                    LinearKeyframe(camera.heading + 120, duration: 40)
                    LinearKeyframe(camera.heading + 240, duration: 40)
                    LinearKeyframe(camera.heading + 360, duration: 40)
                }
            }
            .task {
                while !Task.isCancelled {
                    lap += 1
                    try? await Task.sleep(for: .seconds(120))
                }
            }
            .allowsHitTesting(false)
            .accessibilityHidden(true)
    }
}

private enum ReelSlide: Identifiable {
    case cover(String)
    case asset(PHAsset)

    var id: String {
        switch self {
        case .cover(let id): "cover-\(id)"
        case .asset(let asset): asset.localIdentifier
        }
    }
}

/// Photos one after another, each drifting slowly as it fades into the next.
private struct PhotoReel: View {
    let slides: [ReelSlide]
    @State private var index = 0

    var body: some View {
        ZStack {
            let slide = slides[min(index, slides.count - 1)]
            DriftingPhoto(slide: slide, toward: index.isMultiple(of: 2) ? .topLeading : .bottomTrailing)
                .id(slide.id)
                .transition(.opacity)
        }
        .task(id: slides.count) {
            guard slides.count > 1 else { return }
            while !Task.isCancelled {
                try? await Task.sleep(for: .seconds(7))
                withAnimation(.easeInOut(duration: 1.8)) { index = (index + 1) % slides.count }
            }
        }
        .accessibilityHidden(true)
    }
}

private struct DriftingPhoto: View {
    let slide: ReelSlide
    let toward: UnitPoint
    @State private var image: UIImage?
    @State private var drift = false

    var body: some View {
        GeometryReader { proxy in
            if let image {
                Image(uiImage: image)
                    .resizable()
                    .scaledToFill()
                    .frame(width: proxy.size.width, height: proxy.size.height)
                    .scaleEffect(drift ? 1.16 : 1.03, anchor: toward)
                    .clipped()
            }
        }
        .task {
            switch slide {
            case .cover(let id): image = await MustSeePhotos.cover(id)
            case .asset(let asset): image = await AssetLoader.image(for: asset, size: CGSize(width: 1600, height: 1600), exact: false)
            }
            withAnimation(.linear(duration: 12)) { drift = true }
        }
    }
}

private struct FactTile: View {
    let symbol: String
    let title: LocalizedStringKey
    let value: String

    var body: some View {
        VStack(alignment: .leading, spacing: 6) {
            Label(title, systemImage: symbol)
                .font(.caption.weight(.semibold))
                .foregroundStyle(.white.opacity(0.55))
            Text(verbatim: value)
                .font(.subheadline.weight(.semibold))
                .foregroundStyle(.white)
                .fixedSize(horizontal: false, vertical: true)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
        .padding(14)
        .background(.white.opacity(0.07), in: .rect(cornerRadius: 18, style: .continuous))
    }
}

/// Little hearts that rise and fade when a place goes on the list.
private struct HeartBurst: View {
    let trigger: Int

    private struct Frame {
        var rise: CGFloat = 0
        var opacity: Double = 0
        var scale: CGFloat = 0.4
    }

    var body: some View {
        ZStack {
            ForEach(0..<7, id: \.self) { index in
                let spread = CGFloat(index - 3) * 22
                Image(systemName: "heart.fill")
                    .font(.system(size: index.isMultiple(of: 2) ? 14 : 10))
                    .foregroundStyle(.pink)
                    .keyframeAnimator(initialValue: Frame(), trigger: trigger) { heart, frame in
                        heart
                            .scaleEffect(frame.scale)
                            .opacity(frame.opacity)
                            .offset(x: spread * (0.4 + frame.rise / 140), y: -frame.rise)
                    } keyframes: { _ in
                        KeyframeTrack(\.rise) {
                            CubicKeyframe(70 + CGFloat(index % 3) * 18, duration: 0.9 + Double(index % 3) * 0.1)
                            LinearKeyframe(0, duration: 0.01)
                        }
                        KeyframeTrack(\.opacity) {
                            LinearKeyframe(1, duration: 0.12)
                            LinearKeyframe(0, duration: 0.8 + Double(index % 3) * 0.1)
                        }
                        KeyframeTrack(\.scale) {
                            SpringKeyframe(1.1, duration: 0.3)
                            LinearKeyframe(0.7, duration: 0.6)
                        }
                    }
            }
        }
        .allowsHitTesting(false)
    }
}

private extension View {
    /// Fades and lifts into place, a moment after the page opens.
    func reveal(_ shown: Bool, delay: Double) -> some View {
        self
            .opacity(shown ? 1 : 0)
            .offset(y: shown ? 0 : 14)
            .blur(radius: shown ? 0 : 6)
            .animation(.smooth(duration: 0.8).delay(delay), value: shown)
    }
}

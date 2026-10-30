import SwiftUI
import MapKit

struct MustSeeRoute: Hashable {
    var list: MustSee.List = .china
}

/// Which of the hundred places have been reached, and when, worked out from every stay.
@MainActor
@Observable
final class MustSeeProgress {
    static let shared = MustSeeProgress()
    private(set) var firstVisits: [String: Date] = [:]
    private(set) var isLoaded = false
    @ObservationIgnored private var computedFor = -1

    func update(from stays: [Stay]) async {
        guard stays.count != computedFor else { return }
        computedFor = stays.count
        let visits = stays.map { MustSee.Visit(latitude: $0.latitude, longitude: $0.longitude, arrival: $0.arrival, countryCode: $0.countryCode) }
        let found = await Task.detached(priority: .utility) {
            MustSee.firstVisits(MustSee.china + MustSee.world, visits: visits)
        }.value
        withAnimation(.smooth) {
            firstVisits = found
            isLoaded = true
        }
    }

    func count(_ list: MustSee.List) -> Int { list.places.filter { firstVisits[$0.id] != nil }.count }
}

/// A line that meets the person where they are on the way to a hundred.
enum MustSeeWords {
    static func headline(_ count: Int, of total: Int) -> LocalizedStringKey {
        switch count {
        case 0: "第一盏灯，等你去点亮"
        case 1..<10: "已经出发了，前面还有很多风景"
        case 10..<30: "走过的地方，都成了你的一部分"
        case 30..<60: "你看过的世界，比大多数人都辽阔"
        case 60..<total: "剩下的，是留给未来的惊喜"
        default: "一百处，你都去过了"
        }
    }
}

struct MustSeeView: View {
    @State var list: MustSee.List
    private var summaries = PlaceSummaries.shared
    private var progress = MustSeeProgress.shared
    @State private var filter = Filter.all
    @State private var position: MapCameraPosition
    @State private var selected: MustSeePlace?
    @State private var justLit: [MustSeePlace] = []
    @AppStorage("mustSee.wishes") private var wishesRaw = ""
    @AppStorage("mustSee.seen") private var seenRaw = ""

    enum Filter: Hashable { case all, lit, wished, unlit }

    init(list: MustSee.List) {
        _list = State(initialValue: list)
        _position = State(initialValue: Self.overview(list))
    }

    private var places: [MustSeePlace] { list.places }
    private var wishes: Set<String> { Set(wishesRaw.split(separator: ",").map(String.init)) }
    private func visited(_ place: MustSeePlace) -> Date? { progress.firstVisits[place.id] }
    private var litCount: Int { places.filter { visited($0) != nil }.count }

    private var shown: [MustSeePlace] {
        switch filter {
        case .all: places
        case .lit: places.filter { visited($0) != nil }
        case .wished: places.filter { wishes.contains($0.id) && visited($0) == nil }
        case .unlit: places.filter { visited($0) == nil }
        }
    }

    /// Regions in the list's own order: provinces north to south and Hong Kong, Macao and
    /// Taiwan together at the end of China; countries continent by continent.
    private var regions: [(name: String, places: [MustSeePlace])] {
        var order: [String] = []
        var groups: [String: [MustSeePlace]] = [:]
        for place in shown {
            if groups[place.localizedRegion] == nil { order.append(place.localizedRegion) }
            groups[place.localizedRegion, default: []].append(place)
        }
        return order.map { ($0, groups[$0] ?? []) }
    }

    var body: some View {
        ScrollViewReader { proxy in
            ScrollView {
                VStack(alignment: .leading, spacing: 18) {
                    listPicker
                    hero.id("top")
                    if !justLit.isEmpty { litBanner }
                    if let next = nearestUnlit { nextCard(next) { focus(next, proxy: proxy) } }
                    FilterChips(options: [
                        .init(value: Filter.all, title: String(localized: "全部", bundle: .appLanguage), count: places.count),
                        .init(value: Filter.lit, title: String(localized: "已点亮", bundle: .appLanguage), count: litCount),
                        .init(value: Filter.wished, title: String(localized: "想去", bundle: .appLanguage),
                              count: places.filter { wishes.contains($0.id) && visited($0) == nil }.count),
                        .init(value: Filter.unlit, title: String(localized: "还没去", bundle: .appLanguage), count: places.count - litCount),
                    ], selection: $filter)

                    if shown.isEmpty {
                        emptyFilter
                    } else {
                        LazyVStack(alignment: .leading, spacing: 18) {
                            ForEach(regions, id: \.name) { region in
                                regionSection(region.name, region.places, proxy: proxy)
                            }
                        }
                    }
                    Text("清单由漫迹整理，参考世界遗产名录与国家 5A 级景区。在附近停留过，或在那里拍过照片，就会点亮。")
                        .font(.caption).foregroundStyle(.tertiary)
                        .padding(.horizontal, 4).padding(.top, 8)
                }
                .padding(.horizontal)
                .padding(.bottom, 32)
            }
        }
        .navigationTitle("此生必去")
        .navigationBarTitleDisplayMode(.inline)
        .background(Color(.systemGroupedBackground))
        .task(id: summaries.stays.count) {
            await progress.update(from: summaries.stays)
            noticeNewlyLit()
        }
        .onChange(of: list) {
            selected = nil
            withAnimation(.smooth(duration: 0.8)) { position = Self.overview(list) }
        }
        .sensoryFeedback(.selection, trigger: list)
    }

    // MARK: Pieces

    private var listPicker: some View {
        HStack(spacing: 0) {
            ForEach(MustSee.List.allCases) { option in
                let isOn = option == list
                Button {
                    withAnimation(.snappy) { list = option }
                } label: {
                    VStack(spacing: 2) {
                        Text(option == .china ? "中国 100" : "世界 100").font(.headline)
                        Text("\(progress.count(option)) 处已点亮").font(.caption).opacity(0.75).monospacedDigit()
                    }
                    .frame(maxWidth: .infinity)
                    .padding(.vertical, 10)
                    .foregroundStyle(isOn ? Color.white : Color.primary)
                    .background {
                        if isOn {
                            Capsule().fill(LinearGradient(colors: [Color(red: 0.13, green: 0.16, blue: 0.32), Color(red: 0.27, green: 0.20, blue: 0.42)],
                                                          startPoint: .leading, endPoint: .trailing))
                        }
                    }
                    .contentShape(.capsule)
                }
                .buttonStyle(.plain)
                .accessibilityAddTraits(isOn ? .isSelected : [])
            }
        }
        .padding(4)
        .background(.background.secondary, in: .capsule)
    }

    /// The night map: everywhere on the list a faint star, everywhere reached a warm light.
    private var hero: some View {
        VStack(spacing: 0) {
            Map(position: $position, selection: Binding(get: { selected?.id }, set: { id in
                withAnimation(.snappy) { selected = places.first { $0.id == id } }
            })) {
                ForEach(places) { place in
                    let lit = visited(place) != nil
                    Annotation(place.localizedName, coordinate: ChinaCoordinates.mapCoordinate(for: place.coordinate), anchor: .center) {
                        MustSeePin(lit: lit, wished: wishes.contains(place.id), selected: selected?.id == place.id,
                                   fresh: justLit.contains(place))
                    }
                    .annotationTitles(selected?.id == place.id ? .visible : .hidden)
                    .tag(place.id)
                }
            }
            .mapStyle(.standard(elevation: .flat, emphasis: .muted, pointsOfInterest: .excludingAll))
            .mapControls { }
            .environment(\.colorScheme, .dark)
            .frame(height: 330)
            .overlay(alignment: .bottom) {
                LinearGradient(colors: [.clear, Color(red: 0.06, green: 0.07, blue: 0.13)], startPoint: .top, endPoint: .bottom)
                    .frame(height: 90)
                    .allowsHitTesting(false)
            }
            .overlay(alignment: .topLeading) {
                if let selected { selectedChip(selected).padding(12) }
            }

            VStack(alignment: .leading, spacing: 14) {
                HStack(alignment: .firstTextBaseline, spacing: 6) {
                    Text("\(litCount)")
                        .font(.system(size: 52, weight: .bold, design: .rounded))
                        .foregroundStyle(LinearGradient(colors: [Color(red: 1, green: 0.86, blue: 0.5), .orange], startPoint: .top, endPoint: .bottom))
                        .contentTransition(.numericText())
                    Text(verbatim: "/ \(places.count)")
                        .font(.system(.title3, design: .rounded, weight: .semibold))
                        .foregroundStyle(.white.opacity(0.45))
                    Spacer()
                    Text(verbatim: "\(litCount)%")
                        .font(.system(.subheadline, design: .rounded, weight: .semibold))
                        .foregroundStyle(.white.opacity(0.6))
                        .monospacedDigit()
                }
                Text(MustSeeWords.headline(litCount, of: places.count))
                    .font(.headline)
                    .foregroundStyle(.white.opacity(0.92))
                LitGrid(lit: Self.filled(litCount, of: places.count))
                    .accessibilityHidden(true)
            }
            .padding(.horizontal, 20)
            .padding(.top, 4)
            .padding(.bottom, 20)
            .background(Color(red: 0.06, green: 0.07, blue: 0.13))
        }
        .clipShape(.rect(cornerRadius: 30, style: .continuous))
        .shadow(color: .black.opacity(0.18), radius: 18, y: 8)
    }

    private func selectedChip(_ place: MustSeePlace) -> some View {
        HStack(spacing: 8) {
            Image(systemName: place.kind.symbol).foregroundStyle(visited(place) != nil ? .yellow : .white.opacity(0.7))
            VStack(alignment: .leading, spacing: 1) {
                Text(verbatim: place.localizedName).font(.subheadline.weight(.semibold))
                if let date = visited(place) {
                    Text("\(date.formatted(.dateTime.year().month().day().locale(appLocale))) 第一次到这里").font(.caption2)
                } else {
                    Text("还没去过").font(.caption2).opacity(0.7)
                }
            }
        }
        .foregroundStyle(.white)
        .padding(.horizontal, 12).padding(.vertical, 8)
        .glassEffect(.regular.tint(.black.opacity(0.3)), in: .capsule)
        .transition(.scale(scale: 0.9).combined(with: .opacity))
    }

    private var litBanner: some View {
        HStack(spacing: 12) {
            Image(systemName: "sparkles")
                .font(.title2)
                .foregroundStyle(LinearGradient(colors: [.yellow, .orange], startPoint: .top, endPoint: .bottom))
                .symbolEffect(.bounce, value: justLit.count)
            VStack(alignment: .leading, spacing: 2) {
                Text("新点亮了 \(justLit.count) 处").font(.headline)
                Text(verbatim: justLit.prefix(4).map(\.localizedName).joined(separator: "、") + (justLit.count > 4 ? "…" : ""))
                    .font(.subheadline).foregroundStyle(.secondary)
            }
            Spacer(minLength: 0)
        }
        .padding(16)
        .background(LinearGradient(colors: [Color.orange.opacity(0.16), Color.yellow.opacity(0.08)], startPoint: .leading, endPoint: .trailing),
                    in: .rect(cornerRadius: 22, style: .continuous))
        .transition(.move(edge: .top).combined(with: .opacity))
    }

    /// The closest place not yet reached, from where the person was last.
    private var nearestUnlit: MustSeePlace? {
        guard progress.isLoaded, let here = summaries.stays.first?.location else { return nil }
        return places.filter { visited($0) == nil && $0.countryCode == nil }
            .min { here.distance(from: CLLocation(latitude: $0.latitude, longitude: $0.longitude))
                < here.distance(from: CLLocation(latitude: $1.latitude, longitude: $1.longitude)) }
    }

    private func nextCard(_ place: MustSeePlace, action: @escaping () -> Void) -> some View {
        let km = summaries.stays.first.map { $0.location.distance(from: CLLocation(latitude: place.latitude, longitude: place.longitude)) / 1000 } ?? 0
        return Button(action: action) {
            HStack(spacing: 14) {
                ZStack {
                    Circle().fill(Color.indigo.opacity(0.15))
                    Image(systemName: "location.north.line.fill").foregroundStyle(.indigo)
                }
                .frame(width: 44, height: 44)
                VStack(alignment: .leading, spacing: 2) {
                    Text("离你最近的下一站").font(.caption.weight(.semibold)).foregroundStyle(.secondary)
                    Text(verbatim: place.localizedName).font(.headline).foregroundStyle(.primary)
                    Text("\(place.localizedRegion) · 约 \(Int(km.rounded()).formatted()) 公里").font(.subheadline).foregroundStyle(.secondary)
                }
                Spacer(minLength: 0)
                Image(systemName: "scope").foregroundStyle(.tertiary)
            }
            .padding(14)
            .background(.background.secondary, in: .rect(cornerRadius: 22, style: .continuous))
        }
        .buttonStyle(PressableStyle())
    }

    private func regionSection(_ name: String, _ members: [MustSeePlace], proxy: ScrollViewProxy) -> some View {
        let all = places.filter { $0.localizedRegion == name }
        let lit = all.filter { visited($0) != nil }.count
        return VStack(alignment: .leading, spacing: 8) {
            HStack(alignment: .firstTextBaseline) {
                Text(verbatim: name).font(.title3.bold())
                Spacer()
                Text(verbatim: "\(lit) / \(all.count)")
                    .font(.subheadline.weight(.semibold)).monospacedDigit()
                    .foregroundStyle(lit == all.count ? Color.orange : .secondary)
                if lit == all.count {
                    Image(systemName: "checkmark.seal.fill").foregroundStyle(.orange)
                }
            }
            .padding(.horizontal, 4)
            VStack(spacing: 0) {
                ForEach(members) { place in
                    row(place, proxy: proxy)
                    if place.id != members.last?.id { Divider().padding(.leading, 70) }
                }
            }
            .background(.background.secondary, in: .rect(cornerRadius: 22, style: .continuous))
        }
    }

    @ViewBuilder
    private func row(_ place: MustSeePlace, proxy: ScrollViewProxy) -> some View {
        let date = visited(place)
        let content = HStack(spacing: 14) {
            ZStack {
                RoundedRectangle(cornerRadius: 12, style: .continuous)
                    .fill(date != nil
                          ? AnyShapeStyle(LinearGradient(colors: [Color(red: 1, green: 0.78, blue: 0.35), .orange], startPoint: .topLeading, endPoint: .bottomTrailing))
                          : AnyShapeStyle(Color.secondary.opacity(0.12)))
                Image(systemName: place.kind.symbol)
                    .font(.system(size: 17, weight: .semibold))
                    .foregroundStyle(date != nil ? Color.white : Color.secondary)
            }
            .frame(width: 42, height: 42)
            VStack(alignment: .leading, spacing: 2) {
                Text(verbatim: place.localizedName)
                    .font(.body.weight(date != nil ? .semibold : .regular))
                    .foregroundStyle(.primary)
                if let date {
                    Text("\(date.formatted(.dateTime.year().month().day().locale(appLocale))) · \(Self.ago(date))")
                        .font(.caption).foregroundStyle(.orange)
                } else if wishes.contains(place.id) {
                    Text("想去").font(.caption).foregroundStyle(.pink)
                }
            }
            Spacer(minLength: 0)
            if date != nil {
                Image(systemName: "chevron.forward").font(.footnote.weight(.semibold)).foregroundStyle(.tertiary)
            } else {
                Button {
                    toggleWish(place)
                } label: {
                    Image(systemName: wishes.contains(place.id) ? "heart.fill" : "heart")
                        .font(.body.weight(.semibold))
                        .foregroundStyle(wishes.contains(place.id) ? Color.pink : Color.secondary.opacity(0.6))
                        .symbolEffect(.bounce, value: wishes.contains(place.id))
                        .frame(width: 44, height: 44)
                        .contentShape(.rect)
                }
                .buttonStyle(.plain)
                .accessibilityLabel(wishes.contains(place.id) ? Text("取消想去") : Text("想去"))
            }
        }
        .padding(.leading, 14).padding(.trailing, 6).padding(.vertical, 10)
        .contentShape(.rect)

        if let date {
            // Back to the day it first happened.
            NavigationLink(value: DayRoute(day: Calendar.current.startOfDay(for: date))) { content }
                .buttonStyle(.plain)
        } else {
            content.onTapGesture { focus(place, proxy: proxy) }
        }
    }

    private var emptyFilter: some View {
        VStack(spacing: 8) {
            Image(systemName: filter == .wished ? "heart" : "sparkles").font(.title).foregroundStyle(.secondary)
            Text(filter == .wished ? "点一下 ♡，把想去的地方收进来" : "还没有点亮的地方，出发吧")
                .font(.subheadline).foregroundStyle(.secondary)
        }
        .frame(maxWidth: .infinity)
        .padding(.vertical, 40)
    }

    // MARK: Actions

    private func focus(_ place: MustSeePlace, proxy: ScrollViewProxy) {
        withAnimation(.smooth) { proxy.scrollTo("top", anchor: .top) }
        withAnimation(.smooth(duration: 0.9)) {
            selected = place
            position = .camera(MapCamera(centerCoordinate: ChinaCoordinates.mapCoordinate(for: place.coordinate),
                                         distance: max(place.radius * 6_000, 60_000)))
        }
    }

    private func toggleWish(_ place: MustSeePlace) {
        var set = wishes
        if set.contains(place.id) { set.remove(place.id) } else { set.insert(place.id) }
        wishesRaw = set.sorted().joined(separator: ",")
    }

    /// Places reached since this screen was last opened get a moment of their own.
    private func noticeNewlyLit() {
        guard progress.isLoaded else { return }
        let lit = Set(progress.firstVisits.keys)
        let seen = Set(seenRaw.split(separator: ",").map(String.init))
        // The first time, everything is already known; only what comes later is news.
        if !seenRaw.isEmpty {
            let fresh = (MustSee.china + MustSee.world).filter { lit.contains($0.id) && !seen.contains($0.id) }
            if !fresh.isEmpty {
                withAnimation(.spring(response: 0.5, dampingFraction: 0.8)) { justLit = fresh }
                UINotificationFeedbackGenerator().notificationOccurred(.success)
            }
        }
        seenRaw = lit.isEmpty ? "-" : lit.sorted().joined(separator: ",")
    }

    private static func overview(_ list: MustSee.List) -> MapCameraPosition {
        switch list {
        case .china:
            .region(MKCoordinateRegion(center: CLLocationCoordinate2D(latitude: 34.5, longitude: 104),
                                       span: MKCoordinateSpan(latitudeDelta: 38, longitudeDelta: 52)))
        case .world:
            .region(MKCoordinateRegion(center: CLLocationCoordinate2D(latitude: 20, longitude: 40),
                                       span: MKCoordinateSpan(latitudeDelta: 130, longitudeDelta: 300)))
        }
    }

    /// Squares filled from the first, so the grid reads as how far along the way is.
    static func filled(_ count: Int, of total: Int) -> [Bool] {
        (0..<total).map { $0 < count }
    }

    static func ago(_ date: Date) -> String {
        let days = Calendar.current.dateComponents([.day], from: date, to: Date()).day ?? 0
        if days < 1 { return String(localized: "今天", bundle: .appLanguage) }
        if days < 30 { return String(localized: "\(days) 天前", bundle: .appLanguage) }
        if days < 365 { return String(localized: "\(days / 30) 个月前", bundle: .appLanguage) }
        return String(localized: "\(days / 365) 年前", bundle: .appLanguage)
    }
}

/// A place on the night map: a faint star until reached, then a warm light.
private struct MustSeePin: View {
    let lit: Bool
    let wished: Bool
    let selected: Bool
    let fresh: Bool
    @State private var pulse = false

    var body: some View {
        ZStack {
            if lit {
                Circle()
                    .fill(Color.orange.opacity(0.35))
                    .frame(width: 22, height: 22)
                    .blur(radius: 5)
                    .scaleEffect(fresh && pulse ? 1.8 : 1)
                Circle()
                    .fill(RadialGradient(colors: [Color(red: 1, green: 0.95, blue: 0.75), .orange], center: .center, startRadius: 0, endRadius: 6))
                    .frame(width: selected ? 14 : 10, height: selected ? 14 : 10)
            } else {
                Circle()
                    .fill(wished ? Color.pink.opacity(0.9) : Color.white.opacity(0.55))
                    .frame(width: selected ? 11 : 6, height: selected ? 11 : 6)
                    .overlay(Circle().stroke(.white.opacity(selected ? 0.9 : 0), lineWidth: 2))
            }
        }
        .frame(width: 28, height: 28)
        .contentShape(.circle)
        .onAppear {
            guard fresh else { return }
            withAnimation(.easeInOut(duration: 1.1).repeatForever(autoreverses: true)) { pulse = true }
        }
    }
}

/// A hundred small squares, one per place.
private struct LitGrid: View {
    let lit: [Bool]

    var body: some View {
        let columns = Array(repeating: GridItem(.flexible(), spacing: 4), count: 20)
        LazyVGrid(columns: columns, spacing: 4) {
            ForEach(lit.indices, id: \.self) { index in
                RoundedRectangle(cornerRadius: 2.5, style: .continuous)
                    .fill(lit[index]
                          ? AnyShapeStyle(LinearGradient(colors: [Color(red: 1, green: 0.85, blue: 0.45), .orange], startPoint: .top, endPoint: .bottom))
                          : AnyShapeStyle(Color.white.opacity(0.1)))
                    .aspectRatio(1, contentMode: .fit)
                    .shadow(color: lit[index] ? .orange.opacity(0.6) : .clear, radius: 3)
            }
        }
    }
}

/// The way in, on the Places tab.
struct MustSeeCard: View {
    private var progress = MustSeeProgress.shared
    private var summaries = PlaceSummaries.shared

    var body: some View {
        VStack(alignment: .leading, spacing: 14) {
            HStack {
                VStack(alignment: .leading, spacing: 3) {
                    Text("此生必去").font(.title3.bold()).foregroundStyle(.white)
                    Text("中国与世界，各一百处值得一去的地方").font(.subheadline).foregroundStyle(.white.opacity(0.7))
                }
                Spacer()
                Image(systemName: "chevron.forward").font(.footnote.weight(.semibold)).foregroundStyle(.white.opacity(0.5))
            }
            HStack(spacing: 12) {
                tally("中国", count: progress.count(.china), lit: MustSeeView.filled(progress.count(.china), of: 100))
                tally("世界", count: progress.count(.world), lit: MustSeeView.filled(progress.count(.world), of: 100))
            }
        }
        .padding(18)
        .background(
            LinearGradient(colors: [Color(red: 0.08, green: 0.09, blue: 0.2), Color(red: 0.2, green: 0.14, blue: 0.32)],
                           startPoint: .topLeading, endPoint: .bottomTrailing),
            in: .rect(cornerRadius: 26, style: .continuous)
        )
        .task(id: summaries.stays.count) { await progress.update(from: summaries.stays) }
    }

    private func tally(_ title: LocalizedStringKey, count: Int, lit: [Bool]) -> some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack(alignment: .firstTextBaseline, spacing: 4) {
                Text(title).font(.subheadline.weight(.semibold)).foregroundStyle(.white.opacity(0.8))
                Spacer()
                Text(verbatim: "\(count)")
                    .font(.system(.title2, design: .rounded, weight: .bold))
                    .foregroundStyle(LinearGradient(colors: [Color(red: 1, green: 0.86, blue: 0.5), .orange], startPoint: .top, endPoint: .bottom))
                    .contentTransition(.numericText())
                Text(verbatim: "/100").font(.caption.weight(.semibold)).foregroundStyle(.white.opacity(0.4))
            }
            MiniLitGrid(lit: lit)
        }
        .padding(12)
        .frame(maxWidth: .infinity)
        .background(.white.opacity(0.06), in: .rect(cornerRadius: 16, style: .continuous))
    }
}

private struct MiniLitGrid: View {
    let lit: [Bool]

    var body: some View {
        Canvas { context, size in
            let columns = 20, rows = Int(ceil(Double(lit.count) / 20)), gap: CGFloat = 2
            let side = min((size.width - gap * CGFloat(columns - 1)) / CGFloat(columns), (size.height - gap * CGFloat(rows - 1)) / CGFloat(rows))
            for (index, on) in lit.enumerated() {
                let rect = CGRect(x: CGFloat(index % columns) * (side + gap), y: CGFloat(index / columns) * (side + gap), width: side, height: side)
                context.fill(Path(roundedRect: rect, cornerRadius: 1.5), with: .color(on ? .orange : .white.opacity(0.12)))
            }
        }
        .frame(height: 30)
        .accessibilityHidden(true)
    }
}

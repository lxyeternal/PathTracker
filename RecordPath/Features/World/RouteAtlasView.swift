import SwiftUI
import MapKit

/// Which stretch of time the atlas shows: today's roads, this week's, this month's, a year's
/// or all of them.
enum RouteSpan: Hashable {
    case today, week, month, year, all
    case past(Int)

    static let quick: [RouteSpan] = [.today, .week, .month, .year, .all]

    var title: String {
        switch self {
        case .today: String(localized: "今天", bundle: .appLanguage)
        case .week: String(localized: "本周", bundle: .appLanguage)
        case .month: String(localized: "本月", bundle: .appLanguage)
        case .year: String(localized: "今年", bundle: .appLanguage)
        // Its own key: "全部" elsewhere is a button that reads "See All".
        case .all: String(localized: "route.span.all", defaultValue: "全部", bundle: .appLanguage)
        case let .past(year): "\(year)"
        }
    }

    /// The days it covers; nil for all of them.
    func interval(now: Date = .now, calendar: Calendar = .current) -> DateInterval? {
        switch self {
        case .today: calendar.dateInterval(of: .day, for: now)
        case .week: calendar.dateInterval(of: .weekOfYear, for: now)
        case .month: calendar.dateInterval(of: .month, for: now)
        case .year: calendar.dateInterval(of: .year, for: now)
        case .all: nil
        case let .past(year):
            calendar.date(from: DateComponents(year: year)).flatMap { calendar.dateInterval(of: .year, for: $0) }
        }
    }

    /// A few days' roads fit on the screen whole; years of them open on where life mostly is.
    var fitsWhole: Bool {
        switch self {
        case .today, .week, .month: true
        case .year, .all, .past: false
        }
    }
}

/// The atlas as a screen of its own, for opening from anywhere.
struct RouteAtlasScreen: View {
    var span: RouteSpan = .all
    @Environment(\.dismiss) private var dismiss

    var body: some View {
        NavigationStack {
            RouteAtlasView(span: span)
                .navigationBarTitleDisplayMode(.inline)
                .toolbarBackground(.hidden, for: .navigationBar)
                .toolbar {
                    ToolbarItem(placement: .cancellationAction) {
                        Button("关闭", systemImage: "xmark") { dismiss() }
                    }
                    ToolbarItem(placement: .principal) {
                        Text("走过的路").font(.headline).foregroundStyle(.white)
                    }
                }
                .toolbarColorScheme(.dark, for: .navigationBar)
        }
    }
}

/// Every road ever travelled on one night map. The lines are faint on their own and brighten
/// where they overlap, so the streets walked every day glow and a one-off detour is a whisper.
struct RouteAtlasView: View {
    private var atlas = RouteAtlas.shared
    @Environment(LocationEngine.self) private var engine
    @State private var span: RouteSpan
    @State private var kind: RouteKind = .all
    @State private var shown: [AtlasLine] = []
    @State private var appeared = false

    init(span: RouteSpan = .all) {
        _span = State(initialValue: span)
    }

    var body: some View {
        ZStack {
            Color.black.ignoresSafeArea()
            if atlas.isLoaded {
                RouteAtlasMap(lines: shown, kind: kind, focus: "\(span)", fitsWhole: span.fitsWhole, everywhere: atlas.lines)
                    .ignoresSafeArea()
                    .opacity(appeared ? 1 : 0)
                    .onAppear { withAnimation(.smooth(duration: 0.9)) { appeared = true } }
                if shown.isEmpty { empty.transition(.opacity.combined(with: .scale(scale: 0.96))) }
            } else {
                VStack(spacing: 12) {
                    ProgressView().tint(.white)
                    if atlas.isBuilding {
                        Text("正在整理全部路线…").font(.footnote).foregroundStyle(.white.opacity(0.7))
                    }
                }
                .transition(.opacity)
            }
        }
        .animation(.smooth(duration: 0.35), value: shown.isEmpty)
        .environment(\.colorScheme, .dark)
        .safeAreaInset(edge: .bottom) {
            if atlas.isLoaded { controls }
        }
        .task { await atlas.load() }
        .onChange(of: atlas.lines.count, initial: true) { update() }
        .onChange(of: span) { update() }
        .onChange(of: kind) { update() }
        .onChange(of: engine.pendingPoints.count / 20) { update() }
    }

    /// The stretch being recorded now isn't a saved chunk yet; it's drawn all the same.
    private var live: AtlasLine? {
        let points = engine.pendingPoints
        guard engine.isRecording, points.count > 1 else { return nil }
        return AtlasLine(points: points, mode: MotionClassifier.mode(forSpeeds: points.map(\.speed)))
    }

    private var everything: [AtlasLine] { atlas.lines + (live.map { [$0] } ?? []) }

    private func update() {
        let interval = span.interval()
        shown = everything.filter { line in
            kind.includes(line.mode) && (interval.map { line.start >= $0.start && line.start < $0.end } ?? true)
        }
    }

    /// Years before this one that have roads in them.
    private var pastYears: [Int] {
        let calendar = Calendar.current
        let current = calendar.component(.year, from: .now)
        return Set(atlas.lines.map { calendar.component(.year, from: $0.start) }).filter { $0 != current }.sorted(by: >)
    }

    private var kinds: [RouteKind] {
        let interval = span.interval()
        let inSpan = everything.filter { line in interval.map { line.start >= $0.start && line.start < $0.end } ?? true }
        return RouteKind.allCases.filter { kind in kind == .all || inSpan.contains { kind.includes($0.mode) } }
    }

    private var days: Int {
        let calendar = Calendar.current
        return Set(shown.map { calendar.startOfDay(for: $0.start) }).count
    }

    /// "11月9日 – 15日" under the numbers, so it's plain which days are on the map.
    private var rangeText: String? {
        guard let interval = span.interval() else {
            guard let first = atlas.lines.first?.start else { return nil }
            return String(localized: "从 \(first.formatted(.dateTime.year().month().locale(appLocale))) 至今", bundle: .appLanguage)
        }
        let end = interval.end.addingTimeInterval(-1)
        switch span {
        case .today: return interval.start.formatted(.dateTime.month().day().weekday().locale(appLocale))
        case .week: return (interval.start..<end).formatted(.interval.month().day().locale(appLocale))
        case .month: return interval.start.formatted(.dateTime.year().month().locale(appLocale))
        case .year, .past: return interval.start.formatted(.dateTime.year().locale(appLocale))
        case .all: return nil
        }
    }

    private var controls: some View {
        VStack(spacing: 10) {
            spanPicker
            if kinds.count > 2 {
                ScrollView(.horizontal) {
                    HStack(spacing: 8) {
                        ForEach(kinds) { option in
                            Button {
                                withAnimation(.snappy) { kind = option }
                            } label: {
                                Label(option.title, systemImage: option.symbol)
                                    .font(.subheadline.weight(.semibold))
                                    .foregroundStyle(kind == option ? Color.black : .white)
                                    .padding(.horizontal, 14)
                                    .padding(.vertical, 9)
                                    .background {
                                        if kind == option { Capsule().fill(option.tint) }
                                    }
                                    .contentShape(.capsule)
                            }
                            .buttonStyle(.plain)
                            .glassEffect(.regular.interactive(), in: .capsule)
                        }
                    }
                    .padding(.horizontal)
                }
                .scrollIndicators(.hidden)
                .sensoryFeedback(.selection, trigger: kind)
            }
            HStack(alignment: .firstTextBaseline, spacing: 18) {
                stat(Format.distance(shown.reduce(0) { $0 + $1.distance }), caption: "走过")
                stat("\(days)", caption: "天")
                Spacer(minLength: 0)
                if let rangeText {
                    Text(verbatim: rangeText)
                        .font(.footnote.weight(.medium)).foregroundStyle(.white.opacity(0.65))
                        .contentTransition(.opacity)
                        .animation(.snappy, value: rangeText)
                        .lineLimit(1).minimumScaleFactor(0.8)
                }
            }
            .padding(.horizontal, 22)
            .padding(.vertical, 10)
            .glassEffect(.regular, in: .rect(cornerRadius: 26, style: .continuous))
            .padding(.horizontal)
        }
        .padding(.bottom, 8)
        .foregroundStyle(.white)
    }

    /// Today, this week, this month, this year, everything; earlier years behind the last one.
    private var spanPicker: some View {
        HStack(spacing: 2) {
            ForEach(RouteSpan.quick, id: \.self) { option in
                Button {
                    withAnimation(.snappy) { span = option }
                } label: {
                    Text(verbatim: option.title)
                        .font(.subheadline.weight(.semibold))
                        .foregroundStyle(span == option ? Color.black : .white)
                        .lineLimit(1).minimumScaleFactor(0.8)
                        .frame(maxWidth: .infinity)
                        .padding(.vertical, 9)
                        .background {
                            if span == option { Capsule().fill(RouteKind.all.tint) }
                        }
                        .contentShape(.capsule)
                }
                .buttonStyle(.plain)
                .accessibilityAddTraits(span == option ? .isSelected : [])
            }
            if !pastYears.isEmpty {
                Menu {
                    Picker("年份", selection: $span.animation(.snappy)) {
                        ForEach(pastYears, id: \.self) { Text(verbatim: "\($0)").tag(RouteSpan.past($0)) }
                    }
                } label: {
                    let picked: Int? = if case let .past(year) = span { year } else { nil }
                    HStack(spacing: 3) {
                        if let picked { Text(verbatim: "\(picked)").monospacedDigit() }
                        Image(systemName: picked == nil ? "calendar" : "chevron.up.chevron.down")
                            .font(picked == nil ? .subheadline.weight(.semibold) : .caption2.weight(.bold))
                    }
                    .font(.subheadline.weight(.semibold))
                    .foregroundStyle(picked == nil ? Color.white : .black)
                    .padding(.horizontal, 12)
                    .padding(.vertical, 9)
                    .background {
                        if picked != nil { Capsule().fill(RouteKind.all.tint) }
                    }
                    .contentShape(.capsule)
                }
                .accessibilityLabel("往年")
            }
        }
        .padding(4)
        .glassEffect(.regular, in: .capsule)
        .padding(.horizontal)
        .sensoryFeedback(.selection, trigger: span)
    }

    private func stat(_ value: String, caption: LocalizedStringKey) -> some View {
        VStack(alignment: .leading, spacing: 1) {
            Text(value)
                .font(.title3.weight(.bold))
                .monospacedDigit()
                .contentTransition(.numericText())
                .animation(.snappy, value: value)
            Text(caption).font(.caption).foregroundStyle(.white.opacity(0.6))
        }
    }

    private var empty: some View {
        VStack(spacing: 8) {
            Image(systemName: "point.topright.arrow.triangle.backward.to.point.bottomleft.scurvepath")
                .font(.largeTitle)
                .foregroundStyle(.white.opacity(0.5))
            let title: LocalizedStringKey = span == .all ? "这里还没有路线" : "这段时间还没有路线"
            Text(title).font(.headline).foregroundStyle(.white)
            Text("出门走走，路线会在这里亮起来。").font(.subheadline).foregroundStyle(.white.opacity(0.6))
        }
        .multilineTextAlignment(.center)
        .padding(28)
        .glassEffect(.regular, in: .rect(cornerRadius: 28, style: .continuous))
    }
}

/// How the roads were travelled, grouped the way a person thinks of them.
enum RouteKind: String, CaseIterable, Identifiable {
    case all, onFoot, cycling, driving, flying

    var id: String { rawValue }

    func includes(_ mode: MovementMode) -> Bool {
        switch self {
        case .all: true
        case .onFoot: mode == .walking || mode == .running
        case .cycling: mode == .cycling
        case .driving: mode == .automotive || mode == .subway
        case .flying: mode == .flying
        }
    }

    var title: LocalizedStringKey {
        switch self {
        case .all: "全部"
        case .onFoot: "步行"
        case .cycling: "骑行"
        case .driving: "乘车"
        case .flying: "飞行"
        }
    }

    var symbol: String {
        switch self {
        case .all: "sparkles"
        case .onFoot: "figure.walk"
        case .cycling: "bicycle"
        case .driving: "car.fill"
        case .flying: "airplane"
        }
    }

    /// The light the roads are drawn in.
    var tint: Color { Color(uiColor: lineColor(for: self == .flying ? .flying : .walking)) }

    func lineColor(for mode: MovementMode) -> UIColor {
        switch self {
        // One warm light for every road, a cooler one for the sky.
        case .all: mode == .flying ? UIColor(red: 0.72, green: 0.78, blue: 1, alpha: 1) : UIColor(red: 1, green: 0.80, blue: 0.42, alpha: 1)
        case .onFoot: UIColor(red: 0.45, green: 0.95, blue: 0.55, alpha: 1)
        case .cycling: UIColor(red: 0.35, green: 0.92, blue: 0.95, alpha: 1)
        case .driving: UIColor(red: 0.45, green: 0.68, blue: 1, alpha: 1)
        case .flying: UIColor(red: 0.80, green: 0.62, blue: 1, alpha: 1)
        }
    }
}

/// MapKit's own map view: one multi-line overlay per colour and layer draws tens of thousands
/// of roads in a handful of passes, which a SwiftUI map with a polyline each can't.
struct RouteAtlasMap: UIViewRepresentable {
    let lines: [AtlasLine]
    let kind: RouteKind
    /// Changes when the stretch of time does, so the map goes to where those roads are.
    var focus = ""
    var fitsWhole = false
    /// Every road there is, for somewhere familiar to show when the chosen days have none.
    var everywhere: [AtlasLine] = []

    func makeUIView(context: Context) -> MKMapView {
        let map = MKMapView()
        map.delegate = context.coordinator
        map.overrideUserInterfaceStyle = .dark
        let configuration = MKStandardMapConfiguration(elevationStyle: .flat, emphasisStyle: .muted)
        configuration.pointOfInterestFilter = .excludingAll
        configuration.showsTraffic = false
        map.preferredConfiguration = configuration
        map.showsUserLocation = false
        map.isPitchEnabled = false
        map.showsCompass = true
        map.showsScale = true
        // Above the controls, so the legal notice and compass stay clear of them.
        map.layoutMargins = UIEdgeInsets(top: 60, left: 8, bottom: 200, right: 8)
        // Night falls over the land and sea alone; the roads are drawn above it.
        map.addOverlay(Dusk.world(), level: .aboveRoads)
        return map
    }

    func updateUIView(_ map: MKMapView, context: Context) {
        context.coordinator.update(map, lines: lines, kind: kind, focus: focus, fitsWhole: fitsWhole, everywhere: everywhere)
    }

    func makeCoordinator() -> Coordinator { Coordinator() }

    @MainActor
    final class Coordinator: NSObject, MKMapViewDelegate {
        private var lines: [AtlasLine] = []
        private var kind: RouteKind = .all
        private var focus = ""
        private var framed = false
        private var atHome = false
        private var drawnKey: String?
        /// The whole-world overlays, kept: they're the slowest to make and the most revisited.
        private var countryCache: [String: [MKOverlay]] = [:]

        /// Each colour is spread over a few layers. A road travelled once is in one of them;
        /// one travelled a hundred times is in all of them, and so glows.
        private static let layers = 4

        func update(_ map: MKMapView, lines: [AtlasLine], kind: RouteKind, focus: String, fitsWhole: Bool, everywhere: [AtlasLine]) {
            let changed = lines.count != self.lines.count || lines.first?.start != self.lines.first?.start
                || lines.last?.start != self.lines.last?.start || kind != self.kind
                || lines.last?.distance != self.lines.last?.distance
            // A filter brings its own routes into view: a walk is invisible from a continent away,
            // so on foot and by bike the map goes to the place with the most of them. A different
            // stretch of time does the same: this week's roads may be a country away from this year's.
            let refilter = framed && (kind != self.kind || focus != self.focus) && !lines.isEmpty
            self.lines = lines
            self.kind = kind
            self.focus = focus
            if changed { countryCache = [:]; drawnKey = nil }
            let padding = UIEdgeInsets(top: 70, left: 30, bottom: 210, right: 30)
            if !framed, !lines.isEmpty {
                framed = true
                map.setVisibleMapRect(fitsWhole ? Self.whole(lines) : Self.framing(lines), edgePadding: padding, animated: atHome)
            } else if !framed, !atHome, !everywhere.isEmpty {
                // Nothing in these days yet: wait where life mostly is, not over some default sea.
                atHome = true
                map.setVisibleMapRect(Self.framing(everywhere), edgePadding: padding, animated: false)
            } else if refilter {
                let rect = fitsWhole ? Self.whole(lines)
                    : kind == .onFoot || kind == .cycling ? Self.busiestPlace(lines) : Self.framing(lines)
                map.setVisibleMapRect(rect, edgePadding: padding, animated: true)
            }
            redraw(map)
        }

        /// All of a few days' roads at once. A flight among them would shrink the walks to a
        /// dot, so it's left out of the frame when there's anything else.
        private static func whole(_ lines: [AtlasLine]) -> MKMapRect {
            let ground = lines.filter { $0.mode != .flying }
            var rect = MKMapRect.null
            for line in ground.isEmpty ? lines : ground {
                for corner in [CLLocationCoordinate2D(latitude: Double(line.box.minLat), longitude: Double(line.box.minLon)),
                               CLLocationCoordinate2D(latitude: Double(line.box.maxLat), longitude: Double(line.box.maxLon))] {
                    rect = rect.union(MKMapRect(origin: MKMapPoint(corner), size: MKMapSize(width: 0, height: 0)))
                }
            }
            let minimum = 1_500 * MKMapPointsPerMeterAtLatitude(rect.origin.coordinate.latitude)
            guard rect.width < minimum, rect.height < minimum else { return rect }
            return MKMapRect(x: rect.midX - minimum / 2, y: rect.midY - minimum / 2, width: minimum, height: minimum)
        }

        func mapView(_ map: MKMapView, regionDidChangeAnimated animated: Bool) {
            redraw(map)
        }

        private func detail(for map: MKMapView) -> AtlasLine.Detail {
            let span = map.region.span.latitudeDelta
            return span > 5 ? .country : span > 0.3 ? .city : .street
        }

        private func redraw(_ map: MKMapView) {
            let detail = detail(for: map)
            var box: AtlasBox?
            var key = "\(detail.rawValue)"
            if detail != .country {
                // A grid snapped view, so small pans don't rebuild anything.
                let region = map.region
                let step = region.span.latitudeDelta
                let lat = (region.center.latitude / step).rounded() * step
                let lon = (region.center.longitude / step).rounded() * step
                box = AtlasBox(minLat: Float(lat - step * 1.6), maxLat: Float(lat + step * 1.6),
                               minLon: Float(lon - region.span.longitudeDelta * 1.6), maxLon: Float(lon + region.span.longitudeDelta * 1.6))
                key += "|\(lat)|\(lon)|\(step)"
            }
            guard key != drawnKey else { return }
            drawnKey = key
            let overlays: [MKOverlay]
            if detail == .country, let cached = countryCache[key] {
                overlays = cached
            } else {
                let visible = box.map { box in lines.filter { box.intersects($0.box) } } ?? lines
                // Street detail across a dense city is too much to draw: a step back is plenty.
                let level = detail == .street && visible.count > 3_000 ? .city : detail
                overlays = Self.overlays(visible, detail: level, kind: kind)
                if detail == .country { countryCache[key] = overlays }
            }
            let old = map.overlays.filter { !($0 is Dusk) }
            map.addOverlays(overlays, level: .aboveRoads)
            map.removeOverlays(old)
        }

        private static func overlays(_ lines: [AtlasLine], detail: AtlasLine.Detail, kind: RouteKind) -> [MKOverlay] {
            var groups: [String: (color: UIColor, flying: Bool, lines: [MKPolyline])] = [:]
            for (index, line) in lines.enumerated() {
                var coordinates = line.coordinates(detail)
                guard coordinates.count > 1 else { continue }
                let flying = line.mode == .flying
                let polyline = flying ? MKGeodesicPolyline(coordinates: &coordinates, count: coordinates.count)
                                      : MKPolyline(coordinates: &coordinates, count: coordinates.count)
                let color = kind.lineColor(for: line.mode)
                // The colour follows from the kind and whether it flew.
                let key = "\(flying)|\(index % layers)"
                groups[key, default: (color, flying, [])].lines.append(polyline)
            }
            return groups.values.flatMap { group -> [MKOverlay] in
                // A soft halo under a fine bright core.
                [AtlasOverlay(group.lines, color: group.color, halo: true, flying: group.flying, detail: detail),
                 AtlasOverlay(group.lines, color: group.color, halo: false, flying: group.flying, detail: detail)]
            }
        }

        func mapView(_ map: MKMapView, rendererFor overlay: MKOverlay) -> MKOverlayRenderer {
            if overlay is Dusk {
                let renderer = MKPolygonRenderer(overlay: overlay)
                renderer.fillColor = UIColor(red: 0.02, green: 0.03, blue: 0.08, alpha: 0.55)
                return renderer
            }
            guard let overlay = overlay as? AtlasOverlay else { return MKOverlayRenderer(overlay: overlay) }
            let renderer = MKMultiPolylineRenderer(multiPolyline: overlay)
            let fine = overlay.detail == .street
            renderer.strokeColor = overlay.color.withAlphaComponent(overlay.halo ? 0.10 : (overlay.flying ? 0.35 : 0.42))
            renderer.lineWidth = overlay.halo ? (fine ? 7 : 5) : (overlay.flying ? 1 : (fine ? 2.2 : 1.6))
            renderer.lineCap = .round
            renderer.lineJoin = .round
            if overlay.flying, !overlay.halo { renderer.lineDashPattern = [2, 5] }
            return renderer
        }

        /// Opens on where the person has been lately, not on all of it at once.
        /// The routes in the roughly city-sized cell that holds the most of them.
        private static func busiestPlace(_ lines: [AtlasLine]) -> MKMapRect {
            let cells = Dictionary(grouping: lines) { line in
                [Int(((line.box.minLat + line.box.maxLat) / 2).rounded()), Int(((line.box.minLon + line.box.maxLon) / 2).rounded())]
            }
            var rect = MKMapRect.null
            for line in cells.values.max(by: { $0.count < $1.count }) ?? [] {
                for corner in [CLLocationCoordinate2D(latitude: Double(line.box.minLat), longitude: Double(line.box.minLon)),
                               CLLocationCoordinate2D(latitude: Double(line.box.maxLat), longitude: Double(line.box.maxLon))] {
                    rect = rect.union(MKMapRect(origin: MKMapPoint(corner), size: MKMapSize(width: 0, height: 0)))
                }
            }
            let minimum = 2_000 * MKMapPointsPerMeterAtLatitude(rect.origin.coordinate.latitude)
            guard rect.width < minimum, rect.height < minimum else { return rect }
            return MKMapRect(x: rect.midX - minimum / 2, y: rect.midY - minimum / 2, width: minimum, height: minimum)
        }

        private static func framing(_ lines: [AtlasLine]) -> MKMapRect {
            let year = Date().addingTimeInterval(-365 * 86_400)
            let recent = lines.filter { $0.start >= year && $0.mode != .flying }
            let pool = recent.isEmpty ? lines : recent
            let centers = pool.map { CLLocationCoordinate2D(latitude: Double($0.box.minLat + $0.box.maxLat) / 2,
                                                            longitude: Double($0.box.minLon + $0.box.maxLon) / 2) }
            let main = TrackMap.mainRegion(centers, stays: centers)
            var rect = MKMapRect.null
            for c in main { rect = rect.union(MKMapRect(origin: MKMapPoint(c), size: MKMapSize(width: 0, height: 0))) }
            let minimum = 4_000 * MKMapPointsPerMeterAtLatitude(main.first?.latitude ?? 0)
            if rect.width < minimum || rect.height < minimum {
                let side = max(rect.width, rect.height, minimum)
                rect = MKMapRect(x: rect.midX - side / 2, y: rect.midY - side / 2, width: side, height: side)
            }
            return rect
        }
    }
}

/// The whole world, dimmed.
private final class Dusk: MKPolygon {
    static func world() -> Dusk {
        let world = MKMapRect.world
        var corners = [MKMapPoint(x: world.minX, y: world.minY), MKMapPoint(x: world.maxX, y: world.minY),
                       MKMapPoint(x: world.maxX, y: world.maxY), MKMapPoint(x: world.minX, y: world.maxY)]
        return Dusk(points: &corners, count: corners.count)
    }
}

private final class AtlasOverlay: MKMultiPolyline {
    let color: UIColor
    let halo: Bool
    let flying: Bool
    let detail: AtlasLine.Detail

    init(_ lines: [MKPolyline], color: UIColor, halo: Bool, flying: Bool, detail: AtlasLine.Detail) {
        self.color = color
        self.halo = halo
        self.flying = flying
        self.detail = detail
        super.init(lines)
    }
}

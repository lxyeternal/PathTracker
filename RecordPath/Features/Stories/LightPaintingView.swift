import SwiftUI
import SwiftData
import CoreLocation

struct LightPaintingRoute: Hashable {}

/// Every way the person has gone, drawn as light on black like a long exposure: streets walked
/// every day burn brightest, a single trip is a thin thread, and the places stopped at are
/// stars among them. No map underneath, only the paths.
struct LightPainting: Sendable {
    /// Lines in poster space, 0…1 both ways (y down), with how each was travelled.
    var lines: [(points: [CGPoint], mode: MovementMode)] = []
    /// Places stopped at, in the same space.
    var places: [CGPoint] = []
    var distance = 0.0
    var center: CLLocationCoordinate2D?

    enum Scope: String, CaseIterable, Identifiable {
        case city, everywhere
        var id: String { rawValue }
        var title: String {
            switch self {
            case .city: String(localized: "常在的城市", bundle: .appLanguage)
            case .everywhere: String(localized: "所有足迹", bundle: .appLanguage)
            }
        }
    }

    enum Palette: String, CaseIterable, Identifiable {
        case gold, moonlight, neon
        var id: String { rawValue }
        var title: String {
            switch self {
            case .gold: String(localized: "金色", bundle: .appLanguage)
            case .moonlight: String(localized: "月光", bundle: .appLanguage)
            case .neon: String(localized: "霓虹", bundle: .appLanguage)
            }
        }
        var background: [Color] {
            switch self {
            case .gold: [Color(red: 0.03, green: 0.02, blue: 0.04), Color(red: 0.08, green: 0.05, blue: 0.06)]
            case .moonlight: [Color(red: 0.02, green: 0.04, blue: 0.08), Color(red: 0.04, green: 0.07, blue: 0.14)]
            case .neon: [Color(red: 0.03, green: 0.02, blue: 0.08), Color(red: 0.07, green: 0.03, blue: 0.12)]
            }
        }
        var ink: Color {
            switch self {
            case .gold: Color(red: 1, green: 0.88, blue: 0.7)
            case .moonlight: Color(red: 0.86, green: 0.93, blue: 1)
            case .neon: Color(red: 1, green: 0.85, blue: 0.95)
            }
        }
        func tint(_ mode: MovementMode) -> Color {
            switch self {
            case .gold: Color(red: 1, green: 0.76, blue: 0.42)
            case .moonlight: Color(red: 0.7, green: 0.85, blue: 1)
            case .neon:
                switch mode {
                case .walking, .running: Color(red: 0.45, green: 1, blue: 0.65)
                case .cycling: Color(red: 0.3, green: 0.95, blue: 1)
                case .automotive, .subway: Color(red: 1, green: 0.4, blue: 0.75)
                default: Color(red: 1, green: 0.8, blue: 0.45)
                }
            }
        }
    }

    /// Reads tracks and places on a background context and lays them out for a 9:16 poster.
    static func make(container: ModelContainer, since: Date?, scope: Scope, home: CLLocationCoordinate2D?) async -> LightPainting {
        await Task.detached(priority: .userInitiated) {
            let context = ModelContext(container)
            let flying = MovementMode.flying.rawValue
            let start = since ?? .distantPast
            let chunks = (try? context.fetch(FetchDescriptor<TrackChunk>(predicate: #Predicate { $0.modeRaw != flying && $0.startDate >= start }))) ?? []
            let stays = (try? context.fetch(FetchDescriptor<Stay>(predicate: #Predicate { $0.arrival >= start }))) ?? []
            var tracks = chunks.map { (points: $0.points.simplified(tolerance: 8).map(\.coordinate), mode: $0.mode) }
            var spots = stays.map(\.coordinate)

            let center = scope == .city ? (home ?? busiest(tracks.flatMap(\.points))) : nil
            if let center {
                // Within ~30 km of home: a city and its suburbs.
                let limit = 0.3, lonLimit = 0.3 / cos(center.latitude * .pi / 180)
                func near(_ c: CLLocationCoordinate2D) -> Bool { abs(c.latitude - center.latitude) < limit && abs(c.longitude - center.longitude) < lonLimit }
                tracks = tracks.map { ($0.points.filter(near), $0.mode) }
                spots = spots.filter(near)
            }
            tracks = tracks.filter { $0.points.count > 1 }
            var painting = LightPainting()
            painting.center = center
            painting.distance = tracks.reduce(0) { total, track in
                total + zip(track.points, track.points.dropFirst()).reduce(0) {
                    $0 + CLLocation(latitude: $1.0.latitude, longitude: $1.0.longitude).distance(from: CLLocation(latitude: $1.1.latitude, longitude: $1.1.longitude))
                }
            }
            guard let place = layout(tracks.flatMap(\.points)) else { return painting }
            painting.lines = tracks.map { (track: (points: [CLLocationCoordinate2D], mode: MovementMode)) in (track.points.map(place), track.mode) }
            painting.places = spots.map(place).filter { (0...1).contains($0.x) && (0...1).contains($0.y) }
            return painting
        }.value
    }

    /// The ~10 km square with the most track in it.
    private static func busiest(_ points: [CLLocationCoordinate2D]) -> CLLocationCoordinate2D? {
        var counts: [Int64: (Int, CLLocationCoordinate2D)] = [:]
        for point in points {
            let key = Int64((point.latitude / 0.1).rounded(.down)) &* 100_003 &+ Int64((point.longitude / 0.1).rounded(.down))
            counts[key] = ((counts[key]?.0 ?? 0) + 1, counts[key]?.1 ?? point)
        }
        return counts.values.max { $0.0 < $1.0 }?.1
    }

    /// Mercator, fitted into a 9:16 frame with a margin and room at the bottom for the title.
    private static func layout(_ points: [CLLocationCoordinate2D]) -> ((CLLocationCoordinate2D) -> CGPoint)? {
        func project(_ c: CLLocationCoordinate2D) -> CGPoint {
            let lat = max(-85, min(85, c.latitude)) * .pi / 180
            return CGPoint(x: c.longitude / 360, y: -log(tan(.pi / 4 + lat / 2)) / (2 * .pi))
        }
        let all = points.map(project)
        guard let minX = all.map(\.x).min(), let maxX = all.map(\.x).max(),
              let minY = all.map(\.y).min(), let maxY = all.map(\.y).max() else { return nil }
        let aspect = 9.0 / 16.0, margin = 0.1
        let width = max(maxX - minX, 1e-9), height = max(maxY - minY, 1e-9)
        // A unit across is 16/9 times as long on paper as a unit down, so y takes less of it.
        let scale = min((1 - 2 * margin) / width, (0.78 - margin) / (height * aspect))
        let scaleY = scale * aspect
        let offsetX = (1 - width * scale) / 2, offsetY = margin + ((0.78 - margin) - height * scaleY) / 2
        return { c in
            let p = project(c)
            return CGPoint(x: offsetX + (p.x - minX) * scale, y: offsetY + (p.y - minY) * scaleY)
        }
    }
}

/// The painting itself, at any size.
struct LightPoster: View {
    let painting: LightPainting
    let title: String
    let subtitle: String
    var palette: LightPainting.Palette = .gold

    var body: some View {
        GeometryReader { geo in
            let unit = geo.size.width / 360
            ZStack(alignment: .bottom) {
                LinearGradient(colors: palette.background, startPoint: .top, endPoint: .bottom)
                Canvas { context, size in
                    func path(_ points: [CGPoint]) -> Path {
                        var path = Path()
                        path.addLines(points.map { CGPoint(x: $0.x * size.width, y: $0.y * size.height) })
                        return path
                    }
                    // A wide soft glow, then the bright core; overlapping paths add up like light.
                    context.drawLayer { layer in
                        layer.addFilter(.blur(radius: 6 * unit))
                        layer.blendMode = .plusLighter
                        for line in painting.lines {
                            layer.stroke(path(line.points), with: .color(palette.tint(line.mode).opacity(0.2)),
                                         style: StrokeStyle(lineWidth: 3.5 * unit, lineCap: .round, lineJoin: .round))
                        }
                    }
                    context.drawLayer { layer in
                        layer.blendMode = .plusLighter
                        for line in painting.lines {
                            layer.stroke(path(line.points), with: .color(palette.tint(line.mode).opacity(0.5)),
                                         style: StrokeStyle(lineWidth: 0.9 * unit, lineCap: .round, lineJoin: .round))
                        }
                    }
                    // The places, as stars.
                    context.drawLayer { layer in
                        layer.blendMode = .plusLighter
                        for place in painting.places {
                            let p = CGPoint(x: place.x * size.width, y: place.y * size.height)
                            let r = 5 * unit
                            layer.fill(Path(ellipseIn: CGRect(x: p.x - r, y: p.y - r, width: r * 2, height: r * 2)),
                                       with: .radialGradient(Gradient(colors: [palette.ink.opacity(0.5), .clear]), center: p, startRadius: 0, endRadius: r))
                            layer.fill(Path(ellipseIn: CGRect(x: p.x - 1.1 * unit, y: p.y - 1.1 * unit, width: 2.2 * unit, height: 2.2 * unit)),
                                       with: .color(.white.opacity(0.9)))
                        }
                    }
                }
                // A thin frame inside the edge, like a print.
                Rectangle()
                    .strokeBorder(palette.ink.opacity(0.18), lineWidth: 0.8 * unit)
                    .padding(14 * unit)
                VStack(spacing: 7 * unit) {
                    Text(title)
                        .font(.system(size: 24 * unit, weight: .semibold, design: .serif))
                        .tracking(6 * unit)
                    Rectangle().fill(palette.ink.opacity(0.4)).frame(width: 28 * unit, height: 0.8 * unit)
                    Text(subtitle)
                        .font(.system(size: 9.5 * unit, weight: .medium))
                        .tracking(2.5 * unit)
                        .opacity(0.65)
                    if let center = painting.center {
                        Text(coordinates(center))
                            .font(.system(size: 8 * unit, weight: .regular, design: .monospaced))
                            .tracking(1.5 * unit)
                            .opacity(0.4)
                    }
                }
                .foregroundStyle(palette.ink)
                .padding(.bottom, 40 * unit)
            }
        }
        .aspectRatio(9 / 16, contentMode: .fit)
    }

    private func coordinates(_ c: CLLocationCoordinate2D) -> String {
        String(format: "%.2f°%@  %.2f°%@", abs(c.latitude), c.latitude >= 0 ? "N" : "S", abs(c.longitude), c.longitude >= 0 ? "E" : "W")
    }
}

/// A card that opens the poster.
struct LightPaintingCard: View {
    var body: some View {
        NavigationLink(value: LightPaintingRoute()) {
            HStack(spacing: 14) {
                ZStack {
                    RoundedRectangle(cornerRadius: 14, style: .continuous).fill(Color(red: 0.03, green: 0.03, blue: 0.08))
                    Image(systemName: "scribble.variable")
                        .font(.system(size: 26, weight: .semibold))
                        .foregroundStyle(LinearGradient(colors: [Color(red: 1, green: 0.85, blue: 0.5), Color(red: 1, green: 0.55, blue: 0.3)],
                                                        startPoint: .top, endPoint: .bottom))
                        .shadow(color: .orange.opacity(0.8), radius: 6)
                }
                .frame(width: 56, height: 72)
                VStack(alignment: .leading, spacing: 3) {
                    Text("光绘").font(.system(.headline, design: .serif)).foregroundStyle(.primary)
                    Text("把走过的路画成一张光的海报，常走的路最亮。").font(.subheadline).foregroundStyle(.secondary)
                        .multilineTextAlignment(.leading)
                }
                Spacer(minLength: 0)
                Image(systemName: "chevron.right").font(.caption.weight(.semibold)).foregroundStyle(.tertiary)
            }
            .padding(14)
            .background(.background.secondary, in: .rect(cornerRadius: 24, style: .continuous))
        }
        .buttonStyle(PressableStyle())
    }
}

/// The poster on a dark wall, with what to draw and in which light below it.
struct LightPaintingView: View {
    let home: HomeBase?
    @Environment(\.modelContext) private var context
    @State private var scope: LightPainting.Scope = .city
    @State private var thisYear = true
    @State private var palette: LightPainting.Palette = .gold
    @State private var painting: LightPainting?
    @State private var image: Image?

    private var year: Int { Calendar.current.component(.year, from: Date()) }

    private var title: String {
        scope == .city ? (home?.city ?? String(localized: "我的城市", bundle: .appLanguage))
                       : String(localized: "我的足迹", bundle: .appLanguage)
    }

    private var subtitle: String {
        let when = thisYear ? String(year) : String(localized: "一直以来", bundle: .appLanguage)
        return "\(when) · \(Format.distance(painting?.distance ?? 0))"
    }

    var body: some View {
        ScrollView {
            VStack(spacing: 22) {
                ZStack {
                    if let painting {
                        LightPoster(painting: painting, title: title, subtitle: subtitle, palette: palette)
                            .transition(.opacity.combined(with: .scale(scale: 0.97)))
                    } else {
                        LinearGradient(colors: palette.background, startPoint: .top, endPoint: .bottom)
                            .aspectRatio(9 / 16, contentMode: .fit)
                        ProgressView().tint(.white)
                    }
                }
                .clipShape(.rect(cornerRadius: 6))
                .shadow(color: palette.tint(.walking).opacity(0.25), radius: 30, y: 10)
                .padding(.horizontal, 40)
                .padding(.top, 8)
                .animation(.smooth(duration: 0.8), value: painting == nil)
                .animation(.smooth(duration: 0.5), value: palette)

                if let painting, painting.lines.isEmpty {
                    Text("这段时间还没有轨迹。开着自动记录走一走，光就会出现。")
                        .font(.subheadline).foregroundStyle(.white.opacity(0.6)).multilineTextAlignment(.center)
                        .padding(.horizontal, 32)
                }

                VStack(spacing: 14) {
                    chips(LightPainting.Scope.allCases, selection: $scope) { $0.title }
                    chips([true, false], selection: $thisYear) { $0 ? String(year) : String(localized: "一直以来", bundle: .appLanguage) }
                    HStack(spacing: 12) {
                        ForEach(LightPainting.Palette.allCases) { option in
                            Button { withAnimation(.smooth) { palette = option } } label: {
                                VStack(spacing: 6) {
                                    Circle()
                                        .fill(LinearGradient(colors: [option.tint(.walking), option.tint(.automotive)], startPoint: .topLeading, endPoint: .bottomTrailing))
                                        .frame(width: 30, height: 30)
                                        .shadow(color: option.tint(.walking).opacity(0.7), radius: palette == option ? 8 : 0)
                                        .overlay(Circle().stroke(.white, lineWidth: palette == option ? 2 : 0).padding(-4))
                                    Text(option.title).font(.caption).foregroundStyle(.white.opacity(palette == option ? 1 : 0.6))
                                }
                                .frame(width: 64)
                            }
                            .buttonStyle(.plain)
                        }
                    }
                    .padding(.top, 4)
                }
                .padding(.horizontal)

                if let image {
                    ShareLink(item: image, preview: SharePreview(title, image: image)) {
                        Label("分享这张海报", systemImage: "square.and.arrow.up")
                            .frame(maxWidth: .infinity)
                    }
                    .buttonStyle(.glassProminent)
                    .controlSize(.large)
                    .tint(palette.tint(.walking).opacity(0.9))
                    .padding(.horizontal, 40)
                }
            }
            .padding(.bottom, 32)
        }
        .background(Color(red: 0.02, green: 0.02, blue: 0.04).ignoresSafeArea())
        .toolbarColorScheme(.dark, for: .navigationBar)
        .navigationTitle("光绘")
        .navigationBarTitleDisplayMode(.inline)
        .environment(\.colorScheme, .dark)
        .task(id: "\(scope.rawValue)\(thisYear)") {
            painting = nil
            image = nil
            let since = thisYear ? Calendar.current.date(from: DateComponents(year: year, month: 1, day: 1)) : nil
            let home = home.map { CLLocationCoordinate2D(latitude: $0.latitude, longitude: $0.longitude) }
            painting = await LightPainting.make(container: context.container, since: since, scope: scope, home: home)
            render()
        }
        .onChange(of: palette) { render() }
    }

    /// A row of capsules to pick one of.
    private func chips<T: Hashable>(_ options: [T], selection: Binding<T>, title: @escaping (T) -> String) -> some View {
        HStack(spacing: 8) {
            ForEach(options, id: \.self) { option in
                let selected = selection.wrappedValue == option
                Button { withAnimation(.snappy) { selection.wrappedValue = option } } label: {
                    Text(title(option))
                        .font(.subheadline.weight(.semibold))
                        .foregroundStyle(selected ? .black : .white.opacity(0.75))
                        .padding(.horizontal, 16).padding(.vertical, 8)
                        .background(Capsule().fill(selected ? AnyShapeStyle(.white) : AnyShapeStyle(.white.opacity(0.1))))
                }
                .buttonStyle(.plain)
            }
        }
    }

    @MainActor private func render() {
        guard let painting, !painting.lines.isEmpty else { image = nil; return }
        let renderer = ImageRenderer(content: LightPoster(painting: painting, title: title, subtitle: subtitle, palette: palette)
            .frame(width: 360, height: 640)
            .environment(\.locale, appLocale))
        renderer.scale = 3
        image = renderer.uiImage.map { Image(uiImage: $0) }
    }
}

import SwiftUI
import SwiftData
import CoreLocation

struct LightPaintingRoute: Hashable {}

/// Every way the person has gone, drawn as light on black like a long exposure: streets walked
/// every day burn brightest, a single trip is a thin thread. No map underneath, only the paths.
struct LightPainting: Sendable {
    /// Lines in poster space, 0…1 both ways (y down), with how each was travelled.
    var lines: [(points: [CGPoint], mode: MovementMode)] = []
    var distance = 0.0
    var count = 0

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

    /// Reads the tracks on a background context and lays them out for a 9:16 poster.
    static func make(container: ModelContainer, since: Date?, scope: Scope, home: CLLocationCoordinate2D?) async -> LightPainting {
        await Task.detached(priority: .userInitiated) {
            let context = ModelContext(container)
            let flying = MovementMode.flying.rawValue
            let start = since ?? .distantPast
            let chunks = (try? context.fetch(FetchDescriptor<TrackChunk>(predicate: #Predicate { $0.modeRaw != flying && $0.startDate >= start }))) ?? []
            var tracks = chunks.map { (points: $0.points.simplified(tolerance: 8).map(\.coordinate), mode: $0.mode) }

            if scope == .city, let center = home ?? busiest(tracks.flatMap(\.points)) {
                // Within ~30 km of home, a city and its suburbs.
                let limit = 0.3
                tracks = tracks.map { track in
                    (track.points.filter { abs($0.latitude - center.latitude) < limit && abs($0.longitude - center.longitude) < limit / cos(center.latitude * .pi / 180) }, track.mode)
                }
            }
            tracks = tracks.filter { $0.points.count > 1 }
            var painting = LightPainting()
            painting.count = tracks.count
            painting.distance = tracks.reduce(0) { total, track in
                total + zip(track.points, track.points.dropFirst()).reduce(0) {
                    $0 + CLLocation(latitude: $1.0.latitude, longitude: $1.0.longitude).distance(from: CLLocation(latitude: $1.1.latitude, longitude: $1.1.longitude))
                }
            }
            painting.lines = layout(tracks)
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

    /// Mercator, fitted into a 9:16 frame with a margin, centred.
    private static func layout(_ tracks: [(points: [CLLocationCoordinate2D], mode: MovementMode)]) -> [(points: [CGPoint], mode: MovementMode)] {
        func project(_ c: CLLocationCoordinate2D) -> CGPoint {
            let lat = max(-85, min(85, c.latitude)) * .pi / 180
            return CGPoint(x: c.longitude / 360, y: -log(tan(.pi / 4 + lat / 2)) / (2 * .pi))
        }
        let projected = tracks.map { (points: $0.points.map(project), mode: $0.mode) }
        let all = projected.flatMap(\.points)
        guard let minX = all.map(\.x).min(), let maxX = all.map(\.x).max(),
              let minY = all.map(\.y).min(), let maxY = all.map(\.y).max() else { return [] }
        let aspect = 9.0 / 16.0, margin = 0.1
        let width = max(maxX - minX, 1e-9), height = max(maxY - minY, 1e-9)
        // One scale for both axes, so streets keep their shape.
        // A unit across is 16/9 times as long on paper as a unit down, so y takes less of it.
        let scale = min((1 - 2 * margin) / width, (1 - 2 * margin) / (height * aspect))
        let scaleY = scale * aspect
        let offsetX = (1 - width * scale) / 2, offsetY = (1 - height * scaleY) / 2 - 0.04
        return projected.map { track in
            (track.points.map { CGPoint(x: offsetX + ($0.x - minX) * scale, y: offsetY + ($0.y - minY) * scaleY) }, track.mode)
        }
    }
}

/// The painting itself, at any size.
struct LightPoster: View {
    let painting: LightPainting
    let title: String
    let subtitle: String
    var colorful = false

    var body: some View {
        ZStack(alignment: .bottom) {
            Color(red: 0.02, green: 0.02, blue: 0.05)
            Canvas { context, size in
                func path(_ points: [CGPoint]) -> Path {
                    var path = Path()
                    path.addLines(points.map { CGPoint(x: $0.x * size.width, y: $0.y * size.height) })
                    return path
                }
                let unit = size.width / 360
                // Glow first, then the bright core; overlapping paths add up like light.
                context.drawLayer { layer in
                    layer.addFilter(.blur(radius: 5 * unit))
                    layer.blendMode = .plusLighter
                    for line in painting.lines {
                        layer.stroke(path(line.points), with: .color(tint(line.mode).opacity(0.22)),
                                     style: StrokeStyle(lineWidth: 3 * unit, lineCap: .round, lineJoin: .round))
                    }
                }
                context.drawLayer { layer in
                    layer.blendMode = .plusLighter
                    for line in painting.lines {
                        layer.stroke(path(line.points), with: .color(tint(line.mode).opacity(0.45)),
                                     style: StrokeStyle(lineWidth: 0.9 * unit, lineCap: .round, lineJoin: .round))
                    }
                }
            }
            VStack(spacing: 4) {
                Text(title)
                    .font(.system(size: 22, weight: .semibold, design: .serif))
                    .tracking(3)
                Text(subtitle)
                    .font(.system(size: 10, weight: .medium))
                    .tracking(2)
                    .opacity(0.6)
            }
            .foregroundStyle(Color(red: 1, green: 0.9, blue: 0.75))
            .padding(.bottom, 34)
        }
        .aspectRatio(9 / 16, contentMode: .fit)
    }

    private func tint(_ mode: MovementMode) -> Color {
        guard colorful else { return Color(red: 1, green: 0.78, blue: 0.45) }
        return switch mode {
        case .walking, .running: Color(red: 0.5, green: 1, blue: 0.6)
        case .cycling: Color(red: 0.35, green: 0.95, blue: 1)
        case .automotive, .subway: Color(red: 0.55, green: 0.65, blue: 1)
        default: Color(red: 1, green: 0.78, blue: 0.45)
        }
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
                    Text("光绘").font(.headline).foregroundStyle(.primary)
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

struct LightPaintingView: View {
    let home: HomeBase?
    @Environment(\.modelContext) private var context
    @State private var scope: LightPainting.Scope = .city
    @State private var thisYear = true
    @State private var colorful = false
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
            VStack(spacing: 20) {
                ZStack {
                    if let painting {
                        LightPoster(painting: painting, title: title, subtitle: subtitle, colorful: colorful)
                            .transition(.opacity)
                    } else {
                        Color(red: 0.02, green: 0.02, blue: 0.05).aspectRatio(9 / 16, contentMode: .fit)
                        ProgressView().tint(.white)
                    }
                }
                .clipShape(.rect(cornerRadius: 22, style: .continuous))
                .shadow(color: .black.opacity(0.25), radius: 16, y: 8)
                .padding(.horizontal, 36)
                .animation(.smooth(duration: 0.8), value: painting == nil)

                if let painting, painting.lines.isEmpty {
                    Text("这段时间还没有轨迹。开着自动记录走一走，光就会出现。")
                        .font(.subheadline).foregroundStyle(.secondary).multilineTextAlignment(.center)
                }

                VStack(spacing: 12) {
                    Picker("范围", selection: $scope) {
                        ForEach(LightPainting.Scope.allCases) { Text($0.title).tag($0) }
                    }
                    Picker("时间", selection: $thisYear) {
                        Text(verbatim: String(year)).tag(true)
                        Text("一直以来").tag(false)
                    }
                    Toggle("按出行方式上色", isOn: $colorful.animation())
                }
                .pickerStyle(.segmented)
                .padding(.horizontal)

                if let image {
                    ShareLink(item: image, preview: SharePreview(title, image: image)) {
                        Label("分享这张海报", systemImage: "square.and.arrow.up")
                            .frame(maxWidth: .infinity)
                    }
                    .buttonStyle(.glassProminent)
                    .controlSize(.large)
                    .padding(.horizontal)
                }
            }
            .padding(.vertical)
        }
        .navigationTitle("光绘")
        .navigationBarTitleDisplayMode(.inline)
        .task(id: "\(scope.rawValue)\(thisYear)") {
            painting = nil
            image = nil
            let since = thisYear ? Calendar.current.date(from: DateComponents(year: year, month: 1, day: 1)) : nil
            let home = home.map { CLLocationCoordinate2D(latitude: $0.latitude, longitude: $0.longitude) }
            painting = await LightPainting.make(container: context.container, since: since, scope: scope, home: home)
            render()
        }
        .onChange(of: colorful) { render() }
    }

    @MainActor private func render() {
        guard let painting, !painting.lines.isEmpty else { image = nil; return }
        let renderer = ImageRenderer(content: LightPoster(painting: painting, title: title, subtitle: subtitle, colorful: colorful)
            .frame(width: 360, height: 640)
            .environment(\.locale, appLocale))
        renderer.scale = 3
        image = renderer.uiImage.map { Image(uiImage: $0) }
    }
}

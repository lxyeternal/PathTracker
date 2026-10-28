import SwiftUI
import MapKit
import Photos

// The year-report pages after the cover. Each is one picture you could screenshot: a dark,
// moving scene with one big number and one line of meaning, coming in piece by piece.

// MARK: - Shared pieces

/// A dark map with routes and pins already projected onto it, in 0–1 coordinates of the image.
struct MapBackdrop {
    let image: UIImage
    let lines: [[CGPoint]]
    let pins: [CGPoint]

    @MainActor
    static func render(region: MKCoordinateRegion, size: CGSize,
                       lines: [[CLLocationCoordinate2D]] = [], pins: [CLLocationCoordinate2D] = [], dark: Bool = true) async -> MapBackdrop? {
        let options = MKMapSnapshotter.Options()
        options.region = region
        options.size = size
        options.traitCollection = UITraitCollection(userInterfaceStyle: dark ? .dark : .light)
        let configuration = MKStandardMapConfiguration(elevationStyle: .flat, emphasisStyle: .muted)
        configuration.pointOfInterestFilter = .excludingAll
        options.preferredConfiguration = configuration
        guard let snapshot = try? await MKMapSnapshotter(options: options).start() else { return nil }
        func unit(_ c: CLLocationCoordinate2D) -> CGPoint {
            let p = snapshot.point(for: c.onMap)
            return CGPoint(x: p.x / size.width, y: p.y / size.height)
        }
        return MapBackdrop(image: snapshot.image, lines: lines.map { $0.map(unit) }, pins: pins.map(unit))
    }

    /// A region around some coordinates, the subject in the upper part of the screen so the
    /// words below don't cover it.
    static func region(around coordinates: [CLLocationCoordinate2D], size: CGSize, minimumSpan: Double, lift: Double = 0.18) -> MKCoordinateRegion? {
        let lats = coordinates.map(\.latitude), lons = coordinates.map(\.longitude)
        guard let minLat = lats.min(), let maxLat = lats.max(), let minLon = lons.min(), let maxLon = lons.max() else { return nil }
        let aspect = size.height / max(size.width, 1)
        let lonSpan = max((maxLon - minLon) * 1.5, minimumSpan)
        let latSpan = max((maxLat - minLat) * 2.2, lonSpan * aspect * 0.8, minimumSpan)
        return MKCoordinateRegion(center: CLLocationCoordinate2D(latitude: (minLat + maxLat) / 2 - latSpan * lift, longitude: (minLon + maxLon) / 2),
                                  span: MKCoordinateSpan(latitudeDelta: min(latSpan, 150), longitudeDelta: min(lonSpan, 340)))
    }
}

/// A backdrop filling the page, drifting slowly closer, darkened toward the bottom.
private struct BackdropImage: View {
    let image: UIImage
    let isActive: Bool

    var body: some View {
        ZStack {
            Image(uiImage: image)
                .resizable()
                .scaledToFill()
                .scaleEffect(isActive ? 1.06 : 1)
                .animation(.easeInOut(duration: 12), value: isActive)
            LinearGradient(stops: [.init(color: .black.opacity(0.45), location: 0), .init(color: .clear, location: 0.22),
                                   .init(color: .black.opacity(0.15), location: 0.5), .init(color: .black.opacity(0.88), location: 0.82)],
                           startPoint: .top, endPoint: .bottom)
        }
        .ignoresSafeArea()
    }
}

private struct PageText<Content: View>: View {
    @ViewBuilder let content: Content

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            Spacer()
            content
        }
        .foregroundStyle(.white)
        .padding(.horizontal, 28)
        .padding(.bottom, 64)
        .frame(maxWidth: .infinity, alignment: .leading)
    }
}

private struct StoryNumber: View, Animatable {
    var value: Double
    var unit: String = ""
    var decimals = 0
    var size: CGFloat = 84

    var animatableData: Double {
        get { value }
        set { value = newValue }
    }

    var body: some View {
        HStack(alignment: .firstTextBaseline, spacing: 8) {
            Text(value.formatted(.number.precision(.fractionLength(decimals)).locale(appLocale)))
                .font(.system(size: size, weight: .black, design: .rounded))
                .minimumScaleFactor(0.4)
                .lineLimit(1)
            if !unit.isEmpty {
                Text(unit).font(.system(size: size * 0.32, weight: .heavy, design: .rounded)).opacity(0.8)
            }
        }
    }
}

private extension View {
    func comesIn(_ isActive: Bool, after delay: Double = 0, from offset: CGFloat = 26) -> some View {
        self
            .opacity(isActive ? 1 : 0)
            .offset(y: isActive ? 0 : offset)
            .blur(radius: isActive ? 0 : 8)
            .animation(.spring(response: 0.8, dampingFraction: 0.85).delay(isActive ? delay : 0), value: isActive)
    }
}

private struct Kicker: View {
    let text: LocalizedStringKey
    var tint: Color = .white

    var body: some View {
        Text(text)
            .textCase(.uppercase)
            .font(.footnote.weight(.bold))
            .tracking(2.5)
            .foregroundStyle(tint)
    }
}

// MARK: - Distance: a dotted globe and the orbit you made

struct StoryDistancePage: View {
    let report: YearReport
    let isActive: Bool

    var body: some View {
        ZStack {
            RadialGradient(colors: [Color(red: 0.05, green: 0.2, blue: 0.4), .black], center: .init(x: 0.5, y: 0.32), startRadius: 10, endRadius: 520)
                .ignoresSafeArea()
            StarField().ignoresSafeArea().opacity(0.6)
            DottedGlobe(progress: isActive ? min(report.shareOfEquator, 1) : 0)
                .frame(width: 300, height: 300)
                .position(x: UIScreen.main.bounds.width / 2, y: UIScreen.main.bounds.height * 0.32)
                .scaleEffect(isActive ? 1 : 0.85)
                .opacity(isActive ? 1 : 0)
                .animation(.spring(response: 1.2, dampingFraction: 0.8), value: isActive)
            PageText {
                Kicker(text: "这一年你移动了", tint: Color(red: 0.5, green: 0.85, blue: 1)).comesIn(isActive, after: 0.2)
                StoryNumber(value: isActive ? report.distance / 1000 : 0, unit: String(localized: "公里", bundle: .appLanguage))
                    .animation(.easeOut(duration: 1.8).delay(0.3), value: isActive)
                Text("地面上的路程相当于绕赤道 \(report.shareOfEquator.formatted(.percent.precision(.fractionLength(0...1)).locale(appLocale)))")
                    .font(.title3.weight(.semibold)).foregroundStyle(.white.opacity(0.85))
                    .comesIn(isActive, after: 0.7)
                if report.flightDistance > 0 {
                    Label("另外飞行 \(Format.distance(report.flightDistance))", systemImage: "airplane")
                        .font(.subheadline.weight(.semibold))
                        .padding(.horizontal, 14).padding(.vertical, 8)
                        .glassEffect(.regular, in: .capsule)
                        .comesIn(isActive, after: 0.95)
                }
            }
        }
    }
}

/// A turning globe of dots, with a bright orbit traced as far as `progress` goes.
private struct DottedGlobe: View {
    var progress: Double

    var body: some View {
        TimelineView(.animation(minimumInterval: 1 / 30)) { timeline in
            let spin = timeline.date.timeIntervalSinceReferenceDate * 0.25
            Canvas { context, size in
                let r = min(size.width, size.height) / 2 * 0.78
                let c = CGPoint(x: size.width / 2, y: size.height / 2)
                // Atmosphere.
                context.fill(Path(ellipseIn: CGRect(x: c.x - r * 1.12, y: c.y - r * 1.12, width: r * 2.24, height: r * 2.24)),
                             with: .radialGradient(Gradient(colors: [Color(red: 0.3, green: 0.7, blue: 1).opacity(0.35), .clear]),
                                                   center: c, startRadius: r * 0.9, endRadius: r * 1.12))
                let tilt = 0.4
                for latStep in stride(from: -78.0, through: 78.0, by: 6) {
                    let lat = latStep * .pi / 180
                    let ring = cos(lat)
                    let count = max(6, Int(60 * ring))
                    for i in 0..<count {
                        let lon = Double(i) / Double(count) * 2 * .pi + spin
                        var x = ring * sin(lon), y = sin(lat), z = ring * cos(lon)
                        // Tilt toward the viewer.
                        let y2 = y * cos(tilt) - z * sin(tilt)
                        z = y * sin(tilt) + z * cos(tilt)
                        y = y2
                        guard z > -0.05 else { continue }
                        let dot = 1.1 + 1.4 * z
                        x = c.x + x * r
                        let py = c.y - y * r
                        context.fill(Path(ellipseIn: CGRect(x: x - dot / 2, y: py - dot / 2, width: dot, height: dot)),
                                     with: .color(Color(red: 0.55, green: 0.85, blue: 1).opacity(0.25 + 0.75 * z)))
                    }
                }
                // The orbit: the equator seen at an angle, lit as far as the year's distance goes.
                let orbit = Path(ellipseIn: CGRect(x: c.x - r * 1.28, y: c.y - r * 0.42, width: r * 2.56, height: r * 0.84))
                context.stroke(orbit, with: .color(.white.opacity(0.12)), lineWidth: 1.5)
                let lit = orbit.trimmedPath(from: 0, to: max(0.005, progress))
                var glow = context
                glow.addFilter(.blur(radius: 6))
                glow.stroke(lit, with: .color(Color(red: 1, green: 0.75, blue: 0.35)), lineWidth: 6)
                context.stroke(lit, with: .color(Color(red: 1, green: 0.88, blue: 0.6)), style: StrokeStyle(lineWidth: 2.5, lineCap: .round))
                if let head = lit.currentPoint {
                    context.fill(Path(ellipseIn: CGRect(x: head.x - 5, y: head.y - 5, width: 10, height: 10)), with: .color(.white))
                }
            }
        }
        .animation(.easeInOut(duration: 2.2).delay(0.4), value: progress)
    }
}

private struct StarField: View {
    private let stars: [(CGPoint, CGFloat)] = (0..<70).map { _ in
        (CGPoint(x: .random(in: 0...1), y: .random(in: 0...0.75)), .random(in: 0.6...1.8))
    }

    var body: some View {
        Canvas { context, size in
            for (p, r) in stars {
                context.fill(Path(ellipseIn: CGRect(x: p.x * size.width, y: p.y * size.height, width: r, height: r)), with: .color(.white.opacity(0.7)))
            }
        }
    }
}

// MARK: - Steps: footprints walking up the page

struct StoryStepsPage: View {
    let report: YearReport
    let isActive: Bool

    var body: some View {
        ZStack {
            LinearGradient(colors: [Color(red: 0.02, green: 0.16, blue: 0.1), Color(red: 0.03, green: 0.32, blue: 0.2), .black],
                           startPoint: .top, endPoint: .bottom)
                .ignoresSafeArea()
            if isActive { FootprintTrail().ignoresSafeArea() }
            PageText {
                Kicker(text: "一步一步，走了", tint: Color(red: 0.55, green: 1, blue: 0.7)).comesIn(isActive, after: 0.2)
                StoryNumber(value: isActive ? report.steps : 0, unit: String(localized: "步", bundle: .appLanguage), size: 72)
                    .animation(.easeOut(duration: 1.8).delay(0.3), value: isActive)
                Text("步行 \(Format.distance(report.walkingDistance))，相当于 \(report.marathons.formatted(.number.precision(.fractionLength(0...1)).locale(appLocale))) 个全程马拉松")
                    .font(.title3.weight(.semibold)).foregroundStyle(.white.opacity(0.85))
                    .comesIn(isActive, after: 0.7)
                MarathonMedals(count: Int(report.marathons.rounded(.down)), isActive: isActive)
                    .padding(.top, 6)
            }
        }
    }
}

/// Left, right, left: prints appear up a winding path and fade behind you.
private struct FootprintTrail: View {
    @State private var start = Date()

    var body: some View {
        TimelineView(.animation(minimumInterval: 1 / 30)) { timeline in
            let t = timeline.date.timeIntervalSince(start)
            Canvas { context, size in
                let steps = 26
                let interval = 0.32
                let current = t / interval
                for i in 0..<steps {
                    // Each print lives about four seconds, then the walk starts again.
                    let age = (current - Double(i)).truncatingRemainder(dividingBy: Double(steps) + 8)
                    guard age >= 0, age < 12 else { continue }
                    let opacity = age < 1 ? age : max(0, 1 - (age - 1) / 11)
                    let progress = Double(i) / Double(steps - 1)
                    // Up the top half of the page, clear of the words below.
                    let y = size.height * (0.6 - 0.48 * progress)
                    let x = size.width * (0.5 + 0.26 * sin(progress * .pi * 2.2)) + (i.isMultiple(of: 2) ? -18 : 18)
                    let angle = cos(progress * .pi * 2.2) * 0.45
                    if let symbol = context.resolveSymbol(id: i.isMultiple(of: 2) ? 0 : 1) {
                        var c = context
                        c.opacity = opacity * 0.85
                        c.translateBy(x: x, y: y)
                        c.rotate(by: .radians(angle))
                        c.draw(symbol, at: .zero)
                    }
                }
            } symbols: {
                Image(systemName: "shoeprints.fill").font(.system(size: 30)).foregroundStyle(Color(red: 0.55, green: 1, blue: 0.7)).tag(0)
                Image(systemName: "shoeprints.fill").font(.system(size: 30)).foregroundStyle(Color(red: 0.55, green: 1, blue: 0.7))
                    .scaleEffect(x: -1, y: 1).tag(1)
            }
        }
        .onAppear { start = Date() }
    }
}

private struct MarathonMedals: View {
    let count: Int
    let isActive: Bool

    var body: some View {
        let shown = min(count, 12)
        HStack(spacing: -6) {
            ForEach(0..<shown, id: \.self) { index in
                ZStack {
                    Circle().fill(LinearGradient(colors: [Color(red: 1, green: 0.9, blue: 0.55), Color(red: 0.85, green: 0.6, blue: 0.1)],
                                                 startPoint: .top, endPoint: .bottom))
                    Circle().strokeBorder(.white.opacity(0.6), lineWidth: 1.5)
                    Image(systemName: "figure.run").font(.system(size: 13, weight: .bold)).foregroundStyle(.black.opacity(0.65))
                }
                .frame(width: 30, height: 30)
                .shadow(color: .black.opacity(0.3), radius: 3, y: 2)
                .scaleEffect(isActive ? 1 : 0.2)
                .opacity(isActive ? 1 : 0)
                .animation(.spring(response: 0.45, dampingFraction: 0.55).delay(1.0 + Double(index) * 0.08), value: isActive)
            }
            if count > shown {
                Text("+\(count - shown)").font(.subheadline.weight(.bold)).padding(.leading, 12)
                    .comesIn(isActive, after: 2)
            }
        }
    }
}

// MARK: - Places: flags pinned on the map

struct StoryPlacesPage: View {
    let report: YearReport
    let backdrop: MapBackdrop?
    let pinCodes: [String]
    var elsewhere: [String] = []
    let isActive: Bool

    var body: some View {
        ZStack {
            Color.black.ignoresSafeArea()
            if let backdrop {
                BackdropImage(image: backdrop.image, isActive: isActive)
                GeometryReader { geo in
                    ForEach(Array(zip(pinCodes, backdrop.pins).enumerated()), id: \.offset) { index, item in
                        FlagPin(code: item.0)
                            .position(x: item.1.x * geo.size.width, y: item.1.y * geo.size.height - 24)
                            .scaleEffect(isActive ? 1 : 0.1, anchor: .bottom)
                            .opacity(isActive ? 1 : 0)
                            .animation(.spring(response: 0.5, dampingFraction: 0.55).delay(0.4 + Double(index) * 0.12), value: isActive)
                    }
                }
                .ignoresSafeArea()
            }
            PageText {
                Kicker(text: "这一年去过", tint: Color(red: 1, green: 0.7, blue: 0.45)).comesIn(isActive, after: 0.2)
                HStack(spacing: 10) {
                    count(report.countries.count, "国家和地区", delay: 0.3)
                    count(report.cities.count, "座城市", delay: 0.4)
                    if !report.provinces.isEmpty { count(report.provinces.count, "个省份", delay: 0.5) }
                }
                if !elsewhere.isEmpty {
                    Text("还有 \(elsewhere.map { String.flag(for: $0) }.joined(separator: " "))")
                        .font(.title3.weight(.semibold))
                        .comesIn(isActive, after: 0.75)
                }
                if !report.newCities.isEmpty {
                    VStack(alignment: .leading, spacing: 8) {
                        Text("第一次去").font(.subheadline.weight(.semibold)).foregroundStyle(.white.opacity(0.7))
                        FlowChips(items: Array(report.newCities.prefix(8)))
                    }
                    .padding(.top, 6)
                    .comesIn(isActive, after: 0.9)
                }
            }
        }
    }

    private func count(_ value: Int, _ label: LocalizedStringKey, delay: Double) -> some View {
        VStack(alignment: .leading, spacing: 2) {
            StoryNumber(value: isActive ? Double(value) : 0, size: 44)
                .animation(.easeOut(duration: 1.2).delay(delay), value: isActive)
            Text(label).font(.caption.weight(.semibold)).foregroundStyle(.white.opacity(0.75)).lineLimit(1).minimumScaleFactor(0.6)
        }
        .padding(.horizontal, 14).padding(.vertical, 12)
        .frame(maxWidth: .infinity, alignment: .leading)
        .glassEffect(.regular, in: .rect(cornerRadius: 20, style: .continuous))
        .comesIn(isActive, after: delay)
    }
}

private struct FlagPin: View {
    let code: String

    var body: some View {
        VStack(spacing: 0) {
            Text(String.flag(for: code))
                .font(.system(size: 26))
                .padding(6)
                .background(Circle().fill(.white))
                .shadow(color: .black.opacity(0.4), radius: 6, y: 3)
            Triangle().fill(.white).frame(width: 10, height: 7)
        }
    }

    private struct Triangle: Shape {
        func path(in rect: CGRect) -> Path {
            var p = Path()
            p.move(to: CGPoint(x: rect.minX, y: rect.minY))
            p.addLine(to: CGPoint(x: rect.maxX, y: rect.minY))
            p.addLine(to: CGPoint(x: rect.midX, y: rect.maxY))
            p.closeSubpath()
            return p
        }
    }
}

private struct FlowChips: View {
    let items: [String]

    var body: some View {
        // Two rows at most; the page has little room and the rest are in the lists.
        let rows = [Array(items.prefix(4)), Array(items.dropFirst(4))].filter { !$0.isEmpty }
        VStack(alignment: .leading, spacing: 8) {
            ForEach(rows.indices, id: \.self) { row in
                HStack(spacing: 8) {
                    ForEach(rows[row], id: \.self) { item in
                        Text(item)
                            .font(.subheadline.weight(.semibold))
                            .padding(.horizontal, 12).padding(.vertical, 6)
                            .background(Color(red: 1, green: 0.6, blue: 0.3).opacity(0.25), in: .capsule)
                            .overlay(Capsule().stroke(Color(red: 1, green: 0.7, blue: 0.45).opacity(0.5), lineWidth: 1))
                    }
                }
            }
        }
    }
}

// MARK: - The longest day: its route drawn on the map

struct StoryLongestDayPage: View {
    let report: YearReport
    let backdrop: MapBackdrop?
    let isActive: Bool
    @State private var drawn: CGFloat = 0

    var body: some View {
        ZStack {
            StoryBackgroundFallback()
            if let backdrop {
                BackdropImage(image: backdrop.image, isActive: isActive)
                GeometryReader { geo in
                    let path = Path { p in
                        for line in backdrop.lines where line.count > 1 {
                            p.addLines(line.map { CGPoint(x: $0.x * geo.size.width, y: $0.y * geo.size.height) })
                        }
                    }
                    let trimmed = path.trimmedPath(from: 0, to: drawn)
                    trimmed.stroke(Color(red: 0.75, green: 0.55, blue: 1), style: StrokeStyle(lineWidth: 10, lineCap: .round, lineJoin: .round))
                        .blur(radius: 8)
                    trimmed.stroke(.white, style: StrokeStyle(lineWidth: 3.5, lineCap: .round, lineJoin: .round))
                    if let first = backdrop.lines.first?.first {
                        Circle().fill(.white).frame(width: 12, height: 12)
                            .overlay(Circle().stroke(Color(red: 0.75, green: 0.55, blue: 1), lineWidth: 3))
                            .position(x: first.x * geo.size.width, y: first.y * geo.size.height)
                            .opacity(drawn > 0 ? 1 : 0)
                    }
                }
                .ignoresSafeArea()
            }
            PageText {
                Kicker(text: "移动最远的一天", tint: Color(red: 0.8, green: 0.65, blue: 1)).comesIn(isActive, after: 0.2)
                if let longest = report.longestDay {
                    Text(longest.date.formatted(.dateTime.month(.wide).day().weekday(.wide).locale(appLocale)))
                        .font(.title2.weight(.bold)).comesIn(isActive, after: 0.3)
                    StoryNumber(value: isActive ? longest.distance / 1000 : 0, unit: "km", decimals: 1, size: 72)
                        .animation(.easeOut(duration: 1.6).delay(0.4), value: isActive)
                }
                if let month = report.busiestMonth {
                    Label("最常在路上的是 \(month.month.formatted(.dateTime.month(.wide).locale(appLocale)))，共 \(Format.distance(month.distance))",
                          systemImage: "calendar")
                        .font(.subheadline.weight(.semibold))
                        .padding(.horizontal, 14).padding(.vertical, 8)
                        .glassEffect(.regular, in: .capsule)
                        .comesIn(isActive, after: 1.4)
                }
            }
        }
        .onChange(of: isActive, initial: true) { _, active in
            drawn = 0
            if active { withAnimation(.easeInOut(duration: 2.6).delay(0.5)) { drawn = 1 } }
        }
    }
}

private struct StoryBackgroundFallback: View {
    var body: some View {
        LinearGradient(colors: [Color(red: 0.12, green: 0.05, blue: 0.25), .black], startPoint: .top, endPoint: .bottom)
            .ignoresSafeArea()
    }
}

// MARK: - The favourite place, full bleed

struct StoryFavoritePage: View {
    let report: YearReport
    let photo: PHAsset?
    let isActive: Bool
    @State private var image: UIImage?

    var body: some View {
        ZStack {
            Color.black.ignoresSafeArea()
            Group {
                if let image {
                    BackdropImage(image: image, isActive: isActive)
                } else if let stay = report.favoritePlace?.stay {
                    PlacePicture(stay: stay)
                        .ignoresSafeArea()
                        .overlay { if isActive { PulseRings().ignoresSafeArea() } }
                        .overlay(LinearGradient(colors: [.clear, .black.opacity(0.9)], startPoint: .center, endPoint: .bottom).ignoresSafeArea())
                }
            }
            .opacity(isActive ? 1 : 0.4)
            .animation(.easeOut(duration: 1.2), value: isActive)
            PageText {
                if let favorite = report.favoritePlace {
                    Kicker(text: "除了家，你最常去", tint: Color(red: 1, green: 0.8, blue: 0.5)).comesIn(isActive, after: 0.2)
                    Text(favorite.name)
                        .font(.system(size: 46, weight: .black))
                        .lineLimit(2).minimumScaleFactor(0.5)
                        .comesIn(isActive, after: 0.35)
                    Text("去了 \(favorite.visits) 次").font(.title3.weight(.semibold)).foregroundStyle(.white.opacity(0.85))
                        .comesIn(isActive, after: 0.5)
                }
                if let farthest = report.farthestPlace {
                    Label("离家最远到过\(farthest.name)，\(Format.distance(farthest.distance))", systemImage: "location.north.line.fill")
                        .font(.subheadline.weight(.semibold))
                        .padding(.horizontal, 14).padding(.vertical, 8)
                        .glassEffect(.regular, in: .capsule)
                        .padding(.top, 8)
                        .comesIn(isActive, after: 0.9)
                }
            }
        }
        .task(id: photo?.localIdentifier) {
            guard let photo else { return }
            image = await Self.load(photo)
        }
    }

    private static func load(_ asset: PHAsset) async -> UIImage? {
        let options = PHImageRequestOptions()
        options.isNetworkAccessAllowed = true
        options.deliveryMode = .highQualityFormat
        let size = CGSize(width: UIScreen.main.bounds.width * 3, height: UIScreen.main.bounds.height * 3)
        return await withCheckedContinuation { continuation in
            PHImageManager.default().requestImage(for: asset, targetSize: size, contentMode: .aspectFill, options: options) { image, _ in
                continuation.resume(returning: image)
            }
        }
    }
}

/// Rings spreading from the middle of the page, where the place sits on its map.
private struct PulseRings: View {
    @State private var start = Date()

    var body: some View {
        TimelineView(.animation(minimumInterval: 1 / 30)) { timeline in
            let t = timeline.date.timeIntervalSince(start)
            Canvas { context, size in
                let c = CGPoint(x: size.width / 2, y: size.height / 2)
                for i in 0..<3 {
                    let phase = (t / 2.4 + Double(i) / 3).truncatingRemainder(dividingBy: 1)
                    let r = 30 + phase * 170
                    context.stroke(Path(ellipseIn: CGRect(x: c.x - r, y: c.y - r, width: r * 2, height: r * 2)),
                                   with: .color(Color(red: 1, green: 0.8, blue: 0.5).opacity(0.7 * (1 - phase))), lineWidth: 2)
                }
            }
        }
        .allowsHitTesting(false)
        .onAppear { start = Date() }
    }
}

// MARK: - Photos: a polaroid wall

struct StoryPhotosPage: View {
    let assets: [PHAsset]
    let total: Int
    let isActive: Bool

    var body: some View {
        ZStack {
            LinearGradient(colors: [Color(red: 0.16, green: 0.1, blue: 0.08), .black], startPoint: .top, endPoint: .bottom)
                .ignoresSafeArea()
            GeometryReader { geo in
                ForEach(Array(assets.prefix(9).enumerated()), id: \.element.localIdentifier) { index, asset in
                    let spot = Self.spot(index, in: geo.size)
                    Polaroid(asset: asset)
                        .rotationEffect(.degrees(isActive ? spot.angle : spot.angle * 3))
                        .position(x: spot.point.x, y: isActive ? spot.point.y : spot.point.y - geo.size.height)
                        .animation(.spring(response: 0.7, dampingFraction: 0.72).delay(0.15 + Double(index) * 0.12), value: isActive)
                }
            }
            .padding(.bottom, 200)
            PageText {
                Kicker(text: "这一年留下的画面", tint: Color(red: 1, green: 0.85, blue: 0.6)).comesIn(isActive, after: 0.2)
                StoryNumber(value: isActive ? Double(total) : 0, unit: String(localized: "张照片", bundle: .appLanguage), size: 64)
                    .animation(.easeOut(duration: 1.6).delay(0.3), value: isActive)
            }
        }
    }

    /// Nine places on a loose three-by-three, each a little off.
    private static func spot(_ index: Int, in size: CGSize) -> (point: CGPoint, angle: Double) {
        let col = index % 3, row = index / 3
        let jitter: [(CGFloat, CGFloat, Double)] = [(-6, 8, -7), (4, -6, 4), (8, 10, -3), (-4, -4, 6), (6, 6, -5),
                                                    (-8, 2, 8), (2, 8, -4), (-6, -6, 5), (6, 4, -8)]
        let j = jitter[index % jitter.count]
        let x = size.width * (0.2 + 0.3 * CGFloat(col)) + j.0
        let y = size.height * (0.2 + 0.28 * CGFloat(row)) + j.1
        return (CGPoint(x: x, y: y), j.2)
    }
}

private struct Polaroid: View {
    let asset: PHAsset

    var body: some View {
        VStack(spacing: 6) {
            AssetThumbnail(asset: asset, side: 104)
                .clipShape(.rect(cornerRadius: 2))
            if let date = asset.creationDate {
                Text(date.formatted(.dateTime.month().day().locale(appLocale)))
                    .font(.system(size: 10, weight: .semibold, design: .rounded))
                    .foregroundStyle(.black.opacity(0.55))
            }
        }
        .padding(.horizontal, 7).padding(.top, 7).padding(.bottom, 9)
        .background(Color(white: 0.97), in: .rect(cornerRadius: 3))
        .shadow(color: .black.opacity(0.45), radius: 10, y: 6)
    }
}

// MARK: - The year's passport: every stamp earned, pressed onto one page

@MainActor
enum YearStamps {
    static func count(year: Int) -> Int { StoryPassportPage(year: year, isActive: false).stamps.count }
}

struct StoryPassportPage: View {
    let year: Int
    let isActive: Bool

    var stamps: [Stamp] {
        let book = PlaceSummaries.shared.stamps
        let calendar = Calendar.current
        let inYear = { (stamp: Stamp) in calendar.component(.year, from: stamp.date) == year }
        return book.passport.filter { $0.kind == .entry && inYear($0) } + book.sets.compactMap(\.stamp).filter(inYear)
            + book.earnedOnce.filter { $0.kind == .special && inYear($0) } + book.provinces.filter(inYear) + book.cities.filter(inYear)
    }

    static func hasStamps(year: Int) -> Bool { YearStamps.count(year: year) > 0 }

    /// Where the stamps land, three to a row, nudged off the grid.
    private static let slots: [CGPoint] = [
        CGPoint(x: 0.22, y: 0.2), CGPoint(x: 0.55, y: 0.16), CGPoint(x: 0.8, y: 0.27),
        CGPoint(x: 0.27, y: 0.48), CGPoint(x: 0.6, y: 0.47), CGPoint(x: 0.82, y: 0.6),
        CGPoint(x: 0.2, y: 0.78), CGPoint(x: 0.5, y: 0.8), CGPoint(x: 0.78, y: 0.86),
    ]

    var body: some View {
        let all = stamps
        let shown = Array(all.prefix(Self.slots.count))
        ZStack {
            LinearGradient(colors: [Color(red: 0.24, green: 0.05, blue: 0.08), Color(red: 0.08, green: 0.02, blue: 0.03)],
                           startPoint: .top, endPoint: .bottom)
                .ignoresSafeArea()
            GeometryReader { geo in
                let width = min(geo.size.width - 64, 330)
                let height = width * 1.2
                ZStack {
                    StampPaper(style: .passport)
                    ForEach(Array(shown.enumerated()), id: \.element.id) { index, stamp in
                        StampWithRoute(stamp: stamp)
                            .frame(width: width * 0.34, height: width * 0.34)
                            .rotationEffect(.degrees(stamp.tilt))
                            .scaleEffect(isActive ? 1 : 1.6)
                            .opacity(isActive ? 1 : 0)
                            .animation(.spring(response: 0.28, dampingFraction: 0.6).delay(isActive ? 0.5 + Double(index) * 0.32 : 0), value: isActive)
                            .position(x: Self.slots[index].x * width, y: Self.slots[index].y * height)
                    }
                }
                .frame(width: width, height: height)
                .clipShape(.rect(cornerRadius: 14, style: .continuous))
                .rotationEffect(.degrees(-2))
                .shadow(color: .black.opacity(0.5), radius: 24, y: 12)
                .position(x: geo.size.width / 2, y: geo.size.height * 0.36)
            }
            PageText {
                Kicker(text: "今年的护照", tint: Color(red: 0.95, green: 0.8, blue: 0.5)).comesIn(isActive, after: 0.2)
                StoryNumber(value: isActive ? Double(all.count) : 0, unit: String(localized: "枚印章", bundle: .appLanguage), size: 64)
                    .animation(.easeOut(duration: 1.6).delay(0.4), value: isActive)
                Text(summary(all))
                    .font(.title3.weight(.semibold))
                    .opacity(0.85)
                    .comesIn(isActive, after: 0.8)
            }
        }
        .task(id: isActive) {
            // A thump for each stamp as it lands.
            guard isActive else { return }
            for index in shown.indices {
                guard (try? await Task.sleep(for: .seconds(index == 0 ? 0.62 : 0.32))) != nil else { return }
                UIImpactFeedbackGenerator(style: .rigid).impactOccurred(intensity: 0.8)
            }
        }
    }

    private func summary(_ all: [Stamp]) -> String {
        let counts: [(Stamp.Kind, String)] = [(.entry, String(localized: "入境章", bundle: .appLanguage)),
                                              (.province, String(localized: "省份印", bundle: .appLanguage)),
                                              (.city, String(localized: "城市章", bundle: .appLanguage))]
        var parts = counts.compactMap { kind, name -> String? in
            let n = all.filter { $0.kind == kind }.count
            return n > 0 ? "\(n) \(name)" : nil
        }
        let keepsakes = all.filter { $0.kind == .special || $0.kind == .set }.count
        if keepsakes > 0 { parts.append("\(keepsakes) \(String(localized: "纪念章", bundle: .appLanguage))") }
        return parts.joined(separator: " · ")
    }
}

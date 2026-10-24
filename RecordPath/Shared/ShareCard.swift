import SwiftUI
import MapKit

/// A shareable picture of a day or a trip: the route on a map with the key numbers.
/// Places inside privacy zones are left out.
struct ShareCardContent {
    var title: String
    var subtitle: String
    var segments: [[TrackPoint]]
    var colors: [Color]
    var stays: [CLLocationCoordinate2D]
    var stats: [(label: String, value: String)]

    @MainActor
    init(title: String, subtitle: String, chunks: [TrackChunk], stays: [Stay], stats: [(String, String)]) {
        let zones = PrivacyZones.shared
        var segments: [[TrackPoint]] = []
        var colors: [Color] = []
        for chunk in chunks.sorted(by: { $0.startDate < $1.startDate }) {
            for part in zones.visibleSegments(of: chunk.points.simplified(tolerance: 8)) {
                segments.append(part)
                colors.append(chunk.mode.color)
            }
        }
        self.title = title
        self.subtitle = subtitle
        self.segments = segments
        self.colors = colors
        self.stays = stays.map(\.coordinate).filter { !zones.isHidden($0) }
        self.stats = stats.map { (label: $0.0, value: $0.1) }
    }

    var isEmpty: Bool { segments.isEmpty && stays.isEmpty }

    /// Renders the card at 3× for a crisp 1080-pixel-wide image.
    @MainActor
    func render(colorScheme: ColorScheme) async -> UIImage? {
        let size = CGSize(width: 360, height: 480)
        let mapImage = await snapshot(size: CGSize(width: size.width, height: 300), colorScheme: colorScheme)
        let card = ShareCardView(content: self, map: mapImage)
            .frame(width: size.width, height: size.height)
            .environment(\.colorScheme, colorScheme)
        let renderer = ImageRenderer(content: card)
        renderer.scale = 3
        return renderer.uiImage
    }

    private func snapshot(size: CGSize, colorScheme: ColorScheme) async -> UIImage? {
        let coordinates = segments.flatMap { $0.map(\.coordinate) } + stays
        guard !coordinates.isEmpty else { return nil }
        var rect = MKMapRect.null
        for c in coordinates { rect = rect.union(MKMapRect(origin: MKMapPoint(c), size: MKMapSize(width: 1, height: 1))) }
        let minimum = 1_500 * MKMapPointsPerMeterAtLatitude(coordinates[0].latitude)
        let side = max(rect.width, rect.height, minimum)
        let padding = side * 0.25
        rect = MKMapRect(x: rect.midX - side / 2 - padding, y: rect.midY - side / 2 - padding,
                         width: side + padding * 2, height: side + padding * 2)

        let options = MKMapSnapshotter.Options()
        options.mapRect = rect
        options.size = size
        options.traitCollection = UITraitCollection(userInterfaceStyle: colorScheme == .dark ? .dark : .light)
        options.preferredConfiguration = MKStandardMapConfiguration(emphasisStyle: .muted)
        guard let snapshot = try? await MKMapSnapshotter(options: options).start() else { return nil }

        let format = UIGraphicsImageRendererFormat()
        format.scale = 3
        return UIGraphicsImageRenderer(size: size, format: format).image { context in
            snapshot.image.draw(at: .zero)
            let cg = context.cgContext
            cg.setLineCap(.round)
            cg.setLineJoin(.round)
            for (segment, color) in zip(segments, colors) {
                let path = UIBezierPath()
                for (i, p) in segment.enumerated() {
                    let point = snapshot.point(for: p.coordinate)
                    i == 0 ? path.move(to: point) : path.addLine(to: point)
                }
                UIColor.white.withAlphaComponent(0.9).setStroke()
                path.lineWidth = 6
                path.stroke()
                UIColor(color).setStroke()
                path.lineWidth = 3.5
                path.stroke()
            }
            for coordinate in stays {
                let point = snapshot.point(for: coordinate)
                let dot = UIBezierPath(ovalIn: CGRect(x: point.x - 5, y: point.y - 5, width: 10, height: 10))
                UIColor.white.setFill()
                dot.fill()
                let inner = UIBezierPath(ovalIn: CGRect(x: point.x - 3.2, y: point.y - 3.2, width: 6.4, height: 6.4))
                UIColor.systemBlue.setFill()
                inner.fill()
            }
        }
    }
}

private struct ShareCardView: View {
    let content: ShareCardContent
    let map: UIImage?

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            ZStack {
                Rectangle().fill(.quaternary)
                if let map {
                    Image(uiImage: map).resizable().scaledToFill()
                }
            }
            .frame(height: 300)
            .clipped()

            VStack(alignment: .leading, spacing: 12) {
                VStack(alignment: .leading, spacing: 2) {
                    Text(content.title).font(.system(size: 22, weight: .bold, design: .rounded)).lineLimit(1)
                    Text(content.subtitle).font(.system(size: 13)).foregroundStyle(.secondary).lineLimit(1)
                }
                HStack(alignment: .top, spacing: 18) {
                    ForEach(content.stats.prefix(3), id: \.label) { stat in
                        VStack(alignment: .leading, spacing: 1) {
                            Text(stat.value).font(.system(size: 18, weight: .semibold, design: .rounded)).lineLimit(1)
                            Text(stat.label).font(.system(size: 11)).foregroundStyle(.secondary)
                        }
                    }
                    Spacer(minLength: 0)
                }
                HStack(spacing: 5) {
                    Image(systemName: "point.topright.filled.arrow.triangle.backward.to.point.bottomleft.scurvepath")
                    Text(AppInfo.name)
                }
                .font(.system(size: 11, weight: .semibold))
                .foregroundStyle(.tertiary)
            }
            .padding(18)
            .frame(maxWidth: .infinity, alignment: .leading)
        }
        .background(Color(uiColor: .systemBackground))
    }
}

/// A button that renders the card when tapped, then offers it through the share sheet.
struct ShareCardButton: View {
    let makeContent: @MainActor () -> ShareCardContent
    var label: LocalizedStringKey = "分享图片"

    @Environment(\.colorScheme) private var colorScheme
    @State private var image: UIImage?
    @State private var isRendering = false
    @State private var showingNothing = false

    var body: some View {
        Button {
            Task { await prepare() }
        } label: {
            if isRendering {
                ProgressView()
            } else {
                Label(label, systemImage: "square.and.arrow.up")
            }
        }
        .disabled(isRendering)
        .sheet(item: Binding(get: { image.map(RenderedImage.init) }, set: { if $0 == nil { image = nil } })) { rendered in
            ShareCardPreview(image: rendered.image)
        }
        .alert("没有可以分享的内容", isPresented: $showingNothing) {
            Button("好", role: .cancel) {}
        } message: {
            Text("这里还没有轨迹，或者都在隐私区域内。")
        }
    }

    private func prepare() async {
        let content = makeContent()
        guard !content.isEmpty else { showingNothing = true; return }
        isRendering = true
        image = await content.render(colorScheme: colorScheme)
        isRendering = false
    }
}

private struct RenderedImage: Identifiable {
    let image: UIImage
    var id: ObjectIdentifier { ObjectIdentifier(image) }
}

private struct ShareCardPreview: View {
    let image: UIImage
    @Environment(\.dismiss) private var dismiss

    var body: some View {
        NavigationStack {
            Image(uiImage: image)
                .resizable()
                .scaledToFit()
                .clipShape(.rect(cornerRadius: 20, style: .continuous))
                .shadow(color: .black.opacity(0.15), radius: 16, y: 6)
                .padding(24)
                .frame(maxHeight: .infinity)
                .navigationTitle("分享")
                .navigationBarTitleDisplayMode(.inline)
                .toolbar {
                    ToolbarItem(placement: .cancellationAction) {
                        Button("关闭", systemImage: "xmark") { dismiss() }
                    }
                    ToolbarItem(placement: .primaryAction) {
                        ShareLink(item: Image(uiImage: image), preview: SharePreview(AppInfo.name, image: Image(uiImage: image)))
                    }
                }
                .safeAreaInset(edge: .bottom) {
                    if !PrivacyZones.shared.zones.isEmpty {
                        Label("隐私区域内的轨迹和地点已隐藏", systemImage: "eye.slash")
                            .font(.footnote).foregroundStyle(.secondary).padding(.bottom, 8)
                    }
                }
        }
        .presentationDetents([.large])
    }
}

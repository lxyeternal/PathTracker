import SwiftUI
import SwiftData
import MapKit

/// A trip's picture: its first photo, else its route drawn on a quiet map.
struct TripCover: View {
    let trip: Trip
    @Environment(\.modelContext) private var context
    @Environment(\.colorScheme) private var colorScheme
    @State private var route: UIImage?

    private static let cache = NSCache<NSString, UIImage>()

    var body: some View {
        GeometryReader { proxy in
            ZStack {
                LinearGradient(colors: [Color.blue.opacity(0.10), Color.teal.opacity(0.18)], startPoint: .topLeading, endPoint: .bottomTrailing)
                Text(trip.coverEmoji).font(.system(size: min(proxy.size.width, proxy.size.height) * 0.36))
                if let photo = (trip.photos ?? []).min(by: { $0.takenAt < $1.takenAt }) {
                    PhotoThumbnail(photo: photo, square: false)
                } else if let route {
                    Image(uiImage: route).resizable().scaledToFill().transition(.opacity)
                }
            }
            .frame(width: proxy.size.width, height: proxy.size.height)
            .task(id: "\(trip.id)-\(trip.endDate?.timeIntervalSince1970 ?? 0)-\(colorScheme)-\(Int(proxy.size.width))") {
                guard (trip.photos ?? []).isEmpty else { return }
                let image = await routeImage(size: proxy.size)
                withAnimation(.easeOut(duration: 0.25)) { route = image }
            }
        }
        .clipped()
    }

    private func routeImage(size: CGSize) async -> UIImage? {
        guard size.width > 0, size.height > 0 else { return nil }
        let dark = colorScheme == .dark
        let key = "\(trip.id)-\(trip.endDate?.timeIntervalSince1970 ?? 0)-\(Int(size.width))x\(Int(size.height))-\(dark)" as NSString
        if let cached = Self.cache.object(forKey: key) { return cached }

        let start = trip.startDate, end = trip.endDate ?? Date()
        let id: UUID? = trip.id
        let chunks = trip.isRecording
            ? (try? context.fetch(FetchDescriptor<TrackChunk>(predicate: #Predicate { $0.tripID == id }))) ?? []
            : (try? context.fetch(FetchDescriptor<TrackChunk>(predicate: #Predicate { $0.endDate >= start && $0.startDate <= end }))) ?? []
        let lines = chunks.filter { $0.mode != .flying }.sorted { $0.startDate < $1.startDate }
            .map { ($0.points.simplified(tolerance: 20).map(\.coordinate.onMap), $0.mode) }
            .filter { $0.0.count > 1 }
        guard !lines.isEmpty else { return nil }

        var rect = MKMapRect.null
        for (coordinates, _) in lines {
            for c in coordinates { rect = rect.union(MKMapRect(origin: MKMapPoint(c), size: MKMapSize(width: 1, height: 1))) }
        }
        let minimum = 800 * MKMapPointsPerMeterAtLatitude(lines[0].0[0].latitude)
        let aspect = size.width / size.height
        var width = max(rect.width, minimum), height = max(rect.height, minimum)
        if width / height < aspect { width = height * aspect } else { height = width / aspect }
        width *= 1.35; height *= 1.35
        let options = MKMapSnapshotter.Options()
        options.mapRect = MKMapRect(x: rect.midX - width / 2, y: rect.midY - height / 2, width: width, height: height)
        options.size = size
        options.traitCollection = UITraitCollection(userInterfaceStyle: dark ? .dark : .light)
        let configuration = MKStandardMapConfiguration(emphasisStyle: .muted)
        configuration.pointOfInterestFilter = .excludingAll
        options.preferredConfiguration = configuration
        guard let snapshot = try? await MKMapSnapshotter(options: options).start() else { return nil }

        let format = UIGraphicsImageRendererFormat()
        format.scale = 3
        let image = UIGraphicsImageRenderer(size: size, format: format).image { context in
            snapshot.image.draw(at: .zero)
            context.cgContext.setLineCap(.round)
            context.cgContext.setLineJoin(.round)
            for (coordinates, mode) in lines {
                let path = UIBezierPath()
                for (i, c) in coordinates.enumerated() {
                    let p = snapshot.point(for: c)
                    i == 0 ? path.move(to: p) : path.addLine(to: p)
                }
                UIColor.white.withAlphaComponent(0.9).setStroke()
                path.lineWidth = 5
                path.stroke()
                UIColor(mode.color).setStroke()
                path.lineWidth = 3
                path.stroke()
            }
        }
        Self.cache.setObject(image, forKey: key)
        return image
    }
}

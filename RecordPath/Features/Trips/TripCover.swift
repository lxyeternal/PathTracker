import SwiftUI
import SwiftData
import MapKit

/// A trip's picture: its first photo, else its route drawn on a quiet map.
struct TripCover: View {
    let trip: Trip
    @Environment(\.modelContext) private var context
    @Environment(\.colorScheme) private var colorScheme
    @State private var route: UIImage?

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
        let start = trip.startDate, end = trip.endDate ?? Date()
        let id: UUID? = trip.id
        let chunks = trip.isRecording
            ? (try? context.fetch(FetchDescriptor<TrackChunk>(predicate: #Predicate { $0.tripID == id }))) ?? []
            : (try? context.fetch(FetchDescriptor<TrackChunk>(predicate: #Predicate { $0.endDate >= start && $0.startDate <= end }))) ?? []
        let lines = chunks.filter { $0.mode != .flying }.sorted { $0.startDate < $1.startDate }
            .map { RouteImage.Line(coordinates: $0.points.simplified(tolerance: 20).map(\.coordinate), color: $0.mode.color) }
        return await RouteImage.render(lines, size: size, dark: colorScheme == .dark,
                                       key: "trip-\(trip.id)-\(trip.endDate?.timeIntervalSince1970 ?? 0)")
    }
}

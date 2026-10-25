import SwiftUI
import MapKit
import Photos

/// A place's picture: a photo you posted there, else one you took there, else a small map.
struct PlacePicture: View {
    let stay: Stay
    @State private var asset: PHAsset?
    @State private var snapshot: UIImage?
    @Environment(\.colorScheme) private var colorScheme

    private static let cache = NSCache<NSString, UIImage>()

    var body: some View {
        GeometryReader { proxy in
            ZStack {
                // While the picture loads: the place's icon on its colour.
                LinearGradient(colors: [stay.category.tint.opacity(0.10), stay.category.tint.opacity(0.22)],
                               startPoint: .topLeading, endPoint: .bottomTrailing)
                PlaceIcon(category: stay.category, isLandmark: stay.isLandmark, size: 30).opacity(0.5)
                if let photo = (stay.photos ?? []).min(by: { $0.takenAt < $1.takenAt }) {
                    PhotoThumbnail(photo: photo, square: false)
                } else if let asset {
                    AssetThumbnail(asset: asset, side: max(proxy.size.width, proxy.size.height))
                        .frame(width: proxy.size.width, height: proxy.size.height)
                        .clipped()
                } else if let snapshot {
                    Image(uiImage: snapshot).resizable().scaledToFill()
                        .overlay {
                            PlaceIcon(category: stay.category, isLandmark: stay.isLandmark, size: 30)
                                .overlay(Circle().stroke(.white, lineWidth: 2))
                                .shadow(color: .black.opacity(0.2), radius: 3, y: 1)
                        }
                        .transition(.opacity)
                }
            }
            .frame(width: proxy.size.width, height: proxy.size.height)
            .task(id: "\(stay.id)-\(colorScheme)-\(Int(proxy.size.width))") {
                if let first = DayPhotos.assets(in: DayPhotos.interval(of: stay)).first {
                    asset = first
                } else if (stay.photos ?? []).isEmpty {
                    let image = await Self.snapshot(of: stay, size: proxy.size, dark: colorScheme == .dark)
                    withAnimation(.easeOut(duration: 0.25)) { snapshot = image }
                }
            }
        }
        .clipped()
    }

    private static func snapshot(of stay: Stay, size: CGSize, dark: Bool) async -> UIImage? {
        guard size.width > 0, size.height > 0 else { return nil }
        let key = "\(stay.latitude),\(stay.longitude),\(Int(size.width))x\(Int(size.height)),\(dark)" as NSString
        if let cached = cache.object(forKey: key) { return cached }
        let options = MKMapSnapshotter.Options()
        options.region = MKCoordinateRegion(center: stay.coordinate.onMap, latitudinalMeters: 700, longitudinalMeters: 700)
        options.size = size
        options.traitCollection = UITraitCollection(userInterfaceStyle: dark ? .dark : .light)
        let configuration = MKStandardMapConfiguration(elevationStyle: .realistic, emphasisStyle: .muted)
        // Other places' names would read as this one's.
        configuration.pointOfInterestFilter = .excludingAll
        options.preferredConfiguration = configuration
        guard let image = try? await MKMapSnapshotter(options: options).start().image else { return nil }
        cache.setObject(image, forKey: key)
        return image
    }
}

/// A sight as a picture card: where, which city, when you were there.
struct SightCard: View {
    let stay: Stay
    var width: CGFloat? = 170

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            PlacePicture(stay: stay)
                .frame(height: 120)
            VStack(alignment: .leading, spacing: 2) {
                Text(stay.displayName)
                    .font(.subheadline.weight(.semibold))
                    .lineLimit(1)
                Text([stay.city, stay.arrival.formatted(.dateTime.month().day().locale(appLocale))].compactMap { $0 }.joined(separator: " · "))
                    .font(.caption)
                    .foregroundStyle(.secondary)
                    .lineLimit(1)
            }
            .padding(.horizontal, 12)
            .padding(.vertical, 10)
        }
        .frame(width: width)
        .frame(maxWidth: width == nil ? .infinity : nil, alignment: .leading)
        .background(.background.secondary)
        .clipShape(.rect(cornerRadius: 20, style: .continuous))
        .contentShape(.rect(cornerRadius: 20, style: .continuous))
    }
}

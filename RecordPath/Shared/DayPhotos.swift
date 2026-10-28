import SwiftUI
import Photos

/// Photos taken at a place, shown on the timeline. Read on the device only, never copied.
enum DayPhotos {
    static var status: PHAuthorizationStatus { PHPhotoLibrary.authorizationStatus(for: .readWrite) }
    static var canRead: Bool { status == .authorized || status == .limited }

    static func requestAccess() async -> PHAuthorizationStatus {
        await PHPhotoLibrary.requestAuthorization(for: .readWrite)
    }

    /// Photos (not screenshots) taken during the interval, oldest first.
    static func assets(in interval: DateInterval) -> [PHAsset] {
        guard canRead else { return [] }
        let options = PHFetchOptions()
        options.predicate = NSPredicate(format: "mediaType == %d AND creationDate >= %@ AND creationDate <= %@ AND NOT ((mediaSubtype & %d) != 0)",
                                        PHAssetMediaType.image.rawValue, interval.start as NSDate, interval.end as NSDate,
                                        PHAssetMediaSubtype.photoScreenshot.rawValue)
        options.sortDescriptors = [NSSortDescriptor(key: "creationDate", ascending: true)]
        let result = PHAsset.fetchAssets(with: options)
        return (0..<result.count).map { result.object(at: $0) }
    }

    static func interval(of stay: Stay) -> DateInterval {
        DateInterval(start: stay.arrival, end: max(stay.departure ?? Date(), stay.arrival))
    }
}

struct AssetThumbnail: View {
    let asset: PHAsset
    let side: CGFloat
    @State private var image: UIImage?
    @Environment(\.displayScale) private var scale

    var body: some View {
        Color.secondary.opacity(0.15)
            .frame(width: side, height: side)
            .overlay {
                if let image {
                    Image(uiImage: image).resizable().scaledToFill()
                }
            }
            .clipShape(.rect(cornerRadius: side * 0.18, style: .continuous))
            .task(id: asset.localIdentifier) {
                for await next in AssetLoader.images(for: asset, size: CGSize(width: side * scale, height: side * scale)) {
                    image = next
                }
            }
            .accessibilityLabel("照片")
    }
}

struct AssetPagerStart: Identifiable {
    let id: String
}

/// Photos from the library full screen, swiping between them.
struct AssetPager: View {
    let assets: [PHAsset]
    @State var selection: String
    @Environment(\.dismiss) private var dismiss

    var body: some View {
        NavigationStack {
            ZStack {
                Color.black.ignoresSafeArea()
                TabView(selection: $selection) {
                    ForEach(assets, id: \.localIdentifier) { asset in
                        AssetPage(asset: asset).tag(asset.localIdentifier)
                    }
                }
                .tabViewStyle(.page(indexDisplayMode: assets.count > 1 ? .automatic : .never))
                .ignoresSafeArea()
            }
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("关闭", systemImage: "xmark") { dismiss() }
                }
                if let date = assets.first(where: { $0.localIdentifier == selection })?.creationDate {
                    ToolbarItem(placement: .principal) {
                        Text(date.formatted(.dateTime.month().day().hour().minute().locale(appLocale)))
                            .font(.subheadline.weight(.semibold)).foregroundStyle(.white)
                    }
                }
            }
            .toolbarBackground(.hidden, for: .navigationBar)
        }
        .preferredColorScheme(.dark)
    }
}

private struct AssetPage: View {
    let asset: PHAsset
    @State private var image: UIImage?
    @State private var zoom: CGFloat = 1

    var body: some View {
        Group {
            if let image {
                Image(uiImage: image)
                    .resizable()
                    .scaledToFit()
                    .scaleEffect(zoom)
                    .gesture(MagnifyGesture().onChanged { zoom = max(1, $0.magnification) }.onEnded { _ in
                        withAnimation(.smooth) { zoom = 1 }
                    })
            } else {
                ProgressView().tint(.white)
            }
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .task { image = await AssetLoader.image(for: asset, size: CGSize(width: 2400, height: 2400), exact: false) }
    }
}

enum AssetLoader {
    /// A blurry preview at once, then the full one (from iCloud if need be).
    static func images(for asset: PHAsset, size: CGSize) -> AsyncStream<UIImage> {
        AsyncStream { continuation in
            let options = PHImageRequestOptions()
            options.isNetworkAccessAllowed = true
            options.deliveryMode = .opportunistic
            options.resizeMode = .fast
            let id = cache.requestImage(for: asset, targetSize: size, contentMode: .aspectFill, options: options) { image, info in
                if let image { continuation.yield(image) }
                let degraded = (info?[PHImageResultIsDegradedKey] as? Bool) ?? false
                if !degraded || image == nil { continuation.finish() }
            }
            continuation.onTermination = { _ in cache.cancelImageRequest(id) }
        }
    }

    nonisolated(unsafe) static let cache = PHCachingImageManager()

    static func image(for asset: PHAsset, size: CGSize, exact: Bool) async -> UIImage? {
        let options = PHImageRequestOptions()
        options.isNetworkAccessAllowed = true
        options.deliveryMode = exact ? .highQualityFormat : .opportunistic
        options.resizeMode = exact ? .none : .fast
        return await withCheckedContinuation { continuation in
            var resumed = false
            PHImageManager.default().requestImage(for: asset, targetSize: size, contentMode: .aspectFill, options: options) { image, info in
                // Opportunistic delivery can call back twice; the degraded preview comes first.
                let degraded = (info?[PHImageResultIsDegradedKey] as? Bool) ?? false
                guard !resumed, !degraded || image == nil else { return }
                resumed = true
                continuation.resume(returning: image)
            }
        }
    }
}

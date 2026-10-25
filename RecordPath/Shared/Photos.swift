import SwiftUI
import SwiftData
import ImageIO
import CoreLocation
import Photos

/// Turns picked images into stored photos: re-encoded at a sensible size (originals stay in
/// the photo library), with date and position from EXIF when there is some.
enum PhotoImport {
    static func makePhoto(from data: Data, fallbackDate: Date, fallbackCoordinate: CLLocationCoordinate2D?) -> TripPhoto? {
        guard let image = UIImage(data: data) else { return nil }
        let jpeg = image.preparingThumbnail(of: image.size.fitting(maxDimension: 2048))?.jpegData(compressionQuality: 0.82) ?? data
        let metadata = PhotoMetadata(data: data)
        return TripPhoto(imageData: jpeg, takenAt: metadata.date ?? fallbackDate,
                         coordinate: metadata.coordinate ?? fallbackCoordinate)
    }

    /// The full image of a library photo, for posting.
    static func data(for asset: PHAsset) async -> Data? {
        let options = PHImageRequestOptions()
        options.isNetworkAccessAllowed = true
        options.deliveryMode = .highQualityFormat
        options.version = .current
        return await withCheckedContinuation { continuation in
            PHImageManager.default().requestImageDataAndOrientation(for: asset, options: options) { data, _, _, _ in
                continuation.resume(returning: data)
            }
        }
    }
}

extension CGSize {
    func fitting(maxDimension: CGFloat) -> CGSize {
        let scale = min(1, maxDimension / max(width, height))
        return CGSize(width: width * scale, height: height * scale)
    }
}

/// A stored photo as a square thumbnail, decoded off the main thread and cached.
struct PhotoThumbnail: View {
    let photo: TripPhoto
    var cornerRadius: CGFloat = 0
    /// Off to fill whatever frame it's given.
    var square = true
    @State private var image: UIImage?

    private static let cache = NSCache<NSUUID, UIImage>()

    var body: some View {
        Color.secondary.opacity(0.15)
            .aspectRatio(square ? 1 : nil, contentMode: square ? .fit : .fill)
            .frame(maxWidth: .infinity, maxHeight: .infinity)
            .overlay {
                if let image {
                    Image(uiImage: image).resizable().scaledToFill().transition(.opacity)
                }
            }
            .clipped()
            .clipShape(.rect(cornerRadius: cornerRadius, style: .continuous))
            .task(id: photo.id) {
                let key = photo.id as NSUUID
                if let cached = Self.cache.object(forKey: key) { image = cached; return }
                guard let data = photo.imageData else { return }
                let thumbnail = await Task.detached { UIImage(data: data)?.preparingThumbnail(of: CGSize(width: 360, height: 360)) }.value
                if let thumbnail { Self.cache.setObject(thumbnail, forKey: key) }
                withAnimation(.easeOut(duration: 0.2)) { image = thumbnail }
            }
    }
}

/// Photos full screen, swiping between them, with where and when, the caption, and deleting.
struct PhotoPager: View {
    let photos: [TripPhoto]
    @State var selection: UUID
    @Environment(\.modelContext) private var context
    @Environment(\.dismiss) private var dismiss
    @State private var confirmingDelete = false
    @State private var editingCaption = false
    @State private var caption = ""

    private var current: TripPhoto? { photos.first { $0.id == selection } }

    var body: some View {
        NavigationStack {
            ZStack {
                Color.black.ignoresSafeArea()
                TabView(selection: $selection) {
                    ForEach(photos) { photo in
                        ZoomableImage(photo: photo).tag(photo.id)
                    }
                }
                .tabViewStyle(.page(indexDisplayMode: .never))
                .ignoresSafeArea()
            }
            .overlay(alignment: .bottom) { if let current { infoBar(current) } }
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("关闭", systemImage: "xmark") { dismiss() }
                }
                ToolbarItem(placement: .principal) {
                    if let current {
                        VStack(spacing: 0) {
                            Text(current.placeTitle).font(.subheadline.weight(.semibold))
                            Text(current.takenAt.formatted(Date.FormatStyle(date: .abbreviated, time: .shortened, locale: appLocale)))
                                .font(.caption)
                                .opacity(0.7)
                        }
                        .foregroundStyle(.white)
                    }
                }
                ToolbarItem(placement: .primaryAction) {
                    Menu("更多", systemImage: "ellipsis") {
                        Button("编辑说明", systemImage: "text.bubble") {
                            caption = current?.caption ?? ""
                            editingCaption = true
                        }
                        if let data = current?.imageData, let image = UIImage(data: data) {
                            ShareLink(item: Image(uiImage: image), preview: SharePreview(current?.placeTitle ?? "", image: Image(uiImage: image))) {
                                Label("分享", systemImage: "square.and.arrow.up")
                            }
                        }
                        Button("删除照片", systemImage: "trash", role: .destructive) { confirmingDelete = true }
                    }
                }
            }
            .toolbarBackground(.hidden, for: .navigationBar)
            .preferredColorScheme(.dark)
            .confirmationDialog("删除这张照片？", isPresented: $confirmingDelete, titleVisibility: .visible) {
                Button("删除照片", role: .destructive, action: deleteCurrent)
            }
            .alert("说明", isPresented: $editingCaption) {
                TextField("写点什么", text: $caption)
                Button("保存") {
                    current?.caption = caption.trimmingCharacters(in: .whitespacesAndNewlines).nilIfEmpty
                    try? context.save()
                }
                Button("取消", role: .cancel) {}
            }
        }
    }

    @ViewBuilder
    private func infoBar(_ photo: TripPhoto) -> some View {
        if let text = photo.caption ?? photo.stay?.note, !text.isEmpty {
            Text(text)
                .font(.body)
                .foregroundStyle(.white)
                .frame(maxWidth: .infinity, alignment: .leading)
                .padding(16)
                .background(LinearGradient(colors: [.black.opacity(0), .black.opacity(0.7)], startPoint: .top, endPoint: .bottom))
        }
    }

    private func deleteCurrent() {
        guard let photo = current else { return }
        let index = photos.firstIndex { $0.id == photo.id } ?? 0
        let remaining = photos.filter { $0.id != photo.id }
        context.delete(photo)
        try? context.save()
        if remaining.isEmpty { dismiss() } else { selection = remaining[min(index, remaining.count - 1)].id }
    }
}

private struct ZoomableImage: View {
    let photo: TripPhoto
    @State private var image: UIImage?
    @State private var zoom: CGFloat = 1
    @State private var settledZoom: CGFloat = 1

    var body: some View {
        Group {
            if let image {
                Image(uiImage: image)
                    .resizable()
                    .scaledToFit()
                    .scaleEffect(zoom)
                    .gesture(MagnifyGesture()
                        .onChanged { zoom = max(1, settledZoom * $0.magnification) }
                        .onEnded { _ in settledZoom = zoom })
                    .onTapGesture(count: 2) {
                        withAnimation(.spring(response: 0.35, dampingFraction: 0.8)) {
                            zoom = zoom > 1 ? 1 : 2.5
                            settledZoom = zoom
                        }
                    }
            } else {
                ProgressView().tint(.white)
            }
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .task(id: photo.id) {
            guard let data = photo.imageData else { return }
            image = await Task.detached { UIImage(data: data) }.value
        }
    }
}

extension TripPhoto {
    /// Where it was taken, for captions: the place it was posted for, else its trip.
    var placeTitle: String {
        stay?.displayName ?? trip?.title ?? String(localized: "照片", bundle: .appLanguage)
    }
}

/// Capture date and GPS position read from a photo's EXIF data.
struct PhotoMetadata {
    var date: Date?
    var coordinate: CLLocationCoordinate2D?

    init(data: Data) {
        guard let source = CGImageSourceCreateWithData(data as CFData, nil),
              let properties = CGImageSourceCopyPropertiesAtIndex(source, 0, nil) as? [CFString: Any] else { return }
        if let exif = properties[kCGImagePropertyExifDictionary] as? [CFString: Any],
           let original = exif[kCGImagePropertyExifDateTimeOriginal] as? String {
            let formatter = DateFormatter()
            formatter.locale = Locale(identifier: "en_US_POSIX")
            formatter.dateFormat = "yyyy:MM:dd HH:mm:ss"
            date = formatter.date(from: original)
        }
        if let gps = properties[kCGImagePropertyGPSDictionary] as? [CFString: Any],
           var latitude = gps[kCGImagePropertyGPSLatitude] as? Double,
           var longitude = gps[kCGImagePropertyGPSLongitude] as? Double {
            if (gps[kCGImagePropertyGPSLatitudeRef] as? String) == "S" { latitude = -latitude }
            if (gps[kCGImagePropertyGPSLongitudeRef] as? String) == "W" { longitude = -longitude }
            coordinate = CLLocationCoordinate2D(latitude: latitude, longitude: longitude)
        }
    }
}

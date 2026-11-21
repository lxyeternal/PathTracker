import SwiftUI
import UIKit

/// What the person adds to a place they lit by hand: the day they were there, if they remember
/// it, and a few photos from that trip. Photos are copies kept on this device; the day travels
/// between devices with iCloud, like the list of hand-lit places itself.
@MainActor
@Observable
final class MustSeeMemories {
    static let shared = MustSeeMemories()

    private(set) var dates: [String: Date] = [:]
    /// Bumped when a place's photos change, so views read the folder again.
    private(set) var revision = 0

    static let maxPhotos = 9
    private static let datesKey = "mustSee.manualDates"

    private init() {
        let local = UserDefaults.standard.dictionary(forKey: Self.datesKey) as? [String: Double] ?? [:]
        let cloud = NSUbiquitousKeyValueStore.default.dictionary(forKey: Self.datesKey) as? [String: Double] ?? [:]
        dates = local.merging(cloud) { mine, _ in mine }.mapValues { Date(timeIntervalSince1970: $0) }
    }

    func date(_ id: String) -> Date? { dates[id] }

    func setDate(_ date: Date?, for id: String) {
        dates[id] = date
        let raw = dates.mapValues(\.timeIntervalSince1970)
        UserDefaults.standard.set(raw, forKey: Self.datesKey)
        NSUbiquitousKeyValueStore.default.set(raw, forKey: Self.datesKey)
    }

    // MARK: Photos

    private nonisolated static func folder(_ id: String) -> URL {
        let base = FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask)[0]
        return base.appending(path: "MustSeeMemories", directoryHint: .isDirectory).appending(path: id, directoryHint: .isDirectory)
    }

    /// The place's photos, in the order they were added.
    func photos(_ id: String) -> [URL] {
        _ = revision
        let files = (try? FileManager.default.contentsOfDirectory(at: Self.folder(id), includingPropertiesForKeys: nil)) ?? []
        return files.filter { $0.pathExtension == "jpg" }.sorted { $0.lastPathComponent < $1.lastPathComponent }
    }

    /// Keeps a copy of each picked image, sized for the screen. When the day of the visit isn't
    /// known yet, the earliest photo's own date becomes it.
    func add(_ images: [Data], to id: String) async {
        let room = Self.maxPhotos - photos(id).count
        guard room > 0 else { return }
        let folder = Self.folder(id)
        let taken = await Task.detached(priority: .userInitiated) { () -> [Date] in
            try? FileManager.default.createDirectory(at: folder, withIntermediateDirectories: true)
            var dates: [Date] = []
            for (index, data) in images.prefix(room).enumerated() {
                guard let image = UIImage(data: data),
                      let jpeg = image.preparingThumbnail(of: image.size.fitting(maxDimension: 2048))?.jpegData(compressionQuality: 0.82) else { continue }
                // Sorted by name, so by when they were added.
                let name = String(format: "%014.0f-%02d-%@.jpg", Date().timeIntervalSince1970 * 1000, index, UUID().uuidString.prefix(8) as CVarArg)
                try? jpeg.write(to: folder.appending(path: name), options: .atomic)
                if let date = PhotoMetadata(data: data).date { dates.append(date) }
            }
            return dates
        }.value
        if dates[id] == nil, let earliest = taken.min() { setDate(earliest, for: id) }
        revision += 1
    }

    func remove(_ url: URL) {
        try? FileManager.default.removeItem(at: url)
        MemoryImages.forget(url)
        revision += 1
    }

    /// When the place is no longer lit by hand.
    func forget(_ id: String) {
        try? FileManager.default.removeItem(at: Self.folder(id))
        setDate(nil, for: id)
        revision += 1
    }
}

/// Decodes a kept photo off the main thread, once.
enum MemoryImages {
    private static let cache = NSCache<NSURL, UIImage>()

    static func forget(_ url: URL) { cache.removeObject(forKey: url as NSURL) }

    static func image(_ url: URL, side: CGFloat) async -> UIImage? {
        if side <= 400, let cached = cache.object(forKey: url as NSURL) { return cached }
        let image = await Task.detached(priority: .userInitiated) { () -> UIImage? in
            guard let full = UIImage(contentsOfFile: url.path) else { return nil }
            return side <= 400 ? full.preparingThumbnail(of: full.size.fitting(maxDimension: 400)) : full
        }.value
        if side <= 400, let image { cache.setObject(image, forKey: url as NSURL) }
        return image
    }
}

struct MemoryThumbnail: View {
    let url: URL
    @State private var image: UIImage?

    var body: some View {
        Color.white.opacity(0.08)
            .overlay {
                if let image { Image(uiImage: image).resizable().scaledToFill().transition(.opacity) }
            }
            .clipped()
            .task(id: url) {
                let loaded = await MemoryImages.image(url, side: 400)
                withAnimation(.easeOut(duration: 0.2)) { image = loaded }
            }
            .accessibilityLabel("照片")
    }
}

struct MemoryPagerStart: Identifiable {
    let id: URL
}

/// Kept photos full screen, swiping between them, with a way to remove one.
struct MemoryPager: View {
    let urls: [URL]
    @State var selection: URL
    var onDelete: (URL) -> Void
    @Environment(\.dismiss) private var dismiss
    @State private var confirming = false

    var body: some View {
        NavigationStack {
            ZStack {
                Color.black.ignoresSafeArea()
                TabView(selection: $selection) {
                    ForEach(urls, id: \.self) { url in
                        MemoryPage(url: url).tag(url)
                    }
                }
                .tabViewStyle(.page(indexDisplayMode: urls.count > 1 ? .automatic : .never))
            }
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("关闭", systemImage: "xmark") { dismiss() }
                }
                ToolbarItem(placement: .primaryAction) {
                    Button("移除", systemImage: "trash", role: .destructive) { confirming = true }
                }
            }
            .toolbarBackground(.hidden, for: .navigationBar)
            .confirmationDialog("移除这张照片？", isPresented: $confirming, titleVisibility: .visible) {
                Button("移除", role: .destructive) {
                    onDelete(selection)
                    dismiss()
                }
            } message: {
                Text("只从这里移除，相册里的原图不受影响。")
            }
        }
        .environment(\.colorScheme, .dark)
    }
}

private struct MemoryPage: View {
    let url: URL
    @State private var image: UIImage?

    var body: some View {
        ZStack {
            if let image {
                Image(uiImage: image).resizable().scaledToFit()
            } else {
                ProgressView().tint(.white)
            }
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .task { image = await MemoryImages.image(url, side: 2048) }
    }
}

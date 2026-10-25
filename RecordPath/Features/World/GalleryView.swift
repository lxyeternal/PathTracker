import SwiftUI
import SwiftData

struct GalleryRoute: Hashable {}

/// Every photo posted, newest first, by month; or by place.
struct GalleryView: View {
    @Query(sort: \TripPhoto.takenAt, order: .reverse) private var photos: [TripPhoto]
    @State private var grouping = Grouping.month
    @State private var pagerStart: TripPhoto?
    @State private var pagerPhotos: [TripPhoto] = []
    @Namespace private var namespace

    enum Grouping: Hashable { case month, place }

    private var sections: [(title: String, subtitle: String?, photos: [TripPhoto])] {
        switch grouping {
        case .month:
            let calendar = Calendar.current
            let groups = Dictionary(grouping: photos) { calendar.dateInterval(of: .month, for: $0.takenAt)?.start ?? $0.takenAt }
            return groups.keys.sorted(by: >).map { month in
                (month.formatted(.dateTime.year().month(.wide).locale(appLocale)), nil, groups[month] ?? [])
            }
        case .place:
            let groups = Dictionary(grouping: photos) { $0.placeTitle }
            return groups.map { title, photos in
                (title, photos.first?.stay?.subtitle ?? photos.first?.trip?.dateRangeText, photos)
            }
            .sorted { ($0.photos.first?.takenAt ?? .distantPast) > ($1.photos.first?.takenAt ?? .distantPast) }
        }
    }

    var body: some View {
        ScrollView {
            if photos.isEmpty {
                ContentUnavailableView {
                    Label("还没有照片", systemImage: "photo.stack")
                } description: {
                    Text("在时间线上点开一个地点，就能发布照片和心情。旅程里添加的照片也会出现在这里。")
                }
                .padding(.top, 80)
            } else {
                LazyVStack(alignment: .leading, spacing: 0, pinnedViews: [.sectionHeaders]) {
                    ForEach(sections, id: \.title) { section in
                        Section {
                            LazyVGrid(columns: Array(repeating: GridItem(.flexible(), spacing: 3), count: 3), spacing: 3) {
                                ForEach(section.photos) { photo in
                                    Button {
                                        pagerPhotos = section.photos
                                        pagerStart = photo
                                    } label: {
                                        PhotoThumbnail(photo: photo)
                                            .matchedTransitionSource(id: photo.id, in: namespace)
                                    }
                                    .buttonStyle(.plain)
                                }
                            }
                            .padding(.bottom, 20)
                        } header: {
                            VStack(alignment: .leading, spacing: 2) {
                                Text(section.title).font(.headline)
                                if let subtitle = section.subtitle {
                                    Text(subtitle).font(.caption).foregroundStyle(.secondary)
                                }
                            }
                            .frame(maxWidth: .infinity, alignment: .leading)
                            .padding(.horizontal)
                            .padding(.vertical, 8)
                            .background(.bar)
                        }
                    }
                }
                .padding(.bottom, 24)
                .animation(.smooth, value: grouping)
            }
        }
        .navigationTitle("相册")
        .navigationBarTitleDisplayMode(.inline)
        .toolbar {
            ToolbarItem(placement: .principal) {
                Picker("分组", selection: $grouping) {
                    Text("按月份").tag(Grouping.month)
                    Text("按地点").tag(Grouping.place)
                }
                .pickerStyle(.segmented)
                .frame(width: 200)
            }
        }
        .fullScreenCover(item: $pagerStart) { photo in
            PhotoPager(photos: pagerPhotos, selection: photo.id)
                .navigationTransition(.zoom(sourceID: photo.id, in: namespace))
        }
    }
}

/// The latest photos on the Places tab, opening the gallery.
struct GalleryPreview: View {
    @Query(sort: \TripPhoto.takenAt, order: .reverse) private var photos: [TripPhoto]

    var body: some View {
        NavigationLink(value: GalleryRoute()) {
            VStack(alignment: .leading, spacing: 12) {
                HStack(alignment: .firstTextBaseline) {
                    Text("相册").font(.title3.bold()).foregroundStyle(.primary)
                    Spacer()
                    if !photos.isEmpty {
                        Text("\(photos.count)").font(.subheadline).foregroundStyle(.secondary)
                    }
                    Image(systemName: "chevron.forward").font(.footnote.weight(.semibold)).foregroundStyle(.tertiary)
                }
                if photos.isEmpty {
                    HStack(spacing: 12) {
                        Image(systemName: "photo.badge.plus")
                            .font(.title2)
                            .foregroundStyle(.tint)
                            .frame(width: 52, height: 52)
                            .background(Color.accentColor.opacity(0.12), in: .rect(cornerRadius: 14, style: .continuous))
                        Text("在时间线上点开一个地点，发布照片和心情，它们会收在这里。")
                            .font(.subheadline)
                            .foregroundStyle(.secondary)
                            .multilineTextAlignment(.leading)
                    }
                } else {
                    // A collage: one large, two small.
                    GeometryReader { proxy in
                        let gap: CGFloat = 4
                        let large = (proxy.size.width - gap) * 0.62
                        let small = proxy.size.width - large - gap
                        HStack(spacing: gap) {
                            tile(0).frame(width: large, height: proxy.size.height)
                            VStack(spacing: gap) {
                                tile(1).frame(width: small, height: (proxy.size.height - gap) / 2)
                                tile(2).frame(width: small, height: (proxy.size.height - gap) / 2)
                            }
                        }
                    }
                    .frame(height: 180)
                    .clipShape(.rect(cornerRadius: 18, style: .continuous))
                }
            }
            .padding(16)
            .background(.background.secondary, in: .rect(cornerRadius: 24, style: .continuous))
        }
        .buttonStyle(PressableStyle())
    }

    @ViewBuilder
    private func tile(_ index: Int) -> some View {
        if index < photos.count {
            PhotoThumbnail(photo: photos[index], square: false)
        } else {
            Color.secondary.opacity(0.12)
        }
    }
}

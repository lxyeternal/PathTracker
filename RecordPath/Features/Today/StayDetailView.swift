import SwiftUI
import SwiftData
import MapKit
import Photos

/// Details for one stay, where the user can name the place (applies to every visit
/// nearby), mark it as home/school/work or a sight, post photos and words, open it in Maps or delete it.
struct StayDetailView: View {
    @Bindable var stay: Stay
    /// Hidden when the sheet is already shown from that day.
    var showsDayLink = true
    @Environment(AppNavigator.self) private var navigator
    private var zones = PrivacyZones.shared
    @Environment(\.modelContext) private var context
    @Environment(\.dismiss) private var dismiss
    @Environment(\.placeTagger) private var tagger
    @Environment(LocationEngine.self) private var engine

    @State private var name = ""
    @State private var kind: PlaceKind = .none
    @State private var composing = false
    @State private var pagerStart: TripPhoto?
    @State private var confirmingDelete = false
    @State private var photos: [PHAsset] = []

    enum PlaceKind: String, CaseIterable, Identifiable {
        case none, home, school, work, sight
        var id: String { rawValue }
        var title: String {
            switch self {
            case .none: String(localized: "自动识别", bundle: .appLanguage)
            case .sight: String(localized: "place.kind.sight", defaultValue: "景点", bundle: .appLanguage)
            case .home: String(localized: "家", bundle: .appLanguage)
            case .school: String(localized: "学校", bundle: .appLanguage)
            case .work: String(localized: "公司", bundle: .appLanguage)
            }
        }
        var name: String {
            switch self {
            case .none: ""
            case .home: String(localized: "家", bundle: .appLanguage)
            case .school: String(localized: "学校", bundle: .appLanguage)
            case .work: String(localized: "公司", bundle: .appLanguage)
            case .sight: ""
            }
        }
        var symbol: String {
            switch self {
            case .none: "sparkle.magnifyingglass"
            case .sight: "binoculars.fill"
            case .home: "house.fill"
            case .school: "graduationcap.fill"
            case .work: "briefcase.fill"
            }
        }
    }

    private var posted: [TripPhoto] { (stay.photos ?? []).sorted { $0.takenAt < $1.takenAt } }

    /// The post for this visit: its photos and words, or an invitation to write one.
    @ViewBuilder
    private var postSection: some View {
        Section {
            if posted.isEmpty && (stay.note ?? "").isEmpty {
                Button { composing = true } label: {
                    HStack(spacing: 14) {
                        Image(systemName: "photo.badge.plus")
                            .font(.title2)
                            .foregroundStyle(.white)
                            .frame(width: 48, height: 48)
                            .background(RoundedRectangle(cornerRadius: 14, style: .continuous).fill(Color.accentColor.gradient))
                        VStack(alignment: .leading, spacing: 2) {
                            Text("发布照片和心情").font(.headline).foregroundStyle(.primary)
                            Text(photos.isEmpty ? String(localized: "留下这一刻", bundle: .appLanguage)
                                                : String(localized: "你在这里拍了 \(photos.count) 张照片", bundle: .appLanguage))
                                .font(.subheadline).foregroundStyle(.secondary)
                        }
                    }
                }
            } else {
                if let note = stay.note, !note.isEmpty {
                    Text(note).font(.body)
                }
                if !posted.isEmpty {
                    LazyVGrid(columns: Array(repeating: GridItem(.flexible(), spacing: 4), count: 3), spacing: 4) {
                        ForEach(posted) { photo in
                            Button { pagerStart = photo } label: { PhotoThumbnail(photo: photo, cornerRadius: 10) }
                                .buttonStyle(.plain)
                        }
                    }
                    .listRowInsets(EdgeInsets(top: 8, leading: 12, bottom: 8, trailing: 12))
                }
                Button("编辑", systemImage: "square.and.pencil") { composing = true }
            }
        } header: {
            Text("动态")
        }
    }

    var body: some View {
        NavigationStack {
            Form {
                Section {
                    Map(initialPosition: .camera(MapCamera(centerCoordinate: stay.coordinate.onMap, distance: 900))) {
                        Annotation(stay.displayName, coordinate: stay.coordinate.onMap) {
                            PlaceIcon(category: stay.category, isLandmark: stay.isLandmark, size: 34)
                                .overlay(Circle().stroke(.white, lineWidth: 2))
                        }
                    }
                    .frame(height: 200)
                    .listRowInsets(EdgeInsets())
                }

                Section {
                    TextField(stay.placeName ?? stay.street ?? String(localized: "给这个地方起个名字", bundle: .appLanguage), text: $name)
                        .submitLabel(.done)
                    Picker("类型", selection: $kind) {
                        ForEach(PlaceKind.allCases) { kind in
                            Label(kind.title, systemImage: kind.symbol).tag(kind)
                        }
                    }
                } header: {
                    Text("名称")
                } footer: {
                    Text(kindFooter)
                }

                postSection

                Section("时间") {
                    LabeledContent("到达", value: stay.arrival.formatted(Date.FormatStyle(date: .abbreviated, time: .shortened, locale: appLocale)))
                    LabeledContent("离开", value: stay.departure?.formatted(Date.FormatStyle(date: .abbreviated, time: .shortened, locale: appLocale))
                                   ?? String(localized: "仍在这里", bundle: .appLanguage))
                    LabeledContent("停留", value: Format.duration(stay.duration))
                }

                Section("位置") {
                    if let placeName = stay.placeName { LabeledContent("地点名称", value: placeName) }
                    if let street = stay.street { LabeledContent("街道", value: street) }
                    if let city = stay.city { LabeledContent("所在城市", value: city) }
                    if let country = stay.country {
                        LabeledContent("国家/地区", value: "\(String.flag(for: stay.countryCode)) \(country)")
                    }
                    if stay.tagState != .tagged {
                        Button("重新识别地点", systemImage: "arrow.clockwise") {
                            stay.tagState = .pending
                            try? context.save()
                            tagger?.enqueue()
                        }
                    }
                    if showsDayLink {
                        Button("查看这一天的轨迹", systemImage: "calendar") {
                            dismiss()
                            navigator.show(day: stay.arrival)
                        }
                    }
                    Button("在“地图”中打开", systemImage: "map") { openInMaps() }
                }

                Section {
                    let hidden = zones.isHidden(stay.coordinate)
                    Toggle(isOn: Binding(
                        get: { hidden },
                        set: { hide in
                            if hide {
                                zones.add(name: stay.displayName, at: stay.coordinate)
                            } else if let zone = zones.zone(near: stay.coordinate) {
                                zones.remove(zone)
                            }
                        })) {
                        Label("分享和导出时隐藏这里", systemImage: "eye.slash")
                    }
                } footer: {
                    Text("周围 300 米内的轨迹和地点不会出现在分享图片和 GPX 文件里，你自己仍然能看到。适合家和其他私人地点。")
                }

                Section {
                    Button("删除这条记录", systemImage: "trash", role: .destructive) { confirmingDelete = true }
                }
            }
            .task { photos = DayPhotos.assets(in: DayPhotos.interval(of: stay)) }
            .sheet(isPresented: $composing) { PostComposer(stay: stay) }
            .fullScreenCover(item: $pagerStart) { PhotoPager(photos: posted, selection: $0.id) }
            .navigationTitle(stay.displayName)
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("取消", systemImage: "xmark") { dismiss() }
                }
                ToolbarItem(placement: .confirmationAction) {
                    Button("完成", systemImage: "checkmark") { save() }
                }
            }
            .confirmationDialog("删除这条停留记录？", isPresented: $confirmingDelete, titleVisibility: .visible) {
                Button("删除", role: .destructive) {
                    context.delete(stay)
                    try? context.save()
                    engine.reloadAfterDataChange(discardPending: false)
                    dismiss()
                }
            } message: {
                Text("轨迹会保留，只删除这个地点的停留记录。")
            }
            .onAppear(perform: load)
        }
        .presentationDetents([.large])
    }

    private var kindFooter: String {
        switch kind {
        case .none where stay.isLandmark:
            String(localized: "已自动识别为景点。名称和类型会应用到附近 150 米内的所有到访记录。", bundle: .appLanguage)
        case .none:
            String(localized: "漫迹会自动识别景点和店铺。没认出来的景点，可以在这里选“景点”。名称和类型会应用到附近 150 米内的所有到访记录。", bundle: .appLanguage)
        case .sight:
            String(localized: "这里会算作景点，出现在旅程和年度足迹里。名称和类型会应用到附近 150 米内的所有到访记录。", bundle: .appLanguage)
        default:
            String(localized: "名称和类型会应用到附近 150 米内的所有到访记录。", bundle: .appLanguage)
        }
    }

    private static func kind(of stay: Stay) -> PlaceKind {
        if let personal = PlaceKind(rawValue: stay.categoryRaw ?? ""), personal != .sight { return personal }
        return stay.isLandmark && UserMarkedSights.contains(stay) ? .sight : .none
    }

    private func load() {
        name = stay.customName ?? ""
        kind = Self.kind(of: stay)
    }

    private func save() {
        let newName = name.trimmingCharacters(in: .whitespacesAndNewlines)
        let previousKind = Self.kind(of: stay)
        if newName != (stay.customName ?? "") || kind != previousKind {
            let change: KnownPlaces.CategoryChange = switch kind {
            case .sight: .sight
            case .none: previousKind != .none ? .clear : .keep
            default: .set(kind.rawValue)
            }
            let personal = kind != .none && kind != .sight
            KnownPlaces.rename(stay, to: newName.isEmpty && personal ? kind.name : newName, category: change, in: context)
            if kind == .sight { UserMarkedSights.add(stay) } else if previousKind == .sight { UserMarkedSights.remove(stay) }
            // Back to automatic: look the place up again for its real category.
            if case .clear = change { tagger?.enqueue() }
        }
        try? context.save()
        dismiss()
    }

    private func openInMaps() {
        let item = MKMapItem(location: stay.location, address: nil)
        item.name = stay.displayName
        item.openInMaps()
    }
}

/// Places the user marked as sights by hand, so the picker shows "景点" for them rather than
/// "自动识别". Kept as coordinates in iCloud key-value storage, like privacy zones.
enum UserMarkedSights {
    private static let key = "places.userSights"
    private static var store: NSUbiquitousKeyValueStore { .default }

    private static var all: [[Double]] {
        get { (store.array(forKey: key) as? [[Double]]) ?? (UserDefaults.standard.array(forKey: key) as? [[Double]]) ?? [] }
        set {
            store.set(newValue, forKey: key)
            UserDefaults.standard.set(newValue, forKey: key)
        }
    }

    static func contains(_ stay: Stay) -> Bool {
        all.contains { CLLocation(latitude: $0[0], longitude: $0[1]).distance(from: stay.location) <= KnownPlaces.radius }
    }

    static func add(_ stay: Stay) {
        guard !contains(stay) else { return }
        all.append([stay.latitude, stay.longitude])
    }

    static func remove(_ stay: Stay) {
        all.removeAll { CLLocation(latitude: $0[0], longitude: $0[1]).distance(from: stay.location) <= KnownPlaces.radius }
    }
}

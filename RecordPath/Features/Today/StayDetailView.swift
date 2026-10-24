import SwiftUI
import SwiftData
import MapKit
import Photos

/// Details for one stay, where the user can name the place (applies to every visit
/// nearby), mark it as home/school/work, add a note, open it in Maps or delete it.
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
    @State private var note = ""
    @State private var confirmingDelete = false
    @State private var photos: [PHAsset] = []
    @State private var viewingPhoto: PHAsset?

    enum PlaceKind: String, CaseIterable, Identifiable {
        case none, home, school, work
        var id: String { rawValue }
        var title: LocalizedStringKey {
            switch self {
            case .none: "无"
            case .home: "家"
            case .school: "学校"
            case .work: "公司"
            }
        }
        var name: String {
            switch self {
            case .none: ""
            case .home: String(localized: "家", bundle: .appLanguage)
            case .school: String(localized: "学校", bundle: .appLanguage)
            case .work: String(localized: "公司", bundle: .appLanguage)
            }
        }
        var symbol: String {
            switch self {
            case .none: "mappin"
            case .home: "house.fill"
            case .school: "graduationcap.fill"
            case .work: "briefcase.fill"
            }
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
                    Text("名称会应用到附近 150 米内的所有到访记录，比如把这里叫作“家”。")
                }

                if !photos.isEmpty {
                    Section("在这里拍的照片") {
                        LazyVGrid(columns: [GridItem(.adaptive(minimum: 76), spacing: 6)], spacing: 6) {
                            ForEach(photos, id: \.localIdentifier) { asset in
                                Button { viewingPhoto = asset } label: { AssetThumbnail(asset: asset, side: 76) }
                                    .buttonStyle(.plain)
                            }
                        }
                        .padding(.vertical, 4)
                    }
                }

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

                Section("备注") {
                    TextField("写点什么…", text: $note, axis: .vertical)
                        .lineLimit(3...8)
                }

                Section {
                    Button("删除这条记录", systemImage: "trash", role: .destructive) { confirmingDelete = true }
                }
            }
            .task { photos = DayPhotos.assets(in: DayPhotos.interval(of: stay)) }
            .fullScreenCover(item: Binding(get: { viewingPhoto.map(IdentifiedAsset.init) }, set: { viewingPhoto = $0?.asset })) {
                AssetViewer(asset: $0.asset)
            }
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

    private func load() {
        name = stay.customName ?? ""
        note = stay.note ?? ""
        kind = PlaceKind(rawValue: stay.categoryRaw ?? "") ?? .none
    }

    private func save() {
        let newName = name.trimmingCharacters(in: .whitespacesAndNewlines)
        let previousKind = PlaceKind(rawValue: stay.categoryRaw ?? "") ?? .none
        if newName != (stay.customName ?? "") || kind != previousKind {
            let change: KnownPlaces.CategoryChange =
                kind != .none ? .set(kind.rawValue) : previousKind != .none ? .clear : .keep
            KnownPlaces.rename(stay, to: newName.isEmpty && kind != .none ? kind.name : newName,
                               category: change, in: context)
            // Without a home/school/work kind, look the place up again for its real category.
            if case .clear = change { tagger?.enqueue() }
        }
        stay.note = note.trimmingCharacters(in: .whitespacesAndNewlines).nilIfEmpty
        try? context.save()
        dismiss()
    }

    private func openInMaps() {
        let item = MKMapItem(location: stay.location, address: nil)
        item.name = stay.displayName
        item.openInMaps()
    }
}

private struct IdentifiedAsset: Identifiable {
    let asset: PHAsset
    var id: String { asset.localIdentifier }
}

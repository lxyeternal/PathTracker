import SwiftUI
import SwiftData
import PhotosUI
import Photos

/// Posting about a place: photos (those taken there come first) and a few words. Posts show on
/// the timeline, on the place, in a trip covering that time, and in the gallery.
struct PostComposer: View {
    let stay: Stay
    @Environment(\.modelContext) private var context
    @Environment(\.dismiss) private var dismiss

    @State private var text = ""
    @State private var nearby: [PHAsset] = []
    @State private var chosenAssets: [PHAsset] = []
    @State private var pickerItems: [PhotosPickerItem] = []
    @State private var pickedImages: [(id: UUID, data: Data, image: UIImage)] = []
    @State private var isSaving = false
    @FocusState private var textFocused: Bool

    /// Something to post: photos, or a note that differs from what's there (clearing it counts).
    private var hasChanges: Bool {
        !chosenAssets.isEmpty || !pickedImages.isEmpty
            || text.trimmingCharacters(in: .whitespacesAndNewlines) != (stay.note ?? "").trimmingCharacters(in: .whitespacesAndNewlines)
    }

    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(alignment: .leading, spacing: 22) {
                    header
                    TextField("这一刻，想记下点什么…", text: $text, axis: .vertical)
                        .lineLimit(3...8)
                        .font(.body)
                        .focused($textFocused)
                        .padding(14)
                        .background(.background.secondary, in: .rect(cornerRadius: 18, style: .continuous))
                    if !chosenAssets.isEmpty || !pickedImages.isEmpty { selection }
                    if !nearby.isEmpty { nearbyGrid }
                    PhotosPicker(selection: $pickerItems, maxSelectionCount: 20, matching: .images) {
                        Label("从相册选择", systemImage: "photo.on.rectangle.angled")
                            .font(.headline)
                            .frame(maxWidth: .infinity)
                            .frame(height: 48)
                            .background(.background.secondary, in: .rect(cornerRadius: 16, style: .continuous))
                    }
                }
                .padding()
            }
            .navigationTitle("发布")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("取消", systemImage: "xmark") { dismiss() }
                }
                ToolbarItem(placement: .confirmationAction) {
                    if isSaving {
                        ProgressView()
                    } else {
                        Button("发布", systemImage: "paperplane.fill", action: save)
                            .disabled(!hasChanges)
                    }
                }
            }
            .task {
                text = stay.note ?? ""
                if DayPhotos.status == .notDetermined { _ = await DayPhotos.requestAccess() }
                nearby = DayPhotos.assets(in: DayPhotos.interval(of: stay))
            }
            .onChange(of: pickerItems) { _, items in load(items) }
            .sensoryFeedback(.selection, trigger: chosenAssets.count)
            .interactiveDismissDisabled(hasChanges)
        }
    }

    private var header: some View {
        HStack(spacing: 12) {
            PlaceIcon(category: stay.category, isLandmark: stay.isLandmark, size: 44)
            VStack(alignment: .leading, spacing: 2) {
                Text(stay.displayName).font(.headline)
                Text(stay.arrival.formatted(Date.FormatStyle(date: .abbreviated, time: .shortened, locale: appLocale)))
                    .font(.subheadline).foregroundStyle(.secondary)
            }
        }
    }

    /// What's been chosen so far, in a row, each with a remove button.
    private var selection: some View {
        ScrollView(.horizontal) {
            HStack(spacing: 10) {
                ForEach(chosenAssets, id: \.localIdentifier) { asset in
                    AssetThumbnail(asset: asset, side: 92)
                        .overlay(alignment: .topTrailing) { removeButton { chosenAssets.removeAll { $0 == asset } } }
                        .transition(.scale.combined(with: .opacity))
                }
                ForEach(pickedImages, id: \.id) { item in
                    Image(uiImage: item.image).resizable().scaledToFill()
                        .frame(width: 92, height: 92)
                        .clipShape(.rect(cornerRadius: 16, style: .continuous))
                        .overlay(alignment: .topTrailing) { removeButton { pickedImages.removeAll { $0.id == item.id } } }
                        .transition(.scale.combined(with: .opacity))
                }
            }
            .padding(.vertical, 4)
            .animation(.snappy, value: chosenAssets.count + pickedImages.count)
        }
        .scrollIndicators(.hidden)
    }

    private func removeButton(_ action: @escaping () -> Void) -> some View {
        Button(action: action) {
            Image(systemName: "xmark.circle.fill")
                .font(.title3)
                .symbolRenderingMode(.palette)
                .foregroundStyle(.white, .black.opacity(0.5))
        }
        .padding(4)
    }

    private var nearbyGrid: some View {
        VStack(alignment: .leading, spacing: 10) {
            Text("在这里拍的").font(.headline)
            LazyVGrid(columns: Array(repeating: GridItem(.flexible(), spacing: 4), count: 4), spacing: 4) {
                ForEach(nearby, id: \.localIdentifier) { asset in
                    let index = chosenAssets.firstIndex(of: asset)
                    Button {
                        withAnimation(.snappy) {
                            if let index { chosenAssets.remove(at: index) } else { chosenAssets.append(asset) }
                        }
                    } label: {
                        GeometryReader { proxy in
                            AssetThumbnail(asset: asset, side: proxy.size.width)
                        }
                        .aspectRatio(1, contentMode: .fit)
                        .overlay(alignment: .topTrailing) {
                            ZStack {
                                Circle().fill(index == nil ? Color.black.opacity(0.25) : Color.accentColor)
                                Circle().stroke(.white, lineWidth: 1.5)
                                if let index { Text("\(index + 1)").font(.caption2.bold()).foregroundStyle(.white) }
                            }
                            .frame(width: 22, height: 22)
                            .padding(5)
                        }
                        .scaleEffect(index == nil ? 1 : 0.94)
                    }
                    .buttonStyle(.plain)
                }
            }
        }
    }

    private func load(_ items: [PhotosPickerItem]) {
        guard !items.isEmpty else { return }
        Task {
            for item in items {
                guard let data = try? await item.loadTransferable(type: Data.self), let image = UIImage(data: data),
                      let preview = image.preparingThumbnail(of: CGSize(width: 300, height: 300)) else { continue }
                withAnimation(.snappy) { pickedImages.append((UUID(), data, preview)) }
            }
            pickerItems = []
        }
    }

    private func save() {
        isSaving = true
        Task {
            var datas: [(Data, Date)] = []
            for asset in chosenAssets {
                if let data = await PhotoImport.data(for: asset) { datas.append((data, asset.creationDate ?? stay.arrival)) }
            }
            datas += pickedImages.map { ($0.data, stay.arrival) }
            let trip = coveringTrip()
            for (data, date) in datas {
                guard let photo = PhotoImport.makePhoto(from: data, fallbackDate: date, fallbackCoordinate: stay.coordinate) else { continue }
                // An older photo posted here belongs to this visit in the gallery and on the timeline.
                if abs(photo.takenAt.timeIntervalSince(stay.arrival)) > 2 * 86_400 { photo.takenAt = stay.arrival }
                photo.stay = stay
                photo.trip = trip
                context.insert(photo)
            }
            stay.note = text.trimmingCharacters(in: .whitespacesAndNewlines).nilIfEmpty
            try? context.save()
            isSaving = false
            dismiss()
        }
    }

    /// A trip or recording happening at the time, so the photos show there too.
    private func coveringTrip() -> Trip? {
        let arrival = stay.arrival
        let trips = (try? context.fetch(FetchDescriptor<Trip>(predicate: #Predicate { $0.startDate <= arrival }))) ?? []
        return trips.first { $0.interval.contains(arrival) && !$0.isRecording } ?? trips.first { $0.interval.contains(arrival) }
    }
}

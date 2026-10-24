import SwiftUI
import SwiftData
import PhotosUI
import ImageIO
import CoreLocation

struct TripDetailView: View {
    @Bindable var trip: Trip
    @Environment(\.modelContext) private var context
    @Environment(\.dismiss) private var dismiss
    @Environment(LocationEngine.self) private var engine
    @Environment(AppNavigator.self) private var navigator

    @Query private var chunks: [TrackChunk]
    @Query private var candidateStays: [Stay]
    @State private var pickerItems: [PhotosPickerItem] = []
    @State private var viewingPhoto: TripPhoto?
    @State private var selectedStay: Stay?
    @State private var showingMap = false
    @State private var showingEdit = false
    @State private var confirmingEnd = false
    @State private var confirmingDelete = false
    @State private var isImporting = false
    @Namespace private var namespace

    init(trip: Trip) {
        self.trip = trip
        let start = trip.startDate
        let end = trip.endDate ?? Date.distantFuture
        _chunks = Query(filter: #Predicate<TrackChunk> { $0.endDate >= start && $0.startDate <= end }, sort: \TrackChunk.startDate)
        _candidateStays = Query(filter: #Predicate<Stay> { $0.arrival <= end }, sort: \Stay.arrival)
    }

    private var stays: [Stay] {
        candidateStays.filter { ($0.departure ?? Date()) >= trip.startDate }
    }

    private var photos: [TripPhoto] { (trip.photos ?? []).sorted { $0.takenAt < $1.takenAt } }

    private var countries: [String] {
        stays.compactMap(\.countryCode).removingDuplicates()
    }

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 16) {
                mapCard
                if trip.isActive { endButton }
                metrics
                photosSection
                notesSection
                if !stays.isEmpty { daysSection }
            }
            .padding(.horizontal)
            .padding(.bottom, 24)
        }
        .navigationTitle("\(trip.coverEmoji) \(trip.title)")
        .navigationBarTitleDisplayMode(.inline)
        .toolbar {
            ToolbarItem(placement: .topBarTrailing) {
                Menu("更多", systemImage: "ellipsis") {
                    Button("编辑旅程", systemImage: "pencil") { showingEdit = true }
                    ShareCardButton(makeContent: {
                        ShareCardContent(title: "\(trip.coverEmoji) \(trip.title)",
                                         subtitle: trip.dateRangeText,
                                         chunks: chunks, stays: stays,
                                         stats: [(String(localized: "距离", bundle: .appLanguage), Format.distance(chunks.reduce(0) { $0 + $1.distance })),
                                                 (String(localized: "天数", bundle: .appLanguage), "\(Calendar.current.days(in: trip.interval).count)"),
                                                 (String(localized: "地点", bundle: .appLanguage), "\(stays.count)")])
                    })
                    ShareLink(item: GPXDocument(name: trip.title, chunks: chunks, stays: stays),
                              preview: SharePreview("\(trip.title).gpx")) {
                        Label("导出 GPX", systemImage: "square.and.arrow.up")
                    }
                    Divider()
                    Button("删除旅程", systemImage: "trash", role: .destructive) { confirmingDelete = true }
                }
            }
        }
        .sheet(isPresented: $showingEdit) { EditTripSheet(trip: trip) }
        .sheet(item: $selectedStay) { StayDetailView(stay: $0) }
        .sheet(item: $viewingPhoto) { PhotoViewer(photo: $0) }
        .fullScreenCover(isPresented: $showingMap) {
            DayMapScreen(title: trip.title, chunks: chunks, stays: stays,
                         livePoints: trip.isActive ? engine.pendingPoints : [])
                .navigationTransition(.zoom(sourceID: "trip-map", in: namespace))
        }
        .confirmationDialog("结束这段旅程？", isPresented: $confirmingEnd, titleVisibility: .visible) {
            Button("结束旅程") { withAnimation { engine.endTrip(trip) } }
        } message: {
            Text("之后仍会继续自动记录日常轨迹。")
        }
        .confirmationDialog("删除“\(trip.title)”？", isPresented: $confirmingDelete, titleVisibility: .visible) {
            Button("删除旅程", role: .destructive) {
                if trip.isActive { engine.endTrip(trip) }
                context.delete(trip)
                try? context.save()
                dismiss()
            }
        } message: {
            Text("照片和备注会被删除，轨迹和地点仍保留在每天的记录里。")
        }
        .onChange(of: pickerItems) { _, items in importPhotos(items) }
    }

    /// The trip day by day, each day opening its full timeline.
    private var tripDays: [(day: Date, stays: [Stay])] {
        let calendar = Calendar.current
        let days = calendar.days(in: trip.interval)
        return days.map { day in
            let interval = calendar.dayInterval(for: day)
            return (day, stays.filter { $0.arrival < interval.end && ($0.departure ?? Date()) > interval.start })
        }
    }

    private var daysSection: some View {
        VStack(alignment: .leading, spacing: 10) {
            SectionHeader(title: "每一天", trailing: "\(tripDays.count) 天")
            ForEach(Array(tripDays.enumerated()), id: \.offset) { index, entry in
                VStack(alignment: .leading, spacing: 0) {
                    Button {
                        navigator.show(day: entry.day)
                    } label: {
                        HStack {
                            Text("第 \(index + 1) 天").font(.headline)
                            Text(entry.day.formatted(.dateTime.month().day().weekday(.abbreviated).locale(appLocale)))
                                .foregroundStyle(.secondary)
                            Spacer()
                            Label("当天轨迹", systemImage: "calendar").font(.subheadline).foregroundStyle(.tint)
                        }
                        .padding(.horizontal, 16)
                        .padding(.vertical, 12)
                        .contentShape(.rect)
                    }
                    .buttonStyle(.plain)
                    if entry.stays.isEmpty {
                        Text("这一天没有停留记录").font(.subheadline).foregroundStyle(.secondary)
                            .padding(.horizontal, 16).padding(.bottom, 12)
                    }
                    ForEach(entry.stays) { stay in
                        Button { selectedStay = stay } label: { PlaceRow(stay: stay, timeOnly: true) }.buttonStyle(.plain)
                    }
                }
                .padding(.bottom, 4)
                .background(.background.secondary, in: .rect(cornerRadius: 24, style: .continuous))
            }
        }
    }

    private var mapCard: some View {
        Button { showingMap = true } label: {
            TrackMap(chunks: chunks, stays: stays, livePoints: trip.isActive ? engine.pendingPoints : [], interactive: false)
                .allowsHitTesting(false)
                .frame(height: 280)
                .clipShape(.rect(cornerRadius: 28, style: .continuous))
                .overlay {
                    if chunks.isEmpty && stays.isEmpty {
                        ZStack {
                            Rectangle().fill(.ultraThinMaterial)
                            Label(trip.isActive ? "出发后轨迹会出现在这里" : "这段时间没有轨迹", systemImage: "map")
                                .font(.headline).foregroundStyle(.secondary)
                        }
                        .clipShape(.rect(cornerRadius: 28, style: .continuous))
                    }
                }
        }
        .buttonStyle(PressableStyle())
        .matchedTransitionSource(id: "trip-map", in: namespace)
    }

    private var endButton: some View {
        Button { confirmingEnd = true } label: {
            Label("结束旅程", systemImage: "flag.checkered")
                .font(.headline)
                .frame(maxWidth: .infinity)
                .frame(height: 50)
        }
        .buttonStyle(.glassProminent)
        .tint(.orange)
    }

    private var metrics: some View {
        MetricGrid {
            MetricTile(title: "距离", value: Format.distance(chunks.reduce(0) { $0 + $1.distance }
                                                             + (trip.isActive ? TrackPoint.distance(of: engine.pendingPoints) : 0)),
                       symbol: "point.topright.arrow.triangle.backward.to.point.bottomleft.scurvepath", tint: .blue)
            MetricTile(title: "用时", value: Format.duration(trip.interval.duration), symbol: "clock.fill", tint: .orange)
            MetricTile(title: "地点", value: "\(stays.count)", symbol: "mappin.and.ellipse", tint: .pink)
            MetricTile(title: "国家和地区", value: countries.isEmpty ? "—" : countries.map { String.flag(for: $0) }.joined(),
                       symbol: "flag.fill", tint: .red)
        }
    }

    private var photosSection: some View {
        VStack(alignment: .leading, spacing: 10) {
            HStack {
                SectionHeader(title: "照片")
                if isImporting { ProgressView().padding(.top, 8) }
                PhotosPicker(selection: $pickerItems, maxSelectionCount: 30, matching: .images) {
                    Label("添加", systemImage: "plus").font(.subheadline.weight(.semibold))
                }
                .padding(.top, 8)
            }
            if photos.isEmpty {
                PhotosPicker(selection: $pickerItems, maxSelectionCount: 30, matching: .images) {
                    VStack(spacing: 8) {
                        Image(systemName: "photo.on.rectangle.angled").font(.largeTitle)
                        Text("为这段旅程添加照片").font(.subheadline)
                    }
                    .foregroundStyle(.secondary)
                    .frame(maxWidth: .infinity)
                    .frame(height: 120)
                    .background(.background.secondary, in: .rect(cornerRadius: 24, style: .continuous))
                }
                .buttonStyle(.plain)
            } else {
                LazyVGrid(columns: [GridItem(.adaptive(minimum: 100), spacing: 4)], spacing: 4) {
                    ForEach(photos) { photo in
                        Button { viewingPhoto = photo } label: {
                            PhotoThumbnail(photo: photo)
                        }
                        .buttonStyle(.plain)
                    }
                }
                .clipShape(.rect(cornerRadius: 20, style: .continuous))
            }
        }
    }

    private var notesSection: some View {
        VStack(alignment: .leading, spacing: 10) {
            SectionHeader(title: "备注")
            TextField("记下这段旅程的故事…", text: $trip.notes, axis: .vertical)
                .lineLimit(3...12)
                .padding(16)
                .background(.background.secondary, in: .rect(cornerRadius: 24, style: .continuous))
                .onSubmit { try? context.save() }
        }
    }

    private func importPhotos(_ items: [PhotosPickerItem]) {
        guard !items.isEmpty else { return }
        isImporting = true
        Task {
            for item in items {
                guard let data = try? await item.loadTransferable(type: Data.self),
                      let image = UIImage(data: data) else { continue }
                // Re-encode at a sensible size; full-resolution originals stay in the photo library.
                let jpeg = image.preparingThumbnail(of: image.size.fitting(maxDimension: 2048))?.jpegData(compressionQuality: 0.82) ?? data
                let metadata = PhotoMetadata(data: data)
                let photo = TripPhoto(imageData: jpeg, takenAt: metadata.date ?? Date(),
                                      coordinate: metadata.coordinate ?? engine.currentLocation?.coordinate)
                photo.trip = trip
                context.insert(photo)
            }
            try? context.save()
            pickerItems = []
            isImporting = false
        }
    }
}

private extension CGSize {
    func fitting(maxDimension: CGFloat) -> CGSize {
        let scale = min(1, maxDimension / max(width, height))
        return CGSize(width: width * scale, height: height * scale)
    }
}

private struct PhotoThumbnail: View {
    let photo: TripPhoto
    @State private var image: UIImage?

    var body: some View {
        Color.secondary.opacity(0.15)
            .aspectRatio(1, contentMode: .fit)
            .overlay {
                if let image {
                    Image(uiImage: image).resizable().scaledToFill()
                }
            }
            .clipped()
            .task(id: photo.id) {
                guard let data = photo.imageData else { return }
                image = await Task.detached { UIImage(data: data)?.preparingThumbnail(of: CGSize(width: 300, height: 300)) }.value
            }
    }
}

private struct PhotoViewer: View {
    @Bindable var photo: TripPhoto
    @Environment(\.modelContext) private var context
    @Environment(\.dismiss) private var dismiss
    @State private var confirmingDelete = false
    @State private var caption = ""

    var body: some View {
        NavigationStack {
            VStack(spacing: 16) {
                if let data = photo.imageData, let image = UIImage(data: data) {
                    Image(uiImage: image)
                        .resizable()
                        .scaledToFit()
                        .clipShape(.rect(cornerRadius: 16, style: .continuous))
                        .frame(maxHeight: .infinity)
                }
                TextField("添加说明", text: $caption, axis: .vertical)
                    .padding(14)
                    .background(.background.secondary, in: .rect(cornerRadius: 16, style: .continuous))
            }
            .padding()
            .navigationTitle(photo.takenAt.formatted(Date.FormatStyle(date: .abbreviated, time: .shortened, locale: appLocale)))
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("删除", systemImage: "trash", role: .destructive) { confirmingDelete = true }
                }
                ToolbarItem(placement: .confirmationAction) {
                    Button("完成", systemImage: "checkmark") {
                        photo.caption = caption.trimmingCharacters(in: .whitespacesAndNewlines).nilIfEmpty
                        try? context.save()
                        dismiss()
                    }
                }
            }
            .confirmationDialog("删除这张照片？", isPresented: $confirmingDelete, titleVisibility: .visible) {
                Button("删除照片", role: .destructive) {
                    context.delete(photo)
                    try? context.save()
                    dismiss()
                }
            }
            .onAppear { caption = photo.caption ?? "" }
        }
    }
}

struct EditTripSheet: View {
    @Bindable var trip: Trip
    @Environment(\.modelContext) private var context
    @Environment(\.dismiss) private var dismiss
    @State private var title = ""
    @State private var emoji = ""
    @State private var startDate = Date()
    @State private var endDate = Date()

    var body: some View {
        NavigationStack {
            Form {
                Section("名称") {
                    TextField("旅程名称", text: $title)
                    EmojiPicker(selection: $emoji)
                }
                Section("时间") {
                    DatePicker("开始", selection: $startDate, in: ...(trip.isActive ? Date() : endDate))
                    if !trip.isActive {
                        DatePicker("结束", selection: $endDate, in: startDate...Date())
                    }
                }
            }
            .navigationTitle("编辑旅程")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("取消", systemImage: "xmark") { dismiss() }
                }
                ToolbarItem(placement: .confirmationAction) {
                    Button("完成", systemImage: "checkmark") {
                        trip.title = title.trimmingCharacters(in: .whitespaces)
                        trip.coverEmoji = emoji
                        trip.startDate = startDate
                        if !trip.isActive { trip.endDate = endDate }
                        try? context.save()
                        dismiss()
                    }
                    .disabled(title.trimmingCharacters(in: .whitespaces).isEmpty)
                }
            }
            .onAppear {
                title = trip.title
                emoji = trip.coverEmoji
                startDate = trip.startDate
                endDate = trip.endDate ?? Date()
            }
        }
        .presentationDetents([.medium, .large])
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

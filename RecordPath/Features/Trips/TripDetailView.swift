import SwiftUI
import SwiftData
import PhotosUI
import Photos
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
    /// Photos in the library from the trip's days, read on the device.
    @State private var libraryPhotos: [PHAsset] = []
    @State private var showingGallery = false
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
                if !libraryPhotos.isEmpty {
                    PhotoStack(assets: libraryPhotos) { showingGallery = true }
                }
                mapCard
                if trip.isActive { endButton }
                metrics
                photosSection
                notesSection
                if !trip.isRecording && !stays.isEmpty { daysSection }
            }
            .padding(.horizontal)
            .padding(.bottom, 24)
        }
        .navigationTitle("\(trip.coverEmoji) \(trip.title)")
        .navigationBarTitleDisplayMode(.inline)
        .task(id: trip.id) {
            guard DayPhotos.canRead else { return }
            let interval = trip.interval
            libraryPhotos = await Task.detached(priority: .userInitiated) { DayPhotos.assets(in: interval) }.value
        }
        .sheet(isPresented: $showingGallery) {
            PhotoGallerySheet(title: trip.title, subtitle: trip.dateRangeText, assets: libraryPhotos)
        }
        .toolbar {
            ToolbarItem(placement: .topBarTrailing) {
                Menu("更多", systemImage: "ellipsis") {
                    Button("编辑", systemImage: "pencil") { showingEdit = true }
                    ShareCardButton(makeContent: {
                        ShareCardContent(title: "\(trip.coverEmoji) \(trip.title)",
                                         subtitle: trip.dateRangeText,
                                         chunks: chunks, stays: stays,
                                         stats: shareStats)
                    })
                    ShareLink(item: GPXDocument(name: trip.title, chunks: chunks, stays: stays),
                              preview: SharePreview("\(trip.title).gpx")) {
                        Label("导出 GPX", systemImage: "square.and.arrow.up")
                    }
                    Divider()
                    Button(trip.isRecording ? "删除记录" : "删除旅程", systemImage: "trash", role: .destructive) { confirmingDelete = true }
                }
            }
        }
        .sheet(isPresented: $showingEdit) { EditTripSheet(trip: trip) }
        .sheet(item: $selectedStay) { StayDetailView(stay: $0) }
        .fullScreenCover(item: $viewingPhoto) { PhotoPager(photos: photos, selection: $0.id) }
        .fullScreenCover(isPresented: $showingMap) {
            DayMapScreen(title: trip.title, chunks: chunks, stays: stays,
                         livePoints: trip.isActive ? engine.pendingPoints : [])
                .navigationTransition(.zoom(sourceID: "trip-map", in: namespace))
        }
        .confirmationDialog(trip.isRecording ? "结束这次记录？" : "结束这段旅程？", isPresented: $confirmingEnd, titleVisibility: .visible) {
            Button(trip.isRecording ? "结束记录" : "结束旅程") { withAnimation { engine.endTrip(trip) } }
        } message: {
            Text("之后仍会继续自动记录日常轨迹。")
        }
        .confirmationDialog("删除“\(trip.title)”？", isPresented: $confirmingDelete, titleVisibility: .visible) {
            Button(trip.isRecording ? "删除记录" : "删除旅程", role: .destructive) {
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
                    } else {
                        Label("查看地图", systemImage: "arrow.up.left.and.arrow.down.right")
                            .font(.footnote.weight(.semibold))
                            .padding(.horizontal, 12)
                            .padding(.vertical, 8)
                            .glassEffect(.regular, in: .capsule)
                            .padding(12)
                            .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .bottomLeading)
                    }
                }
        }
        .buttonStyle(PressableStyle())
        .matchedTransitionSource(id: "trip-map", in: namespace)
    }

    private var endButton: some View {
        Button { confirmingEnd = true } label: {
            Label(trip.isRecording ? "结束记录" : "结束旅程", systemImage: "flag.checkered")
                .font(.headline)
                .frame(maxWidth: .infinity)
                .frame(height: 50)
        }
        .buttonStyle(.glassProminent)
        .tint(.orange)
    }

    private var distance: Double {
        chunks.reduce(0) { $0 + $1.distance } + (trip.isActive ? TrackPoint.distance(of: engine.pendingPoints) : 0)
    }

    private var elevationGain: Double {
        chunks.reduce(0) { $0 + TrackPoint.elevationGain(of: $1.points) }
    }

    /// Minutes per kilometre on foot, average speed on a bike, as fitness apps show them.
    private var paceText: String {
        let seconds = trip.interval.duration
        guard distance > 50, seconds > 0 else { return "—" }
        if trip.activity == .cycling { return Format.speed(distance / seconds) }
        return Format.pace(secondsPerKilometre: seconds / (distance / 1000))
    }

    private var shareStats: [(String, String)] {
        let distanceStat = (String(localized: "距离", bundle: .appLanguage), Format.distance(distance))
        if trip.isRecording {
            return [distanceStat,
                    (String(localized: "用时", bundle: .appLanguage), Format.duration(trip.interval.duration)),
                    (String(localized: "爬升", bundle: .appLanguage), Format.elevation(elevationGain))]
        }
        return [distanceStat,
                (String(localized: "天数", bundle: .appLanguage), "\(Calendar.current.days(in: trip.interval).count)"),
                (String(localized: "地点", bundle: .appLanguage), "\(stays.count)")]
    }

    @ViewBuilder
    private var metrics: some View {
        if trip.isRecording {
            MetricGrid {
                MetricTile(title: "距离", value: Format.distance(distance),
                           symbol: "point.topright.arrow.triangle.backward.to.point.bottomleft.scurvepath", tint: .blue)
                MetricTile(title: "用时", value: Format.duration(trip.interval.duration), symbol: "clock.fill", tint: .orange)
                MetricTile(title: trip.activity == .cycling ? "均速" : "配速", value: paceText, symbol: "speedometer", tint: .green)
                MetricTile(title: "爬升", value: Format.elevation(elevationGain), symbol: "mountain.2.fill", tint: .brown)
            }
        } else {
            tripMetrics
        }
    }

    private var tripMetrics: some View {
        MetricGrid {
            MetricTile(title: "距离", value: Format.distance(distance),
                       symbol: "point.topright.arrow.triangle.backward.to.point.bottomleft.scurvepath", tint: .blue)
            MetricTile(title: "用时", value: Format.duration(trip.interval.duration), symbol: "clock.fill", tint: .orange)
            MetricTile(title: "地点", value: "\(stays.count)", symbol: "mappin.and.ellipse", tint: .pink)
            MetricTile(title: "国家与地区", value: countries.isEmpty ? "—" : countries.map { String.flag(for: $0) }.joined(),
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
                        Text(trip.isRecording ? "为这次记录添加照片" : "为这段旅程添加照片").font(.subheadline)
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
            TextField(trip.isRecording ? "记下这次的感受…" : "记下这段旅程的故事…", text: $trip.notes, axis: .vertical)
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
                      let photo = PhotoImport.makePhoto(from: data, fallbackDate: Date(),
                                                        fallbackCoordinate: engine.currentLocation?.coordinate) else { continue }
                photo.trip = trip
                context.insert(photo)
            }
            try? context.save()
            pickerItems = []
            isImporting = false
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

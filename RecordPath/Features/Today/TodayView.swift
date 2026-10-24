import SwiftUI
import Photos
import SwiftData
import CoreLocation

struct TodayView: View {
    @Binding var showingSettings: Bool
    @Environment(AppNavigator.self) private var navigator
    @State private var showingCalendar = false
    @State private var swipeEdge: Edge = .trailing
    @State private var showingNewRecording = false
    @Environment(LocationEngine.self) private var engine

    var body: some View {
        @Bindable var navigator = navigator
        NavigationStack {
            DayContentView(day: day)
                .id(day)
                .transition(.asymmetric(insertion: .move(edge: swipeEdge).combined(with: .opacity),
                                        removal: .opacity))
                // Swipe sideways to move between days, like flipping pages.
                .simultaneousGesture(
                    DragGesture(minimumDistance: 30)
                        .onEnded { value in
                            let dx = value.translation.width, dy = value.translation.height
                            guard abs(dx) > 90, abs(dx) > abs(dy) * 2 else { return }
                            shift(by: dx > 0 ? -1 : 1)
                        }
                )
                .navigationTitle(Format.dayTitle(day))
                .navigationSubtitle(Format.daySubtitle(day))
                .toolbar {
                    ToolbarItemGroup(placement: .topBarLeading) {
                        Button("前一天", systemImage: "chevron.left") { shift(by: -1) }
                        Button("后一天", systemImage: "chevron.right") { shift(by: 1) }
                            .disabled(Calendar.current.isDateInToday(day))
                    }
                    if engine.activeTripID == nil {
                        ToolbarItem(placement: .topBarTrailing) {
                            Button("开始记录", systemImage: "record.circle") { showingNewRecording = true }
                                .tint(.orange)
                        }
                    }
                    ToolbarItem(placement: .topBarTrailing) {
                        Button("选择日期", systemImage: "calendar") { showingCalendar = true }
                    }
                    ToolbarSpacer(.fixed, placement: .topBarTrailing)
                    ToolbarItem(placement: .topBarTrailing) {
                        ProfileToolbarButton(showingSettings: $showingSettings)
                    }
                }
                .sheet(isPresented: $showingNewRecording) {
                    NewRecordingSheet()
                }
                .sheet(isPresented: $showingCalendar) {
                    DayPickerSheet(day: $navigator.day)
                }
                .sensoryFeedback(.selection, trigger: day)
        }
    }

    private var day: Date { navigator.day }

    private func shift(by days: Int) {
        guard let next = Calendar.current.date(byAdding: .day, value: days, to: day), next <= Date() else { return }
        swipeEdge = days > 0 ? .trailing : .leading
        withAnimation(.smooth) { navigator.day = next }
    }
}

private struct DayPickerSheet: View {
    @Binding var day: Date
    @Environment(\.dismiss) private var dismiss
    @State private var selection: Date

    init(day: Binding<Date>) {
        _day = day
        _selection = State(initialValue: day.wrappedValue)
    }

    var body: some View {
        NavigationStack {
            RecordedDayCalendar(selection: $selection)
                .padding(.horizontal)
                .frame(maxHeight: .infinity, alignment: .top)
                .onChange(of: selection) { _, newValue in pick(newValue) }
                .navigationTitle("选择日期")
                .navigationBarTitleDisplayMode(.inline)
                .toolbar {
                    ToolbarItem(placement: .primaryAction) {
                        Button("今天") { pick(Date()) }
                    }
                    ToolbarItem(placement: .cancellationAction) {
                        Button("关闭", systemImage: "xmark") { dismiss() }
                    }
                }
        }
        .presentationDetents([.height(520), .large])
    }

    private func pick(_ date: Date) {
        withAnimation(.smooth) { day = Calendar.current.startOfDay(for: date) }
        dismiss()
    }
}

/// Everything recorded on one calendar day.
struct DayContentView: View {
    @State private var photoAccess = DayPhotos.status
    @AppStorage("timeline.photosOffered") private var photosOffered = false
    let day: Date
    @Environment(LocationEngine.self) private var engine
    @Environment(ActivityProvider.self) private var activityProvider
    @Environment(\.placeTagger) private var tagger
    @Query private var candidateStays: [Stay]
    @Query private var chunks: [TrackChunk]
    @State private var activity: DailyActivity?
    @State private var selectedStay: Stay?
    @State private var selectedMove: MoveSelection?
    @State private var home: CLLocation?
    @Environment(\.modelContext) private var context
    @State private var showingFullMap = false
    @Namespace private var mapNamespace

    init(day: Date) {
        self.day = day
        let interval = Calendar.current.dayInterval(for: day)
        let start = interval.start, end = interval.end
        // Stays can begin days earlier (a long hotel stay), so look back and filter below.
        let lookBack = start.addingTimeInterval(-14 * 86_400)
        _candidateStays = Query(filter: #Predicate<Stay> { $0.arrival < end && $0.arrival >= lookBack },
                                sort: \Stay.arrival)
        _chunks = Query(filter: #Predicate<TrackChunk> { $0.endDate >= start && $0.startDate < end },
                        sort: \TrackChunk.startDate)
    }

    private var interval: DateInterval { Calendar.current.dayInterval(for: day) }
    private var isToday: Bool { Calendar.current.isDateInToday(day) }

    private var stays: [Stay] {
        candidateStays.filter { ($0.departure ?? Date()) > interval.start }
    }

    private var entries: [TimelineEntry] { Timeline.entries(stays: stays, chunks: chunks) }
    private var trackedDistance: Double { chunks.reduce(0) { $0 + $1.distance } + (isToday ? TrackPoint.distance(of: engine.pendingPoints) : 0) }

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 16) {
                if isToday {
                    TrackingStatusCard()
                    TripSuggestionCard(todayStays: stays, home: home)
                }

                mapCard

                metrics

                if entries.isEmpty {
                    emptyTimeline
                } else {
                    SectionHeader(title: "时间线", trailing: "\(stays.count) 个地点")
                    TimelineList(entries: entries, day: day, onSelect: { selectedStay = $0 },
                                 onSelectMove: { selectedMove = $0 })
                        .id(photoAccess)
                    if photoAccess == .notDetermined && !photosOffered { photosCard }
                }
            }
            .padding(.horizontal)
            .padding(.bottom, 24)
        }
        .scrollIndicators(.hidden)
        .refreshable { await load(force: true) }
        .task(id: day) {
            if isToday { home = TripSuggestionCard.homeBase(in: context) }
            await load(force: false)
        }
        .sheet(item: $selectedStay) { stay in
            StayDetailView(stay: stay, showsDayLink: false)
        }
        .sheet(item: $selectedMove) { selection in
            MoveDetailView(move: selection.move, from: selection.from, to: selection.to)
        }
        .fullScreenCover(isPresented: $showingFullMap) {
            DayMapScreen(title: Format.dayTitle(day), chunks: chunks, stays: stays,
                         livePoints: isToday ? engine.pendingPoints : [],
                         subtitle: day.formatted(.dateTime.year().month().day().weekday(.wide).locale(appLocale)))
                .navigationTransition(.zoom(sourceID: "map", in: mapNamespace))
        }
    }

    private func load(force: Bool) async {
        if force { tagger?.enqueue() }
        if isToday { await activityProvider.refreshToday() }
        let value = isToday ? activityProvider.today : await activityProvider.activity(for: day)
        withAnimation(.smooth) { activity = value }
    }

    private var mapCard: some View {
        Button {
            showingFullMap = true
        } label: {
            ZStack(alignment: .bottomLeading) {
                TrackMap(chunks: chunks, stays: stays, livePoints: isToday ? engine.pendingPoints : [],
                         interactive: false, showsUser: isToday)
                    .allowsHitTesting(false)
                if chunks.isEmpty && stays.isEmpty && (!isToday || engine.pendingPoints.isEmpty) {
                    Rectangle().fill(.ultraThinMaterial)
                    Label("这一天还没有轨迹", systemImage: "map")
                        .font(.headline)
                        .foregroundStyle(.secondary)
                        .frame(maxWidth: .infinity, maxHeight: .infinity)
                } else {
                    Label("查看地图", systemImage: "arrow.up.left.and.arrow.down.right")
                        .font(.footnote.weight(.semibold))
                        .padding(.horizontal, 12)
                        .padding(.vertical, 8)
                        .glassEffect(.regular, in: .capsule)
                        .padding(12)
                }
            }
            .frame(height: 320)
            .clipShape(.rect(cornerRadius: 28, style: .continuous))
            .contentShape(.rect(cornerRadius: 28))
        }
        .buttonStyle(PressableStyle())
        .matchedTransitionSource(id: "map", in: mapNamespace)
        .accessibilityLabel("打开当天的地图")
    }

    private var metrics: some View {
        MetricGrid {
            MetricTile(title: "步数", value: activity.map { Format.steps($0.steps) } ?? "—",
                       symbol: "shoeprints.fill", tint: .orange)
            MetricTile(title: "步行距离", value: activity.map { Format.distance($0.walkingDistance) } ?? "—",
                       symbol: "figure.walk", tint: .green)
            MetricTile(title: "移动总距离", value: Format.distance(trackedDistance),
                       symbol: "point.topright.arrow.triangle.backward.to.point.bottomleft.scurvepath", tint: .blue)
            MetricTile(title: "去过的地点", value: "\(stays.count)", symbol: "mappin.and.ellipse", tint: .pink)
        }
        .animation(.smooth, value: activity)
    }

    /// Asked once, where it matters: photos make the timeline a diary.
    private var photosCard: some View {
        HStack(alignment: .top, spacing: 14) {
            Image(systemName: "photo.on.rectangle.angled")
                .font(.title2)
                .foregroundStyle(.blue)
            VStack(alignment: .leading, spacing: 6) {
                Text("在时间线上显示拍的照片").font(.subheadline.weight(.semibold))
                Text("每个地点下面会出现你在那里拍的照片。照片只在手机上读取，不会上传。")
                    .font(.footnote).foregroundStyle(.secondary)
                HStack(spacing: 10) {
                    Button("显示照片") {
                        Task {
                            photoAccess = await DayPhotos.requestAccess()
                            photosOffered = true
                        }
                    }
                    .buttonStyle(.glassProminent)
                    .controlSize(.small)
                    Button("不用了") { withAnimation { photosOffered = true } }
                        .controlSize(.small)
                }
                .padding(.top, 2)
            }
            Spacer(minLength: 0)
        }
        .padding(14)
        .background(.background.secondary, in: .rect(cornerRadius: 20, style: .continuous))
    }

    private var emptyTimeline: some View {
        ContentUnavailableView {
            Label(isToday ? "今天的故事刚刚开始" : "没有记录", systemImage: "figure.walk.departure")
        } description: {
            Text(isToday ? "带着手机出发吧，停留超过几分钟的地方会出现在这里。" : "这一天没有记录到轨迹或停留。")
        }
        .padding(.vertical, 24)
    }
}

/// Scales slightly on press, the way Apple's cards respond to touch.
struct PressableStyle: ButtonStyle {
    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .scaleEffect(configuration.isPressed ? 0.97 : 1)
            .animation(.spring(duration: 0.3, bounce: 0.3), value: configuration.isPressed)
    }
}

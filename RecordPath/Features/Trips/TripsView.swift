import SwiftUI
import SwiftData

struct TripsView: View {
    @Binding var showingSettings: Bool
    @Environment(LocationEngine.self) private var engine
    @Query(sort: \Trip.startDate, order: .reverse) private var all: [Trip]
    @State private var showingNewTrip = false
    @State private var showingNewRecording = false
    @AppStorage("trips.list") private var list = ListKind.trips

    enum ListKind: String { case trips, recordings }

    private var openRecording: Trip? { all.first { $0.isActive && $0.isRecording } }
    private var openTrip: Trip? { all.first { $0.isActive && !$0.isRecording } }
    private var trips: [Trip] { all.filter { !$0.isActive && !$0.isRecording } }
    private var recordings: [Trip] { all.filter { !$0.isActive && $0.isRecording } }

    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(alignment: .leading, spacing: 16) {
                    if let openRecording {
                        NavigationLink(value: openRecording) { ActiveTripCard(trip: openRecording) }
                            .buttonStyle(PressableStyle())
                    }
                    if let openTrip {
                        NavigationLink(value: openTrip) { ActiveTripCard(trip: openTrip) }
                            .buttonStyle(PressableStyle())
                    } else if trips.isEmpty && recordings.isEmpty {
                        startCard
                    }

                    Picker("列表", selection: $list.animation(.snappy)) {
                        Text("旅程 \(trips.count)").tag(ListKind.trips)
                        Text("记录 \(recordings.count)").tag(ListKind.recordings)
                    }
                    .pickerStyle(.segmented)
                    .padding(.top, 4)

                    let items = list == .trips ? trips : recordings
                    if items.isEmpty {
                        emptyState
                    } else {
                        LazyVStack(spacing: 14) {
                            ForEach(items) { trip in
                                NavigationLink(value: trip) { TripRow(trip: trip) }
                                    .buttonStyle(PressableStyle())
                                    .transition(.opacity.combined(with: .scale(scale: 0.97)))
                            }
                        }
                        .id(list)
                    }
                }
                .padding(.horizontal)
                .padding(.bottom, 24)
            }
            .navigationTitle("旅程")
            .toolbar {
                ToolbarItem(placement: .topBarTrailing) {
                    Menu("新建", systemImage: "plus") {
                        Button("新旅程", systemImage: "suitcase") { showingNewTrip = true }
                        Button("开始记录", systemImage: "record.circle") { showingNewRecording = true }
                            .disabled(engine.activeTripID != nil)
                    }
                }
                ToolbarSpacer(.fixed, placement: .topBarTrailing)
                ToolbarItem(placement: .topBarTrailing) {
                    ProfileToolbarButton(showingSettings: $showingSettings)
                }
            }
            .navigationDestination(for: Trip.self) { TripDetailView(trip: $0) }
            .sheet(isPresented: $showingNewTrip) { NewTripSheet() }
            .sheet(isPresented: $showingNewRecording) { NewRecordingSheet() }
        }
    }

    @ViewBuilder
    private var emptyState: some View {
        VStack(spacing: 10) {
            Image(systemName: list == .trips ? "suitcase" : "figure.hiking")
                .font(.largeTitle)
                .foregroundStyle(.tertiary)
            Text(list == .trips
                 ? "旅程把几天的轨迹、地点和照片收在一起。也可以为已经过去的日子补建旅程，轨迹会自动归入。"
                 : "一次徒步、跑步或骑行的记录会出现在这里。在“今天”页右上角开始记录，或者在 Apple Watch 上记录。")
                .font(.footnote)
                .foregroundStyle(.secondary)
                .multilineTextAlignment(.center)
            if list == .recordings, engine.activeTripID == nil {
                Button("开始记录", systemImage: "record.circle") { showingNewRecording = true }
                    .buttonStyle(.bordered)
                    .tint(.orange)
                    .padding(.top, 4)
            }
        }
        .frame(maxWidth: .infinity)
        .padding(.vertical, 28)
        .padding(.horizontal, 20)
    }

    private var startCard: some View {
        Button { showingNewTrip = true } label: {
            HStack(spacing: 16) {
                Image(systemName: "suitcase.fill")
                    .font(.system(size: 28, weight: .semibold))
                    .foregroundStyle(.white)
                    .frame(width: 64, height: 64)
                    .background(RoundedRectangle(cornerRadius: 18, style: .continuous).fill(Color.blue.gradient))
                VStack(alignment: .leading, spacing: 4) {
                    Text("开始一段旅程").font(.title3.bold())
                    Text("出游或出差的几天，轨迹和地点会自动收进来。").font(.subheadline).foregroundStyle(.secondary)
                }
                Spacer()
                Image(systemName: "plus.circle.fill").font(.title).foregroundStyle(.blue)
            }
            .padding(16)
            .background(.background.secondary, in: .rect(cornerRadius: 24, style: .continuous))
        }
        .buttonStyle(PressableStyle())
    }
}

private struct ActiveTripCard: View {
    let trip: Trip
    @Query private var chunks: [TrackChunk]
    @Environment(LocationEngine.self) private var engine

    init(trip: Trip) {
        self.trip = trip
        let start = trip.startDate
        _chunks = Query(filter: #Predicate<TrackChunk> { $0.endDate >= start })
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 14) {
            HStack(spacing: 8) {
                PulsingDot(color: .orange)
                Text(trip.activity.map { String(localized: "\($0.title)记录中", bundle: .appLanguage) }
                     ?? String(localized: "旅程进行中", bundle: .appLanguage))
                    .font(.subheadline.weight(.semibold)).foregroundStyle(.orange)
                Spacer()
                Image(systemName: "chevron.right").font(.caption.weight(.semibold)).foregroundStyle(.tertiary)
            }
            HStack(spacing: 12) {
                Text(trip.coverEmoji).font(.system(size: 40))
                Text(trip.title).font(.title2.bold()).lineLimit(2)
            }
            HStack(spacing: 24) {
                TimelineView(.periodic(from: .now, by: 1)) { context in
                    statistic(title: "用时", value: Format.duration(context.date.timeIntervalSince(trip.startDate)))
                }
                statistic(title: "距离", value: Format.distance(chunks.reduce(0) { $0 + $1.distance }
                                                             + TrackPoint.distance(of: engine.pendingPoints)))
            }
        }
        .padding(18)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background {
            RoundedRectangle(cornerRadius: 24, style: .continuous)
                .fill(.background.secondary)
                .overlay(RoundedRectangle(cornerRadius: 24, style: .continuous).stroke(Color.orange.opacity(0.4), lineWidth: 1))
        }
        .foregroundStyle(.primary)
    }

    private func statistic(title: LocalizedStringKey, value: String) -> some View {
        VStack(alignment: .leading, spacing: 2) {
            Text(title).font(.caption).foregroundStyle(.secondary)
            Text(value).font(.system(.title3, design: .rounded, weight: .semibold)).contentTransition(.numericText())
        }
    }
}

/// A trip or recording as a picture card: its route or first photo, with what and when.
struct TripRow: View {
    let trip: Trip

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            TripCover(trip: trip)
                .frame(height: 132)
                .overlay(alignment: .topLeading) {
                    Text(trip.coverEmoji)
                        .font(.title3)
                        .frame(width: 38, height: 38)
                        .background(.regularMaterial, in: .circle)
                        .padding(10)
                }
                .overlay(alignment: .topTrailing) {
                    if let count = trip.photos?.count, count > 0 {
                        Label("\(count)", systemImage: "photo.fill")
                            .font(.caption.weight(.semibold))
                            .padding(.horizontal, 9).padding(.vertical, 5)
                            .background(.regularMaterial, in: .capsule)
                            .padding(10)
                    }
                }
            VStack(alignment: .leading, spacing: 2) {
                Text(trip.title).font(.headline).lineLimit(1)
                Text(dateText).font(.subheadline).foregroundStyle(.secondary).lineLimit(1)
            }
            .padding(.horizontal, 14)
            .padding(.vertical, 12)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(.background.secondary)
        .clipShape(.rect(cornerRadius: 22, style: .continuous))
        .contentShape(.rect(cornerRadius: 22, style: .continuous))
        .foregroundStyle(.primary)
    }

    private var dateText: String {
        "\(trip.dateRangeText) · \(Format.duration(trip.interval.duration))"
    }
}

struct NewTripSheet: View {
    @Environment(\.modelContext) private var context
    @Environment(\.dismiss) private var dismiss

    @State private var title = ""
    @State private var emoji = "🧭"
    @State private var startsNow = true
    @State private var startDate = Calendar.current.date(byAdding: .day, value: -3, to: Date()) ?? Date()
    @State private var endDate = Date()
    @FocusState private var titleFocused: Bool

    var body: some View {
        NavigationStack {
            Form {
                Section {
                    TextField("名称（可不填），例如“京都赏枫”", text: $title)
                        .focused($titleFocused)
                        .font(.title3)
                    EmojiPicker(selection: $emoji)
                }

                Section {
                    Picker("时间", selection: $startsNow.animation()) {
                        Text("从现在开始").tag(true)
                        Text("已经过去的").tag(false)
                    }
                    .pickerStyle(.segmented)
                    if !startsNow {
                        // Past trips are thought of in whole days: first day 00:00 to last day 24:00.
                        DatePicker("第一天", selection: $startDate, in: ...endDate, displayedComponents: .date)
                        DatePicker("最后一天", selection: $endDate, in: startDate...Date(), displayedComponents: .date)
                    }
                } footer: {
                    Text(startsNow ? "从现在起全天记录的轨迹和地点会自动收进这段旅程，回来后在旅程里点“结束旅程”。"
                                   : "这几天里记录的轨迹和地点会自动归入这段旅程。")
                }
            }
            .navigationTitle("新旅程")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("取消", systemImage: "xmark") { dismiss() }
                }
                ToolbarItem(placement: .confirmationAction) {
                    Button(startsNow ? "开始" : "创建", systemImage: "checkmark", action: create)
                }
            }
            .onAppear { titleFocused = true }
            .onChange(of: startsNow) { titleFocused = false }
        }
        .presentationDetents(startsNow ? [.medium, .large] : [.large])
    }

    /// A past trip is named after where it happened ("杭州 · 10月5日"); a new one after when it began.
    private func defaultName(start: Date) -> String {
        guard !startsNow else {
            return String(localized: "\(start.formatted(.dateTime.month().day().hour().minute().locale(appLocale))) 的记录", bundle: .appLanguage)
        }
        let calendar = Calendar.current
        let firstDay = calendar.startOfDay(for: startDate)
        let lastDay = calendar.startOfDay(for: endDate)
        let end = calendar.date(byAdding: .day, value: 1, to: lastDay) ?? lastDay
        let days = calendar.isDate(firstDay, inSameDayAs: lastDay)
            ? firstDay.formatted(.dateTime.month().day().locale(appLocale))
            : (firstDay..<lastDay).formatted(.interval.month().day().locale(appLocale))
        let stays = (try? context.fetch(FetchDescriptor<Stay>(predicate: #Predicate { $0.arrival >= firstDay && $0.arrival < end }))) ?? []
        let city = Dictionary(grouping: stays.compactMap(\.city), by: { $0 }).max { $0.value.count < $1.value.count }?.key
        return city.map { "\($0) · \(days)" } ?? String(localized: "\(days) 的旅程", bundle: .appLanguage)
    }

    private func create() {
        let calendar = Calendar.current
        let start = startsNow ? Date() : calendar.startOfDay(for: startDate)
        // A name is optional so recording can start with one tap.
        let name = title.trimmingCharacters(in: .whitespaces).nilIfEmpty ?? defaultName(start: start)
        let trip = Trip(title: name, startDate: start)
        trip.coverEmoji = emoji
        if !startsNow {
            let dayAfterLast = calendar.date(byAdding: .day, value: 1, to: calendar.startOfDay(for: endDate)) ?? endDate
            trip.endDate = min(dayAfterLast, Date())
        }
        context.insert(trip)
        try? context.save()
        if startsNow {
            // One trip in progress at a time; a recording during it carries on.
            let others = (try? context.fetch(FetchDescriptor<Trip>())) ?? []
            for other in others where other.id != trip.id && other.isActive && !other.isRecording { other.endDate = Date() }
            try? context.save()
        }
        dismiss()
    }
}

/// A row of trip icons to pick from.
struct EmojiPicker: View {
    @Binding var selection: String
    static let options = ["🧭", "🏔️", "🏖️", "🏙️", "✈️", "🚗", "🚲", "🥾", "🏕️", "🎒", "🗻", "🌸", "🍜", "🎡", "🚆", "⛷️"]

    var body: some View {
        ScrollView(.horizontal) {
            HStack(spacing: 8) {
                ForEach(Self.options, id: \.self) { item in
                    Button {
                        withAnimation(.snappy) { selection = item }
                    } label: {
                        Text(item)
                            .font(.system(size: 28))
                            .frame(width: 48, height: 48)
                            .background(Circle().fill(selection == item ? Color.accentColor.opacity(0.2) : .clear))
                            .overlay(Circle().stroke(selection == item ? Color.accentColor : .clear, lineWidth: 2))
                    }
                    .buttonStyle(.plain)
                    .accessibilityAddTraits(selection == item ? .isSelected : [])
                }
            }
            .padding(.vertical, 4)
        }
        .scrollIndicators(.hidden)
        .sensoryFeedback(.selection, trigger: selection)
    }
}

import SwiftUI
import SwiftData

struct TripsView: View {
    @Binding var showingSettings: Bool
    @Environment(LocationEngine.self) private var engine
    @Query(sort: \Trip.startDate, order: .reverse) private var trips: [Trip]
    @State private var showingNewTrip = false

    private var activeTrip: Trip? { trips.first { $0.isActive && $0.id == engine.activeTripID } ?? trips.first(where: \.isActive) }
    private var pastTrips: [Trip] { trips.filter { $0.id != activeTrip?.id } }

    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(alignment: .leading, spacing: 16) {
                    if let activeTrip {
                        NavigationLink(value: activeTrip) { ActiveTripCard(trip: activeTrip) }
                            .buttonStyle(PressableStyle())
                    } else {
                        startCard
                    }

                    if pastTrips.isEmpty {
                        if activeTrip == nil {
                            Text("旅程把一段时间的轨迹、地点和照片收在一起。你也可以为已经过去的日子补建旅程，轨迹会自动归入。")
                                .font(.footnote).foregroundStyle(.secondary).padding(.horizontal, 4)
                        }
                    } else {
                        SectionHeader(title: "过去的旅程", trailing: "\(pastTrips.count)")
                        LazyVStack(spacing: 12) {
                            ForEach(pastTrips) { trip in
                                NavigationLink(value: trip) { TripRow(trip: trip) }
                                    .buttonStyle(PressableStyle())
                            }
                        }
                    }
                }
                .padding(.horizontal)
                .padding(.bottom, 24)
            }
            .navigationTitle("旅程")
            .toolbar {
                ToolbarItem(placement: .topBarTrailing) {
                    Button("新旅程", systemImage: "plus") { showingNewTrip = true }
                }
                ToolbarSpacer(.fixed, placement: .topBarTrailing)
                ToolbarItem(placement: .topBarTrailing) {
                    ProfileToolbarButton(showingSettings: $showingSettings)
                }
            }
            .navigationDestination(for: Trip.self) { TripDetailView(trip: $0) }
            .sheet(isPresented: $showingNewTrip) { NewTripSheet() }
        }
    }

    private var startCard: some View {
        Button { showingNewTrip = true } label: {
            HStack(spacing: 16) {
                Image(systemName: "figure.hiking")
                    .font(.system(size: 30, weight: .semibold))
                    .foregroundStyle(.white)
                    .frame(width: 64, height: 64)
                    .background(RoundedRectangle(cornerRadius: 18, style: .continuous).fill(Color.orange.gradient))
                VStack(alignment: .leading, spacing: 4) {
                    Text("开始一段旅程").font(.title3.bold())
                    Text("徒步、出游或出差，记录会更精细。").font(.subheadline).foregroundStyle(.secondary)
                }
                Spacer()
                Image(systemName: "plus.circle.fill").font(.title).foregroundStyle(.orange)
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
                Text("旅程进行中").font(.subheadline.weight(.semibold)).foregroundStyle(.orange)
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

struct TripRow: View {
    let trip: Trip

    var body: some View {
        HStack(spacing: 14) {
            Text(trip.coverEmoji)
                .font(.system(size: 30))
                .frame(width: 56, height: 56)
                .background(.background.tertiary, in: .rect(cornerRadius: 16, style: .continuous))
            VStack(alignment: .leading, spacing: 3) {
                Text(trip.title).font(.headline).lineLimit(1)
                Text(dateText).font(.subheadline).foregroundStyle(.secondary)
            }
            Spacer()
            if let count = trip.photos?.count, count > 0 {
                Label("\(count)", systemImage: "photo").font(.footnote).foregroundStyle(.secondary)
            }
            Image(systemName: "chevron.right").font(.caption.weight(.semibold)).foregroundStyle(.tertiary)
        }
        .padding(14)
        .background(.background.secondary, in: .rect(cornerRadius: 22, style: .continuous))
        .foregroundStyle(.primary)
    }

    private var dateText: String {
        "\(trip.dateRangeText) · \(Format.duration(trip.interval.duration))"
    }
}

struct NewTripSheet: View {
    @Environment(\.modelContext) private var context
    @Environment(\.dismiss) private var dismiss
    @Environment(LocationEngine.self) private var engine

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
                    Text(startsNow ? "手动记录使用更高的定位精度，和全天自动记录互不影响，结束后会保存在“旅程”里。"
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
            return String(localized: "\(start.formatted(.dateTime.month().day().hour().minute())) 的记录")
        }
        let calendar = Calendar.current
        let firstDay = calendar.startOfDay(for: startDate)
        let lastDay = calendar.startOfDay(for: endDate)
        let end = calendar.date(byAdding: .day, value: 1, to: lastDay) ?? lastDay
        let days = calendar.isDate(firstDay, inSameDayAs: lastDay)
            ? firstDay.formatted(.dateTime.month().day())
            : (firstDay..<lastDay).formatted(.interval.month().day())
        let stays = (try? context.fetch(FetchDescriptor<Stay>(predicate: #Predicate { $0.arrival >= firstDay && $0.arrival < end }))) ?? []
        let city = Dictionary(grouping: stays.compactMap(\.city), by: { $0 }).max { $0.value.count < $1.value.count }?.key
        return city.map { "\($0) · \(days)" } ?? String(localized: "\(days) 的旅程")
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
            // Only one trip records at a time.
            let others = (try? context.fetch(FetchDescriptor<Trip>())) ?? []
            for other in others where other.id != trip.id && other.isActive { other.endDate = Date() }
            engine.beginTrip(trip)
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

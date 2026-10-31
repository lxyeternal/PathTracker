import SwiftUI
import SwiftData

/// One stretch of travel between two places: where from and to, how long it took, how fast,
/// and how it was travelled. The user can correct the mode or delete a bad segment.
struct MoveDetailView: View {
    let move: Move
    let from: Stay?
    let to: Stay?

    @Environment(\.modelContext) private var context
    @Environment(\.dismiss) private var dismiss
    @Environment(AppNavigator.self) private var navigator
    @State private var mode: MovementMode = .unknown
    @State private var confirmingDelete = false
    @State private var history: [RouteHistory.Trip] = []

    private var points: [TrackPoint] { move.chunks.flatMap(\.points) }

    private var averageSpeed: Double {
        move.duration > 0 ? move.distance / move.duration : 0
    }

    private var maxSpeed: Double {
        // Ignore single-sample spikes so one bad fix doesn't claim 300 km/h on a bicycle.
        let speeds = points.map(\.speed).filter { $0 > 0 }.sorted()
        guard !speeds.isEmpty else { return 0 }
        // Recorded speeds are instantaneous; never show a top speed below the average.
        return max(speeds[min(speeds.count - 1, Int(Double(speeds.count) * 0.95))], averageSpeed)
    }

    var body: some View {
        NavigationStack {
            List {
                Section {
                    TrackMap(chunks: move.chunks, stays: [from, to].compactMap { $0 }, interactive: true)
                        .frame(height: 280)
                        .listRowInsets(EdgeInsets())
                }

                Section {
                    HStack(alignment: .top, spacing: 12) {
                        VStack(spacing: 4) {
                            Circle().fill(.green).frame(width: 10, height: 10)
                            Rectangle().fill(.secondary.opacity(0.3)).frame(width: 2, height: 28)
                            Circle().fill(.red).frame(width: 10, height: 10)
                        }
                        .padding(.top, 6)
                        VStack(alignment: .leading, spacing: 14) {
                            endpoint(title: from?.displayName ?? String(localized: "出发", bundle: .appLanguage), time: move.start)
                            endpoint(title: to?.displayName ?? String(localized: "到达", bundle: .appLanguage), time: move.end)
                        }
                    }
                    .padding(.vertical, 4)
                }

                Section("数据") {
                    LabeledContent("距离", value: Format.distance(move.distance))
                    LabeledContent("用时", value: Format.duration(move.duration))
                    LabeledContent("平均速度", value: Format.speed(averageSpeed))
                    LabeledContent("最高速度", value: Format.speed(maxSpeed))
                }

                if history.count > 1 { routeHistorySection }

                Section {
                    Picker("出行方式", selection: $mode) {
                        ForEach(MovementMode.allCases.filter { $0 != .unknown }, id: \.self) { mode in
                            Label(mode.title, systemImage: mode.symbol).tag(mode)
                        }
                    }
                    .pickerStyle(.navigationLink)
                } footer: {
                    Text("如果识别错了，可以在这里改正。")
                }

                Section {
                    Button("删除这段轨迹", systemImage: "trash", role: .destructive) { confirmingDelete = true }
                } footer: {
                    Text("适合删除 GPS 漂移产生的乱线。停留记录不受影响。")
                }
            }
            .navigationTitle("\(move.mode.title) · \(Format.distance(move.distance))")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .confirmationAction) {
                    Button("完成", systemImage: "checkmark") { dismiss() }
                }
            }
            .onAppear { mode = move.mode == .unknown ? .walking : move.mode }
            .task {
                if let from, let to { history = RouteHistory.trips(from: from, to: to, in: context) }
            }
            .onChange(of: mode) { old, newValue in
                // The first value is only what the picker shows; a change is the person's own.
                guard old != .unknown, newValue != move.mode else { return }
                for chunk in move.chunks { chunk.modeRaw = newValue.rawValue }
                try? context.save()
            }
            .confirmationDialog("删除这段轨迹？", isPresented: $confirmingDelete, titleVisibility: .visible) {
                Button("删除", role: .destructive) {
                    for chunk in move.chunks { context.delete(chunk) }
                    try? context.save()
                    dismiss()
                }
            }
        }
    }

    /// Every time the user made this same trip, e.g. home → school.
    private var routeHistorySection: some View {
        let durations = history.map(\.duration)
        let average = durations.reduce(0, +) / Double(durations.count)
        return Section {
            LabeledContent("走过次数", value: String(localized: "\(history.count) 次", bundle: .appLanguage))
            LabeledContent("平均用时", value: Format.duration(average))
            LabeledContent("最快", value: Format.duration(durations.min() ?? 0))
            ForEach(history.prefix(10)) { trip in
                Button {
                    dismiss()
                    navigator.show(day: trip.departure)
                } label: {
                    HStack {
                        Text(trip.departure.formatted(.dateTime.month().day().weekday(.abbreviated).locale(appLocale)))
                            .foregroundStyle(.primary)
                        Text(Format.time(trip.departure)).foregroundStyle(.secondary)
                        Spacer()
                        Text(Format.duration(trip.duration))
                            .foregroundStyle(trip.duration <= average ? .green : .orange)
                            .monospacedDigit()
                    }
                }
                .tint(.primary)
            }
        } header: {
            Text("这条路线")
        } footer: {
            Text("从“\(from?.displayName ?? "")”到“\(to?.displayName ?? "")”的所有记录，点一条查看那一天。")
        }
    }

    private func endpoint(title: String, time: Date) -> some View {
        VStack(alignment: .leading, spacing: 2) {
            Text(title).font(.body.weight(.semibold)).lineLimit(1)
            Text(Format.time(time)).font(.subheadline).foregroundStyle(.secondary)
        }
    }
}

/// A move with the places on either side, for presenting as a sheet.
struct MoveSelection: Identifiable {
    let move: Move
    let from: Stay?
    let to: Stay?
    var id: Date { move.id }
}

/// Finds earlier trips between the same two places by looking at consecutive stays.
enum RouteHistory {
    struct Trip: Identifiable {
        let departure: Date
        let duration: TimeInterval
        var id: Date { departure }
    }

    @MainActor
    static func trips(from: Stay, to: Stay, in context: ModelContext) -> [Trip] {
        let stays = (try? context.fetch(FetchDescriptor<Stay>(sortBy: [SortDescriptor(\.arrival)]))) ?? []
        var trips: [Trip] = []
        for (a, b) in zip(stays, stays.dropFirst()) {
            guard let left = a.departure, b.arrival > left,
                  a.location.distance(from: from.location) <= KnownPlaces.radius,
                  b.location.distance(from: to.location) <= KnownPlaces.radius else { continue }
            let duration = b.arrival.timeIntervalSince(left)
            if duration < 4 * 3600 { trips.append(Trip(departure: left, duration: duration)) }
        }
        return trips.sorted { $0.departure > $1.departure }
    }
}

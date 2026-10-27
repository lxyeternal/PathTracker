import SwiftUI
import SwiftData
import CoreLocation

/// Tells the user, in one glance, whether today is being recorded and how to fix it if not.
struct TrackingStatusCard: View {
    @Environment(LocationEngine.self) private var engine
    @Query(filter: #Predicate<Trip> { $0.endDate == nil }) private var openTrips: [Trip]
    @State private var confirmingEnd = false

    private var activeTrip: Trip? {
        openTrips.first { $0.id == engine.activeTripID }
    }

    var body: some View {
        VStack(spacing: 10) {
            if let activeTrip { manualRecording(activeTrip) }
            status
        }
        .animation(.smooth, value: engine.activeTripID)
    }

    @ViewBuilder
    private var status: some View {
        Group {
            if let until = engine.pausedUntil, engine.isPaused, engine.activeTripID == nil {
                problem(symbol: "pause.circle.fill", tint: .orange,
                        title: "已暂停记录",
                        detail: "\(pauseText(until))自动恢复。暂停期间不会记录位置。",
                        action: "恢复") { withAnimation { engine.resume() } }
            } else if !engine.isRecording {
                problem(symbol: "pause.circle.fill", tint: .orange,
                        title: "自动记录已关闭", detail: "开启后会全天在后台记录。也可以点右上角的按钮，手动记录一段。",
                        action: "开启") { enable() }
            } else if activeTrip != nil {
                // The trip row above already shows the recording state.
                EmptyView()
            } else if engine.authorization == .denied || engine.authorization == .restricted {
                problem(symbol: "location.slash.fill", tint: .red,
                        title: "无法访问位置", detail: "请在“设置”中允许漫迹使用位置。",
                        action: "去设置") { openSettings() }
            } else if engine.authorization == .notDetermined {
                problem(symbol: "location.fill", tint: .blue,
                        title: "需要位置权限", detail: "允许后才能记录轨迹。",
                        action: "允许") { engine.requestWhenInUse() }
            } else if !engine.hasAlwaysPermission {
                problem(symbol: "location.circle.fill", tint: .yellow,
                        title: "仅在使用时记录", detail: "点“更改”，在“位置”里选“始终”，锁屏或关掉 App 时也能继续记录。",
                        action: "更改") { engine.requestAlways() }
            } else if !engine.isPreciseLocation {
                problem(symbol: "scope", tint: .yellow,
                        title: "精确位置已关闭", detail: "轨迹会偏差很大，建议在设置中打开“精确位置”。",
                        action: "去设置") { openSettings() }
            } else {
                recording
            }
        }
        .animation(.smooth, value: engine.activity)
        .animation(.smooth, value: engine.authorization)
    }

    private func manualRecording(_ trip: Trip) -> some View {
        TripRecordingRow(trip: trip, stayName: engine.openStay?.displayName) { confirmingEnd = true }
            .confirmationDialog("结束“\(trip.title)”？", isPresented: $confirmingEnd, titleVisibility: .visible) {
                Button("结束记录") { withAnimation { engine.endTrip(trip) } }
            } message: {
                Text(engine.isEnabled ? "之后仍会继续全天自动记录。" : "结束后不再记录位置。记录会保存在“旅程”页的“记录”里。")
            }
    }

    private var recording: some View {
        HStack(spacing: 10) {
            PulsingDot(color: engine.activeTripID == nil ? .green : .orange)
            Text(statusText)
                .font(.subheadline.weight(.medium))
                .contentTransition(.opacity)
            Spacer()
            if let stay = engine.openStay {
                Label(stay.displayName, systemImage: "mappin.circle.fill")
                    .font(.subheadline)
                    .foregroundStyle(.secondary)
                    .lineLimit(1)
            }
            if engine.activeTripID == nil {
                Menu {
                    Section("暂停记录") {
                        Button("暂停 1 小时", systemImage: "clock") { pause(hours: 1) }
                        Button("暂停 3 小时", systemImage: "clock") { pause(hours: 3) }
                        Button("暂停到明天早上", systemImage: "moon") { pauseUntilMorning() }
                    }
                } label: {
                    Image(systemName: "pause.circle")
                        .font(.title3)
                        .foregroundStyle(.secondary)
                        .frame(width: 32, height: 32)
                        .contentShape(.rect)
                }
                .accessibilityLabel("暂停记录")
            }
        }
        .padding(.leading, 16)
        .padding(.trailing, 8)
        .padding(.vertical, 8)
        .background(.background.secondary, in: .capsule)
    }

    private func pause(hours: Double) {
        withAnimation { engine.pause(until: Date().addingTimeInterval(hours * 3600)) }
    }

    private func pauseUntilMorning() {
        let calendar = Calendar.current
        let tomorrow = calendar.date(byAdding: .day, value: 1, to: calendar.startOfDay(for: Date())) ?? Date()
        withAnimation { engine.pause(until: tomorrow.addingTimeInterval(7 * 3600)) }
    }

    private func pauseText(_ date: Date) -> String {
        Calendar.current.isDateInToday(date)
            ? String(localized: "\(Format.time(date)) ", bundle: .appLanguage)
            : String(localized: "明天 \(Format.time(date)) ", bundle: .appLanguage)
    }

    private var statusText: LocalizedStringKey {
        let trip = engine.activeTripID != nil
        if engine.openStay != nil, engine.activity != .unavailable {
            return trip ? "记录中" : "正在记录"
        }
        switch engine.activity {
        case .moving: return trip ? "旅程记录中 · 移动中" : "正在记录 · 移动中"
        case .stationary: return "正在记录 · 等待移动"
        case .starting: return "正在启动定位…"
        case .unavailable: return "定位暂时不可用"
        case .off: return "正在记录"
        }
    }

    private func problem(symbol: String, tint: Color, title: LocalizedStringKey, detail: LocalizedStringKey,
                         action: LocalizedStringKey, perform: @escaping () -> Void) -> some View {
        HStack(spacing: 14) {
            Image(systemName: symbol)
                .font(.title2)
                .foregroundStyle(tint)
            VStack(alignment: .leading, spacing: 2) {
                Text(title).font(.subheadline.weight(.semibold))
                Text(detail).font(.footnote).foregroundStyle(.secondary)
            }
            Spacer(minLength: 8)
            Button(action, action: perform)
                .buttonStyle(.glassProminent)
                .controlSize(.small)
        }
        .padding(14)
        .background(.background.secondary, in: .rect(cornerRadius: 20, style: .continuous))
    }

    private func enable() {
        if engine.authorization == .notDetermined { engine.requestWhenInUse() }
        engine.isEnabled = true
    }

    private func openSettings() {
        if let url = URL(string: UIApplication.openSettingsURLString) { UIApplication.shared.open(url) }
    }
}

/// The running trip: name, time and distance so far, and a stop button.
private struct TripRecordingRow: View {
    let trip: Trip
    let stayName: String?
    let onEnd: () -> Void

    @Environment(LocationEngine.self) private var engine
    @Query private var chunks: [TrackChunk]

    init(trip: Trip, stayName: String?, onEnd: @escaping () -> Void) {
        self.trip = trip
        self.stayName = stayName
        self.onEnd = onEnd
        let start = trip.startDate
        _chunks = Query(filter: #Predicate<TrackChunk> { $0.endDate >= start })
    }

    private var distance: Double {
        chunks.reduce(0) { $0 + $1.distance } + TrackPoint.distance(of: engine.pendingPoints)
    }

    var body: some View {
        HStack(spacing: 12) {
            PulsingDot(color: .orange)
            VStack(alignment: .leading, spacing: 2) {
                Text("\(trip.coverEmoji) \(trip.title)")
                    .font(.subheadline.weight(.semibold))
                    .lineLimit(1)
                TimelineView(.periodic(from: .now, by: 1)) { context in
                    Text(detail(now: context.date))
                        .font(.footnote)
                        .foregroundStyle(.secondary)
                        .monospacedDigit()
                        .lineLimit(2)
                }
            }
            Spacer(minLength: 8)
            Button("结束", systemImage: "stop.fill", action: onEnd)
                .buttonStyle(.glassProminent)
                .tint(.orange)
                .controlSize(.small)
        }
        .padding(14)
        .background(.background.secondary, in: .rect(cornerRadius: 20, style: .continuous))
    }

    private func detail(now: Date) -> String {
        var parts = [trip.activity?.title ?? String(localized: "记录中", bundle: .appLanguage), Format.duration(now.timeIntervalSince(trip.startDate)), Format.distance(distance)]
        if let stayName { parts.append(String(localized: "在 \(stayName)", bundle: .appLanguage)) }
        return parts.joined(separator: " · ")
    }
}

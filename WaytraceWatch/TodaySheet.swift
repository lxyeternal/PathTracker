import SwiftUI

/// The little there is to know at a glance, and the one control that belongs on the wrist:
/// pausing all-day recording (at a doctor's, at a friend's place).
struct TodaySheet: View {
    @Environment(PhoneLink.self) private var link
    @Environment(\.dismiss) private var dismiss

    var body: some View {
        NavigationStack {
            List {
                if let snapshot = link.snapshot {
                    Section {
                        stat("步数", value: Format.steps(snapshot.steps), symbol: "shoeprints.fill", tint: .orange)
                        stat("距离", value: Format.distance(snapshot.distance), symbol: "point.topleft.down.to.point.bottomright.curvepath.fill", tint: .blue)
                        stat("地点", value: "\(snapshot.places.count)", symbol: "mappin.and.ellipse", tint: .pink)
                    }
                    recordingSection(snapshot)
                } else {
                    Text("打开 iPhone 上的漫迹，这里就会显示今天的路线。")
                        .foregroundStyle(.secondary)
                }
                if let note = connectionNote {
                    Text(note)
                        .font(.footnote)
                        .foregroundStyle(.secondary)
                        .listRowBackground(Color.clear)
                }
            }
            .navigationTitle("今天")
        }
    }

    private func stat(_ title: LocalizedStringKey, value: String, symbol: String, tint: Color) -> some View {
        HStack {
            Image(systemName: symbol)
                .foregroundStyle(tint)
                .frame(width: 24)
            Text(title)
            Spacer()
            Text(value).fontWeight(.semibold).monospacedDigit()
        }
    }

    @ViewBuilder
    private func recordingSection(_ snapshot: WatchSnapshot) -> some View {
        Section {
            if snapshot.pausedUntil != nil {
                Button("继续记录", systemImage: "play.fill") { link.resume() }
                    .tint(.green)
            } else if snapshot.isEnabled {
                Button("暂停 1 小时", systemImage: "pause.fill") { link.pause(until: Date().addingTimeInterval(3600)) }
                Button("暂停到明天", systemImage: "moon.fill") { link.pause(until: Self.tomorrowMorning) }
            }
        } header: {
            Text("iPhone 全天记录")
        } footer: {
            if let until = snapshot.pausedUntil {
                Text("暂停到 \(Format.time(until))")
            } else if !snapshot.isEnabled {
                Text("已在 iPhone 上关闭")
            }
        }
    }

    private var connectionNote: String? {
        guard let snapshot = link.snapshot, link.isStale else { return nil }
        let time = Format.time(snapshot.generatedAt)
        return String(localized: "iPhone 不在附近，显示的是 \(time) 的数据。", bundle: .appLanguage)
    }

    /// 7:00 tomorrow, the same "until tomorrow morning" the iPhone offers.
    static var tomorrowMorning: Date {
        let calendar = Calendar.current
        let tomorrow = calendar.date(byAdding: .day, value: 1, to: calendar.startOfDay(for: Date())) ?? Date()
        return calendar.date(bySettingHour: 7, minute: 0, second: 0, of: tomorrow) ?? tomorrow
    }
}

/// Picks what kind of recording to start; the last one used comes first.
struct ActivityPicker: View {
    @Environment(WorkoutRecorder.self) private var recorder
    let onStart: (ActivityType) -> Void

    var body: some View {
        NavigationStack {
            List(ordered) { activity in
                Button {
                    onStart(activity)
                } label: {
                    HStack(spacing: 12) {
                        Image(systemName: activity.symbol)
                            .font(.title3)
                            .foregroundStyle(.orange)
                            .frame(width: 32, height: 32)
                        Text(activity.title).font(.headline)
                    }
                    .padding(.vertical, 6)
                }
            }
            .navigationTitle("开始记录")
        }
    }

    private var ordered: [ActivityType] {
        let last = recorder.lastActivity
        return [last] + ActivityType.allCases.filter { $0 != last }
    }
}

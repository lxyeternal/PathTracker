import SwiftUI
import SwiftData
import WatchConnectivity

/// Starts recording one activity (a hike, a run) at high precision, apart from all-day
/// recording. Trips, days of travel, are made on the Trips tab instead.
struct NewRecordingSheet: View {
    @Environment(\.modelContext) private var context
    @Environment(\.dismiss) private var dismiss
    @Environment(LocationEngine.self) private var engine

    @AppStorage("recording.lastActivity") private var lastActivity = ActivityType.walking.rawValue
    @AppStorage("recording.onWatch") private var recordOnWatch = true
    @State private var activity = ActivityType.walking
    @State private var title = ""

    /// Offered only when there's a Watch with the app on it.
    private var hasWatch: Bool {
        WCSession.isSupported() && WCSession.default.activationState == .activated
            && WCSession.default.isPaired && WCSession.default.isWatchAppInstalled
    }

    var body: some View {
        NavigationStack {
            Form {
                Section {
                    HStack(spacing: 8) {
                        ForEach(ActivityType.allCases) { type in
                            ActivityChoice(type: type, isSelected: type == activity) {
                                withAnimation(.snappy) { activity = type }
                            }
                        }
                    }
                    .listRowInsets(EdgeInsets(top: 12, leading: 12, bottom: 12, trailing: 12))
                    TextField(defaultTitle, text: $title)
                } footer: {
                    Text("手动记录使用更高的定位精度，和全天自动记录互不影响。结束后保存在“旅程”页的“记录”里。")
                }

                if hasWatch {
                    Section {
                        Toggle(isOn: $recordOnWatch) {
                            Label("在 Apple Watch 上同时记录", systemImage: "applewatch")
                        }
                    } footer: {
                        Text("手表上的漫迹会自动打开，记录心率并存为体能训练；在任一设备上结束，两边一起结束。")
                    }
                }
            }
            .navigationTitle("开始记录")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("取消", systemImage: "xmark") { dismiss() }
                }
                ToolbarItem(placement: .confirmationAction) {
                    Button("开始", systemImage: "record.circle", action: start)
                }
            }
            .onAppear { activity = ActivityType(rawValue: lastActivity) ?? .walking }
            .sensoryFeedback(.selection, trigger: activity)
        }
        .presentationDetents([.medium, .large])
    }

    /// "徒步 · 10月25日 09:30", so a recording started with one tap still has a useful name.
    private var defaultTitle: String {
        "\(activity.title) · \(Date().formatted(.dateTime.month().day().hour().minute().locale(appLocale)))"
    }

    private func start() {
        let trip = Trip(title: title.trimmingCharacters(in: .whitespaces).nilIfEmpty ?? defaultTitle, startDate: Date())
        trip.activityRaw = activity.rawValue
        trip.coverEmoji = activity.emoji
        context.insert(trip)
        // One recording at a time.
        let open = (try? context.fetch(FetchDescriptor<Trip>(predicate: #Predicate { $0.endDate == nil }))) ?? []
        for other in open where other.id != trip.id && other.isRecording { other.endDate = Date() }
        try? context.save()
        lastActivity = activity.rawValue
        LiveRecording.setRecordsOnWatch(hasWatch && recordOnWatch, for: trip.id)
        engine.beginTrip(trip)
        dismiss()
    }
}

private struct ActivityChoice: View {
    let type: ActivityType
    let isSelected: Bool
    let action: () -> Void

    var body: some View {
        Button(action: action) {
            VStack(spacing: 6) {
                Image(systemName: type.symbol)
                    .font(.title2.weight(.semibold))
                    .foregroundStyle(isSelected ? .white : .orange)
                    .frame(width: 56, height: 56)
                    .background(Circle().fill(isSelected ? AnyShapeStyle(Color.orange.gradient) : AnyShapeStyle(Color.orange.opacity(0.12))))
                Text(type.title)
                    .font(.footnote.weight(isSelected ? .semibold : .regular))
                    .foregroundStyle(isSelected ? .primary : .secondary)
            }
            .frame(maxWidth: .infinity)
        }
        .buttonStyle(.plain)
        .accessibilityAddTraits(isSelected ? .isSelected : [])
    }
}

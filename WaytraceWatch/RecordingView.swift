import SwiftUI
import MapKit

/// While recording: controls on the left, the live route in the middle (where it opens), and
/// the numbers on the right, laid out like the Workout app.
struct RecordingView: View {
    @Environment(WorkoutRecorder.self) private var recorder
    @State private var page = Page.map

    enum Page { case controls, map, metrics }

    var body: some View {
        if recorder.state == .finished, let summary = recorder.summary {
            SummaryView(summary: summary)
        } else {
            TabView(selection: $page) {
                ControlsPage(onAction: { page = .map }).tag(Page.controls)
                LiveMapPage().tag(Page.map)
                MetricsPage().tag(Page.metrics)
            }
            .tabViewStyle(.page)
        }
    }
}

private struct ControlsPage: View {
    @Environment(WorkoutRecorder.self) private var recorder
    let onAction: () -> Void
    @State private var confirmingEnd = false

    var body: some View {
        VStack(spacing: 14) {
            HStack(spacing: 14) {
                controlButton(recorder.state == .paused ? "继续" : "暂停",
                              symbol: recorder.state == .paused ? "play.fill" : "pause.fill",
                              tint: .yellow) {
                    recorder.state == .paused ? recorder.resume() : recorder.pause()
                    onAction()
                }
                controlButton("结束", symbol: "xmark", tint: .red) { confirmingEnd = true }
            }
            if recorder.state == .saving {
                ProgressView("正在保存")
            }
        }
        .disabled(recorder.state == .saving || recorder.state == .starting)
        .confirmationDialog("结束这次记录？", isPresented: $confirmingEnd) {
            Button("结束并保存", role: .destructive) { Task { await recorder.end() } }
        }
    }

    private func controlButton(_ title: LocalizedStringKey, symbol: String, tint: Color, action: @escaping () -> Void) -> some View {
        VStack(spacing: 6) {
            Button(action: action) {
                Image(systemName: symbol)
                    .font(.title2.weight(.semibold))
                    .frame(width: 64, height: 52)
            }
            .tint(tint)
            .buttonStyle(.bordered)
            .buttonBorderShape(.roundedRectangle(radius: 16))
            Text(title).font(.footnote)
        }
    }
}

private struct LiveMapPage: View {
    @Environment(WorkoutRecorder.self) private var recorder
    @State private var position: MapCameraPosition = .userLocation(followsHeading: false, fallback: .automatic)

    var body: some View {
        RouteMap(snapshot: nil, livePoints: recorder.points, isFollowing: true, position: $position)
            .overlay(alignment: .bottom) {
                HStack(spacing: 10) {
                    ElapsedText(font: .system(.body, design: .rounded).weight(.semibold))
                    Text(Format.distance(recorder.distance))
                        .font(.system(.body, design: .rounded).weight(.semibold))
                        .foregroundStyle(.orange)
                }
                .monospacedDigit()
                .padding(.horizontal, 12)
                .padding(.vertical, 6)
                .background(.ultraThinMaterial, in: .capsule)
                .padding(.bottom, 4)
            }
            .overlay(alignment: .topLeading) {
                if recorder.state == .paused {
                    Label("已暂停", systemImage: "pause.fill")
                        .font(.footnote.weight(.semibold))
                        .foregroundStyle(.yellow)
                        .padding(.horizontal, 8).padding(.vertical, 4)
                        .background(.ultraThinMaterial, in: .capsule)
                        .padding(.leading, 6)
                }
            }
            .ignoresSafeArea(edges: .bottom)
    }
}

private struct MetricsPage: View {
    @Environment(WorkoutRecorder.self) private var recorder

    var body: some View {
        VStack(alignment: .leading, spacing: 2) {
            Label(recorder.activity.title, systemImage: recorder.activity.symbol)
                .font(.footnote)
                .foregroundStyle(.orange)
            ElapsedText(font: .system(size: 40, weight: .semibold, design: .rounded))
                .foregroundStyle(recorder.state == .paused ? .yellow : .primary)
            Text(Format.distance(recorder.distance))
                .font(.system(.title2, design: .rounded).weight(.semibold))
            Text(pace)
                .font(.system(.title3, design: .rounded))
                .foregroundStyle(.secondary)
            if let heartRate = recorder.heartRate {
                Label("\(Int(heartRate))", systemImage: "heart.fill")
                    .font(.system(.title3, design: .rounded))
                    .foregroundStyle(.red)
            }
        }
        .monospacedDigit()
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
        .padding(.horizontal, 4)
    }

    /// Speed for cycling, minutes per kilometre for everything on foot, as fitness apps show it.
    private var pace: String {
        let seconds = recorder.elapsed(at: Date())
        guard recorder.distance > 50, seconds > 0 else { return "—" }
        if recorder.activity == .cycling { return Format.speed(recorder.distance / seconds) }
        let perKilometre = seconds / (recorder.distance / 1000)
        let minutes = Int(perKilometre) / 60, rest = Int(perKilometre) % 60
        return String(format: "%d'%02d\"", minutes, rest) + " /km"
    }
}

/// The running time, ticking every second (every minute with the wrist down).
private struct ElapsedText: View {
    @Environment(WorkoutRecorder.self) private var recorder
    @Environment(\.isLuminanceReduced) private var isLuminanceReduced
    let font: Font

    var body: some View {
        TimelineView(.periodic(from: .now, by: isLuminanceReduced ? 60 : 1)) { context in
            Text(Self.clock(recorder.elapsed(at: context.date), showsSeconds: !isLuminanceReduced))
                .font(font)
        }
    }

    static func clock(_ interval: TimeInterval, showsSeconds: Bool) -> String {
        let total = Int(interval)
        let hours = total / 3600, minutes = total / 60 % 60, seconds = total % 60
        if !showsSeconds { return hours > 0 ? String(format: "%d:%02d", hours, minutes) : String(format: "%d′", minutes) }
        return hours > 0 ? String(format: "%d:%02d:%02d", hours, minutes, seconds) : String(format: "%02d:%02d", minutes, seconds)
    }
}

private struct SummaryView: View {
    @Environment(WorkoutRecorder.self) private var recorder
    @Environment(PhoneLink.self) private var link
    let summary: WorkoutRecorder.Summary

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 8) {
                Label(summary.activity.title, systemImage: summary.activity.symbol)
                    .font(.headline)
                    .foregroundStyle(.orange)
                Text(Format.distance(summary.distance))
                    .font(.system(size: 36, weight: .semibold, design: .rounded))
                Text(ElapsedText.clock(summary.duration, showsSeconds: true))
                    .font(.system(.title3, design: .rounded))
                    .foregroundStyle(.secondary)
                    .monospacedDigit()
                Label(syncNote, systemImage: link.pendingRecordings > 0 ? "iphone.and.arrow.forward" : "checkmark.circle.fill")
                    .font(.footnote)
                    .foregroundStyle(.secondary)
                    .padding(.top, 4)
                Button("完成") { recorder.dismissSummary() }
                    .buttonStyle(.borderedProminent)
                    .tint(.orange)
                    .padding(.top, 6)
            }
            .frame(maxWidth: .infinity, alignment: .leading)
        }
        .navigationTitle("已保存")
    }

    private var syncNote: String {
        if link.pendingRecordings == 0 { return String(localized: "已保存到 iPhone 的“旅程”", bundle: .appLanguage) }
        return link.isReachable
            ? String(localized: "正在同步到 iPhone", bundle: .appLanguage)
            : String(localized: "iPhone 在附近时会自动同步到“旅程”", bundle: .appLanguage)
    }
}

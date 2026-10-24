import ActivityKit
import SwiftUI
import WidgetKit

@main
struct WaytraceLiveActivityBundle: WidgetBundle {
    var body: some Widget {
        RecordingLiveActivity()
    }
}

/// A manual recording in progress: what it is, how long, how far. iOS also shows the small
/// layout in the Apple Watch Smart Stack, so a glance at the wrist is enough.
struct RecordingLiveActivity: Widget {
    var body: some WidgetConfiguration {
        ActivityConfiguration(for: RecordingAttributes.self) { context in
            RecordingCard(context: context)
        } dynamicIsland: { context in
            DynamicIsland {
                DynamicIslandExpandedRegion(.leading) {
                    Text(context.attributes.emoji).font(.title)
                }
                DynamicIslandExpandedRegion(.center) {
                    Text(context.attributes.title).font(.headline).lineLimit(1)
                }
                DynamicIslandExpandedRegion(.trailing) {
                    Text(Format.distance(context.state.distance))
                        .font(.title3.weight(.semibold)).monospacedDigit()
                        .foregroundStyle(.orange)
                }
                DynamicIslandExpandedRegion(.bottom) {
                    HStack {
                        ElapsedTime(start: context.attributes.start)
                            .font(.title3.weight(.semibold))
                        Spacer()
                        if context.state.watchRecording {
                            Label("Apple Watch 同步记录中", systemImage: "applewatch")
                                .font(.footnote).foregroundStyle(.secondary)
                        }
                    }
                }
            } compactLeading: {
                Image(systemName: "record.circle").foregroundStyle(.orange)
            } compactTrailing: {
                Text(Format.distance(context.state.distance))
                    .monospacedDigit().foregroundStyle(.orange)
            } minimal: {
                Image(systemName: "record.circle").foregroundStyle(.orange)
            }
            .keylineTint(.orange)
        }
        .supplementalActivityFamilies([.small])
    }
}

private struct RecordingCard: View {
    @Environment(\.activityFamily) private var family
    let context: ActivityViewContext<RecordingAttributes>

    var body: some View {
        switch family {
        case .small:
            // The Watch Smart Stack and CarPlay: compact, readable at a glance.
            VStack(alignment: .leading, spacing: 2) {
                HStack(spacing: 4) {
                    Text(context.attributes.emoji)
                    Text(context.attributes.title).font(.headline).lineLimit(1)
                }
                HStack(alignment: .firstTextBaseline) {
                    ElapsedTime(start: context.attributes.start).font(.title3.weight(.semibold))
                    Spacer(minLength: 4)
                    Text(Format.distance(context.state.distance))
                        .font(.headline).monospacedDigit().foregroundStyle(.orange)
                }
            }
            .padding(10)
        default:
            HStack(spacing: 14) {
                Text(context.attributes.emoji)
                    .font(.system(size: 34))
                    .frame(width: 52, height: 52)
                    .background(.orange.opacity(0.18), in: .circle)
                VStack(alignment: .leading, spacing: 2) {
                    Label("正在记录", systemImage: "record.circle")
                        .font(.caption.weight(.semibold)).foregroundStyle(.orange)
                    Text(context.attributes.title).font(.headline).lineLimit(1)
                    // Full contrast: the Lock Screen wallpaper shows through the card.
                    ElapsedTime(start: context.attributes.start)
                        .font(.subheadline.weight(.semibold))
                }
                Spacer(minLength: 8)
                VStack(alignment: .trailing, spacing: 4) {
                    Text(Format.distance(context.state.distance))
                        .font(.title2.weight(.semibold)).monospacedDigit()
                    if context.state.watchRecording {
                        Image(systemName: "applewatch").foregroundStyle(.orange)
                            .accessibilityLabel("Apple Watch 同步记录中")
                    }
                }
            }
            .padding(16)
        }
    }
}

/// Counts up from the start without the app having to update the activity every second.
private struct ElapsedTime: View {
    let start: Date

    var body: some View {
        Text(timerInterval: start...Date.distantFuture, countsDown: false)
            .monospacedDigit()
    }
}

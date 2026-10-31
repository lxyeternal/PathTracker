import WidgetKit
import SwiftUI

/// Watch-face complications: today's distance and where you are, one tap from the map.
@main
struct WaytraceWidgets: Widget {
    var body: some WidgetConfiguration {
        StaticConfiguration(kind: "today", provider: Provider()) { entry in
            ComplicationView(entry: entry)
                .containerBackground(.fill.tertiary, for: .widget)
        }
        .configurationDisplayName("漫迹")
        .description("今天走了多远，现在在哪里。")
        .supportedFamilies([.accessoryCircular, .accessoryRectangular, .accessoryInline, .accessoryCorner])
    }
}

struct Entry: TimelineEntry {
    var date = Date()
    var snapshot: WatchSnapshot?
}

struct Provider: TimelineProvider {
    func placeholder(in context: Context) -> Entry {
        var sample = WatchSnapshot()
        sample.distance = 6_400
        sample.places = [.init(name: String(localized: "家", bundle: .appLanguage), detail: nil,
                               coordinate: .init(lat: 0, lon: 0), arrival: Date(), departure: nil)]
        return Entry(snapshot: sample)
    }

    func getSnapshot(in context: Context, completion: @escaping (Entry) -> Void) {
        if context.isPreview { return completion(placeholder(in: context)) }
        Task { @MainActor in completion(current()) }
    }

    func getTimeline(in context: Context, completion: @escaping (Timeline<Entry>) -> Void) {
        // The Watch app reloads this whenever the iPhone sends something new; the midnight
        // entry resets today's distance even if nothing arrives.
        Task { @MainActor in
            let now = current()
            var entries = [now]
            let calendar = Calendar.current
            let midnight = calendar.date(byAdding: .day, value: 1, to: calendar.startOfDay(for: now.date))
                ?? now.date.addingTimeInterval(86_400)
            // The pause ends on its own; don't keep saying "paused" after it has.
            if let until = now.snapshot?.pausedUntil, until > now.date, until < midnight {
                var resumed = now
                resumed.date = until
                resumed.snapshot?.pausedUntil = nil
                entries.append(resumed)
            }
            var tomorrow = entries[entries.count - 1]
            tomorrow.date = midnight
            tomorrow.snapshot?.distance = 0
            tomorrow.snapshot?.places = []
            entries.append(tomorrow)
            completion(Timeline(entries: entries, policy: .atEnd))
        }
    }

    @MainActor
    private func current() -> Entry {
        let snapshot = SharedSnapshot.load()
        if let snapshot { LanguageSettings.shared.set(AppLanguage(rawValue: snapshot.language) ?? .system) }
        // Yesterday's numbers would read as today's.
        guard let snapshot, Calendar.current.isDateInToday(snapshot.generatedAt) else {
            return Entry(snapshot: snapshot.map { var empty = $0; empty.distance = 0; empty.places = []; return empty })
        }
        return Entry(snapshot: snapshot)
    }
}

struct ComplicationView: View {
    @Environment(\.widgetFamily) private var family
    let entry: Entry

    private var distance: String { Format.distance(entry.snapshot?.distance ?? 0) }

    /// Where you are, or that recording is paused, which matters more.
    private var status: String {
        guard let snapshot = entry.snapshot else { return String(localized: "打开漫迹", bundle: .appLanguage) }
        if isPaused { return String(localized: "记录已暂停", bundle: .appLanguage) }
        return snapshot.currentPlace?.name ?? String(localized: "在路上", bundle: .appLanguage)
    }

    private var isPaused: Bool { entry.snapshot?.pausedUntil.map { $0 > entry.date } ?? false }

    var body: some View {
        switch family {
        case .accessoryCircular:
            ZStack {
                AccessoryWidgetBackground()
                VStack(spacing: 0) {
                    Image(systemName: isPaused ? "pause.fill" : "shoeprints.fill")
                        .font(.system(size: 13, weight: .semibold))
                        .widgetAccentable()
                    Text(shortDistance)
                        .font(.system(size: 15, weight: .semibold, design: .rounded))
                        .minimumScaleFactor(0.6)
                    Text("km").font(.system(size: 9, weight: .medium)).foregroundStyle(.secondary)
                }
            }
        case .accessoryRectangular:
            VStack(alignment: .leading, spacing: 1) {
                Label("漫迹", systemImage: isPaused ? "pause.circle.fill" : "shoeprints.fill")
                    .font(.headline)
                    .widgetAccentable()
                Text(status).lineLimit(1)
                Text("今天 \(distance)").foregroundStyle(.secondary)
            }
            .frame(maxWidth: .infinity, alignment: .leading)
        case .accessoryInline:
            Label("\(distance) · \(status)", systemImage: "shoeprints.fill")
        case .accessoryCorner:
            Image(systemName: isPaused ? "pause.fill" : "shoeprints.fill")
                .font(.title3)
                .widgetAccentable()
                .widgetLabel(distance)
        default:
            Text(distance)
        }
    }

    /// "6.4" for the small round complication, which labels the unit separately.
    private var shortDistance: String {
        let km = (entry.snapshot?.distance ?? 0) / 1000
        return km.formatted(.number.precision(.fractionLength(km < 100 ? 1 : 0)).locale(appLocale))
    }
}

import SwiftUI
import SwiftData
import Photos

/// Trips found in the history, offered one by one: keep it as a trip, or let it go.
struct FoundTripsSection: View {
    let trips: [Trip]
    @Environment(\.modelContext) private var context
    @AppStorage("foundTrips.dismissed") private var dismissedRaw = ""
    private var summaries = PlaceSummaries.shared

    init(trips: [Trip]) {
        self.trips = trips
    }

    private var dismissed: Set<String> { Set(dismissedRaw.split(separator: ",").map(String.init)) }

    /// Not already a trip, not turned down.
    private var offered: [TripFinder.Found] {
        summaries.foundTrips.filter { found in
            !dismissed.contains(found.id) && !trips.contains { $0.interval.intersects(found.interval) }
        }
    }

    var body: some View {
        let offered = offered
        if !offered.isEmpty {
            VStack(alignment: .leading, spacing: 12) {
                HStack(alignment: .firstTextBaseline) {
                    VStack(alignment: .leading, spacing: 2) {
                        Text("在足迹里找到 \(offered.count) 段旅行").font(.title3.bold())
                        Text("根据你离开常住地的日子整理出来").font(.subheadline).foregroundStyle(.secondary)
                    }
                    Spacer()
                    Button("全部收下") { keepAll(offered) }
                        .font(.subheadline.weight(.semibold))
                }
                ScrollView(.horizontal) {
                    LazyHStack(spacing: 12) {
                        ForEach(offered) { found in
                            FoundTripCard(found: found, keep: { keep(found) }, dismiss: { dismiss(found) })
                                .transition(.scale(scale: 0.85).combined(with: .opacity))
                        }
                    }
                    .scrollTargetLayout()
                }
                .scrollTargetBehavior(.viewAligned)
                .scrollIndicators(.hidden)
                .scrollClipDisabled()
            }
            .padding(.vertical, 4)
        }
    }

    private func keep(_ found: TripFinder.Found) {
        withAnimation(.spring(response: 0.45, dampingFraction: 0.8)) {
            insert(found)
            try? context.save()
        }
        UINotificationFeedbackGenerator().notificationOccurred(.success)
    }

    private func keepAll(_ all: [TripFinder.Found]) {
        withAnimation(.spring(response: 0.5, dampingFraction: 0.85)) {
            all.forEach(insert)
            try? context.save()
        }
        UINotificationFeedbackGenerator().notificationOccurred(.success)
    }

    private func insert(_ found: TripFinder.Found) {
        let trip = Trip(title: found.title, startDate: found.start)
        trip.endDate = found.end
        if let code = found.countryCode, code != "CN" { trip.coverEmoji = String.flag(for: code) } else { trip.coverEmoji = "🧳" }
        context.insert(trip)
    }

    private func dismiss(_ found: TripFinder.Found) {
        withAnimation(.smooth) {
            dismissedRaw = (dismissed.union([found.id])).joined(separator: ",")
        }
    }
}

private struct FoundTripCard: View {
    let found: TripFinder.Found
    let keep: () -> Void
    let dismiss: () -> Void
    @State private var cover: PHAsset?

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            ZStack(alignment: .topTrailing) {
                Group {
                    if let cover {
                        GeometryReader { geo in AssetThumbnail(asset: cover, side: geo.size.width) }
                    } else {
                        TimeCover(interval: found.interval,
                                  stays: PlaceSummaries.shared.stays.filter { found.interval.contains($0.arrival) },
                                  key: "found-\(found.id)")
                    }
                }
                .frame(width: 250, height: 150)
                .clipped()
                Button(action: dismiss) {
                    Image(systemName: "xmark")
                        .font(.caption.weight(.bold))
                        .frame(width: 28, height: 28)
                        .background(.ultraThinMaterial, in: .circle)
                }
                .buttonStyle(.plain)
                .padding(8)
                .accessibilityLabel("不是旅行")
            }
            VStack(alignment: .leading, spacing: 4) {
                Text(found.title).font(.headline).lineLimit(1)
                Text(dates).font(.subheadline).foregroundStyle(.secondary).lineLimit(1)
                Text(found.cities.joined(separator: " · ")).font(.caption).foregroundStyle(.tertiary).lineLimit(1)
                Button(action: keep) {
                    Label("收进旅程", systemImage: "plus")
                        .font(.subheadline.weight(.semibold))
                        .frame(maxWidth: .infinity)
                }
                .buttonStyle(.glassProminent)
                .controlSize(.small)
                .padding(.top, 6)
            }
            .padding(12)
        }
        .frame(width: 250)
        .background(.background.secondary, in: .rect(cornerRadius: 22, style: .continuous))
        .clipShape(.rect(cornerRadius: 22, style: .continuous))
        .task(id: found.id) {
            guard DayPhotos.canRead else { return }
            cover = PlacePhotos.cover(for: "trip-" + found.id, interval: found.interval, near: found.center, within: 80_000)
        }
    }

    private var dates: String {
        let last = found.end.addingTimeInterval(-1)
        let range = Calendar.current.isDate(found.start, inSameDayAs: last)
            ? found.start.formatted(.dateTime.year().month().day().locale(appLocale))
            : (found.start..<last).formatted(.interval.year().month().day().locale(appLocale))
        return String(localized: "\(range) · \(found.days) 天", bundle: .appLanguage)
    }
}

import SwiftUI
import SwiftData
import CoreLocation

/// "那年今日": where you were on this day in earlier years, as a Polaroid that develops while
/// you look at it. Tapping opens that day on top of today's page.
struct OnThisDayCard: View {
    let memories: [Memory]
    @State private var page = 0

    struct Memory: Identifiable {
        let years: Int
        let day: Date
        let stay: Stay
        let places: Int
        var id: Int { years }
    }

    var body: some View {
                VStack(spacing: 8) {
                    TabView(selection: $page) {
                        ForEach(memories.indices, id: \.self) { index in
                            MemoryRow(memory: memories[index])
                                .tag(index)
                        }
                    }
                    .tabViewStyle(.page(indexDisplayMode: .never))
                    .frame(height: 128)
                    if memories.count > 1 {
                        HStack(spacing: 6) {
                            ForEach(memories.indices, id: \.self) { index in
                                Capsule()
                                    .fill(index == page ? Color.orange : Color.secondary.opacity(0.3))
                                    .frame(width: index == page ? 16 : 6, height: 6)
                            }
                        }
                        .animation(.spring(duration: 0.35), value: page)
                    }
                }
                .padding(.vertical, 8)
                .background(.background.secondary, in: .rect(cornerRadius: 24, style: .continuous))
    }

    /// One memory per earlier year that has one, the most memorable first: away from home, a
    /// sight, a place with photos; then the most recent.
    static func find(stays: [Stay], today: Date, home: CLLocation?, calendar: Calendar = .current) -> [Memory] {
        var found: [(memory: Memory, score: Double)] = []
        for years in 1...30 {
            guard let date = calendar.date(byAdding: .year, value: -years, to: today) else { continue }
            let interval = calendar.dayInterval(for: date)
            let that = stays.filter {
                $0.arrival < interval.end && ($0.departure ?? $0.arrival) >= interval.start
                    && ($0.duration >= 20 * 60 || $0.isFromPhotos) && ($0.placeName != nil || $0.city != nil || $0.customName != nil)
            }
            guard !that.isEmpty else { continue }
            func score(_ stay: Stay) -> Double {
                var value = min(stay.duration / 3600, 3) * 0.5
                if stay.isLandmark { value += 3 }
                if let home, stay.location.distance(from: home) > 50_000 { value += 4 }
                if stay.customName != nil { value += 1 }
                if stay.isFromPhotos { value += 1 }
                return value
            }
            guard let best = that.max(by: { score($0) < score($1) }) else { continue }
            found.append((Memory(years: years, day: interval.start, stay: best, places: that.count), score(best) - Double(years) * 0.1))
        }
        return found.sorted { $0.score > $1.score }.map(\.memory)
    }
}

private struct MemoryRow: View {
    let memory: OnThisDayCard.Memory

    var body: some View {
        // Opened on top of today, so the back button brings you home.
        NavigationLink(value: DayRoute(day: memory.day)) {
            HStack(spacing: 16) {
                Polaroid(stay: memory.stay)
                    .rotationEffect(.degrees(-4))
                VStack(alignment: .leading, spacing: 3) {
                    Label("那年今日", systemImage: "calendar.badge.clock")
                        .font(.caption.weight(.bold))
                        .foregroundStyle(.orange)
                    Text("\(memory.years) 年前的今天")
                        .font(.title3.bold())
                    Text(memory.stay.displayName)
                        .font(.subheadline.weight(.semibold))
                        .lineLimit(1)
                    Text([memory.stay.city == memory.stay.displayName ? nil : memory.stay.city,
                          memory.day.formatted(.dateTime.year().month().day().locale(appLocale))]
                            .compactMap { $0 }.joined(separator: " · "))
                        .font(.caption)
                        .foregroundStyle(.secondary)
                        .lineLimit(1)
                }
                Spacer(minLength: 0)
                Image(systemName: "chevron.right").font(.caption.weight(.semibold)).foregroundStyle(.tertiary)
            }
            .padding(.horizontal, 16)
            .contentShape(.rect)
        }
        .buttonStyle(PressableStyle())
    }
}

/// The place's picture in a white frame, developing from a pale wash the first time it's seen.
private struct Polaroid: View {
    let stay: Stay
    @State private var developed = false

    var body: some View {
        VStack(spacing: 0) {
            PlacePicture(stay: stay)
                .frame(width: 78, height: 78)
                .clipShape(.rect(cornerRadius: 2))
                .saturation(developed ? 1 : 0)
                .brightness(developed ? 0 : 0.45)
                .blur(radius: developed ? 0 : 3)
            Color.clear.frame(width: 78, height: 14)
        }
        .padding([.horizontal, .top], 5)
        .background(.white, in: .rect(cornerRadius: 3))
        .shadow(color: .black.opacity(0.18), radius: 5, y: 3)
        .onAppear {
            withAnimation(.easeOut(duration: 1.8).delay(0.3)) { developed = true }
        }
    }
}

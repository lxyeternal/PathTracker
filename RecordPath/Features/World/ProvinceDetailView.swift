import SwiftUI

/// A province opened from the light-up map: where you went in it, its cities, and every
/// visit as runs of days, the same way a country page reads.
struct ProvinceDetailView: View {
    let province: Province
    private var summaries = PlaceSummaries.shared
    @State private var stays: [Stay] = []
    @State private var stints: [CityStint] = []
    @State private var selected: Stay?

    init(province: Province) {
        self.province = province
    }

    private var visit: LightUpInsights.Visit? { summaries.lightUp.provinces[province.id] }

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 16) {
                if let visit {
                    // No outline: the app draws no borders inside China, only where you went.
                    CountryMap(code: "", stays: stays, onSelect: { selected = $0 })
                        .frame(height: 280)
                        .clipShape(.rect(cornerRadius: 28, style: .continuous))

                    MetricGrid {
                        MetricTile(title: "停留天数", value: "\(visit.days.count)", symbol: "calendar", tint: .teal)
                        MetricTile(title: "城市", value: "\(visit.cities.count)", symbol: "building.2.fill", tint: .indigo)
                        MetricTile(title: "首次到访", value: visit.firstVisit.formatted(.dateTime.year().month().day().locale(appLocale)),
                                   symbol: "airplane.arrival", tint: .blue)
                        MetricTile(title: "到访地点", value: "\(stays.count)", symbol: "mappin.and.ellipse", tint: .pink)
                    }

                    StintsByYear(stints: stints)
                } else {
                    ContentUnavailableView("还没点亮", systemImage: "lightbulb",
                                           description: Text("去过\(province.name)之后，这里会亮起来。"))
                        .padding(.top, 60)
                }
            }
            .padding(.horizontal)
            .padding(.bottom, 24)
        }
        .navigationTitle(province.name)
        .navigationBarTitleDisplayMode(.large)
        .sheet(item: $selected) { StayDetailView(stay: $0) }
        .task(id: summaries.stays.count) {
            stays = summaries.stays.filter {
                Province.containing(countryCode: $0.countryCode, region: $0.region, city: $0.city) == province
            }
            stints = CityStint.group(stays)
        }
    }
}

/// Every visit as runs of days in one city. A short history is one list under year headings;
/// a long one is shown a year at a time, with the year's months at a glance on top (tap a
/// month to jump to it) and long months folded.
struct StintsByYear: View {
    let stints: [CityStint]
    @State private var year = 0
    @State private var opened: Set<String> = []

    /// Below this many, everything fits on one page without help.
    private static let short = 12
    /// Visits shown in a month before it folds.
    private static let perMonth = 4

    private var calendar: Calendar { .current }

    private var years: [(year: Int, stints: [CityStint])] {
        Dictionary(grouping: stints) { calendar.component(.year, from: $0.start) }
            .map { ($0.key, $0.value.sorted { $0.start > $1.start }) }
            .sorted { $0.year > $1.year }
    }

    var body: some View {
        let years = years
        if stints.count <= Self.short || years.count == 1 && years[0].stints.count <= Self.short {
            ForEach(years, id: \.year) { group in
                SectionHeader(title: LocalizedStringKey(String(group.year)), trailing: "\(group.stints.count) 次")
                list(group.stints)
            }
        } else {
            let current = years.first { $0.year == year } ?? years[0]
            VStack(alignment: .leading, spacing: 12) {
                SectionHeader(title: "每一次到访", trailing: "\(stints.count) 次")
                FilterChips(options: years.map { .init(value: $0.year, title: String($0.year), count: $0.stints.count) },
                            selection: $year)
                ScrollViewReader { proxy in
                    VStack(alignment: .leading, spacing: 14) {
                        MonthStrip(year: current.year, stints: current.stints) { month in
                            withAnimation(.smooth) { proxy.scrollTo(anchor(current.year, month), anchor: .top) }
                        }
                        ForEach(months(current.stints), id: \.month) { group in
                            monthBlock(year: current.year, month: group.month, stints: group.stints)
                                .id(anchor(current.year, group.month))
                        }
                    }
                    .id(current.year)
                    .transition(.opacity)
                }
            }
            .animation(.smooth, value: year)
            .onAppear { if year == 0 { year = years[0].year } }
        }
    }

    private func anchor(_ year: Int, _ month: Int) -> String { "\(year)-\(month)" }

    private func months(_ stints: [CityStint]) -> [(month: Int, stints: [CityStint])] {
        Dictionary(grouping: stints) { calendar.component(.month, from: $0.start) }
            .map { ($0.key, $0.value) }
            .sorted { $0.month > $1.month }
    }

    private func monthBlock(year: Int, month: Int, stints: [CityStint]) -> some View {
        let key = anchor(year, month)
        let open = opened.contains(key) || stints.count <= Self.perMonth + 1
        let days = stints.reduce(0) { $0 + $1.days }
        return VStack(alignment: .leading, spacing: 8) {
            HStack(alignment: .firstTextBaseline) {
                Text(monthTitle(year: year, month: month)).font(.headline)
                Spacer()
                Text("\(stints.count) 次 · \(days) 天").font(.subheadline).foregroundStyle(.secondary).monospacedDigit()
            }
            .padding(.horizontal, 4)
            list(open ? stints : Array(stints.prefix(Self.perMonth)), more: open ? 0 : stints.count - Self.perMonth) {
                withAnimation(.smooth) { _ = opened.insert(key) }
            }
        }
    }

    private func monthTitle(year: Int, month: Int) -> String {
        let date = calendar.date(from: DateComponents(year: year, month: month, day: 1)) ?? Date()
        return date.formatted(.dateTime.month(.wide).locale(appLocale))
    }

    private func list(_ stints: [CityStint], more: Int = 0, showMore: @escaping () -> Void = {}) -> some View {
        LazyVStack(spacing: 0) {
            ForEach(stints) { stint in
                NavigationLink(value: stint) { CityStintRow(stint: stint) }.buttonStyle(.plain)
            }
            if more > 0 {
                Divider().padding(.leading, 84)
                Button(action: showMore) {
                    HStack {
                        Text("展开其余 \(more) 次").font(.subheadline.weight(.medium))
                        Spacer()
                        Image(systemName: "chevron.down").font(.caption.weight(.semibold))
                    }
                    .foregroundStyle(Color.accentColor)
                    .padding(.horizontal, 16).padding(.vertical, 12)
                    .contentShape(.rect)
                }
                .buttonStyle(.plain)
            }
        }
        .padding(.vertical, 6)
        .background(.background.secondary, in: .rect(cornerRadius: 24, style: .continuous))
    }
}

/// A year's twelve months as bars, taller for more days away; tap one to go to it.
private struct MonthStrip: View {
    let year: Int
    let stints: [CityStint]
    let select: (Int) -> Void
    @State private var grown = false

    var body: some View {
        let calendar = Calendar.current
        var days = [Int](repeating: 0, count: 12)
        for stint in stints { days[calendar.component(.month, from: stint.start) - 1] += stint.days }
        let most = max(days.max() ?? 1, 1)
        return HStack(alignment: .bottom, spacing: 5) {
            ForEach(0..<12, id: \.self) { index in
                Button { if days[index] > 0 { select(index + 1) } } label: {
                    VStack(spacing: 5) {
                        Capsule()
                            .fill(days[index] > 0 ? AnyShapeStyle(Color.accentColor.gradient) : AnyShapeStyle(Color.secondary.opacity(0.15)))
                            .frame(height: days[index] > 0 ? max(8, 54 * CGFloat(days[index]) / CGFloat(most) * (grown ? 1 : 0.1)) : 4)
                        Text(verbatim: "\(index + 1)")
                            .font(.caption2.weight(days[index] > 0 ? .semibold : .regular))
                            .foregroundStyle(days[index] > 0 ? .primary : .tertiary)
                            .monospacedDigit()
                    }
                    .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .bottom)
                    .contentShape(.rect)
                }
                .buttonStyle(.plain)
                .disabled(days[index] == 0)
                .accessibilityLabel(Text(verbatim: "\(index + 1)"))
                .accessibilityValue(Text("\(days[index]) 天"))
            }
        }
        .frame(height: 76)
        .padding(14)
        .background(.background.secondary, in: .rect(cornerRadius: 22, style: .continuous))
        .onAppear { withAnimation(.spring(response: 0.6, dampingFraction: 0.8).delay(0.1)) { grown = true } }
        .onChange(of: year) {
            grown = false
            withAnimation(.spring(response: 0.6, dampingFraction: 0.8)) { grown = true }
        }
    }
}

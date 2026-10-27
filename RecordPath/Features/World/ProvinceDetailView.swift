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

/// Visits as runs of days in one city, under a heading for each year.
struct StintsByYear: View {
    let stints: [CityStint]

    private var groups: [(year: Int, stints: [CityStint])] {
        Dictionary(grouping: stints) { Calendar.current.component(.year, from: $0.start) }
            .map { ($0.key, $0.value) }
            .sorted { $0.year > $1.year }
    }

    var body: some View {
        ForEach(groups, id: \.year) { group in
            SectionHeader(title: LocalizedStringKey(String(group.year)), trailing: "\(group.stints.count) 次")
            LazyVStack(spacing: 0) {
                ForEach(group.stints) { stint in
                    NavigationLink(value: stint) { CityStintRow(stint: stint) }.buttonStyle(.plain)
                }
            }
            .padding(.vertical, 6)
            .background(.background.secondary, in: .rect(cornerRadius: 24, style: .continuous))
        }
    }
}

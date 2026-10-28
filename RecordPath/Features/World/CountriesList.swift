import SwiftUI

/// A row of capsules to narrow a long list: "全部 12 · 亚洲 8 · 欧洲 3". The selected one fills.
struct FilterChips<Value: Hashable>: View {
    struct Option: Identifiable {
        let value: Value
        let title: String
        let count: Int
        var id: Value { value }
    }

    let options: [Option]
    @Binding var selection: Value

    var body: some View {
        ScrollView(.horizontal) {
            HStack(spacing: 8) {
                ForEach(options) { option in
                    let selected = option.value == selection
                    Button {
                        withAnimation(.snappy) { selection = option.value }
                    } label: {
                        HStack(spacing: 5) {
                            Text(verbatim: option.title).font(.subheadline.weight(.semibold))
                            Text(verbatim: "\(option.count)").font(.caption.weight(.bold)).opacity(0.7).monospacedDigit()
                        }
                        .padding(.horizontal, 14).padding(.vertical, 8)
                        .foregroundStyle(selected ? Color.white : Color.primary)
                        .background(selected ? AnyShapeStyle(Color.accentColor) : AnyShapeStyle(.quaternary.opacity(0.6)), in: .capsule)
                        .contentShape(.capsule)
                    }
                    .buttonStyle(.plain)
                    .accessibilityAddTraits(selected ? .isSelected : [])
                }
            }
            .padding(.horizontal, 1)
        }
        .scrollIndicators(.hidden)
        .scrollClipDisabled()
        .sensoryFeedback(.selection, trigger: selection)
    }
}

extension Continent {
    private static let byRegion: [String: Continent] = {
        var map: [String: Continent] = [:]
        for continent in all { for code in continent.regions { map[code] = continent } }
        return map
    }()

    static func of(_ code: String) -> Continent? { byRegion[code] }

    /// "全部" and each continent with somewhere visited in it, the most visited first.
    static func options(for countries: [CountrySummary]) -> [FilterChips<String>.Option] {
        let counts = Dictionary(grouping: countries.compactMap { of($0.code) }, by: \.id).mapValues(\.count)
        let continents = all.filter { counts[$0.id] != nil }.sorted { counts[$0.id]! > counts[$1.id]! }
        return [FilterChips<String>.Option(value: "", title: String(localized: "全部", bundle: .appLanguage), count: countries.count)]
            + continents.map { FilterChips<String>.Option(value: $0.id, title: $0.name, count: counts[$0.id]!) }
    }
}

struct CountriesRoute: Hashable {
    var continent = ""
}

/// One country in a list: flag, name, and how much time was spent there.
struct CountryRow: View {
    let country: CountrySummary

    var body: some View {
        HStack(spacing: 14) {
            Text(country.flag).font(.system(size: 34))
            VStack(alignment: .leading, spacing: 2) {
                Text(country.name).font(.body.weight(.semibold)).lineLimit(1)
                Text(detail).font(.subheadline).foregroundStyle(.secondary).lineLimit(1)
            }
            Spacer(minLength: 0)
            Image(systemName: "chevron.right").font(.caption.weight(.semibold)).foregroundStyle(.tertiary)
        }
        .padding(.horizontal, 16)
        .padding(.vertical, 10)
        .contentShape(.rect)
    }

    private var detail: String {
        let lastYear = Calendar.current.component(.year, from: country.lastVisit)
        return String(localized: "\(country.days.count) 天 · \(country.cities.count) 座城市 · 最近 \(String(lastYear))", bundle: .appLanguage)
    }
}

/// Every country, narrowed by continent and sorted the way you choose. Under "全部" they're
/// gathered by continent, so a long list still reads in parts.
struct CountriesListView: View {
    @State private var continent: String
    @State private var order = Order.days
    @State private var search = ""
    private var summaries = PlaceSummaries.shared

    enum Order: String, CaseIterable { case days, recent, first, name }

    init(route: CountriesRoute) {
        _continent = State(initialValue: route.continent)
    }

    private var countries: [CountrySummary] { summaries.world.countries }

    private var shown: [CountrySummary] {
        countries
            .filter { continent.isEmpty || Continent.of($0.code)?.id == continent }
            .filter { search.isEmpty || $0.name.localizedStandardContains(search) || $0.code.localizedCaseInsensitiveContains(search) }
            .sorted(by: sorter)
    }

    private func sorter(_ a: CountrySummary, _ b: CountrySummary) -> Bool {
        switch order {
        case .days: a.days.count > b.days.count
        case .recent: a.lastVisit > b.lastVisit
        case .first: a.firstVisit < b.firstVisit
        case .name: a.name.localizedStandardCompare(b.name) == .orderedAscending
        }
    }

    /// Under "全部", one block per continent, the one with most countries first.
    private var groups: [(continent: Continent?, countries: [CountrySummary])] {
        guard continent.isEmpty, search.isEmpty else { return [(nil, shown)] }
        let grouped = Dictionary(grouping: shown) { Continent.of($0.code)?.id ?? "" }
        return grouped.map { key, countries in (Continent.all.first { $0.id == key }, countries) }
            .sorted { $0.countries.count > $1.countries.count }
    }

    var body: some View {
        ScrollView {
            LazyVStack(alignment: .leading, spacing: 14, pinnedViews: .sectionHeaders) {
                Section {
                    if shown.isEmpty {
                        ContentUnavailableView.search(text: search).padding(.top, 40)
                    }
                    ForEach(groups, id: \.continent?.id) { group in
                        VStack(alignment: .leading, spacing: 8) {
                            if let place = group.continent {
                                HStack(alignment: .firstTextBaseline) {
                                    Text(place.name).font(.headline)
                                    Spacer()
                                    Text(verbatim: "\(group.countries.count) / \(place.regions.count)")
                                        .font(.subheadline).foregroundStyle(.secondary).monospacedDigit()
                                }
                                .padding(.horizontal, 4)
                            }
                            VStack(spacing: 0) {
                                ForEach(group.countries) { country in
                                    NavigationLink(value: country) { CountryRow(country: country) }.buttonStyle(.plain)
                                    if country.id != group.countries.last?.id { Divider().padding(.leading, 64) }
                                }
                            }
                            .padding(.vertical, 6)
                            .background(.background.secondary, in: .rect(cornerRadius: 24, style: .continuous))
                        }
                        .transition(.opacity)
                    }
                } header: {
                    FilterChips(options: Continent.options(for: countries), selection: $continent)
                        .padding(.vertical, 8)
                        .background(.background)
                }
            }
            .padding(.horizontal)
            .padding(.bottom, 24)
            .animation(.smooth, value: continent)
            .animation(.smooth, value: order)
        }
        .navigationTitle("国家和地区")
        .navigationBarTitleDisplayMode(.inline)
        .searchable(text: $search, prompt: "搜索国家或地区")
        .toolbar {
            ToolbarItem(placement: .topBarTrailing) {
                Menu("排序", systemImage: "arrow.up.arrow.down") {
                    Picker("排序", selection: $order) {
                        Text("停留最久").tag(Order.days)
                        Text("最近去过").tag(Order.recent)
                        Text("最早去过").tag(Order.first)
                        Text("名称").tag(Order.name)
                    }
                }
            }
        }
    }
}

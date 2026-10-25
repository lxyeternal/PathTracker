import SwiftUI
import SwiftData

struct CountryDetailView: View {
    let country: CountrySummary
    @Query private var stays: [Stay]
    @State private var selected: Stay?

    init(country: CountrySummary) {
        self.country = country
        let code = country.code
        _stays = Query(filter: #Predicate<Stay> { $0.countryCode == code }, sort: \Stay.arrival, order: .reverse)
    }

    private var cities: [(name: String, visits: Int, days: Int)] {
        Dictionary(grouping: stays.filter { $0.city != nil }, by: { $0.city! })
            .map { name, stays in
                let days = Set(stays.flatMap { Calendar.current.days(in: DateInterval(start: $0.arrival, end: max($0.departure ?? Date(), $0.arrival))) })
                return (name, stays.count, days.count)
            }
            .sorted { $0.days > $1.days }
    }

    private var landmarks: [Stay] {
        var names = Set<String>()
        return stays.filter { $0.isLandmark && names.insert($0.displayName).inserted }
    }

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 16) {
                WorldMap(stays: stays, interactive: true, onSelect: { selected = $0 })
                    .frame(height: 260)
                    .clipShape(.rect(cornerRadius: 28, style: .continuous))

                MetricGrid {
                    MetricTile(title: "停留天数", value: "\(country.days.count)", symbol: "calendar", tint: .teal)
                    MetricTile(title: "城市", value: "\(cities.count)", symbol: "building.2.fill", tint: .indigo)
                    MetricTile(title: "首次到访", value: country.firstVisit.formatted(.dateTime.year().month().day().locale(appLocale)),
                               symbol: "airplane.arrival", tint: .blue)
                    MetricTile(title: "最近一次", value: country.lastVisit.formatted(.dateTime.year().month().day().locale(appLocale)),
                               symbol: "clock.fill", tint: .orange)
                }

                if !cities.isEmpty {
                    SectionHeader(title: "城市")
                    VStack(spacing: 0) {
                        ForEach(cities, id: \.name) { city in
                            HStack {
                                Image(systemName: "building.2").foregroundStyle(.indigo).frame(width: 28)
                                Text(city.name).font(.body.weight(.medium))
                                Spacer()
                                Text("\(city.days) 天 · \(city.visits) 处").font(.subheadline).foregroundStyle(.secondary)
                            }
                            .padding(.horizontal, 16)
                            .padding(.vertical, 12)
                        }
                    }
                    .padding(.vertical, 4)
                    .background(.background.secondary, in: .rect(cornerRadius: 24, style: .continuous))
                }

                if !landmarks.isEmpty {
                    SectionHeader(title: "景点")
                    VStack(spacing: 0) {
                        ForEach(landmarks) { stay in
                            Button { selected = stay } label: { PlaceRow(stay: stay) }.buttonStyle(.plain)
                        }
                    }
                    .padding(.vertical, 6)
                    .background(.background.secondary, in: .rect(cornerRadius: 24, style: .continuous))
                }

                SectionHeader(title: "所有停留", trailing: "\(stays.count)")
                VStack(spacing: 0) {
                    ForEach(stays.prefix(100)) { stay in
                        Button { selected = stay } label: { PlaceRow(stay: stay) }.buttonStyle(.plain)
                    }
                }
                .padding(.vertical, 6)
                .background(.background.secondary, in: .rect(cornerRadius: 24, style: .continuous))
            }
            .padding(.horizontal)
            .padding(.bottom, 24)
        }
        .navigationTitle("\(country.flag) \(country.name)")
        .navigationBarTitleDisplayMode(.large)
        .sheet(item: $selected) { StayDetailView(stay: $0) }
    }
}

enum PlacesList: Hashable { case frequent, landmarks }

/// Full lists behind the "全部" buttons, searchable.
struct PlacesListView: View {
    let list: PlacesList
    @Query(sort: \Stay.arrival, order: .reverse) private var stays: [Stay]
    @State private var search = ""
    @State private var selected: Stay?

    var body: some View {
        let insights = WorldInsights(stays: stays)
        Group {
            switch list {
            case .frequent:
                List {
                    ForEach(insights.frequentPlaces.filter { matches($0.representative) }) { place in
                        NavigationLink(value: PlaceVisits.around(place.representative, in: stays)) {
                            HStack(spacing: 14) {
                                PlaceIcon(category: place.representative.category)
                                VStack(alignment: .leading) {
                                    Text(place.representative.displayName).font(.body.weight(.semibold))
                                    Text("\(place.visits) 次 · 共 \(Format.duration(place.totalTime))")
                                        .font(.subheadline).foregroundStyle(.secondary)
                                }
                            }
                        }
                    }
                }
            case .landmarks:
                ScrollView {
                    LazyVGrid(columns: [GridItem(.flexible(), spacing: 12), GridItem(.flexible(), spacing: 12)], spacing: 12) {
                        ForEach(insights.landmarks.filter(matches)) { stay in
                            NavigationLink(value: PlaceVisits.around(stay, in: stays)) { SightCard(stay: stay, width: nil) }
                                .buttonStyle(PressableStyle())
                        }
                    }
                    .padding(.horizontal)
                    .padding(.bottom, 24)
                }
            }
        }
        .overlay {
            if !search.isEmpty && (list == .frequent ? insights.frequentPlaces.filter({ matches($0.representative) }).isEmpty
                                                     : insights.landmarks.filter(matches).isEmpty) {
                ContentUnavailableView.search(text: search)
            }
        }
        .searchable(text: $search, prompt: "搜索地点")
        .navigationTitle(list == .frequent ? "常去的地方" : "去过的景点")
        .sheet(item: $selected) { StayDetailView(stay: $0) }
    }

    private func matches(_ stay: Stay) -> Bool {
        search.isEmpty || stay.displayName.localizedStandardContains(search)
            || (stay.city?.localizedStandardContains(search) ?? false)
    }
}

import SwiftUI
import SwiftData
import MapKit

/// Every visit to one place, grouped so "我什么时候去过外滩？" has an answer.
/// A place to open, by the stay that stands for it. Cheap to make in a list; the visits
/// around it are gathered when the page opens.
struct PlaceAround: Hashable {
    let id: PersistentIdentifier

    init(_ stay: Stay) { id = stay.persistentModelID }
}

struct PlaceVisits: Identifiable, Hashable {
    let name: String
    let visits: [Stay]

    var id: String { name + (latest.city ?? "") }
    var latest: Stay { visits.max { $0.arrival < $1.arrival }! }
    var first: Stay { visits.min { $0.arrival < $1.arrival }! }
    var totalTime: TimeInterval { visits.reduce(0) { $0 + $1.duration } }

    static func == (lhs: Self, rhs: Self) -> Bool { lhs.id == rhs.id && lhs.visits.count == rhs.visits.count }
    func hash(into hasher: inout Hasher) { hasher.combine(id) }

    /// All visits to the place a stay belongs to.
    static func around(_ stay: Stay, in stays: [Stay]) -> PlaceVisits {
        let members = stays.filter { $0.location.distance(from: stay.location) <= KnownPlaces.radius }
        return PlaceVisits(name: stay.displayName, visits: members.isEmpty ? [stay] : members)
    }

    /// Groups stays by their display name within ~150 m, newest place first.
    static func group(_ stays: [Stay]) -> [PlaceVisits] {
        var groups: [(name: String, anchor: CLLocation, members: [Stay])] = []
        for stay in stays {
            let name = stay.displayName
            if let index = groups.firstIndex(where: { $0.name == name && $0.anchor.distance(from: stay.location) <= KnownPlaces.radius }) {
                groups[index].members.append(stay)
            } else {
                groups.append((name, stay.location, [stay]))
            }
        }
        return groups.map { PlaceVisits(name: $0.name, visits: $0.members) }
            .sorted { $0.latest.arrival > $1.latest.arrival }
    }
}

struct PlaceSearchResults: View {
    let query: String
    let stays: [Stay]
    let countries: [CountrySummary]

    private var matchingCountries: [CountrySummary] {
        countries.filter { $0.name.localizedStandardContains(query) || $0.code.localizedStandardContains(query) }
    }

    private var matchingPlaces: [PlaceVisits] {
        PlaceVisits.group(stays.filter { stay in
            stay.displayName.localizedStandardContains(query)
                || (stay.city?.localizedStandardContains(query) ?? false)
                || (stay.street?.localizedStandardContains(query) ?? false)
                || (stay.note?.localizedStandardContains(query) ?? false)
        })
    }

    var body: some View {
        let places = matchingPlaces
        let countries = matchingCountries
        VStack(alignment: .leading, spacing: 10) {
            if places.isEmpty && countries.isEmpty {
                ContentUnavailableView.search(text: query)
                    .padding(.top, 40)
            }
            if !countries.isEmpty {
                SectionHeader(title: "国家和地区")
                VStack(spacing: 0) {
                    ForEach(countries) { country in
                        NavigationLink(value: country) {
                            HStack(spacing: 14) {
                                Text(country.flag).font(.system(size: 30))
                                Text(country.name).font(.body.weight(.semibold))
                                Spacer()
                                Text("\(country.days.count) 天").foregroundStyle(.secondary)
                                Image(systemName: "chevron.right").font(.caption.weight(.semibold)).foregroundStyle(.tertiary)
                            }
                            .padding(.horizontal, 16)
                            .padding(.vertical, 10)
                            .contentShape(.rect)
                        }
                        .buttonStyle(.plain)
                    }
                }
                .padding(.vertical, 6)
                .background(.background.secondary, in: .rect(cornerRadius: 24, style: .continuous))
            }
            if !places.isEmpty {
                SectionHeader(title: "地点", trailing: "\(places.count)")
                VStack(spacing: 0) {
                    ForEach(places) { place in
                        NavigationLink(value: place) { PlaceVisitsRow(place: place) }
                            .buttonStyle(.plain)
                    }
                }
                .padding(.vertical, 6)
                .background(.background.secondary, in: .rect(cornerRadius: 24, style: .continuous))
            }
        }
    }
}

struct PlaceVisitsRow: View {
    let place: PlaceVisits

    var body: some View {
        HStack(spacing: 14) {
            PlaceIcon(category: place.latest.category, isLandmark: place.latest.isLandmark)
            VStack(alignment: .leading, spacing: 2) {
                Text(place.name).font(.body.weight(.semibold)).lineLimit(1)
                Text(summary).font(.subheadline).foregroundStyle(.secondary).lineLimit(1)
            }
            Spacer()
            Image(systemName: "chevron.right").font(.caption.weight(.semibold)).foregroundStyle(.tertiary)
        }
        .padding(.horizontal, 16)
        .padding(.vertical, 10)
        .contentShape(.rect)
    }

    private var summary: String {
        let date = place.latest.arrival
        let last = Calendar.current.isDate(date, equalTo: Date(), toGranularity: .year)
            ? date.formatted(.dateTime.month().day().locale(appLocale)) : date.formatted(.dateTime.year().month().day().locale(appLocale))
        let city = place.latest.city.map { "\($0) · " } ?? ""
        return place.visits.count == 1
            ? "\(city)\(last)"
            : String(localized: "\(city)\(place.visits.count) 次 · 最近 \(last)", bundle: .appLanguage)
    }
}

/// All visits to a place, newest first; each one opens that day.
struct PlaceVisitsView: View {
    let place: PlaceVisits
    @Environment(AppNavigator.self) private var navigator
    @State private var selected: Stay?

    private var sortedVisits: [Stay] { place.visits.sorted { $0.arrival > $1.arrival } }

    var body: some View {
        List {
            Section {
                Map(initialPosition: .camera(MapCamera(centerCoordinate: place.latest.coordinate.onMap, distance: 1500))) {
                    Annotation(place.name, coordinate: place.latest.coordinate.onMap) {
                        PlaceIcon(category: place.latest.category, isLandmark: place.latest.isLandmark, size: 34)
                            .overlay(Circle().stroke(.white, lineWidth: 2))
                    }
                }
                .allowsHitTesting(false)
                .frame(height: 180)
                    .listRowInsets(EdgeInsets())
            }
            Section {
                LabeledContent("到访次数", value: "\(place.visits.count)")
                LabeledContent("累计停留", value: Format.duration(place.totalTime))
                LabeledContent("第一次", value: place.first.arrival.formatted(Date.FormatStyle(date: .abbreviated, time: .omitted, locale: appLocale)))
                if let address = [place.latest.street, place.latest.city, place.latest.country].compactMap({ $0 }).first {
                    LabeledContent("位置", value: address)
                }
            }
            Section {
                ForEach(sortedVisits) { visit in
                    Button {
                        navigator.show(day: visit.arrival)
                    } label: {
                        HStack {
                            VStack(alignment: .leading, spacing: 2) {
                                Text(visit.arrival.formatted(.dateTime.year().month().day().weekday(.abbreviated).locale(appLocale)))
                                    .foregroundStyle(.primary)
                                Text("\(Format.time(visit.arrival)) · 停留 \(Format.duration(visit.duration))")
                                    .font(.subheadline).foregroundStyle(.secondary)
                            }
                            Spacer()
                            Image(systemName: "calendar").foregroundStyle(Color.accentColor)
                        }
                    }
                    .tint(.primary)
                    .swipeActions {
                        Button("详情", systemImage: "info.circle") { selected = visit }.tint(.gray)
                    }
                }
            } header: {
                Text("每一次到访")
            } footer: {
                Text("点一次到访，查看那一天的完整轨迹。")
            }
        }
        .navigationTitle(place.name)
        .navigationBarTitleDisplayMode(.inline)
        .toolbar {
            ToolbarItem(placement: .primaryAction) {
                Button("编辑", systemImage: "pencil") { selected = place.latest }
            }
        }
        .sheet(item: $selected) { StayDetailView(stay: $0) }
    }
}

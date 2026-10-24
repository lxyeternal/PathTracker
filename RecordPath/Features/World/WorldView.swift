import SwiftUI
import SwiftData
import MapKit

struct WorldView: View {
    @Binding var showingSettings: Bool
    @Query(sort: \Stay.arrival, order: .reverse) private var stays: [Stay]
    @State private var insights = WorldInsights()
    @State private var lightUp = LightUpInsights()
    @State private var selectedStay: Stay?
    @State private var showingMap = false
    @State private var search = ""
    @Namespace private var namespace

    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(alignment: .leading, spacing: 16) {
                    if stays.isEmpty {
                        ContentUnavailableView("足迹会在这里出现",
                                               systemImage: "globe.asia.australia",
                                               description: Text("去过的国家、城市和景点会被自动整理出来。"))
                            .padding(.top, 60)
                    } else if !search.isEmpty {
                        PlaceSearchResults(query: search, stays: stays, countries: insights.countries)
                    } else {
                        summaryGrid
                        lightUpCard
                        mapCard
                        if !insights.countries.isEmpty { countries }
                        if !insights.frequentPlaces.isEmpty { frequentPlaces }
                        if !insights.landmarks.isEmpty { landmarks }
                    }
                }
                .padding(.horizontal)
                .padding(.bottom, 24)
            }
            .navigationTitle("足迹")
            .searchable(text: $search, prompt: "搜索地点、城市或国家")
            .navigationDestination(for: PlaceVisits.self) { PlaceVisitsView(place: $0) }
            .toolbar {
                ToolbarItem(placement: .topBarTrailing) {
                    ProfileToolbarButton(showingSettings: $showingSettings)
                }
            }
            .navigationDestination(for: CountrySummary.self) { country in
                CountryDetailView(country: country)
            }
            .navigationDestination(for: PlacesList.self) { list in
                PlacesListView(list: list)
            }
            .navigationDestination(for: LightUpRoute.self) { _ in
                LightUpView(stays: stays)
            }
            .sheet(item: $selectedStay) { StayDetailView(stay: $0) }
            .fullScreenCover(isPresented: $showingMap) {
                WorldMapScreen(stays: stays)
                    .navigationTransition(.zoom(sourceID: "world", in: namespace))
            }
            .task(id: stays.map(\.tagStateRaw).reduce(stays.count, +)) {
                withAnimation(.smooth) {
                    insights = WorldInsights(stays: stays)
                    lightUp = LightUpInsights(stays: stays)
                }
            }
        }
    }

    private var summaryGrid: some View {
        MetricGrid {
            MetricTile(title: "国家与地区", value: "\(insights.countries.count)", symbol: "flag.fill", tint: .red)
            MetricTile(title: "城市", value: "\(insights.cityCount)", symbol: "building.2.fill", tint: .indigo)
            MetricTile(title: "景点", value: "\(insights.landmarks.count)", symbol: "star.fill", tint: .yellow)
            MetricTile(title: "记录天数", value: "\(insights.trackedDays)", symbol: "calendar", tint: .teal)
        }
    }

    /// A peek at the light-up map: the province tiles, small, with the counts.
    private var lightUpCard: some View {
        NavigationLink(value: LightUpRoute()) {
            HStack(spacing: 16) {
                ProvinceTileMap(insights: lightUp, showsLabels: false)
                    .allowsHitTesting(false)
                    .frame(width: 104)
                VStack(alignment: .leading, spacing: 4) {
                    Text("点亮地图").font(.headline)
                    Text("\(lightUp.provinces.count) 个省级行政区 · \(lightUp.countries.count) 个国家和地区")
                        .font(.subheadline).foregroundStyle(.secondary)
                }
                Spacer(minLength: 0)
                Image(systemName: "chevron.right").font(.caption.weight(.semibold)).foregroundStyle(.tertiary)
            }
            .padding(14)
            .background(.background.secondary, in: .rect(cornerRadius: 24, style: .continuous))
        }
        .buttonStyle(PressableStyle())
    }

    private var mapCard: some View {
        Button { showingMap = true } label: {
            WorldMap(stays: stays, interactive: false)
                .allowsHitTesting(false)
                .frame(height: 240)
                .clipShape(.rect(cornerRadius: 28, style: .continuous))
                .overlay(alignment: .bottomLeading) {
                    Label("全部足迹", systemImage: "arrow.up.left.and.arrow.down.right")
                        .font(.footnote.weight(.semibold))
                        .padding(.horizontal, 12)
                        .padding(.vertical, 8)
                        .glassEffect(.regular, in: .capsule)
                        .padding(12)
                }
        }
        .buttonStyle(PressableStyle())
        .matchedTransitionSource(id: "world", in: namespace)
    }

    private var countries: some View {
        VStack(alignment: .leading, spacing: 10) {
            SectionHeader(title: "国家和地区")
            VStack(spacing: 0) {
                ForEach(insights.countries) { country in
                    NavigationLink(value: country) {
                        HStack(spacing: 14) {
                            Text(country.flag).font(.system(size: 34))
                            VStack(alignment: .leading, spacing: 2) {
                                Text(country.name).font(.body.weight(.semibold))
                                Text("\(country.days.count) 天 · \(country.cities.count) 座城市")
                                    .font(.subheadline).foregroundStyle(.secondary)
                            }
                            Spacer()
                            Image(systemName: "chevron.right").font(.caption.weight(.semibold)).foregroundStyle(.tertiary)
                        }
                        .padding(.horizontal, 16)
                        .padding(.vertical, 10)
                        .contentShape(.rect)
                    }
                    .buttonStyle(.plain)
                    if country.id != insights.countries.last?.id { Divider().padding(.leading, 64) }
                }
            }
            .padding(.vertical, 6)
            .background(.background.secondary, in: .rect(cornerRadius: 24, style: .continuous))
        }
    }

    private var frequentPlaces: some View {
        VStack(alignment: .leading, spacing: 10) {
            HStack {
                SectionHeader(title: "常去的地方")
                NavigationLink("全部", value: PlacesList.frequent).font(.subheadline).padding(.top, 8).padding(.trailing, 4)
            }
            ScrollView(.horizontal) {
                HStack(spacing: 12) {
                    ForEach(insights.frequentPlaces) { place in
                        NavigationLink(value: PlaceVisits.around(place.representative, in: stays)) {
                            FrequentPlaceCard(place: place)
                        }
                        .buttonStyle(PressableStyle())
                    }
                }
                .scrollTargetLayout()
            }
            .scrollIndicators(.hidden)
            .scrollTargetBehavior(.viewAligned)
            .contentMargins(.horizontal, 0)
            Text("给常去的地方起个名字，比如“家”或“学校”，以后每次到访都会自动用上。")
                .font(.footnote).foregroundStyle(.secondary).padding(.horizontal, 4)
        }
    }

    private var landmarks: some View {
        VStack(alignment: .leading, spacing: 10) {
            HStack {
                SectionHeader(title: "去过的景点")
                NavigationLink("全部", value: PlacesList.landmarks).font(.subheadline).padding(.top, 8).padding(.trailing, 4)
            }
            VStack(spacing: 0) {
                ForEach(insights.landmarks.prefix(5)) { stay in
                    NavigationLink(value: PlaceVisits.around(stay, in: stays)) { PlaceRow(stay: stay) }
                        .buttonStyle(.plain)
                }
            }
            .padding(.vertical, 6)
            .background(.background.secondary, in: .rect(cornerRadius: 24, style: .continuous))
        }
    }
}

struct FrequentPlaceCard: View {
    let place: FrequentPlace

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            PlaceIcon(category: place.representative.category, isLandmark: false, size: 40)
            Spacer(minLength: 0)
            Text(place.representative.displayName)
                .font(.headline)
                .lineLimit(1)
            Text("\(place.visits) 次 · \(Format.duration(place.totalTime))")
                .font(.footnote)
                .foregroundStyle(.secondary)
        }
        .padding(14)
        .frame(width: 150, height: 140, alignment: .leading)
        .background(.background.secondary, in: .rect(cornerRadius: 22, style: .continuous))
    }
}

struct PlaceRow: View {
    let stay: Stay
    /// Within a day's list, show the time range instead of the date.
    var timeOnly = false

    var body: some View {
        HStack(spacing: 14) {
            PlaceIcon(category: stay.category, isLandmark: stay.isLandmark)
            VStack(alignment: .leading, spacing: 2) {
                Text(stay.displayName).font(.body.weight(.semibold)).lineLimit(1)
                Text([stay.city, timeOnly ? timeRange : stay.arrival.formatted(Date.FormatStyle(date: .abbreviated, time: .omitted, locale: appLocale))].compactMap { $0 }.joined(separator: " · "))
                    .font(.subheadline).foregroundStyle(.secondary)
            }
            Spacer()
            Image(systemName: "chevron.right").font(.caption.weight(.semibold)).foregroundStyle(.tertiary)
        }
        .padding(.horizontal, 16)
        .padding(.vertical, 10)
        .contentShape(.rect)
    }

    private var timeRange: String {
        let end = stay.departure.map(Format.time) ?? String(localized: "现在", bundle: .appLanguage)
        return "\(Format.time(stay.arrival)) – \(end)"
    }
}

/// One dot per place visited (merged when close together) and flags per country.
struct WorldMap: View {
    let stays: [Stay]
    var interactive = true
    var onSelect: ((Stay) -> Void)?

    @State private var position: MapCameraPosition = .automatic

    private var places: [Stay] {
        var seen = Set<String>()
        return stays.filter { stay in
            let key = "\((stay.latitude * 200).rounded())|\((stay.longitude * 200).rounded())"
            return seen.insert(key).inserted
        }
    }

    var body: some View {
        Map(position: $position, interactionModes: interactive ? .all : []) {
            ForEach(places) { stay in
                Annotation(stay.displayName, coordinate: stay.coordinate.onMap, anchor: .center) {
                    Button { onSelect?(stay) } label: {
                        Circle()
                            .fill((stay.isLandmark ? Color.yellow : Color.accentColor).gradient)
                            .frame(width: interactive ? 14 : 10, height: interactive ? 14 : 10)
                            .overlay(Circle().stroke(.white, lineWidth: 2))
                            .shadow(radius: 2)
                    }
                    .buttonStyle(.plain)
                    .disabled(onSelect == nil)
                }
                .annotationTitles(.hidden)
            }
        }
        .mapStyle(.standard(elevation: .realistic, emphasis: .muted, pointsOfInterest: .excludingAll))
    }
}

private struct WorldMapScreen: View {
    let stays: [Stay]
    @Environment(\.dismiss) private var dismiss
    @Environment(AppNavigator.self) private var navigator
    @State private var selected: Stay?

    var body: some View {
        NavigationStack {
            WorldMap(stays: stays, interactive: true, onSelect: { selected = $0 })
                .ignoresSafeArea()
                .navigationTitle("全部足迹")
                .navigationBarTitleDisplayMode(.inline)
                .toolbar {
                    ToolbarItem(placement: .cancellationAction) {
                        Button("关闭", systemImage: "xmark") { dismiss() }
                    }
                }
                .sheet(item: $selected) { StayDetailView(stay: $0) }
                .onChange(of: navigator.jumpCount) { dismiss() }
        }
    }
}

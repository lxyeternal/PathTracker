import SwiftUI
import MapKit
import Observation

/// Somewhere the person wants to go that isn't on either list of a hundred: found by name in
/// Apple Maps and kept as their own. It lights up like the others once a stay falls close by.
struct WishPlace: Codable, Identifiable, Hashable, Sendable {
    let id: String
    let name: String
    /// Where it is, as Apple Maps says it: "京都府 日本".
    let detail: String
    /// Map coordinates, as Apple Maps gave them.
    let latitude: Double
    let longitude: Double
    let kind: String
    let added: Date

    /// How close a stay must be to count as having been there, in kilometres.
    static let radius = 3.0

    var placeKind: MustSeePlace.Kind { MustSeePlace.Kind(rawValue: kind) ?? .city }
    var coordinate: CLLocationCoordinate2D { CLLocationCoordinate2D(latitude: latitude, longitude: longitude) }

    /// The same place as the blind box sees it.
    var place: BlindBox.Place {
        var place = BlindBox.Place(id: id, name: name, region: detail, latitude: latitude, longitude: longitude, kind: placeKind)
        place.radius = Self.radius
        return place
    }

    /// The nearest kind the lists know for what Apple Maps calls this place.
    static func kind(for category: MKPointOfInterestCategory?) -> MustSeePlace.Kind {
        switch category {
        case .beach?, .marina?: .water
        case .nationalPark?, .park?, .campground?, .zoo?, .aquarium?: .wild
        case .museum?, .castle?, .fortress?, .landmark?, .nationalMonument?, .planetarium?, .library?, .theater?: .heritage
        default: .city
        }
    }
}

/// The person's own places to go, kept on the device and carried between devices by iCloud.
@MainActor
@Observable
final class WishPlaces {
    static let shared = WishPlaces()
    private static let key = "wishPlaces"

    private(set) var all: [WishPlace] = []
    /// When each was first reached.
    private(set) var firstVisits: [String: Date] = [:]
    @ObservationIgnored private var computedFor = -1

    private init() {
        all = Self.decode(NSUbiquitousKeyValueStore.default.data(forKey: Self.key) ?? UserDefaults.standard.data(forKey: Self.key)) ?? []
        NotificationCenter.default.addObserver(forName: NSUbiquitousKeyValueStore.didChangeExternallyNotification,
                                               object: NSUbiquitousKeyValueStore.default, queue: .main) { note in
            let keys = note.userInfo?[NSUbiquitousKeyValueStoreChangedKeysKey] as? [String] ?? []
            guard keys.contains(Self.key) else { return }
            MainActor.assumeIsolated {
                let store = WishPlaces.shared
                if let synced = Self.decode(NSUbiquitousKeyValueStore.default.data(forKey: Self.key)), synced != store.all {
                    store.all = synced
                    store.computedFor = -1
                }
            }
        }
    }

    private static func decode(_ data: Data?) -> [WishPlace]? {
        data.flatMap { try? JSONDecoder().decode([WishPlace].self, from: $0) }
    }

    /// Not reached yet, newest first.
    var waiting: [WishPlace] { all.filter { firstVisits[$0.id] == nil }.sorted { $0.added > $1.added } }
    var reached: [WishPlace] { all.filter { firstVisits[$0.id] != nil }.sorted { (firstVisits[$0.id] ?? .distantPast) > (firstVisits[$1.id] ?? .distantPast) } }

    /// Adds a place from Apple Maps, unless it's already there. Returns false if it was.
    @discardableResult
    func add(_ item: MKMapItem) -> Bool {
        let coordinate = item.location.coordinate
        let id = String(format: "wish-%.4f-%.4f", coordinate.latitude, coordinate.longitude)
        guard !all.contains(where: { $0.id == id }) else { return false }
        let name = item.name ?? item.address?.shortAddress ?? String(localized: "想去的地方", bundle: .appLanguage)
        let detail = item.addressRepresentations?.cityWithContext ?? item.address?.shortAddress ?? ""
        all.append(WishPlace(id: id, name: name, detail: detail == name ? "" : detail, latitude: coordinate.latitude, longitude: coordinate.longitude,
                             kind: WishPlace.kind(for: item.pointOfInterestCategory).rawValue, added: .now))
        save()
        return true
    }

    func remove(_ place: WishPlace) {
        all.removeAll { $0.id == place.id }
        firstVisits[place.id] = nil
        save()
    }

    /// When all the data is deleted.
    func removeAll() {
        all = []
        firstVisits = [:]
        save()
    }

    /// Works out which places have been reached, once per change to the stays.
    func update(from stays: [Stay]) {
        let revision = PlaceSummaries.shared.revision
        guard revision != computedFor || firstVisits.keys.contains(where: { id in !all.contains { $0.id == id } }) else { return }
        computedFor = revision
        guard !all.isEmpty else { firstVisits = [:]; return }
        // A layover at an airport isn't a visit to the city around it.
        let visits = stays.filter { $0.category != .airport }.map { (coordinate: $0.coordinate.onMap, arrival: $0.arrival) }
        firstVisits = Self.firstVisits(all, visits: visits)
    }

    nonisolated static func firstVisits(_ places: [WishPlace], visits: [(coordinate: CLLocationCoordinate2D, arrival: Date)]) -> [String: Date] {
        var result: [String: Date] = [:]
        let span = WishPlace.radius / 111
        for place in places {
            let centre = CLLocation(latitude: place.latitude, longitude: place.longitude)
            for visit in visits where abs(visit.coordinate.latitude - place.latitude) <= span {
                guard result[place.id].map({ visit.arrival < $0 }) ?? true,
                      CLLocation(latitude: visit.coordinate.latitude, longitude: visit.coordinate.longitude).distance(from: centre) <= WishPlace.radius * 1000
                else { continue }
                result[place.id] = visit.arrival
            }
        }
        return result
    }

    private func save() {
        let data = try? JSONEncoder().encode(all)
        UserDefaults.standard.set(data, forKey: Self.key)
        NSUbiquitousKeyValueStore.default.set(data, forKey: Self.key)
    }
}

// MARK: - On the must-see page

/// The person's own places, above the two lists: what's waiting, what's been reached, and
/// the way to add another.
struct WishPlacesSection: View {
    /// Where the person was last, for how far each place is.
    let here: CLLocation?
    private var store = WishPlaces.shared
    private var summaries = PlaceSummaries.shared
    @State private var adding = false

    init(here: CLLocation?) { self.here = here }

    var body: some View {
        let places = store.waiting + store.reached
        VStack(alignment: .leading, spacing: 8) {
            HStack(alignment: .firstTextBaseline) {
                Text("我想去的地方").font(.title3.bold())
                Spacer()
                if !places.isEmpty {
                    Text(verbatim: "\(store.reached.count) / \(places.count)")
                        .font(.subheadline.weight(.semibold)).monospacedDigit().foregroundStyle(.secondary)
                }
            }
            .padding(.horizontal, 4)
            VStack(spacing: 0) {
                ForEach(places) { place in
                    row(place)
                    Divider().padding(.leading, 82)
                }
                Button { adding = true } label: {
                    HStack(spacing: 14) {
                        Image(systemName: "plus")
                            .font(.system(size: 18, weight: .semibold))
                            .foregroundStyle(.pink)
                            .frame(width: 54, height: 54)
                            .background(Color.pink.opacity(0.12), in: .rect(cornerRadius: 12, style: .continuous))
                        VStack(alignment: .leading, spacing: 2) {
                            Text("添加想去的地方").font(.body.weight(.medium)).foregroundStyle(.primary)
                            if places.isEmpty {
                                Text("清单之外的地方，也可以收进来").font(.caption).foregroundStyle(.secondary)
                            }
                        }
                        Spacer(minLength: 0)
                    }
                    .padding(.horizontal, 14).padding(.vertical, 10)
                    .contentShape(.rect)
                }
                .buttonStyle(.plain)
            }
            .background(.background.secondary, in: .rect(cornerRadius: 22, style: .continuous))
        }
        .animation(.smooth, value: store.all)
        .sheet(isPresented: $adding) { WishPlaceSearch() }
        .task(id: summaries.revision) { store.update(from: summaries.stays) }
        .onChange(of: store.all) { store.update(from: summaries.stays) }
    }

    private func row(_ place: WishPlace) -> some View {
        let date = store.firstVisits[place.id]
        return HStack(spacing: 14) {
            ZStack {
                RoundedRectangle(cornerRadius: 12, style: .continuous)
                    .fill(date != nil ? AnyShapeStyle(LinearGradient(colors: [Color(red: 1, green: 0.78, blue: 0.35), .orange], startPoint: .topLeading, endPoint: .bottomTrailing))
                                      : AnyShapeStyle(Color.pink.opacity(0.12)))
                Image(systemName: date != nil ? "checkmark" : "heart.fill")
                    .font(.system(size: 18, weight: .semibold))
                    .foregroundStyle(date != nil ? Color.white : Color.pink)
            }
            .frame(width: 54, height: 54)
            VStack(alignment: .leading, spacing: 2) {
                Text(verbatim: place.name).font(.body.weight(date != nil ? .semibold : .regular)).lineLimit(1)
                if let date {
                    Text("\(date.formatted(.dateTime.year().month().day().locale(appLocale))) · \(MustSeeView.ago(date))")
                        .font(.caption).foregroundStyle(.orange)
                } else {
                    Text(verbatim: subtitle(place)).font(.caption).foregroundStyle(.secondary).lineLimit(1)
                }
            }
            Spacer(minLength: 0)
            Menu {
                Button("在地图中打开", systemImage: "map") { openInMaps(place) }
                Button("移除", systemImage: "trash", role: .destructive) { withAnimation(.smooth) { store.remove(place) } }
            } label: {
                Image(systemName: "ellipsis")
                    .font(.body.weight(.semibold))
                    .foregroundStyle(.secondary)
                    .frame(width: 44, height: 44)
                    .contentShape(.rect)
            }
            .tint(.secondary)
            .accessibilityLabel("更多")
        }
        .padding(.leading, 14).padding(.trailing, 6).padding(.vertical, 10)
    }

    /// "日本京都 · 约 1,850 公里": where it is and how far from where the person was last.
    private func subtitle(_ place: WishPlace) -> String {
        var parts = place.detail.isEmpty ? [] : [place.detail]
        if let here {
            parts.append(String(localized: "约 \(Format.distance(here.distance(from: CLLocation(latitude: place.latitude, longitude: place.longitude))))", bundle: .appLanguage))
        }
        return parts.joined(separator: " · ")
    }

    private func openInMaps(_ place: WishPlace) {
        let item = MKMapItem(location: CLLocation(latitude: place.latitude, longitude: place.longitude), address: nil)
        item.name = place.name
        item.openInMaps()
    }
}

/// Finding a place by name, the way Apple Maps does as you type.
private struct WishPlaceSearch: View {
    @Environment(\.dismiss) private var dismiss
    @State private var query = ""
    @State private var completer = Completer()
    @State private var resolving: MKLocalSearchCompletion?
    @State private var failed = false

    var body: some View {
        NavigationStack {
            List {
                ForEach(completer.results, id: \.self) { result in
                    Button { pick(result) } label: {
                        HStack(spacing: 12) {
                            Image(systemName: "mappin.circle.fill").font(.title2).foregroundStyle(.pink)
                            VStack(alignment: .leading, spacing: 2) {
                                Text(verbatim: result.title).foregroundStyle(.primary)
                                if !result.subtitle.isEmpty {
                                    Text(verbatim: result.subtitle).font(.caption).foregroundStyle(.secondary).lineLimit(1)
                                }
                            }
                            Spacer(minLength: 0)
                            if resolving == result { ProgressView() }
                        }
                        .contentShape(.rect)
                    }
                    .buttonStyle(.plain)
                    .disabled(resolving != nil)
                }
            }
            .listStyle(.plain)
            .overlay {
                if query.trimmingCharacters(in: .whitespaces).isEmpty {
                    ContentUnavailableView("想去哪儿？", systemImage: "heart.circle",
                                           description: Text("输入城市、景点或任何地方的名字。到过之后，它会像清单上的地方一样被点亮。"))
                } else if completer.results.isEmpty, completer.isDone {
                    ContentUnavailableView.search(text: query)
                }
            }
            .searchable(text: $query, placement: .navigationBarDrawer(displayMode: .always), prompt: Text("城市、景点、地名"))
            .onChange(of: query) { _, text in completer.search(text) }
            .navigationTitle("添加想去的地方")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("关闭", systemImage: "xmark") { dismiss() }
                }
            }
            .alert("没能找到这个地方", isPresented: $failed) {
                Button("好") {}
            } message: {
                Text("检查一下网络，或者换个名字再试。")
            }
        }
    }

    private func pick(_ result: MKLocalSearchCompletion) {
        resolving = result
        Task {
            defer { resolving = nil }
            guard let item = try? await MKLocalSearch(request: MKLocalSearch.Request(completion: result)).start().mapItems.first else {
                failed = true
                return
            }
            WishPlaces.shared.add(item)
            UINotificationFeedbackGenerator().notificationOccurred(.success)
            dismiss()
        }
    }

    @MainActor
    @Observable
    final class Completer: NSObject, MKLocalSearchCompleterDelegate {
        private(set) var results: [MKLocalSearchCompletion] = []
        /// Whether the latest search has come back, so "no results" isn't said while still asking.
        private(set) var isDone = false
        @ObservationIgnored private let completer = MKLocalSearchCompleter()

        override init() {
            super.init()
            completer.delegate = self
            completer.resultTypes = [.address, .pointOfInterest]
        }

        func search(_ text: String) {
            let text = text.trimmingCharacters(in: .whitespaces)
            isDone = false
            if text.isEmpty {
                results = []
                completer.cancel()
            } else {
                completer.queryFragment = text
            }
        }

        nonisolated func completerDidUpdateResults(_ completer: MKLocalSearchCompleter) {
            MainActor.assumeIsolated {
                results = completer.results
                isDone = true
            }
        }

        nonisolated func completer(_ completer: MKLocalSearchCompleter, didFailWithError error: Error) {
            MainActor.assumeIsolated {
                results = []
                isDone = true
            }
        }
    }
}

import Foundation
import CoreLocation
import Observation

/// Firsts waiting to be celebrated in the app: a new country, province, city or sight, or a
/// milestone. They usually happen with the phone in a pocket, so they wait here (and in a
/// notification) until the next time the app is open, then play once.
@MainActor
@Observable
final class Celebrations {
    static let shared = Celebrations()

    struct Item: Codable, Identifiable, Equatable {
        enum Kind: String, Codable { case country, province, city, sight, milestone }

        let id: String
        let kind: Kind
        let title: String
        let subtitle: String
        var countryCode: String?
        var latitude: Double?
        var longitude: Double?
        var date = Date()

        var coordinate: CLLocationCoordinate2D? {
            guard let latitude, let longitude else { return nil }
            return CLLocationCoordinate2D(latitude: latitude, longitude: longitude)
        }

        /// The milestone this celebrates, from an id like "milestone.countries.10".
        var milestone: Milestone? {
            let parts = id.split(separator: ".")
            guard kind == .milestone, parts.count == 3, let kind = Milestone.Kind(rawValue: String(parts[1])),
                  let threshold = Int(parts[2]) else { return nil }
            return Milestone(kind: kind, threshold: threshold)
        }

        /// Sights are frequent, so they get a quiet banner rather than a ceremony.
        var isCeremony: Bool { kind != .sight }
    }

    private(set) var pending: [Item] = []
    private let key = "celebrations.pending"

    private init() {
        if let data = UserDefaults.standard.data(forKey: key),
           let items = try? JSONDecoder().decode([Item].self, from: data) {
            pending = items
        }
    }

    func add(_ item: Item) {
        guard !pending.contains(where: { $0.id == item.id }) else { return }
        pending.append(item)
        save()
    }

    func finish(_ item: Item) {
        pending.removeAll { $0.id == item.id }
        save()
    }

    /// Bigger news first: countries, provinces, milestones, then cities; sights last.
    var ceremonies: [Item] {
        let order: [Item.Kind] = [.country, .province, .milestone, .city]
        return pending.filter(\.isCeremony).sorted {
            (order.firstIndex(of: $0.kind) ?? 9, $0.date) < (order.firstIndex(of: $1.kind) ?? 9, $1.date)
        }
    }

    var nextSight: Item? { pending.first { $0.kind == .sight } }

    private func save() {
        // Old news isn't worth a ceremony: keep at most a dozen.
        if pending.count > 12 { pending.removeFirst(pending.count - 12) }
        UserDefaults.standard.set(try? JSONEncoder().encode(pending), forKey: key)
    }

    #if DEBUG
    /// One of each, for trying the ceremonies out.
    func addSamples() {
        let now = Date().timeIntervalSince1970
        add(Item(id: "sample.country.\(now)", kind: .country, title: String(localized: "欢迎来到\("日本") \(String.flag(for: "JP"))", bundle: .appLanguage),
                 subtitle: String(localized: "这是你去过的第 \(5) 个国家和地区。", bundle: .appLanguage),
                 countryCode: "JP", latitude: 35.68, longitude: 139.76))
        add(Item(id: "milestone.cities.25", kind: .milestone, title: Milestone(kind: .cities, threshold: 25).title,
                 subtitle: Milestone(kind: .cities, threshold: 25).kind.title))
        add(Item(id: "sample.city.\(now)", kind: .city, title: String(localized: "第一次来\("苏州")", bundle: .appLanguage),
                 subtitle: String(localized: "这是你去过的第 \(13) 座城市。", bundle: .appLanguage),
                 countryCode: "CN", latitude: 31.32, longitude: 120.62))
        add(Item(id: "sample.sight.\(now)", kind: .sight, title: "拙政园", subtitle: String(localized: "新景点", bundle: .appLanguage),
                 countryCode: "CN", latitude: 31.3253, longitude: 120.6283))
    }
    #endif
}

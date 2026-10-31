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
        enum Kind: String, Codable { case country, province, city, sight, milestone, reunion, special, set, postcard }

        let id: String
        let kind: Kind
        let title: String
        let subtitle: String
        var countryCode: String?
        var latitude: Double?
        var longitude: Double?
        var date = Date()
        /// A new country: where the border was crossed, and whether by air.
        var port: String?
        var byAir: Bool?
        /// A new city: its name as the stamp prints it.
        var city: String?
        /// A reunion: the last and the first time here, and how many visits now.
        var lastVisit: Date?
        var firstVisit: Date?
        var visits: Int?
        /// A special stamp: which one and what it prints; a set: its id; a postcard: the trip's id.
        var code: String?
        var value: String?

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

        /// The stamp a new country, province or city earns, as the ceremony presses it.
        var stamp: Stamp? {
            switch kind {
            case .country:
                return Stamp(id: "ceremony.\(id)", kind: .entry, date: date, countryCode: countryCode, port: port, byAir: byAir ?? false,
                             latitude: latitude ?? 0, longitude: longitude ?? 0)
            case .province:
                let provinceID = id.replacingOccurrences(of: "arrival.", with: "")
                return Stamp(id: "province.\(provinceID)", kind: .province, date: date, countryCode: countryCode, provinceID: provinceID,
                             latitude: latitude ?? 0, longitude: longitude ?? 0)
            case .city:
                guard let city else { return nil }
                return Stamp(id: "city.\(countryCode ?? "")|\(city)", kind: .city, date: date, countryCode: countryCode, city: city,
                             latitude: latitude ?? 0, longitude: longitude ?? 0)
            case .special:
                return Stamp(id: "special.\(code ?? "")", kind: .special, date: date, countryCode: countryCode, city: city,
                             latitude: latitude ?? 0, longitude: longitude ?? 0, code: code, value: value)
            case .set:
                return Stamp(id: "set.\(code ?? "")", kind: .set, date: date, countryCode: countryCode, city: city,
                             latitude: latitude ?? 0, longitude: longitude ?? 0, code: code)
            default:
                return nil
            }
        }
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

    /// Drops everything waiting, when all the data is deleted.
    func removeAll() {
        pending.removeAll()
        save()
    }

    func finish(_ item: Item) {
        pending.removeAll { $0.id == item.id }
        save()
    }

    /// Bigger news first: countries, provinces, milestones, then cities; sights last.
    var ceremonies: [Item] {
        let order: [Item.Kind] = [.postcard, .country, .set, .special, .province, .milestone, .city, .reunion]
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
                 countryCode: "JP", latitude: 35.55, longitude: 139.78, port: "羽田空港", byAir: true))
        add(Item(id: "arrival.zhejiang", kind: .province, title: String(localized: "第一次来\("浙江")", bundle: .appLanguage),
                 subtitle: String(localized: "盖上了第 \(6) 枚省份印。", bundle: .appLanguage),
                 countryCode: "CN", latitude: 30.27, longitude: 120.15))
        add(Item(id: "milestone.cities.25", kind: .milestone, title: Milestone(kind: .cities, threshold: 25).title,
                 subtitle: Milestone(kind: .cities, threshold: 25).kind.title))
        add(Item(id: "sample.city.\(now)", kind: .city, title: String(localized: "第一次来\("苏州")", bundle: .appLanguage),
                 subtitle: String(localized: "这是你去过的第 \(13) 座城市。", bundle: .appLanguage),
                 countryCode: "CN", latitude: 31.32, longitude: 120.62, city: "苏州"))
        add(Item(id: "sample.special.\(now)", kind: .special, title: String(localized: "你跨过了赤道", bundle: .appLanguage),
                 subtitle: String(localized: "从这里开始，季节反过来了。", bundle: .appLanguage), countryCode: "ID",
                 latitude: -0.5, longitude: 117.1, city: "Samarinda", code: "equator", value: "0°00′"))
        add(Item(id: "sample.set.\(now)", kind: .set, title: String(localized: "集齐了“\("関西")”", bundle: .appLanguage),
                 subtitle: "京都、大阪、奈良都去过了。", countryCode: "JP", latitude: 34.68, longitude: 135.8, city: "奈良", code: "kansai"))
        add(Item(id: "sample.reunion.\(now)", kind: .reunion, title: "西湖", subtitle: "杭州",
                 countryCode: "CN", latitude: 30.25, longitude: 120.14,
                 lastVisit: Date().addingTimeInterval(-932 * 86_400), firstVisit: Date().addingTimeInterval(-2100 * 86_400), visits: 4))
        add(Item(id: "sample.sight.\(now)", kind: .sight, title: "拙政园", subtitle: String(localized: "新景点", bundle: .appLanguage),
                 countryCode: "CN", latitude: 31.3253, longitude: 120.6283))
    }
    #endif
}

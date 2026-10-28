import Foundation
import os

/// China's 34 provincial-level divisions, laid out as a tile map: each sits roughly where it is
/// geographically, without drawing any borders.
struct Province: Identifiable, Hashable {
    let id: String
    let chineseName: String
    let englishName: String
    /// ISO 3166-2 code, the usual English short form ("GD").
    let code: String
    let row: Int
    let column: Int
    /// For Hong Kong, Macau and Taiwan, which geocoding reports as their own regions.
    var regionCode: String?

    var name: String { appLocale.language.languageCode == .chinese ? chineseName : englishName }

    static let columns = 8
    static let rows = 8

    static let all: [Province] = [
        Province(id: "heilongjiang", chineseName: "黑龙江", englishName: "Heilongjiang", code: "HL", row: 0, column: 7),
        Province(id: "neimenggu", chineseName: "内蒙古", englishName: "Inner Mongolia", code: "NM", row: 1, column: 4),
        Province(id: "beijing", chineseName: "北京", englishName: "Beijing", code: "BJ", row: 1, column: 5),
        Province(id: "liaoning", chineseName: "辽宁", englishName: "Liaoning", code: "LN", row: 1, column: 6),
        Province(id: "jilin", chineseName: "吉林", englishName: "Jilin", code: "JL", row: 1, column: 7),
        Province(id: "xinjiang", chineseName: "新疆", englishName: "Xinjiang", code: "XJ", row: 2, column: 0),
        Province(id: "ningxia", chineseName: "宁夏", englishName: "Ningxia", code: "NX", row: 2, column: 3),
        Province(id: "shanxi", chineseName: "山西", englishName: "Shanxi", code: "SX", row: 2, column: 4),
        Province(id: "hebei", chineseName: "河北", englishName: "Hebei", code: "HE", row: 2, column: 5),
        Province(id: "tianjin", chineseName: "天津", englishName: "Tianjin", code: "TJ", row: 2, column: 6),
        Province(id: "qinghai", chineseName: "青海", englishName: "Qinghai", code: "QH", row: 3, column: 1),
        Province(id: "gansu", chineseName: "甘肃", englishName: "Gansu", code: "GS", row: 3, column: 2),
        Province(id: "shaanxi", chineseName: "陕西", englishName: "Shaanxi", code: "SN", row: 3, column: 3),
        Province(id: "henan", chineseName: "河南", englishName: "Henan", code: "HA", row: 3, column: 4),
        Province(id: "shandong", chineseName: "山东", englishName: "Shandong", code: "SD", row: 3, column: 5),
        Province(id: "xizang", chineseName: "西藏", englishName: "Tibet", code: "XZ", row: 4, column: 0),
        Province(id: "sichuan", chineseName: "四川", englishName: "Sichuan", code: "SC", row: 4, column: 2),
        Province(id: "chongqing", chineseName: "重庆", englishName: "Chongqing", code: "CQ", row: 4, column: 3),
        Province(id: "hubei", chineseName: "湖北", englishName: "Hubei", code: "HB", row: 4, column: 4),
        Province(id: "anhui", chineseName: "安徽", englishName: "Anhui", code: "AH", row: 4, column: 5),
        Province(id: "jiangsu", chineseName: "江苏", englishName: "Jiangsu", code: "JS", row: 4, column: 6),
        Province(id: "shanghai", chineseName: "上海", englishName: "Shanghai", code: "SH", row: 4, column: 7),
        Province(id: "guizhou", chineseName: "贵州", englishName: "Guizhou", code: "GZ", row: 5, column: 2),
        Province(id: "hunan", chineseName: "湖南", englishName: "Hunan", code: "HN", row: 5, column: 3),
        Province(id: "jiangxi", chineseName: "江西", englishName: "Jiangxi", code: "JX", row: 5, column: 4),
        Province(id: "zhejiang", chineseName: "浙江", englishName: "Zhejiang", code: "ZJ", row: 5, column: 5),
        Province(id: "yunnan", chineseName: "云南", englishName: "Yunnan", code: "YN", row: 6, column: 1),
        Province(id: "guangxi", chineseName: "广西", englishName: "Guangxi", code: "GX", row: 6, column: 2),
        Province(id: "guangdong", chineseName: "广东", englishName: "Guangdong", code: "GD", row: 6, column: 3),
        Province(id: "fujian", chineseName: "福建", englishName: "Fujian", code: "FJ", row: 6, column: 4),
        Province(id: "taiwan", chineseName: "台湾", englishName: "Taiwan", code: "TW", row: 6, column: 6, regionCode: "TW"),
        Province(id: "hainan", chineseName: "海南", englishName: "Hainan", code: "HI", row: 7, column: 2),
        Province(id: "macau", chineseName: "澳门", englishName: "Macau", code: "MO", row: 7, column: 3, regionCode: "MO"),
        Province(id: "hongkong", chineseName: "香港", englishName: "Hong Kong", code: "HK", row: 7, column: 4, regionCode: "HK"),
    ]

    /// Which division a place is in, from what geocoding reported: the region code for Hong Kong,
    /// Macau and Taiwan; otherwise the province named in "杭州市, 浙江省" / "Hangzhou, Zhejiang"
    /// or, for the four municipalities, the city itself.
    /// Thousands of places share a few dozen names, so answers are remembered.
    private static let cache = OSAllocatedUnfairLock(initialState: [String: Province?]())

    static func containing(countryCode: String?, region: String?, city: String?) -> Province? {
        let key = "\(countryCode ?? "")|\(region ?? "")|\(city ?? "")"
        if let known = cache.withLock({ $0[key] }) { return known }
        let found = lookUp(countryCode: countryCode, region: region, city: city)
        cache.withLock { $0[key] = .some(found) }
        return found
    }

    private static func lookUp(countryCode: String?, region: String?, city: String?) -> Province? {
        if let code = countryCode, let special = all.first(where: { $0.regionCode == code }) { return special }
        guard countryCode == "CN" else { return nil }
        for text in [region, city].compactMap({ $0?.lowercased() }) {
            if let match = all.first(where: { $0.regionCode == nil && $0.matches(text) }) { return match }
        }
        return nil
    }

    private func matches(_ text: String) -> Bool {
        if text.contains(chineseName) { return true }
        // English parts are compared whole, so "Shanxi" never matches "Shaanxi".
        let parts = text.split(separator: ",").map { part -> String in
            var name = part.trimmingCharacters(in: .whitespaces)
            if let suffix = Self.englishSuffixes.first(where: { name.hasSuffix($0) }) { name.removeLast(suffix.count) }
            return name
        }
        return parts.contains { englishAliases.contains($0) }
    }

    private var englishAliases: [String] {
        switch id {
        case "xizang": ["tibet", "xizang"]
        case "neimenggu": ["inner mongolia", "nei mongol"]
        default: [englishName.lowercased()]
        }
    }

    private static let englishSuffixes = [" zhuang autonomous region", " hui autonomous region", " uyghur autonomous region",
                                          " uygur autonomous region", " autonomous region", " province", " municipality",
                                          " sheng", " shi", " city"]
}

/// The world's countries and regions grouped by continent, from the system's own region data.
struct Continent: Identifiable {
    let id: String
    let regions: [String]

    var name: String { appLocale.localizedString(forRegionCode: id) ?? id }

    /// Antarctica and islands nobody lives on, which no one counts as a place they could visit.
    private static let uninhabited: Set<String> = ["AQ", "BV", "HM", "TF", "UM", "GS", "IO", "CP", "DG", "EA", "IC", "TA", "AC", "CQ", "XK"]

    static let all: [Continent] = {
        var byContinent: [String: [String]] = [:]
        for region in Locale.Region.isoRegions {
            let code = region.identifier
            guard code.count == 2, code.allSatisfy(\.isLetter), !uninhabited.contains(code),
                  let continent = region.continent?.identifier else { continue }
            byContinent[continent, default: []].append(code)
        }
        return byContinent.map { Continent(id: $0.key, regions: $0.value.sorted()) }
    }()
}

/// What has been "lit up": provinces and countries visited, with when and how much.
struct LightUpInsights {
    struct Visit {
        var days: Set<Date> = []
        var cities: [String: Int] = [:]
        var firstVisit = Date.distantFuture

        var topCities: [String] { cities.sorted { $0.value > $1.value }.map(\.key) }
    }

    var provinces: [String: Visit] = [:]
    var countries: Set<String> = []

    init() {}

    init(stays: [Stay]) {
        let calendar = Calendar.current
        let cityNames = CityNames.canonical(for: stays)
        for stay in stays {
            guard let code = stay.countryCode else { continue }
            countries.insert(code)
            guard let province = Province.containing(countryCode: code, region: stay.region, city: stay.city) else { continue }
            var visit = provinces[province.id] ?? Visit()
            visit.days.formUnion(calendar.days(in: DateInterval(start: stay.arrival, end: max(stay.departure ?? Date(), stay.arrival))))
            if let key = CityNames.key(stay), let city = cityNames[key] { visit.cities[city, default: 0] += 1 }
            visit.firstVisit = min(visit.firstVisit, stay.arrival)
            provinces[province.id] = visit
        }
    }

    var continentsVisited: Int {
        Continent.all.filter { !Set($0.regions).isDisjoint(with: countries) }.count
    }
}

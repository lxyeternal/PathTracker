import SwiftUI
import CoreLocation
import os

/// The inks stamps are pressed in. Fixed colours, not adaptive: a stamp is ink on paper, and
/// the paper stays paper-coloured in dark mode too.
enum Ink: Int, CaseIterable {
    case navy, crimson, forest, plum, teal, umber, slate, cinnabar

    var color: Color {
        switch self {
        case .navy: Color(red: 0.16, green: 0.30, blue: 0.62)
        case .crimson: Color(red: 0.70, green: 0.17, blue: 0.20)
        case .forest: Color(red: 0.20, green: 0.45, blue: 0.29)
        case .plum: Color(red: 0.42, green: 0.27, blue: 0.58)
        case .teal: Color(red: 0.08, green: 0.43, blue: 0.50)
        case .umber: Color(red: 0.58, green: 0.32, blue: 0.16)
        case .slate: Color(red: 0.22, green: 0.25, blue: 0.30)
        case .cinnabar: Color(red: 0.78, green: 0.20, blue: 0.14)
        }
    }

    /// Cinnabar is kept for provinces.
    static let everyday: [Ink] = [.navy, .crimson, .forest, .plum, .teal, .umber, .slate]
}

enum StampShape: Int, CaseIterable {
    case rectangle, rounded, circle, oval, octagon, hexagon, ticket, scalloped
}

/// How a country's border stamps look: the name in its own language, an ink and a shape.
struct CountryStampStyle {
    let native: String
    let ink: Ink
    let shape: StampShape

    static func of(_ code: String) -> CountryStampStyle {
        let seed = StampSeed.of(code)
        let fallbackShapes: [StampShape] = [.rectangle, .rounded, .circle, .oval, .octagon, .hexagon, .ticket]
        let english = Locale(identifier: "en").localizedString(forRegionCode: code)?.uppercased() ?? code
        if let curated = curated[code] {
            return CountryStampStyle(native: curated.0, ink: curated.1, shape: curated.2)
        }
        return CountryStampStyle(native: english, ink: Ink.everyday[Int(seed % UInt64(Ink.everyday.count))],
                                 shape: fallbackShapes[Int((seed >> 8) % UInt64(fallbackShapes.count))])
    }

    /// Names as they'd be printed at the border. Anything not listed uses its English name.
    private static let curated: [String: (String, Ink, StampShape)] = [
        "CN": ("中国", .crimson, .rectangle), "HK": ("香港", .crimson, .octagon), "MO": ("澳門", .forest, .octagon),
        "TW": ("台灣", .navy, .rounded), "JP": ("日本国", .crimson, .circle), "KR": ("대한민국", .navy, .rounded),
        "KP": ("조선", .crimson, .rectangle), "MN": ("МОНГОЛ УЛС", .navy, .hexagon), "SG": ("SINGAPORE", .crimson, .rectangle),
        "MY": ("MALAYSIA", .navy, .oval), "TH": ("ประเทศไทย", .plum, .rounded), "VN": ("VIỆT NAM", .crimson, .circle),
        "ID": ("INDONESIA", .forest, .ticket), "PH": ("PILIPINAS", .navy, .oval), "KH": ("កម្ពុជា", .umber, .octagon),
        "LA": ("ລາວ", .teal, .rounded), "MM": ("မြန်မာ", .forest, .circle), "BN": ("BRUNEI", .umber, .hexagon),
        "IN": ("भारत", .navy, .oval), "NP": ("नेपाल", .crimson, .hexagon), "LK": ("ශ්‍රී ලංකාව", .umber, .ticket),
        "BT": ("BHUTAN", .umber, .circle), "MV": ("MALDIVES", .teal, .oval), "PK": ("PAKISTAN", .forest, .rectangle),
        "AE": ("الإمارات", .forest, .rounded), "QA": ("قطر", .plum, .oval), "SA": ("السعودية", .forest, .rectangle),
        "JO": ("الأردن", .crimson, .octagon), "IL": ("ישראל", .navy, .rectangle), "TR": ("TÜRKİYE", .crimson, .circle),
        "EG": ("مصر", .umber, .hexagon), "MA": ("المغرب · MAROC", .crimson, .octagon), "IR": ("ایران", .forest, .rounded),
        "KZ": ("ҚАЗАҚСТАН", .teal, .oval), "UZ": ("OʻZBEKISTON", .teal, .hexagon), "GE": ("საქართველო", .crimson, .rounded),
        "RU": ("РОССИЯ", .navy, .rectangle), "UA": ("УКРАЇНА", .navy, .rounded), "GR": ("ΕΛΛΑΔΑ", .navy, .circle),
        "BG": ("БЪЛГАРИЯ", .forest, .rectangle), "RS": ("СРБИЈА", .crimson, .oval),
        "GB": ("UNITED KINGDOM", .slate, .rectangle), "IE": ("ÉIRE · IRELAND", .forest, .oval), "FR": ("FRANCE", .navy, .rounded),
        "DE": ("DEUTSCHLAND", .slate, .rectangle), "IT": ("ITALIA", .forest, .oval), "ES": ("ESPAÑA", .crimson, .rounded),
        "PT": ("PORTUGAL", .forest, .circle), "NL": ("NEDERLAND", .umber, .rectangle), "BE": ("BELGIË · BELGIQUE", .slate, .octagon),
        "LU": ("LËTZEBUERG", .teal, .hexagon), "CH": ("SCHWEIZ · SUISSE", .crimson, .rectangle), "AT": ("ÖSTERREICH", .crimson, .oval),
        "CZ": ("ČESKO", .navy, .ticket), "PL": ("POLSKA", .crimson, .rounded), "HU": ("MAGYARORSZÁG", .forest, .hexagon),
        "SK": ("SLOVENSKO", .navy, .oval), "SI": ("SLOVENIJA", .teal, .rounded), "HR": ("HRVATSKA", .navy, .circle),
        "RO": ("ROMÂNIA", .umber, .rectangle), "DK": ("DANMARK", .crimson, .rectangle), "SE": ("SVERIGE", .navy, .circle),
        "NO": ("NORGE", .crimson, .oval), "FI": ("SUOMI", .navy, .rounded), "IS": ("ÍSLAND", .teal, .hexagon),
        "EE": ("EESTI", .navy, .ticket), "LV": ("LATVIJA", .crimson, .rounded), "LT": ("LIETUVA", .forest, .oval),
        "MC": ("MONACO", .crimson, .circle), "VA": ("CITTÀ DEL VATICANO", .umber, .circle), "MT": ("MALTA", .crimson, .octagon),
        "US": ("UNITED STATES", .navy, .rounded), "CA": ("CANADA", .crimson, .rectangle), "MX": ("MÉXICO", .forest, .circle),
        "CU": ("CUBA", .navy, .oval), "BR": ("BRASIL", .forest, .rounded), "AR": ("ARGENTINA", .navy, .oval),
        "CL": ("CHILE", .crimson, .rectangle), "PE": ("PERÚ", .crimson, .hexagon), "CO": ("COLOMBIA", .umber, .rounded),
        "AU": ("AUSTRALIA", .navy, .rectangle), "NZ": ("AOTEAROA · NEW ZEALAND", .slate, .oval), "FJ": ("FIJI", .teal, .circle),
        "ZA": ("SOUTH AFRICA", .forest, .rounded), "KE": ("KENYA", .crimson, .hexagon), "TZ": ("TANZANIA", .forest, .oval),
        "MU": ("MAURICE", .teal, .rounded), "SC": ("SEYCHELLES", .teal, .octagon), "ET": ("ኢትዮጵያ", .forest, .circle),
    ]
}

/// China's provinces by their one-character name, the way they're carved on seals.
enum ProvinceSeal {
    static func character(for id: String) -> String {
        switch id {
        case "beijing": "京"; case "tianjin": "津"; case "hebei": "冀"; case "shanxi": "晋"; case "neimenggu": "蒙"
        case "liaoning": "辽"; case "jilin": "吉"; case "heilongjiang": "黑"; case "shanghai": "沪"; case "jiangsu": "苏"
        case "zhejiang": "浙"; case "anhui": "皖"; case "fujian": "闽"; case "jiangxi": "赣"; case "shandong": "鲁"
        case "henan": "豫"; case "hubei": "鄂"; case "hunan": "湘"; case "guangdong": "粤"; case "guangxi": "桂"
        case "hainan": "琼"; case "chongqing": "渝"; case "sichuan": "蜀"; case "guizhou": "黔"; case "yunnan": "滇"
        case "xizang": "藏"; case "shaanxi": "秦"; case "gansu": "陇"; case "qinghai": "青"; case "ningxia": "宁"
        case "xinjiang": "新"; case "hongkong": "港"; case "macau": "澳"; case "taiwan": "台"
        default: "印"
        }
    }

    /// Alternating carvings, like a page of seals: white characters cut into red, or red
    /// characters standing out of the stone.
    static func isCarved(_ id: String) -> Bool {
        (Province.all.firstIndex { $0.id == id } ?? 0) % 3 != 1
    }
}

/// Cities with a stamp of their own: the local name, a nickname or line people know it by,
/// and a motif. Every other city gets a stamp made from its name.
struct CityStampStyle {
    let title: String
    let motto: String?
    let symbol: String
    let ink: Ink
    let shape: StampShape

    struct Entry {
        let country: String
        let names: [String]
        let latitude: Double
        let longitude: Double
        let title: String
        let motto: String?
        let symbol: String
        let ink: Ink
        let shape: StampShape
        /// The city's name as the app shows it, in Chinese and in English.
        var zh: String
        var en: String

        var localizedName: String { appLocale.language.languageCode == .chinese ? zh : en }
    }

    static func of(city: String, countryCode: String?, coordinate: CLLocationCoordinate2D) -> CityStampStyle {
        if let entry = match(city: city, countryCode: countryCode, coordinate: coordinate) {
            return CityStampStyle(title: entry.title, motto: entry.motto, symbol: entry.symbol, ink: entry.ink, shape: entry.shape)
        }
        let seed = StampSeed.of("\(countryCode ?? "")|\(city)")
        let shapes: [StampShape] = [.circle, .scalloped, .octagon, .rounded, .hexagon]
        let symbols = ["building.2.fill", "house.fill", "tree.fill", "signpost.right.fill", "map.fill", "leaf.fill"]
        return CityStampStyle(title: city, motto: nil, symbol: symbols[Int((seed >> 4) % UInt64(symbols.count))],
                              ink: Ink.everyday[Int(seed % UInt64(Ink.everyday.count))],
                              shape: shapes[Int((seed >> 12) % UInt64(shapes.count))])
    }

    /// A city's stamp is drawn often and its name never changes: matched once.
    private static let matches = OSAllocatedUnfairLock(initialState: [String: Entry?]())

    static func match(city: String, countryCode: String?, coordinate: CLLocationCoordinate2D) -> Entry? {
        let key = "\(countryCode ?? "")|\(city)"
        if let known = matches.withLock({ $0[key] }) { return known }
        let found = lookUp(city: city, countryCode: countryCode, coordinate: coordinate)
        matches.withLock { $0[key] = .some(found) }
        return found
    }

    private static func lookUp(city: String, countryCode: String?, coordinate: CLLocationCoordinate2D) -> Entry? {
        let name = normalize(city)
        let here = CLLocation(latitude: coordinate.latitude, longitude: coordinate.longitude)
        let candidates = catalog.filter { countryCode == nil || $0.country == countryCode }
        if let byName = candidates.first(where: { $0.names.contains { normalize($0) == name } }) { return byName }
        // Geocoders name the same city many ways ("Kuta", "Denpasar"); close enough counts.
        return candidates
            .map { ($0, CLLocation(latitude: $0.latitude, longitude: $0.longitude).distance(from: here)) }
            .filter { $0.1 < 30_000 }
            .min { $0.1 < $1.1 }?.0
    }

    private static func normalize(_ name: String) -> String {
        var text = name.lowercased().folding(options: [.diacriticInsensitive], locale: nil)
        for suffix in ["市", " city", "-shi", " shi"] where text.hasSuffix(suffix) { text.removeLast(suffix.count) }
        return text.trimmingCharacters(in: .whitespaces)
    }

    private static func e(_ country: String, _ names: [String], _ lat: Double, _ lon: Double, _ title: String, _ motto: String?,
                          _ symbol: String, _ ink: Ink, _ shape: StampShape, zh: String, en: String) -> Entry {
        Entry(country: country, names: names, latitude: lat, longitude: lon, title: title, motto: motto, symbol: symbol, ink: ink, shape: shape,
              zh: zh, en: en)
    }

    /// A city's name under its stamp: the stamp itself is printed the way the place writes its
    /// name (東京, PARIS), the label follows the app's language (东京 / Tokyo).
    static func displayName(_ stamp: Stamp) -> String {
        guard let city = stamp.city else { return "" }
        return match(city: city, countryCode: stamp.countryCode, coordinate: stamp.coordinate)?.localizedName ?? city
    }

    static let catalog: [Entry] = [
        // China
        e("CN", ["北京", "Beijing"], 39.904, 116.407, "北京", "京华", "building.columns.fill", .crimson, .circle, zh: "北京", en: "Beijing"),
        e("CN", ["上海", "Shanghai"], 31.230, 121.474, "上海", "申城", "building.2.fill", .navy, .scalloped, zh: "上海", en: "Shanghai"),
        e("CN", ["天津", "Tianjin"], 39.125, 117.190, "天津", "津门", "ferry.fill", .teal, .octagon, zh: "天津", en: "Tianjin"),
        e("CN", ["重庆", "Chongqing"], 29.563, 106.551, "重庆", "山城", "cablecar.fill", .umber, .hexagon, zh: "重庆", en: "Chongqing"),
        e("CN", ["广州", "Guangzhou"], 23.129, 113.264, "广州", "羊城", "building.2.fill", .forest, .circle, zh: "广州", en: "Guangzhou"),
        e("CN", ["深圳", "Shenzhen"], 22.543, 114.058, "深圳", "鹏城", "bird.fill", .teal, .rounded, zh: "深圳", en: "Shenzhen"),
        e("CN", ["杭州", "Hangzhou"], 30.274, 120.155, "杭州", "西子湖畔", "water.waves", .teal, .circle, zh: "杭州", en: "Hangzhou"),
        e("CN", ["南京", "Nanjing"], 32.060, 118.797, "南京", "金陵", "building.columns.fill", .plum, .octagon, zh: "南京", en: "Nanjing"),
        e("CN", ["苏州", "Suzhou"], 31.299, 120.585, "苏州", "姑苏", "leaf.fill", .forest, .scalloped, zh: "苏州", en: "Suzhou"),
        e("CN", ["成都", "Chengdu"], 30.573, 104.066, "成都", "天府之国", "pawprint.fill", .forest, .circle, zh: "成都", en: "Chengdu"),
        e("CN", ["西安", "Xi'an", "Xian"], 34.342, 108.940, "西安", "长安", "building.columns.fill", .umber, .rectangle, zh: "西安", en: "Xi'an"),
        e("CN", ["武汉", "Wuhan"], 30.593, 114.305, "武汉", "江城", "water.waves", .navy, .rounded, zh: "武汉", en: "Wuhan"),
        e("CN", ["长沙", "Changsha"], 28.228, 112.939, "长沙", "星城", "sparkles", .crimson, .hexagon, zh: "长沙", en: "Changsha"),
        e("CN", ["厦门", "Xiamen"], 24.480, 118.089, "厦门", "鹭岛", "bird.fill", .teal, .oval, zh: "厦门", en: "Xiamen"),
        e("CN", ["青岛", "Qingdao"], 36.067, 120.383, "青岛", "琴岛", "sailboat.fill", .navy, .circle, zh: "青岛", en: "Qingdao"),
        e("CN", ["大连", "Dalian"], 38.914, 121.615, "大连", "滨城", "sailboat.fill", .teal, .rounded, zh: "大连", en: "Dalian"),
        e("CN", ["哈尔滨", "Harbin"], 45.803, 126.535, "哈尔滨", "冰城", "snowflake", .navy, .octagon, zh: "哈尔滨", en: "Harbin"),
        e("CN", ["沈阳", "Shenyang"], 41.806, 123.432, "沈阳", "盛京", "crown.fill", .umber, .circle, zh: "沈阳", en: "Shenyang"),
        e("CN", ["长春", "Changchun"], 43.817, 125.324, "长春", "北国春城", "leaf.fill", .forest, .rounded, zh: "长春", en: "Changchun"),
        e("CN", ["昆明", "Kunming"], 25.038, 102.718, "昆明", "春城", "camera.macro", .crimson, .scalloped, zh: "昆明", en: "Kunming"),
        e("CN", ["丽江", "Lijiang"], 26.872, 100.227, "丽江", "古城", "mountain.2.fill", .umber, .hexagon, zh: "丽江", en: "Lijiang"),
        e("CN", ["大理", "Dali"], 25.606, 100.268, "大理", "风花雪月", "wind", .navy, .circle, zh: "大理", en: "Dali"),
        e("CN", ["西双版纳", "景洪", "Jinghong", "Xishuangbanna"], 22.008, 100.797, "西双版纳", "彩云之南", "tree.fill", .forest, .oval, zh: "西双版纳", en: "Xishuangbanna"),
        e("CN", ["拉萨", "Lhasa"], 29.652, 91.172, "拉萨", "日光城", "sun.max.fill", .crimson, .octagon, zh: "拉萨", en: "Lhasa"),
        e("CN", ["桂林", "Guilin"], 25.274, 110.290, "桂林", "山水甲天下", "mountain.2.fill", .forest, .rounded, zh: "桂林", en: "Guilin"),
        e("CN", ["南宁", "Nanning"], 22.817, 108.366, "南宁", "绿城", "tree.fill", .forest, .circle, zh: "南宁", en: "Nanning"),
        e("CN", ["三亚", "Sanya"], 18.253, 109.512, "三亚", "鹿城", "beach.umbrella.fill", .teal, .scalloped, zh: "三亚", en: "Sanya"),
        e("CN", ["海口", "Haikou"], 20.044, 110.199, "海口", "椰城", "sun.max.fill", .teal, .rounded, zh: "海口", en: "Haikou"),
        e("CN", ["福州", "Fuzhou"], 26.074, 119.297, "福州", "榕城", "tree.fill", .forest, .hexagon, zh: "福州", en: "Fuzhou"),
        e("CN", ["泉州", "Quanzhou"], 24.874, 118.676, "泉州", "刺桐城", "sailboat.fill", .crimson, .circle, zh: "泉州", en: "Quanzhou"),
        e("CN", ["济南", "Jinan"], 36.651, 117.120, "济南", "泉城", "drop.fill", .teal, .circle, zh: "济南", en: "Jinan"),
        e("CN", ["郑州", "Zhengzhou"], 34.747, 113.625, "郑州", "商都", "train.side.front.car", .umber, .rectangle, zh: "郑州", en: "Zhengzhou"),
        e("CN", ["洛阳", "Luoyang"], 34.620, 112.454, "洛阳", "神都", "camera.macro", .plum, .octagon, zh: "洛阳", en: "Luoyang"),
        e("CN", ["开封", "Kaifeng"], 34.797, 114.308, "开封", "汴京", "building.columns.fill", .umber, .hexagon, zh: "开封", en: "Kaifeng"),
        e("CN", ["合肥", "Hefei"], 31.821, 117.227, "合肥", "庐州", "book.fill", .navy, .rounded, zh: "合肥", en: "Hefei"),
        e("CN", ["黄山", "Huangshan"], 29.715, 118.338, "黄山", "徽州", "mountain.2.fill", .slate, .octagon, zh: "黄山", en: "Huangshan"),
        e("CN", ["南昌", "Nanchang"], 28.682, 115.858, "南昌", "洪城", "flag.fill", .crimson, .circle, zh: "南昌", en: "Nanchang"),
        e("CN", ["景德镇", "Jingdezhen"], 29.269, 117.178, "景德镇", "瓷都", "cup.and.saucer.fill", .navy, .scalloped, zh: "景德镇", en: "Jingdezhen"),
        e("CN", ["贵阳", "Guiyang"], 26.647, 106.630, "贵阳", "林城", "tree.fill", .forest, .rounded, zh: "贵阳", en: "Guiyang"),
        e("CN", ["石家庄", "Shijiazhuang"], 38.042, 114.515, "石家庄", "石门", "train.side.front.car", .slate, .rectangle, zh: "石家庄", en: "Shijiazhuang"),
        e("CN", ["太原", "Taiyuan"], 37.871, 112.549, "太原", "龙城", "flame.fill", .umber, .circle, zh: "太原", en: "Taiyuan"),
        e("CN", ["大同", "Datong"], 40.077, 113.300, "大同", "云冈", "building.columns.fill", .slate, .hexagon, zh: "大同", en: "Datong"),
        e("CN", ["呼和浩特", "Hohhot"], 40.842, 111.749, "呼和浩特", "青城", "wind", .teal, .oval, zh: "呼和浩特", en: "Hohhot"),
        e("CN", ["兰州", "Lanzhou"], 36.061, 103.834, "兰州", "金城", "water.waves", .umber, .rounded, zh: "兰州", en: "Lanzhou"),
        e("CN", ["敦煌", "Dunhuang"], 40.142, 94.662, "敦煌", "沙州", "sun.dust.fill", .umber, .octagon, zh: "敦煌", en: "Dunhuang"),
        e("CN", ["西宁", "Xining"], 36.617, 101.778, "西宁", "夏都", "mountain.2.fill", .navy, .circle, zh: "西宁", en: "Xining"),
        e("CN", ["银川", "Yinchuan"], 38.487, 106.231, "银川", "凤城", "bird.fill", .umber, .hexagon, zh: "银川", en: "Yinchuan"),
        e("CN", ["乌鲁木齐", "Urumqi", "Ürümqi"], 43.825, 87.617, "乌鲁木齐", "亚心之都", "mountain.2.fill", .teal, .rounded, zh: "乌鲁木齐", en: "Urumqi"),
        e("CN", ["宁波", "Ningbo"], 29.868, 121.544, "宁波", "甬城", "ferry.fill", .navy, .octagon, zh: "宁波", en: "Ningbo"),
        e("CN", ["绍兴", "Shaoxing"], 29.997, 120.582, "绍兴", "水乡", "sailboat.fill", .slate, .scalloped, zh: "绍兴", en: "Shaoxing"),
        e("CN", ["嘉兴", "Jiaxing"], 30.746, 120.756, "嘉兴", "禾城", "sailboat.fill", .crimson, .circle, zh: "嘉兴", en: "Jiaxing"),
        e("CN", ["扬州", "Yangzhou"], 32.394, 119.413, "扬州", "广陵", "moon.stars.fill", .plum, .rounded, zh: "扬州", en: "Yangzhou"),
        e("CN", ["无锡", "Wuxi"], 31.491, 120.312, "无锡", "太湖明珠", "water.waves", .teal, .hexagon, zh: "无锡", en: "Wuxi"),
        e("CN", ["珠海", "Zhuhai"], 22.271, 113.577, "珠海", "百岛之市", "sailboat.fill", .teal, .circle, zh: "珠海", en: "Zhuhai"),
        e("CN", ["张家界", "Zhangjiajie"], 29.117, 110.479, "张家界", "武陵源", "mountain.2.fill", .forest, .octagon, zh: "张家界", en: "Zhangjiajie"),
        e("CN", ["秦皇岛", "Qinhuangdao"], 39.935, 119.600, "秦皇岛", "港城", "water.waves", .navy, .rounded, zh: "秦皇岛", en: "Qinhuangdao"),
        e("CN", ["烟台", "Yantai"], 37.464, 121.448, "烟台", "仙境", "cloud.fill", .teal, .circle, zh: "烟台", en: "Yantai"),
        e("CN", ["威海", "Weihai"], 37.513, 122.120, "威海", "海滨", "sailboat.fill", .navy, .scalloped, zh: "威海", en: "Weihai"),
        e("HK", ["香港", "Hong Kong"], 22.320, 114.170, "香港", "東方之珠", "sailboat.fill", .crimson, .circle, zh: "香港", en: "Hong Kong"),
        e("MO", ["澳门", "澳門", "Macau", "Macao"], 22.199, 113.544, "澳門", "濠江", "dice.fill", .forest, .octagon, zh: "澳门", en: "Macau"),
        e("TW", ["台北", "臺北", "Taipei"], 25.033, 121.565, "臺北", nil, "building.2.fill", .navy, .rounded, zh: "台北", en: "Taipei"),
        // Asia
        e("JP", ["東京", "东京", "Tokyo"], 35.681, 139.767, "東京", "TOKYO", "tram.fill", .crimson, .circle, zh: "东京", en: "Tokyo"),
        e("JP", ["京都", "Kyoto"], 35.012, 135.768, "京都", "古都", "building.columns.fill", .umber, .octagon, zh: "京都", en: "Kyoto"),
        e("JP", ["大阪", "Osaka"], 34.694, 135.502, "大阪", "天下の台所", "fork.knife", .navy, .scalloped, zh: "大阪", en: "Osaka"),
        e("JP", ["奈良", "Nara"], 34.685, 135.805, "奈良", "平城京", "pawprint.fill", .forest, .circle, zh: "奈良", en: "Nara"),
        e("JP", ["札幌", "Sapporo"], 43.062, 141.354, "札幌", "SAPPORO", "snowflake", .navy, .hexagon, zh: "札幌", en: "Sapporo"),
        e("JP", ["横浜", "横滨", "Yokohama"], 35.444, 139.638, "横浜", "YOKOHAMA", "ferry.fill", .teal, .rounded, zh: "横滨", en: "Yokohama"),
        e("JP", ["福岡", "福冈", "Fukuoka"], 33.590, 130.402, "福岡", "博多", "fork.knife", .crimson, .rounded, zh: "福冈", en: "Fukuoka"),
        e("JP", ["那覇", "那霸", "Naha"], 26.212, 127.681, "那覇", "琉球", "sun.max.fill", .teal, .circle, zh: "那霸", en: "Naha"),
        e("JP", ["箱根", "Hakone"], 35.232, 139.107, "箱根", "温泉", "mountain.2.fill", .plum, .octagon, zh: "箱根", en: "Hakone"),
        e("KR", ["서울", "首尔", "Seoul"], 37.566, 126.978, "서울", "SEOUL", "building.2.fill", .navy, .rounded, zh: "首尔", en: "Seoul"),
        e("KR", ["부산", "釜山", "Busan"], 35.180, 129.075, "부산", "BUSAN", "water.waves", .teal, .circle, zh: "釜山", en: "Busan"),
        e("KR", ["제주", "济州", "Jeju"], 33.499, 126.531, "제주", "탐라", "leaf.fill", .forest, .scalloped, zh: "济州", en: "Jeju"),
        e("SG", ["Singapore", "新加坡"], 1.290, 103.852, "SINGAPORE", "LION CITY", "building.2.fill", .crimson, .scalloped, zh: "新加坡", en: "Singapore"),
        e("MY", ["Kuala Lumpur", "吉隆坡"], 3.139, 101.687, "KUALA LUMPUR", nil, "building.2.fill", .navy, .rounded, zh: "吉隆坡", en: "Kuala Lumpur"),
        e("MY", ["George Town", "Penang", "槟城", "乔治市"], 5.414, 100.329, "PENANG", "PEARL OF THE ORIENT", "fork.knife", .teal, .circle, zh: "槟城", en: "Penang"),
        e("TH", ["Bangkok", "曼谷", "กรุงเทพมหานคร"], 13.756, 100.502, "กรุงเทพฯ", "BANGKOK", "building.columns.fill", .plum, .octagon, zh: "曼谷", en: "Bangkok"),
        e("TH", ["Chiang Mai", "清迈"], 18.788, 98.985, "เชียงใหม่", "CHIANG MAI", "leaf.fill", .forest, .circle, zh: "清迈", en: "Chiang Mai"),
        e("TH", ["Phuket", "普吉"], 7.880, 98.392, "ภูเก็ต", "PHUKET", "beach.umbrella.fill", .teal, .scalloped, zh: "普吉岛", en: "Phuket"),
        e("VN", ["Hanoi", "Hà Nội", "河内"], 21.028, 105.854, "HÀ NỘI", "THĂNG LONG", "building.columns.fill", .crimson, .rounded, zh: "河内", en: "Hanoi"),
        e("VN", ["Ho Chi Minh City", "Thành phố Hồ Chí Minh", "胡志明市"], 10.776, 106.701, "SÀI GÒN", nil, "bicycle", .navy, .circle, zh: "胡志明市", en: "Ho Chi Minh City"),
        e("VN", ["Da Nang", "Đà Nẵng", "岘港"], 16.054, 108.202, "ĐÀ NẴNG", nil, "beach.umbrella.fill", .teal, .hexagon, zh: "岘港", en: "Da Nang"),
        e("ID", ["Denpasar", "Bali", "巴厘岛", "Kuta", "Ubud"], -8.650, 115.216, "BALI", "PULAU DEWATA", "sun.horizon.fill", .forest, .scalloped, zh: "巴厘岛", en: "Bali"),
        e("ID", ["Jakarta", "雅加达"], -6.208, 106.846, "JAKARTA", nil, "building.2.fill", .crimson, .rounded, zh: "雅加达", en: "Jakarta"),
        e("PH", ["Manila", "马尼拉"], 14.599, 120.984, "MAYNILA", nil, "sailboat.fill", .navy, .circle, zh: "马尼拉", en: "Manila"),
        e("KH", ["Siem Reap", "暹粒"], 13.362, 103.860, "សៀមរាប", "ANGKOR", "building.columns.fill", .umber, .octagon, zh: "暹粒", en: "Siem Reap"),
        e("IN", ["New Delhi", "Delhi", "新德里"], 28.614, 77.209, "नई दिल्ली", "NEW DELHI", "building.columns.fill", .umber, .circle, zh: "新德里", en: "New Delhi"),
        e("AE", ["Dubai", "迪拜"], 25.204, 55.271, "دبي", "DUBAI", "building.2.fill", .umber, .hexagon, zh: "迪拜", en: "Dubai"),
        e("TR", ["Istanbul", "İstanbul", "伊斯坦布尔"], 41.008, 28.978, "İSTANBUL", nil, "moon.stars.fill", .crimson, .circle, zh: "伊斯坦布尔", en: "Istanbul"),
        e("EG", ["Cairo", "开罗"], 30.044, 31.236, "القاهرة", "CAIRO", "triangle.fill", .umber, .octagon, zh: "开罗", en: "Cairo"),
        // Europe
        e("GB", ["London", "伦敦"], 51.507, -0.128, "LONDON", nil, "clock.fill", .crimson, .circle, zh: "伦敦", en: "London"),
        e("GB", ["Edinburgh", "爱丁堡"], 55.953, -3.188, "EDINBURGH", nil, "building.columns.fill", .navy, .octagon, zh: "爱丁堡", en: "Edinburgh"),
        e("FR", ["Paris", "巴黎"], 48.857, 2.352, "PARIS", "LA VILLE LUMIÈRE", "sparkles", .navy, .scalloped, zh: "巴黎", en: "Paris"),
        e("FR", ["Nice", "尼斯"], 43.710, 7.262, "NICE", "CÔTE D'AZUR", "sun.max.fill", .teal, .circle, zh: "尼斯", en: "Nice"),
        e("IT", ["Roma", "Rome", "罗马"], 41.903, 12.496, "ROMA", "CAPUT MUNDI", "building.columns.fill", .umber, .circle, zh: "罗马", en: "Rome"),
        e("IT", ["Venezia", "Venice", "威尼斯"], 45.441, 12.316, "VENEZIA", "LA SERENISSIMA", "sailboat.fill", .crimson, .octagon, zh: "威尼斯", en: "Venice"),
        e("IT", ["Firenze", "Florence", "佛罗伦萨"], 43.770, 11.256, "FIRENZE", nil, "paintpalette.fill", .forest, .scalloped, zh: "佛罗伦萨", en: "Florence"),
        e("IT", ["Milano", "Milan", "米兰"], 45.464, 9.190, "MILANO", nil, "tshirt.fill", .slate, .rounded, zh: "米兰", en: "Milan"),
        e("ES", ["Barcelona", "巴塞罗那"], 41.385, 2.173, "BARCELONA", nil, "sun.max.fill", .crimson, .hexagon, zh: "巴塞罗那", en: "Barcelona"),
        e("ES", ["Madrid", "马德里"], 40.417, -3.704, "MADRID", nil, "crown.fill", .navy, .circle, zh: "马德里", en: "Madrid"),
        e("PT", ["Lisboa", "Lisbon", "里斯本"], 38.722, -9.139, "LISBOA", nil, "tram.fill", .teal, .rounded, zh: "里斯本", en: "Lisbon"),
        e("NL", ["Amsterdam", "阿姆斯特丹"], 52.368, 4.904, "AMSTERDAM", nil, "bicycle", .umber, .circle, zh: "阿姆斯特丹", en: "Amsterdam"),
        e("DE", ["Berlin", "柏林"], 52.520, 13.405, "BERLIN", nil, "building.columns.fill", .slate, .octagon, zh: "柏林", en: "Berlin"),
        e("DE", ["München", "Munich", "慕尼黑"], 48.135, 11.582, "MÜNCHEN", nil, "mug.fill", .navy, .rounded, zh: "慕尼黑", en: "Munich"),
        e("AT", ["Wien", "Vienna", "维也纳"], 48.208, 16.374, "WIEN", nil, "music.note", .crimson, .scalloped, zh: "维也纳", en: "Vienna"),
        e("AT", ["Hallstatt", "哈尔施塔特"], 47.562, 13.649, "HALLSTATT", nil, "house.fill", .teal, .circle, zh: "哈尔施塔特", en: "Hallstatt"),
        e("CZ", ["Praha", "Prague", "布拉格"], 50.076, 14.438, "PRAHA", nil, "building.columns.fill", .plum, .octagon, zh: "布拉格", en: "Prague"),
        e("HU", ["Budapest", "布达佩斯"], 47.498, 19.040, "BUDAPEST", nil, "water.waves", .forest, .rounded, zh: "布达佩斯", en: "Budapest"),
        e("CH", ["Zürich", "Zurich", "苏黎世"], 47.377, 8.542, "ZÜRICH", nil, "water.waves", .navy, .circle, zh: "苏黎世", en: "Zurich"),
        e("CH", ["Luzern", "Lucerne", "琉森", "卢塞恩"], 47.050, 8.309, "LUZERN", nil, "sailboat.fill", .teal, .scalloped, zh: "琉森", en: "Lucerne"),
        e("CH", ["Interlaken", "因特拉肯"], 46.686, 7.863, "INTERLAKEN", nil, "mountain.2.fill", .forest, .octagon, zh: "因特拉肯", en: "Interlaken"),
        e("CH", ["Zermatt", "采尔马特"], 46.020, 7.749, "ZERMATT", "MATTERHORN", "mountain.2.fill", .crimson, .rounded, zh: "采尔马特", en: "Zermatt"),
        e("CH", ["Genève", "Geneva", "日内瓦"], 46.204, 6.143, "GENÈVE", nil, "drop.fill", .navy, .hexagon, zh: "日内瓦", en: "Geneva"),
        e("DK", ["København", "Copenhagen", "哥本哈根"], 55.676, 12.568, "KØBENHAVN", nil, "sailboat.fill", .crimson, .circle, zh: "哥本哈根", en: "Copenhagen"),
        e("SE", ["Stockholm", "斯德哥尔摩"], 59.329, 18.069, "STOCKHOLM", nil, "crown.fill", .navy, .rounded, zh: "斯德哥尔摩", en: "Stockholm"),
        e("NO", ["Oslo", "奥斯陆"], 59.914, 10.752, "OSLO", nil, "ferry.fill", .navy, .octagon, zh: "奥斯陆", en: "Oslo"),
        e("FI", ["Helsinki", "赫尔辛基"], 60.170, 24.938, "HELSINKI", nil, "snowflake", .teal, .circle, zh: "赫尔辛基", en: "Helsinki"),
        e("IS", ["Reykjavík", "Reykjavik", "雷克雅未克"], 64.147, -21.942, "REYKJAVÍK", nil, "sparkles", .teal, .hexagon, zh: "雷克雅未克", en: "Reykjavík"),
        e("GR", ["Athens", "Αθήνα", "雅典"], 37.984, 23.728, "ΑΘΗΝΑ", "ATHENS", "building.columns.fill", .navy, .circle, zh: "雅典", en: "Athens"),
        e("GR", ["Santorini", "Thira", "Fira", "圣托里尼"], 36.416, 25.432, "ΣΑΝΤΟΡΙΝΗ", "SANTORINI", "sun.horizon.fill", .navy, .scalloped, zh: "圣托里尼", en: "Santorini"),
        e("RU", ["Moscow", "Москва", "莫斯科"], 55.756, 37.617, "МОСКВА", "MOSCOW", "star.fill", .crimson, .octagon, zh: "莫斯科", en: "Moscow"),
        // Americas, Oceania, Africa
        e("US", ["New York", "纽约"], 40.713, -74.006, "NEW YORK", "THE BIG APPLE", "building.2.fill", .navy, .circle, zh: "纽约", en: "New York"),
        e("US", ["Los Angeles", "洛杉矶"], 34.052, -118.244, "LOS ANGELES", "CITY OF ANGELS", "sun.max.fill", .umber, .scalloped, zh: "洛杉矶", en: "Los Angeles"),
        e("US", ["San Francisco", "旧金山"], 37.775, -122.419, "SAN FRANCISCO", "GOLDEN GATE", "cablecar.fill", .crimson, .rounded, zh: "旧金山", en: "San Francisco"),
        e("US", ["Las Vegas", "拉斯维加斯"], 36.170, -115.140, "LAS VEGAS", nil, "dice.fill", .plum, .octagon, zh: "拉斯维加斯", en: "Las Vegas"),
        e("US", ["Seattle", "西雅图"], 47.606, -122.332, "SEATTLE", nil, "cup.and.saucer.fill", .forest, .circle, zh: "西雅图", en: "Seattle"),
        e("US", ["Chicago", "芝加哥"], 41.878, -87.630, "CHICAGO", "WINDY CITY", "wind", .navy, .hexagon, zh: "芝加哥", en: "Chicago"),
        e("US", ["Honolulu", "火奴鲁鲁", "檀香山"], 21.307, -157.858, "HONOLULU", "ALOHA", "beach.umbrella.fill", .teal, .scalloped, zh: "檀香山", en: "Honolulu"),
        e("US", ["Washington", "华盛顿"], 38.907, -77.037, "WASHINGTON", "D.C.", "building.columns.fill", .slate, .circle, zh: "华盛顿", en: "Washington"),
        e("CA", ["Vancouver", "温哥华"], 49.283, -123.121, "VANCOUVER", nil, "leaf.fill", .crimson, .rounded, zh: "温哥华", en: "Vancouver"),
        e("CA", ["Toronto", "多伦多"], 43.653, -79.383, "TORONTO", nil, "building.2.fill", .navy, .octagon, zh: "多伦多", en: "Toronto"),
        e("MX", ["Ciudad de México", "Mexico City", "墨西哥城"], 19.433, -99.133, "CDMX", nil, "sun.max.fill", .forest, .circle, zh: "墨西哥城", en: "Mexico City"),
        e("PE", ["Cusco", "Cuzco", "库斯科"], -13.532, -71.968, "CUSCO", "MACHU PICCHU", "mountain.2.fill", .umber, .octagon, zh: "库斯科", en: "Cusco"),
        e("BR", ["Rio de Janeiro", "里约热内卢"], -22.907, -43.173, "RIO DE JANEIRO", nil, "beach.umbrella.fill", .forest, .scalloped, zh: "里约热内卢", en: "Rio de Janeiro"),
        e("AR", ["Buenos Aires", "布宜诺斯艾利斯"], -34.604, -58.382, "BUENOS AIRES", nil, "music.note", .navy, .circle, zh: "布宜诺斯艾利斯", en: "Buenos Aires"),
        e("AU", ["Sydney", "悉尼"], -33.869, 151.209, "SYDNEY", nil, "sailboat.fill", .navy, .scalloped, zh: "悉尼", en: "Sydney"),
        e("AU", ["Melbourne", "墨尔本"], -37.814, 144.963, "MELBOURNE", nil, "cup.and.saucer.fill", .slate, .rounded, zh: "墨尔本", en: "Melbourne"),
        e("NZ", ["Auckland", "奥克兰"], -36.849, 174.763, "AUCKLAND", nil, "sailboat.fill", .teal, .circle, zh: "奥克兰", en: "Auckland"),
        e("NZ", ["Queenstown", "皇后镇"], -45.031, 168.663, "QUEENSTOWN", nil, "mountain.2.fill", .forest, .octagon, zh: "皇后镇", en: "Queenstown"),
        e("ZA", ["Cape Town", "开普敦"], -33.925, 18.424, "CAPE TOWN", nil, "mountain.2.fill", .forest, .rounded, zh: "开普敦", en: "Cape Town"),
        e("MA", ["Marrakech", "Marrakesh", "马拉喀什"], 31.630, -7.981, "مراكش", "MARRAKECH", "sun.dust.fill", .crimson, .octagon, zh: "马拉喀什", en: "Marrakech"),
    ]
}

/// A group of cities that belong together. Visit them all and the set's own stamp is pressed.
struct StampSet: Identifiable {
    let id: String
    let title: String
    let motto: String
    let symbol: String
    let ink: Ink
    /// Cities by the title their stamp prints, as in the city catalog.
    let members: [String]
    var layout: Layout = .map(.circle)

    /// How the set's stamp is drawn: a carved seal of its name, its cities as a route on a
    /// little map, or a luggage label.
    enum Layout {
        case seal(carved: Bool)
        case map(StampShape)
        case label(StampShape)
    }

    struct Progress: Identifiable {
        let group: StampSet
        /// Members visited, with the stamp that earned each.
        let visited: [String: Stamp]
        var id: String { group.id }
        var isComplete: Bool { visited.count == group.members.count }
        /// The set's stamp, dated the day the last city was reached.
        var stamp: Stamp? {
            guard isComplete, let last = visited.values.max(by: { $0.date < $1.date }) else { return nil }
            return Stamp(id: "set.\(group.id)", kind: .set, date: last.date, countryCode: last.countryCode, city: last.city,
                         latitude: last.latitude, longitude: last.longitude, code: group.id)
        }
    }

    static func progress(cities: [Stamp]) -> [Progress] {
        var byTitle: [String: Stamp] = [:]
        for stamp in cities {
            guard let city = stamp.city,
                  let entry = CityStampStyle.match(city: city, countryCode: stamp.countryCode, coordinate: stamp.coordinate),
                  byTitle[entry.title] == nil else { continue }
            byTitle[entry.title] = stamp
        }
        return all.map { group in
            Progress(group: group, visited: byTitle.filter { group.members.contains($0.key) })
        }
    }

    static func named(_ id: String?) -> StampSet? { all.first { $0.id == id } }

    /// The set's name in the app's language; its stamp keeps the name the places use.
    var localizedName: String {
        let names: [String: (String, String)] = [
            "jiangnan": ("江南", "Jiangnan"), "capitals": ("六大古都", "Six Ancient Capitals"), "silkroad": ("丝绸之路", "Silk Road"),
            "bay": ("粤港澳", "Greater Bay Area"), "yunnan": ("彩云之南", "Yunnan"), "northeast": ("白山黑水", "Northeast China"),
            "coast": ("北方海滨", "Northern Coast"), "kansai": ("关西", "Kansai"), "kanto": ("关东", "Kanto"),
            "swiss": ("瑞士阿尔卑斯", "Swiss Alps"), "italy": ("意大利", "Italy"), "uswest": ("美国西部", "American West"),
            "nordic": ("北欧", "Nordic Capitals"), "southeastasia": ("新马泰", "Singapore, Malaysia, Thailand"),
        ]
        guard let pair = names[id] else { return title }
        return appLocale.language.languageCode == .chinese ? pair.0 : pair.1
    }

    /// A member city's name in the app's language.
    static func memberName(_ title: String) -> String {
        CityStampStyle.catalog.first { $0.title == title }?.localizedName ?? title
    }

    static let all: [StampSet] = [
        StampSet(id: "jiangnan", title: "江南", motto: "烟雨江南", symbol: "sailboat.fill", ink: .teal,
                 members: ["苏州", "杭州", "无锡", "扬州", "绍兴", "嘉兴"], layout: .seal(carved: true)),
        StampSet(id: "capitals", title: "六大古都", motto: "千年帝都", symbol: "building.columns.fill", ink: .crimson,
                 members: ["北京", "西安", "南京", "洛阳", "开封", "杭州"], layout: .seal(carved: false)),
        StampSet(id: "silkroad", title: "丝绸之路", motto: "驼铃声声", symbol: "sun.dust.fill", ink: .umber,
                 members: ["西安", "兰州", "敦煌", "乌鲁木齐"], layout: .map(.ticket)),
        StampSet(id: "bay", title: "粤港澳", motto: "大湾区", symbol: "ferry.fill", ink: .navy,
                 members: ["广州", "深圳", "香港", "澳門", "珠海"], layout: .map(.hexagon)),
        StampSet(id: "yunnan", title: "彩云之南", motto: "云南", symbol: "cloud.sun.fill", ink: .forest,
                 members: ["昆明", "大理", "丽江", "西双版纳"], layout: .seal(carved: true)),
        StampSet(id: "northeast", title: "白山黑水", motto: "东北", symbol: "snowflake", ink: .slate,
                 members: ["哈尔滨", "长春", "沈阳", "大连"], layout: .seal(carved: false)),
        StampSet(id: "coast", title: "北方海滨", motto: "看海去", symbol: "water.waves", ink: .navy,
                 members: ["秦皇岛", "大连", "烟台", "威海", "青岛"], layout: .map(.oval)),
        StampSet(id: "kansai", title: "関西", motto: "KANSAI", symbol: "building.columns.fill", ink: .crimson,
                 members: ["京都", "大阪", "奈良"], layout: .seal(carved: true)),
        StampSet(id: "kanto", title: "関東", motto: "KANTO", symbol: "tram.fill", ink: .plum,
                 members: ["東京", "横浜", "箱根"], layout: .map(.circle)),
        StampSet(id: "swiss", title: "SWISS ALPS", motto: "SCHWEIZ · SUISSE", symbol: "mountain.2.fill", ink: .crimson,
                 members: ["ZÜRICH", "LUZERN", "INTERLAKEN", "ZERMATT", "GENÈVE"], layout: .label(.hexagon)),
        StampSet(id: "italy", title: "ITALIA", motto: "LA DOLCE VITA", symbol: "fork.knife", ink: .forest,
                 members: ["ROMA", "FIRENZE", "VENEZIA", "MILANO"], layout: .label(.oval)),
        StampSet(id: "uswest", title: "AMERICAN WEST", motto: "ROAD TRIP", symbol: "car.fill", ink: .umber,
                 members: ["SEATTLE", "SAN FRANCISCO", "LOS ANGELES", "LAS VEGAS"], layout: .map(.rounded)),
        StampSet(id: "nordic", title: "NORDEN", motto: "NORDIC CAPITALS", symbol: "snowflake", ink: .navy,
                 members: ["KØBENHAVN", "OSLO", "STOCKHOLM", "HELSINKI"], layout: .map(.scalloped)),
        StampSet(id: "southeastasia", title: "新马泰", motto: "SOUTHEAST ASIA", symbol: "sun.max.fill", ink: .forest,
                 members: ["SINGAPORE", "KUALA LUMPUR", "กรุงเทพฯ"], layout: .label(.ticket)),
    ]
}

/// How a special stamp looks: shape, ink, what it says.
struct SpecialStampStyle {
    let shape: StampShape
    let ink: Ink
    let symbol: String
    /// Round the rim, or across the top.
    let label: String

    static func of(_ code: String) -> SpecialStampStyle {
        switch code {
        case "equator": SpecialStampStyle(shape: .circle, ink: .teal, symbol: "globe.americas.fill", label: "EQUATOR · 赤道")
        case "dateline": SpecialStampStyle(shape: .ticket, ink: .plum, symbol: "arrow.left.arrow.right", label: "INTERNATIONAL DATE LINE")
        case "arctic": SpecialStampStyle(shape: .hexagon, ink: .navy, symbol: "snowflake", label: "ARCTIC CIRCLE · 北极圈")
        case "antarctic": SpecialStampStyle(shape: .hexagon, ink: .navy, symbol: "snowflake", label: "ANTARCTIC CIRCLE · 南极圈")
        case "record.north": SpecialStampStyle(shape: .octagon, ink: .navy, symbol: "arrow.up", label: "最北 · NORTHERNMOST")
        case "record.south": SpecialStampStyle(shape: .octagon, ink: .crimson, symbol: "arrow.down", label: "最南 · SOUTHERNMOST")
        case "record.east": SpecialStampStyle(shape: .octagon, ink: .forest, symbol: "arrow.right", label: "最东 · EASTERNMOST")
        case "record.west": SpecialStampStyle(shape: .octagon, ink: .umber, symbol: "arrow.left", label: "最西 · WESTERNMOST")
        case "record.high": SpecialStampStyle(shape: .octagon, ink: .slate, symbol: "mountain.2.fill", label: "最高 · HIGHEST")
        default: SpecialStampStyle(shape: .scalloped, ink: .crimson, symbol: "sparkles", label: "跨年 · HAPPY NEW YEAR")
        }
    }
}

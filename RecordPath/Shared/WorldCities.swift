import Foundation
import CoreLocation

/// The cities people travel to most outside mainland China, by both names. Looking a place up
/// from inside China often brings back only a local or English name, and of a suburb at that
/// ("Mascot NSW", "Mueang Phuket District"): anywhere within reach of one of these is shown
/// as the city itself, in the app's language.
enum WorldCities {
    struct City: Sendable {
        let chinese: String
        let english: String
        let latitude: Double
        let longitude: Double
    }

    /// How far out a city's name reaches, in metres: its suburbs and its airport.
    static let reach = 30_000.0

    /// The city a place belongs to, if it's close to one.
    static func near(_ location: CLLocation) -> City? {
        let coordinate = location.coordinate
        return all.lazy
            .filter { abs($0.latitude - coordinate.latitude) < 0.4 && abs(($0.longitude - coordinate.longitude).remainder(dividingBy: 360)) < 0.8 }
            .map { ($0, location.distance(from: CLLocation(latitude: $0.latitude, longitude: $0.longitude))) }
            .filter { $0.1 <= reach }
            .min { $0.1 < $1.1 }?.0
    }

    private static func c(_ chinese: String, _ english: String, _ latitude: Double, _ longitude: Double) -> City {
        City(chinese: chinese, english: english, latitude: latitude, longitude: longitude)
    }

    static let all: [City] = [
        // East and South-East Asia
        c("东京", "Tokyo", 35.68, 139.77), c("大阪", "Osaka", 34.69, 135.50), c("京都", "Kyoto", 35.01, 135.77),
        c("名古屋", "Nagoya", 35.18, 136.91), c("札幌", "Sapporo", 43.06, 141.35), c("福冈", "Fukuoka", 33.59, 130.40),
        c("那霸", "Naha", 26.21, 127.68), c("奈良", "Nara", 34.69, 135.80), c("神户", "Kobe", 34.69, 135.19),
        c("横滨", "Yokohama", 35.44, 139.64), c("广岛", "Hiroshima", 34.39, 132.46),
        c("首尔", "Seoul", 37.57, 126.98), c("釜山", "Busan", 35.18, 129.08), c("济州", "Jeju", 33.50, 126.53),
        c("曼谷", "Bangkok", 13.75, 100.50), c("清迈", "Chiang Mai", 18.79, 98.99), c("普吉", "Phuket", 7.89, 98.39),
        c("芭堤雅", "Pattaya", 12.93, 100.88), c("甲米", "Krabi", 8.06, 98.92), c("苏梅岛", "Koh Samui", 9.51, 100.01),
        c("新加坡", "Singapore", 1.35, 103.82), c("吉隆坡", "Kuala Lumpur", 3.14, 101.69), c("槟城", "Penang", 5.41, 100.33),
        c("马六甲", "Malacca", 2.19, 102.25), c("亚庇", "Kota Kinabalu", 5.98, 116.07), c("兰卡威", "Langkawi", 6.35, 99.80),
        c("新山", "Johor Bahru", 1.49, 103.74),
        c("雅加达", "Jakarta", -6.21, 106.85), c("巴厘岛", "Bali", -8.65, 115.22), c("日惹", "Yogyakarta", -7.80, 110.37),
        c("马尼拉", "Manila", 14.60, 120.98), c("宿务", "Cebu", 10.32, 123.89), c("长滩岛", "Boracay", 11.97, 121.92),
        c("河内", "Hanoi", 21.03, 105.85), c("胡志明市", "Ho Chi Minh City", 10.78, 106.70), c("岘港", "Da Nang", 16.05, 108.21),
        c("芽庄", "Nha Trang", 12.24, 109.19), c("会安", "Hoi An", 15.88, 108.34),
        c("金边", "Phnom Penh", 11.56, 104.92), c("暹粒", "Siem Reap", 13.36, 103.86),
        c("万象", "Vientiane", 17.97, 102.63), c("琅勃拉邦", "Luang Prabang", 19.89, 102.13),
        c("仰光", "Yangon", 16.84, 96.17), c("乌兰巴托", "Ulaanbaatar", 47.92, 106.92),
        c("台北", "Taipei", 25.04, 121.56), c("高雄", "Kaohsiung", 22.63, 120.30), c("台中", "Taichung", 24.15, 120.67),
        c("台南", "Tainan", 22.99, 120.21), c("花莲", "Hualien", 23.99, 121.60),
        // South and West Asia
        c("新德里", "New Delhi", 28.61, 77.21), c("孟买", "Mumbai", 19.08, 72.88), c("阿格拉", "Agra", 27.18, 78.01),
        c("斋浦尔", "Jaipur", 26.91, 75.79), c("加德满都", "Kathmandu", 27.71, 85.32), c("科伦坡", "Colombo", 6.93, 79.86),
        c("马累", "Malé", 4.18, 73.51), c("迪拜", "Dubai", 25.20, 55.27), c("阿布扎比", "Abu Dhabi", 24.45, 54.38),
        c("多哈", "Doha", 25.29, 51.53), c("利雅得", "Riyadh", 24.71, 46.68), c("伊斯坦布尔", "Istanbul", 41.01, 28.98),
        c("安卡拉", "Ankara", 39.93, 32.86), c("安塔利亚", "Antalya", 36.90, 30.70), c("特拉维夫", "Tel Aviv", 32.08, 34.78),
        c("安曼", "Amman", 31.95, 35.93), c("塔什干", "Tashkent", 41.30, 69.24), c("撒马尔罕", "Samarkand", 39.65, 66.96),
        c("阿拉木图", "Almaty", 43.24, 76.89), c("第比利斯", "Tbilisi", 41.72, 44.79),
        // Europe
        c("伦敦", "London", 51.51, -0.13), c("爱丁堡", "Edinburgh", 55.95, -3.19), c("曼彻斯特", "Manchester", 53.48, -2.24),
        c("牛津", "Oxford", 51.75, -1.26), c("剑桥", "Cambridge", 52.21, 0.12), c("都柏林", "Dublin", 53.35, -6.26),
        c("巴黎", "Paris", 48.86, 2.35), c("尼斯", "Nice", 43.70, 7.27), c("里昂", "Lyon", 45.76, 4.84),
        c("马赛", "Marseille", 43.30, 5.37), c("波尔多", "Bordeaux", 44.84, -0.58), c("斯特拉斯堡", "Strasbourg", 48.57, 7.75),
        c("柏林", "Berlin", 52.52, 13.40), c("慕尼黑", "Munich", 48.14, 11.58), c("法兰克福", "Frankfurt", 50.11, 8.68),
        c("汉堡", "Hamburg", 53.55, 9.99), c("科隆", "Cologne", 50.94, 6.96), c("杜塞尔多夫", "Düsseldorf", 51.23, 6.78),
        c("斯图加特", "Stuttgart", 48.78, 9.18), c("海德堡", "Heidelberg", 49.40, 8.67), c("德累斯顿", "Dresden", 51.05, 13.74),
        c("苏黎世", "Zurich", 47.37, 8.54), c("日内瓦", "Geneva", 46.20, 6.14), c("卢塞恩", "Lucerne", 47.05, 8.31),
        c("伯尔尼", "Bern", 46.95, 7.45), c("因特拉肯", "Interlaken", 46.69, 7.86), c("巴塞尔", "Basel", 47.56, 7.59),
        c("采尔马特", "Zermatt", 46.02, 7.75), c("洛桑", "Lausanne", 46.52, 6.63),
        c("维也纳", "Vienna", 48.21, 16.37), c("萨尔茨堡", "Salzburg", 47.81, 13.04), c("因斯布鲁克", "Innsbruck", 47.27, 11.40),
        c("罗马", "Rome", 41.90, 12.50), c("米兰", "Milan", 45.46, 9.19), c("威尼斯", "Venice", 45.44, 12.32),
        c("佛罗伦萨", "Florence", 43.77, 11.26), c("那不勒斯", "Naples", 40.85, 14.27), c("都灵", "Turin", 45.07, 7.69),
        c("马德里", "Madrid", 40.42, -3.70), c("巴塞罗那", "Barcelona", 41.39, 2.17), c("塞维利亚", "Seville", 37.39, -5.98),
        c("瓦伦西亚", "Valencia", 39.47, -0.38), c("格拉纳达", "Granada", 37.18, -3.60),
        c("里斯本", "Lisbon", 38.72, -9.14), c("波尔图", "Porto", 41.15, -8.61),
        c("阿姆斯特丹", "Amsterdam", 52.37, 4.90), c("鹿特丹", "Rotterdam", 51.92, 4.48), c("布鲁塞尔", "Brussels", 50.85, 4.35),
        c("布鲁日", "Bruges", 51.21, 3.22), c("卢森堡", "Luxembourg", 49.61, 6.13),
        c("哥本哈根", "Copenhagen", 55.68, 12.57), c("斯德哥尔摩", "Stockholm", 59.33, 18.07), c("奥斯陆", "Oslo", 59.91, 10.75),
        c("卑尔根", "Bergen", 60.39, 5.32), c("赫尔辛基", "Helsinki", 60.17, 24.94), c("雷克雅未克", "Reykjavik", 64.15, -21.94),
        c("布拉格", "Prague", 50.08, 14.44), c("布达佩斯", "Budapest", 47.50, 19.04), c("华沙", "Warsaw", 52.23, 21.01),
        c("克拉科夫", "Kraków", 50.06, 19.94), c("雅典", "Athens", 37.98, 23.73), c("圣托里尼", "Santorini", 36.42, 25.43),
        c("杜布罗夫尼克", "Dubrovnik", 42.65, 18.09), c("萨格勒布", "Zagreb", 45.81, 15.98),
        c("莫斯科", "Moscow", 55.76, 37.62), c("圣彼得堡", "Saint Petersburg", 59.93, 30.34), c("符拉迪沃斯托克", "Vladivostok", 43.12, 131.89),
        // Africa
        c("开罗", "Cairo", 30.04, 31.24), c("卢克索", "Luxor", 25.69, 32.64), c("马拉喀什", "Marrakesh", 31.63, -7.98),
        c("卡萨布兰卡", "Casablanca", 33.57, -7.59), c("内罗毕", "Nairobi", -1.29, 36.82), c("开普敦", "Cape Town", -33.92, 18.42),
        c("约翰内斯堡", "Johannesburg", -26.20, 28.05), c("亚的斯亚贝巴", "Addis Ababa", 9.01, 38.75), c("路易港", "Port Louis", -20.16, 57.50),
        // Americas
        c("纽约", "New York", 40.71, -74.01), c("洛杉矶", "Los Angeles", 34.05, -118.24), c("旧金山", "San Francisco", 37.77, -122.42),
        c("圣何塞", "San Jose", 37.34, -121.89), c("西雅图", "Seattle", 47.61, -122.33), c("拉斯维加斯", "Las Vegas", 36.17, -115.14),
        c("圣迭戈", "San Diego", 32.72, -117.16), c("芝加哥", "Chicago", 41.88, -87.63), c("波士顿", "Boston", 42.36, -71.06),
        c("华盛顿", "Washington, D.C.", 38.91, -77.04), c("费城", "Philadelphia", 39.95, -75.17), c("迈阿密", "Miami", 25.76, -80.19),
        c("奥兰多", "Orlando", 28.54, -81.38), c("休斯敦", "Houston", 29.76, -95.37), c("达拉斯", "Dallas", 32.78, -96.80),
        c("亚特兰大", "Atlanta", 33.75, -84.39), c("檀香山", "Honolulu", 21.31, -157.86), c("丹佛", "Denver", 39.74, -104.99),
        c("温哥华", "Vancouver", 49.28, -123.12), c("多伦多", "Toronto", 43.65, -79.38), c("蒙特利尔", "Montreal", 45.50, -73.57),
        c("渥太华", "Ottawa", 45.42, -75.70), c("卡尔加里", "Calgary", 51.05, -114.07),
        c("墨西哥城", "Mexico City", 19.43, -99.13), c("坎昆", "Cancún", 21.16, -86.85), c("哈瓦那", "Havana", 23.11, -82.37),
        c("里约热内卢", "Rio de Janeiro", -22.91, -43.21), c("圣保罗", "São Paulo", -23.55, -46.63), c("巴西利亚", "Brasília", -15.79, -47.88),
        c("伊瓜苏", "Foz do Iguaçu", -25.52, -54.59), c("布宜诺斯艾利斯", "Buenos Aires", -34.60, -58.38), c("圣地亚哥", "Santiago", -33.45, -70.67),
        c("利马", "Lima", -12.05, -77.04), c("库斯科", "Cusco", -13.53, -71.97), c("波哥大", "Bogotá", 4.71, -74.07),
        // Oceania
        c("悉尼", "Sydney", -33.87, 151.21), c("墨尔本", "Melbourne", -37.81, 144.96), c("布里斯班", "Brisbane", -27.47, 153.03),
        c("黄金海岸", "Gold Coast", -28.02, 153.40), c("珀斯", "Perth", -31.95, 115.86), c("凯恩斯", "Cairns", -16.92, 145.77),
        c("阿德莱德", "Adelaide", -34.93, 138.60), c("堪培拉", "Canberra", -35.28, 149.13),
        c("奥克兰", "Auckland", -36.85, 174.76), c("皇后镇", "Queenstown", -45.03, 168.66), c("基督城", "Christchurch", -43.53, 172.64),
        c("惠灵顿", "Wellington", -41.29, 174.78), c("楠迪", "Nadi", -17.80, 177.42),
    ]
}

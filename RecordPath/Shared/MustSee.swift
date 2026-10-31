import Foundation
import CoreLocation

/// Waytrace's own lists of places worth a lifetime: a hundred in China (Hong Kong, Macao and
/// Taiwan among them) and a hundred elsewhere, drawn from World Heritage sites, China's 5A
/// scenic areas and the places travellers name most. A place counts as visited when any stay,
/// recorded or from photos, falls within its radius, so a park is as big as the park.
struct MustSeePlace: Identifiable, Hashable, Sendable {
    enum Kind: String, Sendable {
        case heritage, mountain, water, city, wild

        var symbol: String {
            switch self {
            case .heritage: "building.columns.fill"
            case .mountain: "mountain.2.fill"
            case .water: "water.waves"
            case .city: "building.2.fill"
            case .wild: "leaf.fill"
            }
        }
    }

    let id: String
    let name: String
    let nameEn: String
    /// Province in China, country elsewhere.
    let region: String
    let regionEn: String
    let latitude: Double
    let longitude: Double
    /// How close a stay must be, in kilometres.
    let radius: Double
    let kind: Kind
    /// Places as big as a country, counted by being there at all.
    var countryCode: String? = nil

    var coordinate: CLLocationCoordinate2D { CLLocationCoordinate2D(latitude: latitude, longitude: longitude) }
    var localizedName: String { MustSee.isChinese ? name : nameEn }
    var localizedRegion: String { MustSee.isChinese ? region : regionEn }
}

enum MustSee {
    enum List: String, CaseIterable, Identifiable, Sendable {
        case china, world
        var id: String { rawValue }
        var places: [MustSeePlace] { self == .china ? MustSee.china : MustSee.world }
    }

    static var isChinese: Bool { appLocale.language.languageCode == .chinese }

    /// A stay reduced to what matching needs, so the work can leave the main thread.
    struct Visit: Sendable {
        let latitude: Double
        let longitude: Double
        let arrival: Date
        let countryCode: String?
    }

    /// The place worth a lifetime a stay was at: the nearest whose area holds it. Country-sized
    /// places don't tag single visits, and city-sized ones only tag sights, not every hotel and
    /// café in town.
    static func place(for stay: Stay) -> MustSeePlace? {
        let location = stay.location
        return (china + world)
            .filter { place in
                guard place.countryCode == nil, place.radius <= 3 || stay.isLandmark else { return false }
                let span = place.radius / 111 + 0.01
                return abs(place.latitude - stay.latitude) <= span && abs(place.longitude - stay.longitude) <= span * 3
            }
            .map { ($0, location.distance(from: CLLocation(latitude: $0.latitude, longitude: $0.longitude))) }
            .filter { $0.1 <= $0.0.radius * 1000 }
            .min { $0.1 < $1.1 }?.0
    }

    /// When each place was first visited.
    static func firstVisits(_ places: [MustSeePlace], visits: [Visit]) -> [String: Date] {
        let byLatitude = visits.sorted { $0.latitude < $1.latitude }
        var result: [String: Date] = [:]
        for place in places {
            if let code = place.countryCode {
                if let first = visits.filter({ $0.countryCode == code }).map(\.arrival).min() { result[place.id] = first }
                continue
            }
            let center = CLLocation(latitude: place.latitude, longitude: place.longitude)
            let span = place.radius / 111
            // Binary search to the band of latitudes that could be close enough.
            var low = 0, high = byLatitude.count
            while low < high {
                let mid = (low + high) / 2
                if byLatitude[mid].latitude < place.latitude - span { low = mid + 1 } else { high = mid }
            }
            var first: Date?
            var i = low
            while i < byLatitude.count, byLatitude[i].latitude <= place.latitude + span {
                let visit = byLatitude[i]
                if first.map({ visit.arrival < $0 }) ?? true,
                   CLLocation(latitude: visit.latitude, longitude: visit.longitude).distance(from: center) <= place.radius * 1000 {
                    first = visit.arrival
                }
                i += 1
            }
            if let first { result[place.id] = first }
        }
        return result
    }

    private static func p(_ id: String, _ name: String, _ nameEn: String, _ region: String, _ regionEn: String,
                          _ lat: Double, _ lon: Double, _ radius: Double, _ kind: MustSeePlace.Kind,
                          country: String? = nil) -> MustSeePlace {
        MustSeePlace(id: id, name: name, nameEn: nameEn, region: region, regionEn: regionEn,
                     latitude: lat, longitude: lon, radius: radius, kind: kind, countryCode: country)
    }

    // MARK: China

    static let china: [MustSeePlace] = [
        p("forbidden-city", "故宫", "Forbidden City", "北京", "Beijing", 39.9163, 116.3972, 1.5, .heritage),
        p("badaling", "八达岭长城", "Great Wall at Badaling", "北京", "Beijing", 40.3597, 116.0200, 3, .heritage),
        p("mutianyu", "慕田峪长城", "Great Wall at Mutianyu", "北京", "Beijing", 40.4319, 116.5704, 3, .heritage),
        p("temple-of-heaven", "天坛", "Temple of Heaven", "北京", "Beijing", 39.8822, 116.4066, 1.5, .heritage),
        p("summer-palace", "颐和园", "Summer Palace", "北京", "Beijing", 39.9999, 116.2755, 1.5, .heritage),
        p("bund", "外滩", "The Bund", "上海", "Shanghai", 31.2400, 121.4900, 1.5, .city),
        p("yu-garden", "豫园", "Yu Garden", "上海", "Shanghai", 31.2272, 121.4921, 1, .heritage),
        p("chengde", "承德避暑山庄", "Chengde Mountain Resort", "河北", "Hebei", 40.9910, 117.9390, 3, .heritage),
        p("shanhaiguan", "山海关", "Shanhai Pass", "河北", "Hebei", 40.0090, 119.7540, 3, .heritage),
        p("pingyao", "平遥古城", "Ancient City of Pingyao", "山西", "Shanxi", 37.2020, 112.1790, 3, .heritage),
        p("yungang", "云冈石窟", "Yungang Grottoes", "山西", "Shanxi", 40.1100, 113.1260, 2, .heritage),
        p("wutaishan", "五台山", "Mount Wutai", "山西", "Shanxi", 39.0090, 113.5900, 15, .mountain),
        p("hukou", "壶口瀑布", "Hukou Waterfall", "山西", "Shanxi", 36.1480, 110.4430, 3, .water),
        p("hulunbuir", "呼伦贝尔草原", "Hulunbuir Grassland", "内蒙古", "Inner Mongolia", 49.2120, 119.7660, 60, .wild),
        p("ejina", "额济纳胡杨林", "Ejina Poplar Forest", "内蒙古", "Inner Mongolia", 41.9500, 101.0500, 30, .wild),
        p("mukden-palace", "沈阳故宫", "Mukden Palace", "辽宁", "Liaoning", 41.7962, 123.4560, 1.5, .heritage),
        p("changbaishan", "长白山天池", "Changbai Mountain", "吉林", "Jilin", 42.0060, 128.0560, 15, .mountain),
        p("harbin", "哈尔滨冰雪大世界", "Harbin Ice City", "黑龙江", "Heilongjiang", 45.7790, 126.6180, 10, .city),
        p("suzhou-gardens", "苏州园林", "Classical Gardens of Suzhou", "江苏", "Jiangsu", 31.3240, 120.6290, 2, .heritage),
        p("zhouzhuang", "周庄", "Zhouzhuang", "江苏", "Jiangsu", 31.1160, 120.8460, 2, .water),
        p("zhongshanling", "中山陵", "Sun Yat-sen Mausoleum", "江苏", "Jiangsu", 32.0640, 118.8480, 3, .heritage),
        p("west-lake", "西湖", "West Lake", "浙江", "Zhejiang", 30.2460, 120.1500, 4, .water),
        p("wuzhen", "乌镇", "Wuzhen", "浙江", "Zhejiang", 30.7440, 120.4870, 2, .water),
        p("qiandaohu", "千岛湖", "Qiandao Lake", "浙江", "Zhejiang", 29.6050, 119.0400, 20, .water),
        p("putuoshan", "普陀山", "Mount Putuo", "浙江", "Zhejiang", 30.0090, 122.3880, 5, .mountain),
        p("huangshan", "黄山", "Mount Huangshan", "安徽", "Anhui", 30.1300, 118.1670, 12, .mountain),
        p("hongcun", "宏村", "Hongcun Village", "安徽", "Anhui", 30.0013, 117.9877, 2, .heritage),
        p("gulangyu", "鼓浪屿", "Gulangyu", "福建", "Fujian", 24.4470, 118.0660, 2, .city),
        p("wuyishan", "武夷山", "Mount Wuyi", "福建", "Fujian", 27.6500, 117.9600, 15, .mountain),
        p("tulou", "福建土楼", "Fujian Tulou", "福建", "Fujian", 24.5862, 117.0610, 15, .heritage),
        p("lushan", "庐山", "Mount Lu", "江西", "Jiangxi", 29.5560, 115.9850, 12, .mountain),
        p("wuyuan", "婺源", "Wuyuan", "江西", "Jiangxi", 29.2480, 117.8620, 25, .wild),
        p("sanqingshan", "三清山", "Mount Sanqing", "江西", "Jiangxi", 28.9100, 118.0600, 8, .mountain),
        p("taishan", "泰山", "Mount Tai", "山东", "Shandong", 36.2560, 117.1010, 6, .mountain),
        p("qufu", "曲阜三孔", "Temple of Confucius, Qufu", "山东", "Shandong", 35.5970, 116.9920, 3, .heritage),
        p("qingdao", "青岛老城", "Old Qingdao", "山东", "Shandong", 36.0610, 120.3200, 6, .city),
        p("longmen", "龙门石窟", "Longmen Grottoes", "河南", "Henan", 34.5560, 112.4720, 2, .heritage),
        p("shaolin", "少林寺", "Shaolin Temple", "河南", "Henan", 34.5070, 112.9350, 3, .heritage),
        p("yuntaishan", "云台山", "Yuntai Mountain", "河南", "Henan", 35.4250, 113.3900, 8, .mountain),
        p("wudangshan", "武当山", "Wudang Mountains", "湖北", "Hubei", 32.4010, 111.0040, 10, .mountain),
        p("shennongjia", "神农架", "Shennongjia", "湖北", "Hubei", 31.4560, 110.3900, 30, .wild),
        p("yellow-crane", "黄鹤楼", "Yellow Crane Tower", "湖北", "Hubei", 30.5450, 114.3020, 1.5, .heritage),
        p("zhangjiajie", "张家界", "Zhangjiajie", "湖南", "Hunan", 29.3460, 110.4380, 15, .mountain),
        p("fenghuang", "凤凰古城", "Fenghuang Old Town", "湖南", "Hunan", 27.9480, 109.5990, 3, .heritage),
        p("canton-tower", "广州塔与珠江", "Canton Tower", "广东", "Guangdong", 23.1060, 113.3240, 6, .city),
        p("kaiping", "开平碉楼", "Kaiping Diaolou", "广东", "Guangdong", 22.2860, 112.5600, 12, .heritage),
        p("danxiashan", "丹霞山", "Mount Danxia", "广东", "Guangdong", 25.0300, 113.7350, 8, .mountain),
        p("li-river", "漓江与阳朔", "Li River and Yangshuo", "广西", "Guangxi", 24.7780, 110.4960, 15, .water),
        p("longji", "龙脊梯田", "Longji Rice Terraces", "广西", "Guangxi", 25.7550, 110.1100, 8, .wild),
        p("detian", "德天瀑布", "Detian Falls", "广西", "Guangxi", 22.8530, 106.7230, 3, .water),
        p("yalong-bay", "三亚亚龙湾", "Yalong Bay, Sanya", "海南", "Hainan", 18.2280, 109.6400, 10, .water),
        p("chongqing", "重庆山城", "Chongqing", "重庆", "Chongqing", 29.5640, 106.5780, 5, .city),
        p("dazu", "大足石刻", "Dazu Rock Carvings", "重庆", "Chongqing", 29.7540, 105.7930, 3, .heritage),
        p("wulong", "武隆天生三桥", "Wulong Natural Bridges", "重庆", "Chongqing", 29.4340, 107.7980, 6, .wild),
        p("jiuzhaigou", "九寨沟", "Jiuzhaigou", "四川", "Sichuan", 33.2600, 103.9180, 20, .water),
        p("huanglong", "黄龙", "Huanglong", "四川", "Sichuan", 32.7480, 103.8270, 6, .water),
        p("emeishan", "峨眉山", "Mount Emei", "四川", "Sichuan", 29.5440, 103.3320, 12, .mountain),
        p("leshan", "乐山大佛", "Leshan Giant Buddha", "四川", "Sichuan", 29.5450, 103.7700, 2, .heritage),
        p("dujiangyan", "都江堰", "Dujiangyan", "四川", "Sichuan", 31.0010, 103.6080, 3, .heritage),
        p("yading", "稻城亚丁", "Yading", "四川", "Sichuan", 28.4300, 100.3500, 20, .mountain),
        p("panda-base", "成都大熊猫基地", "Chengdu Panda Base", "四川", "Sichuan", 30.7340, 104.1450, 2, .wild),
        p("siguniang", "四姑娘山", "Mount Siguniang", "四川", "Sichuan", 31.0700, 102.9000, 15, .mountain),
        p("huangguoshu", "黄果树瀑布", "Huangguoshu Waterfall", "贵州", "Guizhou", 25.9910, 105.6660, 4, .water),
        p("xijiang", "西江千户苗寨", "Xijiang Miao Village", "贵州", "Guizhou", 26.4950, 108.1750, 3, .heritage),
        p("fanjingshan", "梵净山", "Mount Fanjing", "贵州", "Guizhou", 27.9060, 108.6950, 10, .mountain),
        p("lijiang", "丽江古城", "Old Town of Lijiang", "云南", "Yunnan", 26.8720, 100.2300, 3, .heritage),
        p("yulong", "玉龙雪山", "Jade Dragon Snow Mountain", "云南", "Yunnan", 27.1000, 100.1800, 15, .mountain),
        p("dali", "大理古城与洱海", "Dali and Erhai Lake", "云南", "Yunnan", 25.6950, 100.1620, 10, .water),
        p("shangri-la", "香格里拉", "Shangri-La", "云南", "Yunnan", 27.8290, 99.7070, 20, .wild),
        p("yuanyang", "元阳梯田", "Yuanyang Rice Terraces", "云南", "Yunnan", 23.0900, 102.7500, 15, .wild),
        p("xishuangbanna", "西双版纳", "Xishuangbanna", "云南", "Yunnan", 22.0070, 100.7970, 25, .wild),
        p("lugu-lake", "泸沽湖", "Lugu Lake", "云南", "Yunnan", 27.7100, 100.7800, 12, .water),
        p("stone-forest", "石林", "Stone Forest", "云南", "Yunnan", 24.8160, 103.3250, 4, .wild),
        p("potala", "布达拉宫", "Potala Palace", "西藏", "Tibet", 29.6578, 91.1170, 1.5, .heritage),
        p("namtso", "纳木错", "Namtso", "西藏", "Tibet", 30.7300, 90.6000, 25, .water),
        p("everest-base", "珠峰大本营", "Everest Base Camp", "西藏", "Tibet", 28.1400, 86.8500, 15, .mountain),
        p("yamdrok", "羊卓雍措", "Yamdrok Lake", "西藏", "Tibet", 28.9500, 90.6000, 20, .water),
        p("nyingchi", "林芝与雅鲁藏布大峡谷", "Nyingchi and the Yarlung Tsangpo", "西藏", "Tibet", 29.6000, 94.9000, 40, .wild),
        p("terracotta", "兵马俑", "Terracotta Army", "陕西", "Shaanxi", 34.3850, 109.2780, 2, .heritage),
        p("xian-wall", "西安城墙", "Xi'an City Wall", "陕西", "Shaanxi", 34.2600, 108.9450, 5, .heritage),
        p("huashan", "华山", "Mount Hua", "陕西", "Shaanxi", 34.4780, 110.0850, 6, .mountain),
        p("mogao", "莫高窟", "Mogao Caves", "甘肃", "Gansu", 40.0420, 94.8040, 2, .heritage),
        p("crescent-lake", "鸣沙山月牙泉", "Crescent Lake", "甘肃", "Gansu", 40.0880, 94.6720, 3, .wild),
        p("zhangye-danxia", "张掖七彩丹霞", "Zhangye Danxia", "甘肃", "Gansu", 38.9600, 100.0700, 8, .wild),
        p("jiayuguan", "嘉峪关", "Jiayu Pass", "甘肃", "Gansu", 39.8010, 98.2180, 3, .heritage),
        p("qinghai-lake", "青海湖", "Qinghai Lake", "青海", "Qinghai", 36.8900, 100.1700, 50, .water),
        p("chaka", "茶卡盐湖", "Chaka Salt Lake", "青海", "Qinghai", 36.7900, 99.0800, 8, .water),
        p("shapotou", "沙坡头", "Shapotou", "宁夏", "Ningxia", 37.4650, 104.9880, 6, .wild),
        p("kanas", "喀纳斯湖", "Kanas Lake", "新疆", "Xinjiang", 48.7000, 87.0300, 20, .water),
        p("tianchi", "天山天池", "Heavenly Lake of Tianshan", "新疆", "Xinjiang", 43.8850, 88.1300, 6, .water),
        p("sayram", "赛里木湖", "Sayram Lake", "新疆", "Xinjiang", 44.6000, 81.1800, 25, .water),
        p("kashgar", "喀什古城", "Old City of Kashgar", "新疆", "Xinjiang", 39.4700, 75.9900, 4, .heritage),
        p("victoria-harbour", "维多利亚港", "Victoria Harbour", "香港", "Hong Kong", 22.2930, 114.1700, 4, .city),
        p("victoria-peak", "太平山顶", "Victoria Peak", "香港", "Hong Kong", 22.2710, 114.1500, 2, .city),
        p("macau-historic", "澳门历史城区", "Historic Centre of Macao", "澳门", "Macao", 22.1975, 113.5409, 2, .heritage),
        p("sun-moon-lake", "日月潭", "Sun Moon Lake", "台湾", "Taiwan", 23.8600, 120.9150, 8, .water),
        p("taroko", "太鲁阁", "Taroko Gorge", "台湾", "Taiwan", 24.1600, 121.6200, 12, .mountain),
        p("alishan", "阿里山", "Alishan", "台湾", "Taiwan", 23.5100, 120.8050, 8, .mountain),
        p("taipei-101", "台北101", "Taipei 101", "台湾", "Taiwan", 25.0340, 121.5645, 2, .city),
        p("jiufen", "九份", "Jiufen", "台湾", "Taiwan", 25.1090, 121.8440, 2, .heritage),
    ]

    // MARK: World

    static let world: [MustSeePlace] = [
        // Asia
        p("kyoto", "京都古寺", "Temples of Kyoto", "日本", "Japan", 35.0116, 135.7681, 10, .heritage),
        p("fuji", "富士山", "Mount Fuji", "日本", "Japan", 35.3606, 138.7274, 25, .mountain),
        p("tokyo", "东京", "Tokyo", "日本", "Japan", 35.6812, 139.7671, 15, .city),
        p("gyeongbokgung", "景福宫", "Gyeongbokgung", "韩国", "South Korea", 37.5796, 126.9770, 2, .heritage),
        p("jeju", "济州岛", "Jeju Island", "韩国", "South Korea", 33.3617, 126.5292, 40, .wild),
        p("grand-palace", "曼谷大皇宫", "Grand Palace, Bangkok", "泰国", "Thailand", 13.7500, 100.4913, 2, .heritage),
        p("chiang-mai", "清迈古城", "Chiang Mai", "泰国", "Thailand", 18.7883, 98.9853, 5, .city),
        p("phuket", "普吉岛", "Phuket", "泰国", "Thailand", 7.8804, 98.3923, 30, .water),
        p("angkor", "吴哥窟", "Angkor Wat", "柬埔寨", "Cambodia", 13.4125, 103.8670, 10, .heritage),
        p("ha-long", "下龙湾", "Ha Long Bay", "越南", "Vietnam", 20.9101, 107.1839, 25, .water),
        p("hoi-an", "会安古镇", "Hoi An", "越南", "Vietnam", 15.8801, 108.3380, 3, .heritage),
        p("bali", "巴厘岛", "Bali", "印度尼西亚", "Indonesia", -8.4095, 115.1889, 60, .water),
        p("borobudur", "婆罗浮屠", "Borobudur", "印度尼西亚", "Indonesia", -7.6079, 110.2038, 2, .heritage),
        p("marina-bay", "滨海湾", "Marina Bay", "新加坡", "Singapore", 1.2834, 103.8607, 6, .city),
        p("palawan", "巴拉望", "Palawan", "菲律宾", "Philippines", 11.2027, 119.4160, 25, .water),
        p("bagan", "蒲甘", "Bagan", "缅甸", "Myanmar", 21.1717, 94.8585, 10, .heritage),
        p("kathmandu", "加德满都谷地", "Kathmandu Valley", "尼泊尔", "Nepal", 27.7043, 85.3070, 8, .heritage),
        p("taj-mahal", "泰姬陵", "Taj Mahal", "印度", "India", 27.1751, 78.0421, 2, .heritage),
        p("sigiriya", "狮子岩", "Sigiriya", "斯里兰卡", "Sri Lanka", 7.9570, 80.7603, 3, .heritage),
        p("maldives", "马尔代夫", "Maldives", "马尔代夫", "Maldives", 3.2028, 73.2207, 400, .water, country: "MV"),
        p("petra", "佩特拉", "Petra", "约旦", "Jordan", 30.3285, 35.4444, 4, .heritage),
        p("burj-khalifa", "迪拜哈利法塔", "Burj Khalifa, Dubai", "阿联酋", "UAE", 25.1972, 55.2744, 4, .city),
        p("cappadocia", "卡帕多奇亚", "Cappadocia", "土耳其", "Türkiye", 38.6431, 34.8289, 20, .wild),
        p("hagia-sophia", "圣索菲亚大教堂", "Hagia Sophia", "土耳其", "Türkiye", 41.0086, 28.9802, 3, .heritage),
        p("pamukkale", "棉花堡", "Pamukkale", "土耳其", "Türkiye", 37.9204, 29.1212, 3, .water),
        p("jerusalem", "耶路撒冷老城", "Old City of Jerusalem", "以色列", "Israel", 31.7767, 35.2345, 2, .heritage),
        p("samarkand", "撒马尔罕", "Samarkand", "乌兹别克斯坦", "Uzbekistan", 39.6542, 66.9597, 5, .heritage),
        // Europe
        p("eiffel", "埃菲尔铁塔", "Eiffel Tower", "法国", "France", 48.8584, 2.2945, 2, .city),
        p("versailles", "凡尔赛宫", "Palace of Versailles", "法国", "France", 48.8049, 2.1204, 2, .heritage),
        p("mont-saint-michel", "圣米歇尔山", "Mont-Saint-Michel", "法国", "France", 48.6361, -1.5115, 3, .heritage),
        p("provence", "普罗旺斯薰衣草田", "Lavender of Provence", "法国", "France", 43.8370, 5.9830, 20, .wild),
        p("london", "伦敦", "London", "英国", "United Kingdom", 51.5055, -0.0754, 10, .city),
        p("stonehenge", "巨石阵", "Stonehenge", "英国", "United Kingdom", 51.1789, -1.8262, 2, .heritage),
        p("edinburgh", "爱丁堡", "Edinburgh", "英国", "United Kingdom", 55.9486, -3.1999, 5, .city),
        p("colosseum", "罗马斗兽场", "Colosseum", "意大利", "Italy", 41.8902, 12.4922, 3, .heritage),
        p("venice", "威尼斯", "Venice", "意大利", "Italy", 45.4408, 12.3155, 4, .water),
        p("florence", "佛罗伦萨", "Florence", "意大利", "Italy", 43.7731, 11.2560, 4, .heritage),
        p("cinque-terre", "五渔村", "Cinque Terre", "意大利", "Italy", 44.1270, 9.7090, 8, .water),
        p("amalfi", "阿马尔菲海岸", "Amalfi Coast", "意大利", "Italy", 40.6340, 14.6027, 12, .water),
        p("vatican", "梵蒂冈", "Vatican City", "梵蒂冈", "Vatican City", 41.9022, 12.4539, 1.5, .heritage),
        p("sagrada-familia", "圣家堂", "Sagrada Família", "西班牙", "Spain", 41.4036, 2.1744, 2, .heritage),
        p("alhambra", "阿尔罕布拉宫", "Alhambra", "西班牙", "Spain", 37.1761, -3.5881, 2, .heritage),
        p("lisbon", "里斯本", "Lisbon", "葡萄牙", "Portugal", 38.7223, -9.1393, 8, .city),
        p("santorini", "圣托里尼", "Santorini", "希腊", "Greece", 36.4166, 25.4320, 12, .water),
        p("acropolis", "雅典卫城", "Acropolis of Athens", "希腊", "Greece", 37.9715, 23.7257, 2, .heritage),
        p("jungfrau", "少女峰", "Jungfrau", "瑞士", "Switzerland", 46.5370, 7.9626, 15, .mountain),
        p("matterhorn", "马特洪峰", "Matterhorn", "瑞士", "Switzerland", 46.0207, 7.7491, 10, .mountain),
        p("hallstatt", "哈尔施塔特", "Hallstatt", "奥地利", "Austria", 47.5622, 13.6493, 4, .water),
        p("neuschwanstein", "新天鹅堡", "Neuschwanstein", "德国", "Germany", 47.5576, 10.7498, 3, .heritage),
        p("prague", "布拉格老城", "Old Town of Prague", "捷克", "Czechia", 50.0870, 14.4210, 4, .heritage),
        p("amsterdam", "阿姆斯特丹运河", "Canals of Amsterdam", "荷兰", "Netherlands", 52.3676, 4.9041, 6, .city),
        p("bruges", "布鲁日", "Bruges", "比利时", "Belgium", 51.2093, 3.2247, 4, .heritage),
        p("budapest", "布达佩斯", "Budapest", "匈牙利", "Hungary", 47.4979, 19.0402, 8, .city),
        p("dubrovnik", "杜布罗夫尼克", "Dubrovnik", "克罗地亚", "Croatia", 42.6410, 18.1100, 3, .heritage),
        p("plitvice", "十六湖", "Plitvice Lakes", "克罗地亚", "Croatia", 44.8654, 15.5820, 10, .water),
        p("geiranger", "盖朗厄尔峡湾", "Geirangerfjord", "挪威", "Norway", 62.1010, 7.2060, 15, .water),
        p("lofoten", "罗弗敦群岛", "Lofoten Islands", "挪威", "Norway", 68.2000, 13.9000, 60, .wild),
        p("golden-circle", "冰岛黄金圈", "Iceland's Golden Circle", "冰岛", "Iceland", 64.3271, -20.1199, 40, .wild),
        p("jokulsarlon", "杰古沙龙冰河湖", "Jökulsárlón", "冰岛", "Iceland", 64.0784, -16.2306, 10, .water),
        p("rovaniemi", "罗瓦涅米", "Rovaniemi", "芬兰", "Finland", 66.5436, 25.8473, 15, .wild),
        p("red-square", "红场", "Red Square", "俄罗斯", "Russia", 55.7539, 37.6208, 2, .heritage),
        p("baikal", "贝加尔湖", "Lake Baikal", "俄罗斯", "Russia", 53.5587, 108.1650, 150, .water),
        // Africa
        p("giza", "吉萨金字塔", "Pyramids of Giza", "埃及", "Egypt", 29.9792, 31.1342, 3, .heritage),
        p("luxor", "卢克索", "Luxor", "埃及", "Egypt", 25.7188, 32.6573, 8, .heritage),
        p("sahara", "撒哈拉沙漠", "Sahara at Merzouga", "摩洛哥", "Morocco", 31.0990, -4.0130, 25, .wild),
        p("marrakech", "马拉喀什", "Marrakesh", "摩洛哥", "Morocco", 31.6295, -7.9811, 6, .city),
        p("chefchaouen", "舍夫沙万", "Chefchaouen", "摩洛哥", "Morocco", 35.1688, -5.2636, 3, .city),
        p("masai-mara", "马赛马拉", "Maasai Mara", "肯尼亚", "Kenya", -1.4900, 35.1400, 50, .wild),
        p("serengeti", "塞伦盖蒂", "Serengeti", "坦桑尼亚", "Tanzania", -2.3333, 34.8333, 80, .wild),
        p("kilimanjaro", "乞力马扎罗山", "Mount Kilimanjaro", "坦桑尼亚", "Tanzania", -3.0674, 37.3556, 25, .mountain),
        p("victoria-falls", "维多利亚瀑布", "Victoria Falls", "赞比亚/津巴布韦", "Zambia / Zimbabwe", -17.9243, 25.8572, 6, .water),
        p("table-mountain", "开普敦桌山", "Table Mountain", "南非", "South Africa", -33.9628, 18.4098, 12, .mountain),
        p("baobabs", "猴面包树大道", "Avenue of the Baobabs", "马达加斯加", "Madagascar", -20.2508, 44.4183, 5, .wild),
        p("sossusvlei", "纳米布沙漠", "Namib Desert", "纳米比亚", "Namibia", -24.7275, 15.3426, 30, .wild),
        // Americas
        p("grand-canyon", "大峡谷", "Grand Canyon", "美国", "United States", 36.0544, -112.1401, 30, .wild),
        p("new-york", "纽约", "New York City", "美国", "United States", 40.7580, -73.9855, 15, .city),
        p("yellowstone", "黄石公园", "Yellowstone", "美国", "United States", 44.4280, -110.5885, 60, .wild),
        p("yosemite", "优胜美地", "Yosemite", "美国", "United States", 37.8651, -119.5383, 25, .mountain),
        p("golden-gate", "金门大桥", "Golden Gate Bridge", "美国", "United States", 37.8199, -122.4783, 4, .city),
        p("antelope", "羚羊峡谷", "Antelope Canyon", "美国", "United States", 36.8619, -111.3743, 5, .wild),
        p("hawaii", "夏威夷", "Hawaiʻi", "美国", "United States", 20.8, -156.3, 300, .water),
        p("banff", "班夫与路易斯湖", "Banff and Lake Louise", "加拿大", "Canada", 51.4254, -116.1773, 30, .water),
        p("niagara", "尼亚加拉瀑布", "Niagara Falls", "加拿大/美国", "Canada / United States", 43.0896, -79.0849, 4, .water),
        p("chichen-itza", "奇琴伊察", "Chichén Itzá", "墨西哥", "Mexico", 20.6843, -88.5678, 2, .heritage),
        p("havana", "哈瓦那老城", "Old Havana", "古巴", "Cuba", 23.1365, -82.3594, 4, .heritage),
        p("machu-picchu", "马丘比丘", "Machu Picchu", "秘鲁", "Peru", -13.1631, -72.5450, 4, .heritage),
        p("rainbow-mountain", "彩虹山", "Rainbow Mountain", "秘鲁", "Peru", -13.8695, -71.3030, 5, .mountain),
        p("uyuni", "乌尤尼盐沼", "Salar de Uyuni", "玻利维亚", "Bolivia", -20.1338, -67.4891, 60, .water),
        p("torres-del-paine", "百内国家公园", "Torres del Paine", "智利", "Chile", -50.9423, -73.4068, 40, .mountain),
        p("easter-island", "复活节岛", "Easter Island", "智利", "Chile", -27.1127, -109.3497, 20, .heritage),
        p("iguazu", "伊瓜苏瀑布", "Iguazú Falls", "阿根廷/巴西", "Argentina / Brazil", -25.6953, -54.4367, 6, .water),
        p("perito-moreno", "莫雷诺冰川", "Perito Moreno Glacier", "阿根廷", "Argentina", -50.4967, -73.1377, 8, .water),
        p("rio", "里约热内卢", "Rio de Janeiro", "巴西", "Brazil", -22.9519, -43.2105, 12, .city),
        p("galapagos", "加拉帕戈斯群岛", "Galápagos Islands", "厄瓜多尔", "Ecuador", -0.9538, -90.9656, 150, .wild),
        // Oceania
        p("sydney-opera", "悉尼歌剧院", "Sydney Opera House", "澳大利亚", "Australia", -33.8568, 151.2153, 4, .city),
        p("great-barrier-reef", "大堡礁", "Great Barrier Reef", "澳大利亚", "Australia", -16.9186, 145.7781, 80, .water),
        p("uluru", "乌鲁鲁", "Uluru", "澳大利亚", "Australia", -25.3444, 131.0369, 15, .wild),
        p("milford-sound", "米尔福德峡湾", "Milford Sound", "新西兰", "New Zealand", -44.6414, 167.8974, 20, .water),
        p("queenstown", "皇后镇", "Queenstown", "新西兰", "New Zealand", -45.0312, 168.6626, 15, .city),
        p("bora-bora", "波拉波拉岛", "Bora Bora", "法属波利尼西亚", "French Polynesia", -16.5004, -151.7415, 15, .water),
    ]
}

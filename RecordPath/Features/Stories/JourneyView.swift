import SwiftUI
import MapKit

struct JourneyRoute: Hashable {}

/// A famous road laid out stop by stop. The distance the person has travelled on the ground
/// carries them along it, and every town they've "passed" lights up.
struct ClassicRoute: Identifiable, Hashable {
    struct Stop: Hashable {
        let name: String
        let nameEn: String
        let latitude: Double
        let longitude: Double
        let note: String
        let noteEn: String

        var coordinate: CLLocationCoordinate2D { CLLocationCoordinate2D(latitude: latitude, longitude: longitude) }
        var localizedName: String { MustSee.isChinese ? name : nameEn }
        var localizedNote: String { MustSee.isChinese ? note : noteEn }
    }

    let id: String
    let name: String
    let nameEn: String
    let symbol: String
    let tint: Color
    let stops: [Stop]

    var localizedName: String { MustSee.isChinese ? name : nameEn }

    /// Distance from the start to each stop, as the crow flies between stops.
    var marks: [Double] {
        var total = 0.0
        return stops.indices.map { index in
            if index > 0 {
                total += CLLocation(latitude: stops[index - 1].latitude, longitude: stops[index - 1].longitude)
                    .distance(from: CLLocation(latitude: stops[index].latitude, longitude: stops[index].longitude))
            }
            return total
        }
    }

    var length: Double { marks.last ?? 0 }

    /// The line from the start to `distance` along the route, ending exactly there.
    func path(upTo distance: Double) -> [CLLocationCoordinate2D] {
        let marks = marks
        var path = [stops[0].coordinate]
        for index in 1..<stops.count {
            if marks[index] <= distance {
                path.append(stops[index].coordinate)
            } else {
                let t = (distance - marks[index - 1]) / max(marks[index] - marks[index - 1], 1)
                let a = stops[index - 1], b = stops[index]
                path.append(CLLocationCoordinate2D(latitude: a.latitude + (b.latitude - a.latitude) * t,
                                                   longitude: a.longitude + (b.longitude - a.longitude) * t))
                break
            }
        }
        return path
    }

    static let all: [ClassicRoute] = [canal, highway318, silkRoad, route66]

    static func s(_ name: String, _ nameEn: String, _ lat: Double, _ lon: Double, _ note: String, _ noteEn: String) -> Stop {
        Stop(name: name, nameEn: nameEn, latitude: lat, longitude: lon, note: note, noteEn: noteEn)
    }

    static let canal = ClassicRoute(id: "canal", name: "京杭大运河", nameEn: "The Grand Canal", symbol: "ferry.fill", tint: .teal, stops: [
        s("杭州", "Hangzhou", 30.27, 120.16, "运河的南端，拱宸桥下船来船往了几百年。", "The canal's southern end; boats have passed under Gongchen Bridge for centuries."),
        s("嘉兴", "Jiaxing", 30.75, 120.76, "南湖烟雨，一船红色的历史。", "Misty South Lake and a boat full of history."),
        s("苏州", "Suzhou", 31.30, 120.59, "枫桥夜泊，园林里藏着整个江南。", "Maple Bridge at night, and gardens that hold all of Jiangnan."),
        s("无锡", "Wuxi", 31.49, 120.31, "太湖边的清名桥，运河人家枕水而居。", "Qingming Bridge by Lake Tai, homes built over the water."),
        s("常州", "Changzhou", 31.81, 119.97, "老城门外，运河穿城而过。", "The canal runs right through the old town."),
        s("镇江", "Zhenjiang", 32.19, 119.43, "运河在这里与长江相遇。", "Here the canal meets the Yangtze."),
        s("扬州", "Yangzhou", 32.39, 119.41, "烟花三月下扬州，瘦西湖最温柔。", "Yangzhou in spring, and gentle Slender West Lake."),
        s("淮安", "Huai'an", 33.61, 119.02, "南船北马的分界，漕运总督曾在这里。", "Where boats gave way to horses; the grain-transport governor sat here."),
        s("徐州", "Xuzhou", 34.26, 117.18, "五省通衢，楚汉故地。", "Crossroads of five provinces, homeland of the Han."),
        s("济宁", "Jining", 35.41, 116.59, "运河之都，离孔子的家乡很近。", "Capital of the canal, close to Confucius's hometown."),
        s("聊城", "Liaocheng", 36.46, 115.99, "江北水城，光岳楼守着东昌湖。", "A water town north of the river, Guangyue Tower over Dongchang Lake."),
        s("德州", "Dezhou", 37.44, 116.36, "九达天衢，扒鸡的香味飘了几百年。", "Nine roads meet here, and its braised chicken is centuries old."),
        s("沧州", "Cangzhou", 38.30, 116.84, "武术之乡，铁狮子还在。", "Home of martial arts, where the iron lion still stands."),
        s("天津", "Tianjin", 39.13, 117.20, "三岔河口，九河下梢。", "Where three rivers meet, at the foot of nine."),
        s("北京通州", "Tongzhou, Beijing", 39.91, 116.66, "运河的北端，燃灯塔下，一路走到了终点。", "The northern end, under Randeng Pagoda. You made it."),
    ])

    static let highway318 = ClassicRoute(id: "318", name: "318 国道", nameEn: "China National Highway 318", symbol: "road.lanes", tint: .orange, stops: [
        s("上海", "Shanghai", 31.23, 121.47, "零公里，从人民广场出发。", "Kilometre zero, from People's Square."),
        s("宣城", "Xuancheng", 30.94, 118.76, "宣纸的故乡，敬亭山相看两不厌。", "Home of Xuan paper and Jingting Mountain."),
        s("武汉", "Wuhan", 30.59, 114.31, "过长江，黄鹤楼上看江城。", "Across the Yangtze, the river city from Yellow Crane Tower."),
        s("宜昌", "Yichang", 30.69, 111.29, "三峡的门口，江水从这里变得开阔。", "The gate of the Three Gorges, where the river opens up."),
        s("重庆", "Chongqing", 29.56, 106.55, "山城，路在楼顶，轻轨穿楼。", "The mountain city, roads on rooftops and trains through buildings."),
        s("成都", "Chengdu", 30.57, 104.07, "川藏线从这里真正开始。", "Where the Sichuan–Tibet road really begins."),
        s("雅安", "Ya'an", 29.98, 103.01, "雨城，进藏前最后的温柔。", "The rain city, the last soft place before Tibet."),
        s("康定", "Kangding", 30.05, 101.96, "跑马溜溜的山上，折多山在等你。", "The town of the love song; Zheduo Pass waits above."),
        s("理塘", "Litang", 30.00, 100.27, "世界高城，天空近得伸手可及。", "One of the world's highest towns, the sky close enough to touch."),
        s("巴塘", "Batang", 30.00, 99.10, "金沙江畔，过江就是西藏。", "On the Jinsha River; across it is Tibet."),
        s("芒康", "Markam", 29.68, 98.59, "进藏第一站，盐井的盐田在澜沧江边。", "First stop in Tibet; salt terraces by the Lancang."),
        s("八宿", "Baxoi", 30.05, 96.92, "怒江七十二拐，一圈一圈绕下去。", "The 72 bends down to the Nu River."),
        s("然乌", "Rawu", 29.50, 96.77, "然乌湖倒映着雪山。", "Rawu Lake mirrors the snow peaks."),
        s("波密", "Bomê", 29.86, 95.77, "冰川和森林，西藏的江南。", "Glaciers and forests, Tibet's Jiangnan."),
        s("林芝", "Nyingchi", 29.65, 94.36, "春天桃花开满雅鲁藏布江。", "Peach blossom along the Yarlung Tsangpo in spring."),
        s("拉萨", "Lhasa", 29.65, 91.13, "布达拉宫就在眼前。你走到了日光城。", "The Potala Palace before you. You reached the city of sunlight."),
    ])

    static let silkRoad = ClassicRoute(id: "silk", name: "丝绸之路", nameEn: "The Silk Road", symbol: "sun.dust.fill", tint: .brown, stops: [
        s("西安", "Xi'an", 34.34, 108.94, "长安，驼队从这里出发。", "Chang'an, where the caravans set out."),
        s("天水", "Tianshui", 34.58, 105.72, "麦积山的佛像看了一千多年的路人。", "Maijishan's Buddhas have watched travellers for 1,500 years."),
        s("兰州", "Lanzhou", 36.06, 103.83, "黄河穿城，一碗牛肉面。", "The Yellow River through town, and a bowl of beef noodles."),
        s("武威", "Wuwei", 37.93, 102.64, "马踏飞燕从这里出土。", "Where the Flying Horse of Gansu was found."),
        s("张掖", "Zhangye", 38.93, 100.45, "七彩丹霞，像打翻了颜料。", "Rainbow mountains, like spilt paint."),
        s("酒泉", "Jiuquan", 39.73, 98.49, "嘉峪关，长城的西端。", "Jiayu Pass, the western end of the Great Wall."),
        s("敦煌", "Dunhuang", 40.14, 94.66, "莫高窟和鸣沙山，月牙泉在沙里。", "Mogao Caves, singing dunes and a crescent spring in the sand."),
        s("吐鲁番", "Turpan", 42.95, 89.19, "火焰山下，葡萄沟里很凉快。", "Below the Flaming Mountains, cool in the grape valley."),
        s("乌鲁木齐", "Ürümqi", 43.83, 87.62, "离海最远的城市。", "The city farthest from any sea."),
        s("喀什", "Kashgar", 39.47, 75.99, "古城的巷子里，馕坑冒着热气。", "Bread ovens steaming in old-town lanes."),
        s("撒马尔罕", "Samarkand", 39.65, 66.96, "雷吉斯坦广场的蓝色穹顶。", "The blue domes of Registan Square."),
        s("布哈拉", "Bukhara", 39.77, 64.42, "两千年的老城，驼队在这里歇脚。", "A two-thousand-year-old town where caravans rested."),
        s("德黑兰", "Tehran", 35.69, 51.39, "厄尔布尔士山下的波斯。", "Persia below the Alborz mountains."),
        s("巴格达", "Baghdad", 33.31, 44.36, "一千零一夜的故乡。", "Home of the Thousand and One Nights."),
        s("大马士革", "Damascus", 33.51, 36.29, "世界上最古老的城市之一。", "One of the oldest cities in the world."),
        s("伊斯坦布尔", "Istanbul", 41.01, 28.98, "欧亚之间，博斯普鲁斯海峡。", "Between Europe and Asia, on the Bosphorus."),
        s("罗马", "Rome", 41.90, 12.50, "条条大路通罗马，丝绸到了终点。", "All roads lead to Rome, and so did the silk."),
    ])

    static let route66 = ClassicRoute(id: "66", name: "66 号公路", nameEn: "Route 66", symbol: "car.side.fill", tint: .red, stops: [
        s("芝加哥", "Chicago", 41.88, -87.63, "起点牌就在密歇根湖边。", "The 'Begin' sign stands near Lake Michigan."),
        s("圣路易斯", "St. Louis", 38.63, -90.20, "大拱门，西部的门户。", "The Gateway Arch, door to the West."),
        s("斯普林菲尔德", "Springfield", 37.21, -93.29, "66 号公路的诞生地。", "Birthplace of Route 66."),
        s("塔尔萨", "Tulsa", 36.15, -95.99, "霓虹和装饰艺术。", "Neon and Art Deco."),
        s("俄克拉何马城", "Oklahoma City", 35.47, -97.52, "牛仔和草原。", "Cowboys and prairie."),
        s("阿马里洛", "Amarillo", 35.22, -101.83, "凯迪拉克牧场，车尾插在地里。", "Cadillac Ranch, tail fins in the dirt."),
        s("阿尔伯克基", "Albuquerque", 35.08, -106.65, "热气球飞过沙漠。", "Balloons over the desert."),
        s("弗拉格斯塔夫", "Flagstaff", 35.20, -111.65, "离大峡谷很近，星空很亮。", "Close to the Grand Canyon, under bright stars."),
        s("金曼", "Kingman", 35.19, -114.05, "公路最长的一段原样路面。", "The longest stretch of the old road."),
        s("巴斯托", "Barstow", 34.90, -117.02, "莫哈韦沙漠的中转站。", "A stop in the Mojave."),
        s("洛杉矶", "Los Angeles", 34.05, -118.24, "天使之城就在眼前。", "The City of Angels ahead."),
        s("圣莫尼卡", "Santa Monica", 34.01, -118.50, "路的尽头是太平洋。你走完了。", "The end of the trail is the Pacific. You made it."),
    ])
}

/// Where the person has got to along a route.
struct JourneyProgress {
    let route: ClassicRoute
    let travelled: Double

    var isComplete: Bool { travelled >= route.length }
    /// How far along the route that puts you; a finished route stays finished.
    var shown: Double { min(travelled, route.length) }
    var fraction: Double { shown / max(route.length, 1) }

    var lastStopIndex: Int { route.marks.lastIndex { $0 <= shown } ?? 0 }
    var lastStop: ClassicRoute.Stop { route.stops[lastStopIndex] }
    var nextStop: ClassicRoute.Stop? { route.stops.indices.contains(lastStopIndex + 1) ? route.stops[lastStopIndex + 1] : nil }
    var toNext: Double { nextStop == nil ? 0 : route.marks[lastStopIndex + 1] - shown }
}

enum JourneyChoice {
    static let key = "journey.route"

    /// The route the person chose; until they choose, the shortest one they haven't finished,
    /// so there is always somewhere still to get to.
    static func route(for id: String, home: HomeBase?, distance: Double) -> ClassicRoute {
        if let route = ClassicRoute.all.first(where: { $0.id == id }) { return route }
        let order: [ClassicRoute] = (home?.countryCode == "US" ? [.route66, .canal, .highway318] : [.canal, .highway318, .route66])
            .sorted { $0.length < $1.length } + [.silkRoad]
        return order.first { $0.length > distance } ?? .silkRoad
    }
}

extension JourneyProgress {
    /// Where you are in "station space": 3.4 is 40% of the way from the fourth stop to the fifth.
    var stationPosition: Double {
        guard nextStop != nil else { return Double(route.stops.count - 1) }
        let marks = route.marks
        let from = marks[lastStopIndex], to = marks[lastStopIndex + 1]
        return Double(lastStopIndex) + (shown - from) / max(to - from, 1)
    }
}

/// The route as a subway line: stations you've passed filled in, the next one ringed, and a
/// little figure walking between them. Scrolls sideways and opens on where you are.
struct MetroLine: View {
    let progress: JourneyProgress
    var spacing: CGFloat = 66

    private var tint: Color { progress.route.tint }

    var body: some View {
        let stops = progress.route.stops
        let width = spacing * CGFloat(stops.count - 1)
        let here = spacing * CGFloat(progress.stationPosition)
        ScrollViewReader { proxy in
            ScrollView(.horizontal) {
                ZStack(alignment: .topLeading) {
                    Capsule().fill(Color.secondary.opacity(0.18))
                        .frame(width: width, height: 6)
                        .offset(y: 37)
                    Capsule().fill(LinearGradient(colors: [tint.opacity(0.7), tint], startPoint: .leading, endPoint: .trailing))
                        .frame(width: max(6, here), height: 6)
                        .offset(y: 37)
                    ForEach(Array(stops.enumerated()), id: \.offset) { index, stop in
                        station(stop, index: index)
                            .frame(width: spacing)
                            .offset(x: spacing * CGFloat(index) - spacing / 2, y: 30)
                            .id(index)
                    }
                    if !progress.isComplete {
                        Image(systemName: "figure.walk")
                            .font(.system(size: 12, weight: .bold))
                            .foregroundStyle(.white)
                            .frame(width: 26, height: 26)
                            .background(Circle().fill(tint.gradient))
                            .overlay(Circle().stroke(.white, lineWidth: 2))
                            .shadow(color: tint.opacity(0.5), radius: 6, y: 2)
                            .offset(x: here - 13, y: 0)
                    }
                }
                .frame(width: width, height: 84, alignment: .topLeading)
                .padding(.horizontal, spacing / 2)
            }
            .scrollIndicators(.hidden)
            .onAppear { proxy.scrollTo(progress.lastStopIndex, anchor: .center) }
        }
    }

    private func station(_ stop: ClassicRoute.Stop, index: Int) -> some View {
        let reached = index <= progress.lastStopIndex
        let isNext = index == progress.lastStopIndex + 1 && !progress.isComplete
        return VStack(spacing: 7) {
            ZStack {
                Circle().fill(reached ? AnyShapeStyle(tint) : AnyShapeStyle(Color(uiColor: .systemBackground)))
                Circle().strokeBorder(reached ? .white : (isNext ? tint : Color.secondary.opacity(0.35)), lineWidth: reached ? 3 : (isNext ? 3 : 2))
            }
            .frame(width: 20, height: 20)
            .shadow(color: reached ? tint.opacity(0.35) : .clear, radius: 3)
            Text(stop.localizedName)
                .font(.caption2.weight(reached || isNext ? .semibold : .regular))
                .foregroundStyle(reached ? .primary : (isNext ? tint : .secondary))
                .lineLimit(1)
                .minimumScaleFactor(0.7)
        }
    }
}

/// The route's own shape, drawn from its stops: a smooth line through them.
struct RouteShape: Shape {
    let points: [CGPoint]

    func path(in rect: CGRect) -> Path {
        let pts = points.map { CGPoint(x: rect.minX + $0.x * rect.width, y: rect.minY + $0.y * rect.height) }
        var path = Path()
        guard let first = pts.first else { return path }
        path.move(to: first)
        for i in 1..<pts.count {
            // Catmull–Rom through the stops, as cubic curves.
            let p0 = pts[max(i - 2, 0)], p1 = pts[i - 1], p2 = pts[i], p3 = pts[min(i + 1, pts.count - 1)]
            let c1 = CGPoint(x: p1.x + (p2.x - p0.x) / 6, y: p1.y + (p2.y - p0.y) / 6)
            let c2 = CGPoint(x: p2.x - (p3.x - p1.x) / 6, y: p2.y - (p3.y - p1.y) / 6)
            path.addCurve(to: p2, control1: c1, control2: c2)
        }
        return path
    }
}

extension ClassicRoute {
    /// The stops placed in a unit square, keeping the route's shape, with a margin.
    func layout(aspect: CGFloat, margin: CGFloat = 0.12) -> [CGPoint] {
        let midLat = stops.map(\.latitude).reduce(0, +) / Double(stops.count)
        let raw = stops.map { CGPoint(x: $0.longitude * cos(midLat * .pi / 180), y: -$0.latitude) }
        let minX = raw.map(\.x).min()!, maxX = raw.map(\.x).max()!, minY = raw.map(\.y).min()!, maxY = raw.map(\.y).max()!
        let spanX = max(maxX - minX, 0.01), spanY = max(maxY - minY, 0.01)
        let fitX = (1 - 2 * margin) / spanX, fitY = (1 - 2 * margin) * aspect / spanY
        let scale = min(fitX, fitY)
        // A road running mostly east–west would be a thin line; let north–south stretch up to
        // five times, as a poster would, so the route fills its frame below the title.
        let scaleY = min(fitY, scale * 5)
        let offX = (1 - spanX * scale) / 2, offY = (1 - spanY * scaleY / aspect) / 2 + margin * 0.5
        return raw.map { CGPoint(x: offX + ($0.x - minX) * scale, y: offY + ($0.y - minY) * scaleY / aspect) }
    }
}

/// The route as art: its line glowing on a dark field, the part you've walked lit in its
/// colour, every stop a point of light.
struct JourneyRouteArt: View {
    let progress: JourneyProgress
    /// 0…1 of the walked part, animated by the page.
    var drawn: Double

    var body: some View {
        GeometryReader { geo in
            let route = progress.route
            let points = route.layout(aspect: geo.size.width / max(geo.size.height, 1))
            // How far along the drawn line you are, measured on the line itself.
            let lengths = zip(points, points.dropFirst()).map { hypot(($1.x - $0.x) * geo.size.width, ($1.y - $0.y) * geo.size.height) }
            let total = max(lengths.reduce(0, +), 1)
            let position = progress.stationPosition
            let whole = Int(position)
            let walked = lengths.prefix(whole).reduce(0, +) + (whole < lengths.count ? lengths[whole] * (position - Double(whole)) : 0)
            let fraction = walked / total
            ZStack(alignment: .topLeading) {
                LinearGradient(colors: [Color(red: 0.05, green: 0.06, blue: 0.12), Color(red: 0.1, green: 0.1, blue: 0.2)], startPoint: .top, endPoint: .bottom)
                RadialGradient(colors: [route.tint.opacity(0.35), .clear], center: .center, startRadius: 10, endRadius: geo.size.width * 0.7)
                RouteShape(points: points)
                    .stroke(.white.opacity(0.22), style: StrokeStyle(lineWidth: 2, lineCap: .round, dash: [2, 6]))
                RouteShape(points: points)
                    .trim(from: 0, to: drawn * fraction)
                    .stroke(route.tint, style: StrokeStyle(lineWidth: 10, lineCap: .round, lineJoin: .round))
                    .blur(radius: 8)
                    .opacity(0.8)
                RouteShape(points: points)
                    .trim(from: 0, to: drawn * fraction)
                    .stroke(LinearGradient(colors: [route.tint.opacity(0.8), .white], startPoint: .leading, endPoint: .trailing),
                            style: StrokeStyle(lineWidth: 3.5, lineCap: .round, lineJoin: .round))
                ForEach(Array(points.enumerated()), id: \.offset) { index, point in
                    let reached = Double(index) <= progress.stationPosition * drawn + 0.001
                    let showName = index == 0 || index == route.stops.count - 1 || index == progress.lastStopIndex || index == progress.lastStopIndex + 1
                    ZStack {
                        Circle().fill(reached ? .white : .white.opacity(0.3)).frame(width: reached ? 7 : 5, height: reached ? 7 : 5)
                            .shadow(color: reached ? route.tint : .clear, radius: 4)
                        if showName {
                            Text(route.stops[index].localizedName)
                                .font(.system(size: 11, weight: .semibold))
                                .foregroundStyle(.white.opacity(reached ? 0.95 : 0.6))
                                .fixedSize()
                                .offset(y: 13)
                        }
                    }
                    .position(x: point.x * geo.size.width, y: point.y * geo.size.height)
                }
                VStack(alignment: .leading, spacing: 4) {
                    Label(route.localizedName, systemImage: route.symbol)
                        .font(.system(size: 26, weight: .bold, design: .serif))
                        .labelStyle(.titleOnly)
                    Text("全程 \(Format.distance(route.length)) · \(route.stops.count) 站")
                        .font(.caption.weight(.medium)).tracking(1).opacity(0.7)
                }
                .foregroundStyle(.white)
                .padding(20)
            }
        }
    }
}

/// "你已经走到了哪里", for the Stats tab.
struct JourneyCard: View {
    let distance: Double
    let home: HomeBase?
    @AppStorage(JourneyChoice.key) private var routeID = ""

    var body: some View {
        let progress = JourneyProgress(route: JourneyChoice.route(for: routeID, home: home, distance: distance), travelled: distance)
        let tint = progress.route.tint
        NavigationLink(value: JourneyRoute()) {
            VStack(alignment: .leading, spacing: 14) {
                HStack(alignment: .top) {
                    VStack(alignment: .leading, spacing: 5) {
                        Text("你已经走到了哪里").font(.caption.weight(.semibold)).foregroundStyle(.secondary)
                        Text(progress.isComplete ? String(localized: "你走完了\(progress.route.localizedName)", bundle: .appLanguage)
                                                 : String(localized: "你走到了\(progress.lastStop.localizedName)", bundle: .appLanguage))
                            .font(.system(.title2, design: .serif, weight: .bold))
                            .foregroundStyle(.primary)
                        Text("沿着\(progress.route.localizedName)")
                            .font(.footnote.weight(.semibold)).foregroundStyle(tint)
                    }
                    Spacer()
                    VStack(alignment: .trailing, spacing: 0) {
                        Text(progress.fraction.formatted(.percent.precision(.fractionLength(0)).locale(appLocale)))
                            .font(.system(size: 30, weight: .bold, design: .rounded)).foregroundStyle(tint).monospacedDigit()
                        Text("已走").font(.caption2).foregroundStyle(.secondary)
                    }
                }
                MetroLine(progress: progress)
                    .frame(height: 84)
                    .padding(.horizontal, -18)
                HStack {
                    Text("\(Format.distance(progress.shown)) / \(Format.distance(progress.route.length))").monospacedDigit()
                    Spacer()
                    if let next = progress.nextStop {
                        Text("下一站\(next.localizedName) · \(Format.distance(progress.toNext))")
                    }
                }
                .font(.footnote).foregroundStyle(.secondary)
            }
            .padding(18)
            .background {
                RoundedRectangle(cornerRadius: 28, style: .continuous).fill(.background.secondary)
                    .overlay(alignment: .topTrailing) {
                        Circle().fill(tint.opacity(0.14)).frame(width: 220).blur(radius: 50).offset(x: 60, y: -80)
                    }
                    .clipShape(.rect(cornerRadius: 28, style: .continuous))
            }
        }
        .buttonStyle(PressableStyle())
    }
}

/// The whole road: drawn as art, the route to choose, and every stop with its story.
struct JourneyView: View {
    let distance: Double
    let home: HomeBase?
    @AppStorage(JourneyChoice.key) private var routeID = ""
    /// Grows from nothing to where you are when the page opens.
    @State private var drawn = 0.0

    private var route: ClassicRoute { JourneyChoice.route(for: routeID, home: home, distance: distance) }

    var body: some View {
        let progress = JourneyProgress(route: route, travelled: distance)
        ScrollView {
            VStack(alignment: .leading, spacing: 22) {
                JourneyRouteArt(progress: progress, drawn: drawn)
                    .frame(height: 320)
                    .clipShape(.rect(cornerRadius: 28, style: .continuous))
                numbers(progress)
                routePicker
                VStack(alignment: .leading, spacing: 0) {
                    ForEach(Array(route.stops.enumerated()), id: \.offset) { index, stop in
                        stopRow(stop, index: index, progress: progress)
                    }
                }
                Text("你在地面上走过的路（不含飞行），按城市之间的直线距离铺在这条路上。")
                    .font(.footnote).foregroundStyle(.secondary)
            }
            .padding(.horizontal)
            .padding(.bottom, 32)
        }
        .navigationTitle(route.localizedName)
        .navigationBarTitleDisplayMode(.inline)
        .task(id: route.id) {
            drawn = 0
            try? await Task.sleep(for: .milliseconds(150))
            withAnimation(.easeOut(duration: 1.6)) { drawn = 1 }
        }
        .sensoryFeedback(.selection, trigger: route.id)
    }

    private func numbers(_ progress: JourneyProgress) -> some View {
        HStack(spacing: 0) {
            figure(Format.distance(progress.shown), "已走")
            Divider().frame(height: 34)
            figure(progress.fraction.formatted(.percent.precision(.fractionLength(0)).locale(appLocale)), "完成")
            Divider().frame(height: 34)
            figure("\(progress.lastStopIndex + 1) / \(route.stops.count)", "到达的站")
        }
        .padding(.vertical, 14)
        .background(.background.secondary, in: .rect(cornerRadius: 20, style: .continuous))
    }

    private func figure(_ value: String, _ label: LocalizedStringKey) -> some View {
        VStack(spacing: 3) {
            Text(value).font(.system(.title3, design: .rounded, weight: .bold)).monospacedDigit().lineLimit(1).minimumScaleFactor(0.7)
            Text(label).font(.caption).foregroundStyle(.secondary)
        }
        .frame(maxWidth: .infinity)
    }

    /// The four roads as small cards, each drawn in its own shape.
    private var routePicker: some View {
        ScrollView(.horizontal) {
            HStack(spacing: 10) {
                ForEach(ClassicRoute.all) { option in
                    let selected = option.id == route.id
                    Button {
                        withAnimation(.snappy) { routeID = option.id }
                    } label: {
                        VStack(alignment: .leading, spacing: 6) {
                            RouteShape(points: option.layout(aspect: 120 / 44, margin: 0.08))
                                .stroke(option.tint, style: StrokeStyle(lineWidth: 2.5, lineCap: .round, lineJoin: .round))
                                .frame(width: 120, height: 44)
                            Text(option.localizedName).font(.footnote.weight(.semibold)).foregroundStyle(.primary)
                            HStack(spacing: 4) {
                                Text(Format.distance(option.length))
                                if distance >= option.length { Image(systemName: "checkmark.seal.fill").foregroundStyle(option.tint) }
                            }
                            .font(.caption2).foregroundStyle(.secondary)
                        }
                        .padding(12)
                        .background(.background.secondary, in: .rect(cornerRadius: 18, style: .continuous))
                        .overlay(RoundedRectangle(cornerRadius: 18, style: .continuous)
                            .strokeBorder(selected ? option.tint : .clear, lineWidth: 2))
                    }
                    .buttonStyle(PressableStyle())
                }
            }
        }
        .scrollIndicators(.hidden)
        .scrollClipDisabled()
    }

    private func stopRow(_ stop: ClassicRoute.Stop, index: Int, progress: JourneyProgress) -> some View {
        let reached = index <= progress.lastStopIndex
        let isNext = index == progress.lastStopIndex + 1 && !progress.isComplete
        let isLast = index == route.stops.count - 1
        return HStack(alignment: .top, spacing: 14) {
            VStack(spacing: 0) {
                ZStack {
                    Circle().fill(reached ? AnyShapeStyle(route.tint) : AnyShapeStyle(Color(uiColor: .systemBackground)))
                    Circle().strokeBorder(reached ? .white : (isNext ? route.tint : Color.secondary.opacity(0.35)), lineWidth: 3)
                }
                .frame(width: 20, height: 20)
                .shadow(color: reached ? route.tint.opacity(0.4) : .clear, radius: 3)
                if !isLast {
                    Rectangle()
                        .fill(index < progress.lastStopIndex ? AnyShapeStyle(route.tint) : AnyShapeStyle(Color.secondary.opacity(0.18)))
                        .frame(width: 4)
                        .frame(maxHeight: .infinity)
                }
            }
            .frame(width: 24)
            VStack(alignment: .leading, spacing: 4) {
                HStack(alignment: .firstTextBaseline, spacing: 8) {
                    Text(stop.localizedName)
                        .font(.system(.body, design: .serif, weight: .semibold))
                        .foregroundStyle(reached || isNext ? .primary : .secondary)
                    if index == progress.lastStopIndex && !progress.isComplete {
                        Text("你在这里").font(.caption2.weight(.bold)).foregroundStyle(.white)
                            .padding(.horizontal, 7).padding(.vertical, 2).background(route.tint, in: .capsule)
                    } else if isNext {
                        Text("下一站 · \(Format.distance(progress.toNext))").font(.caption2.weight(.semibold)).foregroundStyle(route.tint)
                    }
                    Spacer()
                    Text(index == 0 ? String(localized: "起点", bundle: .appLanguage) : Format.distance(route.marks[index]))
                        .font(.caption).foregroundStyle(.tertiary).monospacedDigit()
                }
                Text(stop.localizedNote).font(.subheadline).foregroundStyle(reached ? .secondary : .tertiary)
            }
            .padding(.bottom, 24)
        }
    }
}

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

/// The road drawn on a map: the part travelled bright, the rest dashed, and you on it.
struct JourneyMap: View {
    let route: ClassicRoute
    let distance: Double
    var interactive = false

    var body: some View {
        let done = route.path(upTo: distance)
        Map(initialPosition: .rect(rect), interactionModes: interactive ? .all : []) {
            MapPolyline(coordinates: route.stops.map(\.coordinate))
                .stroke(.white.opacity(0.85), style: StrokeStyle(lineWidth: 3, lineCap: .round, dash: [4, 6]))
            if done.count > 1 {
                MapPolyline(coordinates: done)
                    .stroke(.white, style: StrokeStyle(lineWidth: 8, lineCap: .round, lineJoin: .round))
                MapPolyline(coordinates: done)
                    .stroke(route.tint.gradient, style: StrokeStyle(lineWidth: 5, lineCap: .round, lineJoin: .round))
            }
            ForEach(Array(route.stops.enumerated()), id: \.offset) { index, stop in
                let reached = route.marks[index] <= distance
                Annotation(interactive ? stop.localizedName : "", coordinate: stop.coordinate) {
                    Circle()
                        .fill(reached ? AnyShapeStyle(route.tint.gradient) : AnyShapeStyle(Color.gray.opacity(0.6)))
                        .frame(width: reached ? 12 : 8, height: reached ? 12 : 8)
                        .overlay(Circle().stroke(.white, lineWidth: 2))
                }
            }
            if let here = done.last {
                Annotation("", coordinate: here) {
                    Image(systemName: "figure.walk")
                        .font(.system(size: 13, weight: .bold))
                        .foregroundStyle(.white)
                        .frame(width: 30, height: 30)
                        .background(Circle().fill(route.tint.gradient))
                        .overlay(Circle().stroke(.white, lineWidth: 2.5))
                        .shadow(color: .black.opacity(0.25), radius: 4, y: 2)
                }
            }
        }
        .mapStyle(.standard(elevation: .flat, emphasis: .muted, pointsOfInterest: .excludingAll))
    }

    private var rect: MKMapRect {
        var rect = MKMapRect.null
        for stop in route.stops { rect = rect.union(MKMapRect(origin: MKMapPoint(stop.coordinate), size: MKMapSize(width: 0, height: 0))) }
        let pad = max(rect.width, rect.height) * 0.18
        return rect.insetBy(dx: -pad, dy: -pad)
    }
}

/// "你已经走到了哪里", for the Stats tab.
struct JourneyCard: View {
    let distance: Double
    let home: HomeBase?
    @AppStorage(JourneyChoice.key) private var routeID = ""

    var body: some View {
        let progress = JourneyProgress(route: JourneyChoice.route(for: routeID, home: home, distance: distance), travelled: distance)
        NavigationLink(value: JourneyRoute()) {
            VStack(alignment: .leading, spacing: 12) {
                HStack(alignment: .firstTextBaseline) {
                    Text("你已经走到了哪里").font(.title3.bold()).foregroundStyle(.primary)
                    Spacer()
                    Image(systemName: "chevron.forward").font(.footnote.weight(.semibold)).foregroundStyle(.tertiary)
                }
                JourneyMap(route: progress.route, distance: progress.shown)
                    .frame(height: 170)
                    .clipShape(.rect(cornerRadius: 18, style: .continuous))
                    .allowsHitTesting(false)
                JourneyLine(progress: progress)
            }
            .padding(16)
            .background(.background.secondary, in: .rect(cornerRadius: 24, style: .continuous))
        }
        .buttonStyle(PressableStyle())
    }
}

/// Where you've got to, in words, with a bar under it.
struct JourneyLine: View {
    let progress: JourneyProgress

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            if progress.isComplete {
                Text("你走完了\(progress.route.localizedName)").font(.headline).foregroundStyle(.primary)
                Text("一共 \(Format.distance(progress.route.length))。换一条路，继续走吧。")
                    .font(.subheadline).foregroundStyle(.secondary)
            } else {
                Text("沿着\(progress.route.localizedName)，你走到了\(progress.lastStop.localizedName)")
                    .font(.headline).foregroundStyle(.primary)
                if let next = progress.nextStop {
                    Text("离下一站\(next.localizedName)还有 \(Format.distance(progress.toNext))")
                        .font(.subheadline).foregroundStyle(.secondary)
                }
            }
            ProgressView(value: progress.fraction).tint(progress.route.tint)
        }
        .multilineTextAlignment(.leading)
    }
}

/// The whole road: a map to explore, the route to choose, and every stop with its story.
struct JourneyView: View {
    let distance: Double
    let home: HomeBase?
    @AppStorage(JourneyChoice.key) private var routeID = ""
    /// Grows from nothing to where you are when the page opens.
    @State private var shown = 0.0

    private var route: ClassicRoute { JourneyChoice.route(for: routeID, home: home, distance: distance) }

    var body: some View {
        let progress = JourneyProgress(route: route, travelled: distance)
        ScrollView {
            VStack(alignment: .leading, spacing: 20) {
                JourneyMap(route: route, distance: shown, interactive: true)
                    .id(route.id)
                    .frame(height: 340)
                    .clipShape(.rect(cornerRadius: 24, style: .continuous))
                Text("你在地面上走过的 \(Format.distance(distance))，铺在\(route.localizedName)上。")
                    .font(.subheadline).foregroundStyle(.secondary)
                JourneyLine(progress: progress)
                VStack(alignment: .leading, spacing: 0) {
                    ForEach(Array(route.stops.enumerated()), id: \.offset) { index, stop in
                        stopRow(stop, index: index, progress: progress)
                    }
                }
            }
            .padding(.horizontal)
            .padding(.bottom, 32)
        }
        .navigationTitle(route.localizedName)
        .navigationBarTitleDisplayMode(.inline)
        .toolbar {
            ToolbarItem(placement: .topBarTrailing) {
                Menu {
                    Picker("路线", selection: Binding(get: { route.id }, set: { routeID = $0 })) {
                        ForEach(ClassicRoute.all) { route in
                            Label("\(route.localizedName) · \(Format.distance(route.length))", systemImage: route.symbol).tag(route.id)
                        }
                    }
                } label: {
                    Label("换一条路", systemImage: "arrow.triangle.swap")
                }
            }
        }
        .task(id: route.id) { await grow(to: progress.shown) }
        .sensoryFeedback(.success, trigger: route.id)
    }

    private func stopRow(_ stop: ClassicRoute.Stop, index: Int, progress: JourneyProgress) -> some View {
        let reached = route.marks[index] <= progress.shown
        let isLast = index == route.stops.count - 1
        return HStack(alignment: .top, spacing: 14) {
            VStack(spacing: 0) {
                Circle()
                    .fill(reached ? AnyShapeStyle(route.tint.gradient) : AnyShapeStyle(Color.secondary.opacity(0.25)))
                    .frame(width: 14, height: 14)
                    .overlay {
                        if index == progress.lastStopIndex && !progress.isComplete {
                            Circle().stroke(route.tint.opacity(0.4), lineWidth: 6).frame(width: 24, height: 24)
                        }
                    }
                    .padding(.top, 4)
                if !isLast {
                    Rectangle()
                        .fill(route.marks[index + 1] <= progress.shown ? AnyShapeStyle(route.tint) : AnyShapeStyle(Color.secondary.opacity(0.2)))
                        .frame(width: 2)
                        .frame(maxHeight: .infinity)
                }
            }
            .frame(width: 24)
            VStack(alignment: .leading, spacing: 3) {
                HStack(alignment: .firstTextBaseline) {
                    Text(stop.localizedName).font(.body.weight(.semibold)).foregroundStyle(reached ? .primary : .secondary)
                    Spacer()
                    Text(index == 0 ? String(localized: "起点", bundle: .appLanguage) : Format.distance(route.marks[index]))
                        .font(.caption).foregroundStyle(.tertiary).monospacedDigit()
                }
                Text(stop.localizedNote).font(.subheadline).foregroundStyle(reached ? .secondary : .tertiary)
            }
            .padding(.bottom, 22)
        }
    }

    private func grow(to target: Double) async {
        shown = 0
        let steps = 40
        for step in 1...steps {
            try? await Task.sleep(for: .milliseconds(30))
            let t = Double(step) / Double(steps)
            shown = target * (1 - pow(1 - t, 3))
        }
    }
}

import SwiftUI

struct LightUpRoute: Hashable {}

/// The passport and the stamp book: border stamps for countries, seals for China's provinces
/// and a stamp for every city, each pressed the first time it's seen.
struct LightUpView: View {
    private var summaries = PlaceSummaries.shared
    private var insights: LightUpInsights { summaries.lightUp }
    private var book: StampBook { summaries.stamps }
    @State private var scope = Scope.passport
    @State private var openProvince: Province?
    @State private var openCountry: CountrySummary?
    @State private var shareImage: Image?

    enum Scope: Hashable { case passport, provinces, cities, keepsakes }

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 18) {
                Picker("范围", selection: $scope.animation(.snappy)) {
                    Text("护照").tag(Scope.passport)
                    Text("省份").tag(Scope.provinces)
                    Text("城市").tag(Scope.cities)
                    Text("纪念").tag(Scope.keepsakes)
                }
                .pickerStyle(.segmented)

                switch scope {
                case .passport: world
                case .provinces: china
                case .cities: cities
                case .keepsakes: CommemorativeView(book: book)
                }
            }
            .padding(.horizontal)
            .padding(.bottom, 24)
        }
        .navigationTitle("护照与印章")
        .navigationBarTitleDisplayMode(.inline)
        .navigationDestination(item: $openCountry) { CountryDetailView(country: $0) }
        .toolbar {
            if let shareImage, scope == .provinces {
                ToolbarItem(placement: .topBarTrailing) {
                    ShareLink(item: shareImage, preview: SharePreview(String(localized: "我的省份印", bundle: .appLanguage), image: shareImage)) {
                        Label("分享", systemImage: "square.and.arrow.up")
                    }
                }
            }
        }
        // Unlit provinces have nothing to open yet: a gentle note instead of an empty page.
        .sheet(item: $openProvince) { province in
            ContentUnavailableView {
                Label {
                    Text("还没盖上“\(ProvinceSeal.character(for: province.id))”")
                } icon: {
                    ProvinceSealArt(id: province.id)
                        .frame(width: 64, height: 64)
                        .inkWorn(seed: StampSeed.of(province.id), inked: false)
                }
            } description: {
                Text("去过\(province.name)之后，这枚印会盖上。")
            }
            .presentationDetents([.height(300)])
        }
        .task(id: insights.provinces.count + insights.countries.count) { renderShareImage() }
    }

    // MARK: Cities

    @ViewBuilder
    private var cities: some View {
        if book.cities.isEmpty {
            ContentUnavailableView("还没有城市章", systemImage: "seal",
                                   description: Text("每到一座新城市，就会得到一枚它的纪念章，中间印着你那天走过的路。"))
        } else {
            ProgressHeader(lit: book.cities.count, total: nil, title: "收集的城市章", tint: .indigo,
                           detail: String(localized: "中间的线条，是你第一天在那里走过的路", bundle: .appLanguage))
            CityStampBook(book: book)
        }
    }

    // MARK: China

    private var china: some View {
        VStack(alignment: .leading, spacing: 18) {
            ProgressHeader(lit: insights.provinces.count, total: Province.all.count,
                           title: "盖上的省份印", tint: Ink.cinnabar.color)
            ProvinceTileMap(insights: insights, linksLitTiles: true, animates: true) { openProvince = $0 }
                .padding(14)
                .background { StampPaper(style: .seals) }
                .clipShape(.rect(cornerRadius: 24, style: .continuous))
            if !litProvinces.isEmpty {
                VStack(spacing: 0) {
                    ForEach(litProvinces, id: \.province.id) { item in
                        NavigationLink(value: item.province) {
                            HStack(spacing: 12) {
                                StampArt(stamp: Stamp(id: "province.\(item.province.id)", kind: .province, date: item.visit.firstVisit,
                                                      provinceID: item.province.id))
                                    .frame(width: 30, height: 30)
                                Text(item.province.name).font(.body.weight(.semibold))
                                // Municipalities are their own city; don't say "上海 上海".
                                Text(item.visit.topCities.filter { $0 != item.province.name && $0 != item.province.chineseName }
                                        .prefix(3).joined(separator: "、"))
                                    .font(.subheadline).foregroundStyle(.secondary).lineLimit(1)
                                Spacer()
                                Text("\(item.visit.days.count) 天").font(.subheadline).foregroundStyle(.secondary).monospacedDigit()
                                Image(systemName: "chevron.right").font(.caption.weight(.semibold)).foregroundStyle(.tertiary)
                            }
                            .padding(.horizontal, 16).padding(.vertical, 12)
                            .contentShape(.rect)
                        }
                        .buttonStyle(.plain)
                        if item.province.id != litProvinces.last?.province.id { Divider().padding(.leading, 16) }
                    }
                }
                .background(.background.secondary, in: .rect(cornerRadius: 22, style: .continuous))
            }
        }
    }

    private var litProvinces: [(province: Province, visit: LightUpInsights.Visit)] {
        Province.all.compactMap { p in insights.provinces[p.id].map { (p, $0) } }
            .sorted { $0.visit.days.count > $1.visit.days.count }
    }

    // MARK: World

    private var world: some View {
        VStack(alignment: .leading, spacing: 18) {
            PassportBook(book: book) { stamp in
                openCountry = summaries.world.countries.first { $0.code == stamp.countryCode }
            }
            ProgressHeader(lit: insights.countries.count, total: Continent.all.reduce(0) { $0 + $1.regions.count },
                           title: "去过的国家和地区", tint: .red,
                           detail: String(localized: "跨越 \(insights.continentsVisited) 个大洲", bundle: .appLanguage))
            ForEach(continents) { continent in
                FlagWall(continent: continent, visited: insights.countries, countries: summaries.world.countries)
            }
        }
    }

    /// Continents with visits first, the rest in a stable order.
    private var continents: [Continent] {
        Continent.all.sorted {
            let a = $0.regions.filter(insights.countries.contains).count, b = $1.regions.filter(insights.countries.contains).count
            return a != b ? a > b : $0.id < $1.id
        }
    }

    // MARK: Sharing

    @MainActor
    private func renderShareImage() {
        let card = LightUpShareCard(insights: insights)
            .frame(width: 390)
            .environment(\.locale, appLocale)
        let renderer = ImageRenderer(content: card)
        renderer.scale = 3
        shareImage = renderer.uiImage.map { Image(uiImage: $0) }
    }
}

private struct ProgressHeader: View {
    let lit: Int
    /// Nil when there's no whole to count towards, like cities.
    let total: Int?
    let title: LocalizedStringKey
    let tint: Color
    var detail: String?

    var body: some View {
        HStack(spacing: 16) {
            if let total {
                ZStack {
                    Circle().stroke(tint.opacity(0.15), lineWidth: 8)
                    Circle()
                        .trim(from: 0, to: total > 0 ? CGFloat(lit) / CGFloat(total) : 0)
                        .stroke(tint.gradient, style: StrokeStyle(lineWidth: 8, lineCap: .round))
                        .rotationEffect(.degrees(-90))
                    Text("\(Int((Double(lit) / Double(max(total, 1)) * 100).rounded()))%")
                        .font(.system(.subheadline, design: .rounded, weight: .semibold))
                }
                .frame(width: 64, height: 64)
            }
            VStack(alignment: .leading, spacing: 2) {
                Text(title).font(.subheadline).foregroundStyle(.secondary)
                HStack(alignment: .firstTextBaseline, spacing: 4) {
                    Text("\(lit)").font(.system(size: 34, weight: .bold, design: .rounded)).contentTransition(.numericText())
                    if let total { Text("/ \(total)").font(.title3).foregroundStyle(.secondary) }
                }
                if let detail { Text(detail).font(.footnote).foregroundStyle(.secondary) }
            }
            Spacer()
        }
        .padding(16)
        .background(.background.secondary, in: .rect(cornerRadius: 24, style: .continuous))
    }
}

/// The 34 divisions as seals placed roughly where they are: pressed in red where you've been,
/// a faint outline waiting where you haven't. Drawn on its own paper.
struct ProvinceTileMap: View {
    let insights: LightUpInsights
    /// Off for the small preview, where the outlines would be too small to read.
    var showsLabels = true
    /// Lit tiles open the province page; the rest call `onSelect`.
    var linksLitTiles = false
    /// Seals not seen before are pressed in one by one. Off where the map is rendered to an image.
    var animates = false
    var onSelect: (Province) -> Void = { _ in }

    var body: some View {
        GeometryReader { proxy in
            let spacing: CGFloat = showsLabels ? 6 : 3
            let side = (proxy.size.width - spacing * CGFloat(Province.columns - 1)) / CGFloat(Province.columns)
            ZStack(alignment: .topLeading) {
                ForEach(Province.all) { province in
                    let visit = insights.provinces[province.id]
                    Group {
                        if linksLitTiles && visit != nil {
                            NavigationLink(value: province) { tile(province, visit: visit, side: side) }
                        } else {
                            Button { onSelect(province) } label: { tile(province, visit: visit, side: side) }
                        }
                    }
                    .buttonStyle(PressableStyle())
                    .accessibilityLabel(province.name)
                    .accessibilityValue(visit.map { String(localized: "去过 \($0.days.count) 天", bundle: .appLanguage) }
                                        ?? String(localized: "还没去过", bundle: .appLanguage))
                    .offset(x: CGFloat(province.column) * (side + spacing), y: CGFloat(province.row) * (side + spacing))
                }
            }
        }
        .aspectRatio(CGFloat(Province.columns) / CGFloat(Province.rows), contentMode: .fit)
    }

    @ViewBuilder
    private func tile(_ province: Province, visit: LightUpInsights.Visit?, side: CGFloat) -> some View {
        if let visit {
            let stamp = Stamp(id: "province.\(province.id)", kind: .province, date: visit.firstVisit, provinceID: province.id)
            let seal = StampArt(stamp: stamp).frame(width: side, height: side)
            if animates {
                seal.stampIn(stamp, delay: 0.25 + Double(province.row + province.column) * 0.07, tilt: stamp.tilt * 0.35)
            } else {
                seal.rotationEffect(.degrees(stamp.tilt * 0.35))
            }
        } else {
            RoundedRectangle(cornerRadius: side * 0.16, style: .continuous)
                .stroke(StampPaper.line, style: StrokeStyle(lineWidth: 1, dash: [3, 2.5]))
                .overlay {
                    if showsLabels {
                        Text(ProvinceSeal.character(for: province.id))
                            .font(.system(size: side * 0.5, weight: .heavy))
                            .foregroundStyle(StampPaper.line)
                    }
                }
                .frame(width: side, height: side)
        }
    }
}

private struct FlagWall: View {
    let continent: Continent
    let visited: Set<String>
    let countries: [CountrySummary]

    private var litCount: Int { continent.regions.filter(visited.contains).count }

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            HStack(alignment: .firstTextBaseline) {
                Text(continent.name).font(.headline)
                Spacer()
                Text("\(litCount) / \(continent.regions.count)").font(.subheadline).foregroundStyle(.secondary).monospacedDigit()
            }
            ProgressView(value: Double(litCount), total: Double(max(continent.regions.count, 1)))
                .tint(.red)
            LazyVGrid(columns: [GridItem(.adaptive(minimum: 34), spacing: 6)], spacing: 6) {
                ForEach(continent.regions, id: \.self) { code in
                    let lit = visited.contains(code)
                    let flag = Text(String.flag(for: code))
                        .font(.system(size: 26))
                        .grayscale(lit ? 0 : 1)
                        .opacity(lit ? 1 : 0.22)
                    Group {
                        if let country = countries.first(where: { $0.code == code }) {
                            NavigationLink(value: country) { flag }.buttonStyle(PressableStyle())
                        } else {
                            flag
                        }
                    }
                        .accessibilityLabel(appLocale.localizedString(forRegionCode: code) ?? code)
                        .accessibilityValue(lit ? String(localized: "去过", bundle: .appLanguage) : String(localized: "还没去过", bundle: .appLanguage))
                }
            }
        }
        .padding(16)
        .background(.background.secondary, in: .rect(cornerRadius: 24, style: .continuous))
    }
}

/// The picture shared from the light-up page.
private struct LightUpShareCard: View {
    let insights: LightUpInsights

    var body: some View {
        VStack(alignment: .leading, spacing: 16) {
            HStack {
                Text("我的省份印").font(.title2.bold())
                Spacer()
                Text(AppInfo.name).font(.subheadline.weight(.semibold)).foregroundStyle(.secondary)
            }
            HStack(spacing: 24) {
                stat("\(insights.provinces.count)", String(localized: "个省级行政区", bundle: .appLanguage))
                stat("\(insights.countries.count)", String(localized: "个国家和地区", bundle: .appLanguage))
            }
            ProvinceTileMap(insights: insights)
                .padding(12)
                .background { StampPaper(style: .seals) }
                .clipShape(.rect(cornerRadius: 20))
        }
        .padding(24)
        .background(Color(.systemBackground))
    }

    private func stat(_ value: String, _ label: String) -> some View {
        HStack(alignment: .firstTextBaseline, spacing: 4) {
            Text(value).font(.system(size: 30, weight: .bold, design: .rounded)).foregroundStyle(.orange)
            Text(label).font(.subheadline).foregroundStyle(.secondary)
        }
    }
}

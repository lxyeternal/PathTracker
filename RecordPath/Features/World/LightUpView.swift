import SwiftUI

struct LightUpRoute: Hashable {}

/// "点亮": China's provinces as a tile map and the world's countries as a wall of flags, lit up
/// as you visit them. No borders are drawn, so there's nothing to get wrong on a map.
struct LightUpView: View {
    let stays: [Stay]
    @State private var insights = LightUpInsights()
    @State private var scope = Scope.china
    @State private var selectedProvince: Province?
    @State private var shareImage: Image?

    enum Scope: Hashable { case china, world }

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 18) {
                Picker("范围", selection: $scope.animation(.snappy)) {
                    Text("中国").tag(Scope.china)
                    Text("世界").tag(Scope.world)
                }
                .pickerStyle(.segmented)

                switch scope {
                case .china: china
                case .world: world
                }
            }
            .padding(.horizontal)
            .padding(.bottom, 24)
        }
        .navigationTitle("点亮地图")
        .navigationBarTitleDisplayMode(.inline)
        .toolbar {
            if let shareImage {
                ToolbarItem(placement: .topBarTrailing) {
                    ShareLink(item: shareImage, preview: SharePreview(String(localized: "我的点亮地图", bundle: .appLanguage), image: shareImage)) {
                        Label("分享", systemImage: "square.and.arrow.up")
                    }
                }
            }
        }
        .sheet(item: $selectedProvince) { province in
            ProvinceSheet(province: province, visit: insights.provinces[province.id])
                .presentationDetents([.medium])
        }
        .task(id: stays.count) {
            insights = LightUpInsights(stays: stays)
            // Start where there's something to see.
            if insights.provinces.isEmpty, !insights.countries.isEmpty { scope = .world }
            renderShareImage()
        }
    }

    // MARK: China

    private var china: some View {
        VStack(alignment: .leading, spacing: 18) {
            ProgressHeader(lit: insights.provinces.count, total: Province.all.count,
                           title: "已点亮的省级行政区", tint: .orange)
            ProvinceTileMap(insights: insights) { selectedProvince = $0 }
            if !litProvinces.isEmpty {
                VStack(spacing: 0) {
                    ForEach(litProvinces, id: \.province.id) { item in
                        Button { selectedProvince = item.province } label: {
                            HStack {
                                Text(item.province.name).font(.body.weight(.semibold))
                                // Municipalities are their own city; don't say "上海 上海".
                                Text(item.visit.topCities.filter { $0 != item.province.name && $0 != item.province.chineseName }
                                        .prefix(3).joined(separator: "、"))
                                    .font(.subheadline).foregroundStyle(.secondary).lineLimit(1)
                                Spacer()
                                Text("\(item.visit.days.count) 天").font(.subheadline).foregroundStyle(.secondary).monospacedDigit()
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
            ProgressHeader(lit: insights.countries.count, total: Continent.all.reduce(0) { $0 + $1.regions.count },
                           title: "已点亮的国家和地区", tint: .red,
                           detail: String(localized: "跨越 \(insights.continentsVisited) 个大洲", bundle: .appLanguage))
            ForEach(continents) { continent in
                FlagWall(continent: continent, visited: insights.countries)
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
    let total: Int
    let title: LocalizedStringKey
    let tint: Color
    var detail: String?

    var body: some View {
        HStack(spacing: 16) {
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
            VStack(alignment: .leading, spacing: 2) {
                Text(title).font(.subheadline).foregroundStyle(.secondary)
                HStack(alignment: .firstTextBaseline, spacing: 4) {
                    Text("\(lit)").font(.system(size: 34, weight: .bold, design: .rounded)).contentTransition(.numericText())
                    Text("/ \(total)").font(.title3).foregroundStyle(.secondary)
                }
                if let detail { Text(detail).font(.footnote).foregroundStyle(.secondary) }
            }
            Spacer()
        }
        .padding(16)
        .background(.background.secondary, in: .rect(cornerRadius: 24, style: .continuous))
    }
}

/// The 34 divisions as tiles placed roughly where they are; visited ones lit, brighter with
/// more days there.
struct ProvinceTileMap: View {
    let insights: LightUpInsights
    /// Off for the small preview, where names would be too small to read.
    var showsLabels = true
    var onSelect: (Province) -> Void = { _ in }

    var body: some View {
        GeometryReader { proxy in
            let spacing: CGFloat = 5
            let side = (proxy.size.width - spacing * CGFloat(Province.columns - 1)) / CGFloat(Province.columns)
            ZStack(alignment: .topLeading) {
                ForEach(Province.all) { province in
                    let visit = insights.provinces[province.id]
                    Button { onSelect(province) } label: {
                        Text(showsLabels ? province.tileLabel : "")
                            .font(.system(size: side * 0.26, weight: .semibold))
                            .minimumScaleFactor(0.6)
                            .lineLimit(1)
                            .foregroundStyle(visit == nil ? Color.secondary : .white)
                            .frame(width: side, height: side)
                            .background(RoundedRectangle(cornerRadius: side * 0.22, style: .continuous).fill(fill(for: visit)))
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

    private func fill(for visit: LightUpInsights.Visit?) -> AnyShapeStyle {
        guard let visit else { return AnyShapeStyle(Color.secondary.opacity(0.14)) }
        // A day passing through is lit; a week or more glows.
        let strength = min(1, 0.55 + Double(visit.days.count) / 14)
        return AnyShapeStyle(Color.orange.opacity(strength).gradient)
    }
}

private struct FlagWall: View {
    let continent: Continent
    let visited: Set<String>

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
                    Text(String.flag(for: code))
                        .font(.system(size: 26))
                        .grayscale(lit ? 0 : 1)
                        .opacity(lit ? 1 : 0.22)
                        .accessibilityLabel(appLocale.localizedString(forRegionCode: code) ?? code)
                        .accessibilityValue(lit ? String(localized: "去过", bundle: .appLanguage) : String(localized: "还没去过", bundle: .appLanguage))
                }
            }
        }
        .padding(16)
        .background(.background.secondary, in: .rect(cornerRadius: 24, style: .continuous))
    }
}

private struct ProvinceSheet: View {
    let province: Province
    let visit: LightUpInsights.Visit?

    var body: some View {
        NavigationStack {
            List {
                if let visit {
                    Section {
                        LabeledContent("去过的天数", value: "\(visit.days.count)")
                        LabeledContent("第一次", value: visit.firstVisit.formatted(.dateTime.year().month().day().locale(appLocale)))
                    }
                    if !visit.cities.isEmpty {
                        Section("城市") {
                            ForEach(visit.topCities, id: \.self) { Text($0) }
                        }
                    }
                } else {
                    ContentUnavailableView("还没点亮", systemImage: "lightbulb",
                                           description: Text("去过\(province.name)之后，这里会亮起来。"))
                }
            }
            .navigationTitle(province.name)
            .navigationBarTitleDisplayMode(.inline)
        }
    }
}

/// The picture shared from the light-up page.
private struct LightUpShareCard: View {
    let insights: LightUpInsights

    var body: some View {
        VStack(alignment: .leading, spacing: 16) {
            HStack {
                Text("我的点亮地图").font(.title2.bold())
                Spacer()
                Text(AppInfo.name).font(.subheadline.weight(.semibold)).foregroundStyle(.secondary)
            }
            HStack(spacing: 24) {
                stat("\(insights.provinces.count)", String(localized: "个省级行政区", bundle: .appLanguage))
                stat("\(insights.countries.count)", String(localized: "个国家和地区", bundle: .appLanguage))
            }
            ProvinceTileMap(insights: insights)
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

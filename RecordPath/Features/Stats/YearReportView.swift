import SwiftUI
import SwiftData

/// The year in footprints, one page at a time, ending with a card to share.
struct YearReportView: View {
    @Environment(\.dismiss) private var dismiss
    @Environment(\.modelContext) private var context
    @Environment(ActivityProvider.self) private var activityProvider
    @Query(sort: \Stay.arrival) private var stays: [Stay]
    @Query private var trips: [Trip]

    @State private var year = Calendar.current.component(.year, from: Date())
    @State private var report: YearReport?
    @State private var page = 0
    @State private var shareImage: Image?

    var body: some View {
        ZStack {
            if let report {
                if report.isEmpty {
                    ContentUnavailableView("\(String(year)) 年还没有记录", systemImage: "calendar",
                                           description: Text("记录一段时间之后，这里会整理出你的年度足迹。"))
                } else {
                    TabView(selection: $page) {
                        ForEach(Array(pages(for: report).enumerated()), id: \.offset) { index, page in
                            page.tag(index)
                        }
                    }
                    .tabViewStyle(.page(indexDisplayMode: .always))
                    .indexViewStyle(.page(backgroundDisplayMode: .always))
                    .ignoresSafeArea()
                }
            } else {
                ProgressView()
            }
        }
        .overlay(alignment: .top) { topBar }
        .task(id: year) { await load() }
        .sensoryFeedback(.selection, trigger: page)
    }

    private var topBar: some View {
        HStack {
            if YearReport.years(in: stays).count > 1 {
                Menu {
                    Picker("年份", selection: $year) {
                        ForEach(YearReport.years(in: stays), id: \.self) { Text(verbatim: String($0)).tag($0) }
                    }
                } label: {
                    Label(String(year), systemImage: "chevron.down")
                        .labelStyle(.titleAndIcon)
                        .font(.subheadline.weight(.semibold))
                }
                .buttonStyle(.glass)
            }
            Spacer()
            Button("关闭", systemImage: "xmark") { dismiss() }
                .labelStyle(.iconOnly)
                .buttonStyle(.glass)
                .buttonBorderShape(.circle)
        }
        .padding(.horizontal)
        .padding(.top, 8)
    }

    private func load() async {
        report = nil
        page = 0
        let calendar = Calendar.current
        guard let start = calendar.date(from: DateComponents(year: year, month: 1, day: 1)),
              let end = calendar.date(byAdding: .year, value: 1, to: start) else { return }
        let chunks = (try? context.fetch(FetchDescriptor<TrackChunk>(predicate: #Predicate { $0.startDate >= start && $0.startDate < end }))) ?? []
        let movements = chunks.map { YearReport.Movement(start: $0.startDate, distance: $0.distance, mode: $0.mode) }
        let days = min(calendar.dateComponents([.day], from: start, to: min(end, Date())).day ?? 0, 366) + 1
        let steps = await activityProvider.activity(from: start, days: days)
        let made = YearReport.make(year: year, stays: stays, movements: movements, steps: steps, trips: trips)
        withAnimation(.smooth) { report = made }
        shareImage = render(made)
    }

    @MainActor
    private func render(_ report: YearReport) -> Image? {
        let renderer = ImageRenderer(content: YearShareCard(report: report).frame(width: 390).environment(\.locale, appLocale))
        renderer.scale = 3
        return renderer.uiImage.map { Image(uiImage: $0) }
    }

    // MARK: Pages

    private func pages(for report: YearReport) -> [AnyView] {
        var pages: [AnyView] = [AnyView(cover(report)), AnyView(distancePage(report))]
        if report.steps > 0 { pages.append(AnyView(stepsPage(report))) }
        if !report.countries.isEmpty { pages.append(AnyView(placesPage(report))) }
        if report.longestDay != nil { pages.append(AnyView(standoutPage(report))) }
        if report.favoritePlace != nil || report.farthestPlace != nil { pages.append(AnyView(favoritePage(report))) }
        pages.append(AnyView(sharePage(report)))
        return pages
    }

    private func cover(_ report: YearReport) -> some View {
        ReportPage(tint: .orange) {
            Text(verbatim: String(report.year))
                .font(.system(size: 96, weight: .heavy, design: .rounded))
            Text("我的年度足迹").font(.title.bold())
            Text("这一年记录了 \(report.daysRecorded) 天").font(.title3).foregroundStyle(.secondary)
            Spacer().frame(height: 20)
            Label("向左滑动", systemImage: "hand.point.left.fill").font(.footnote).foregroundStyle(.secondary)
        }
    }

    private func distancePage(_ report: YearReport) -> some View {
        ReportPage(tint: .blue, symbol: "point.topright.arrow.triangle.backward.to.point.bottomleft.scurvepath") {
            Text("这一年你移动了").font(.title2.weight(.semibold))
            BigNumber(Format.distance(report.distance))
            Text("地面上的路程相当于绕赤道 \(report.shareOfEquator.formatted(.percent.precision(.fractionLength(0...1)).locale(appLocale)))")
                .font(.title3).foregroundStyle(.secondary)
            if report.flightDistance > 0 {
                Text("其中飞行 \(Format.distance(report.flightDistance))").font(.title3).foregroundStyle(.secondary)
            }
        }
    }

    private func stepsPage(_ report: YearReport) -> some View {
        ReportPage(tint: .green, symbol: "shoeprints.fill") {
            Text("一步一步，走了").font(.title2.weight(.semibold))
            BigNumber(Format.steps(report.steps))
            Text("步行 \(Format.distance(report.walkingDistance))，相当于 \(report.marathons.formatted(.number.precision(.fractionLength(0...1)).locale(appLocale))) 个全程马拉松")
                .font(.title3).foregroundStyle(.secondary)
        }
    }

    private func placesPage(_ report: YearReport) -> some View {
        ReportPage(tint: .red, symbol: "globe.asia.australia.fill") {
            Text("去过的地方").font(.title2.weight(.semibold))
            HStack(alignment: .firstTextBaseline, spacing: 18) {
                countStat(report.countries.count, "国家和地区")
                countStat(report.cities.count, "座城市")
                if !report.provinces.isEmpty { countStat(report.provinces.count, "个省份") }
            }
            if !report.newCountries.isEmpty {
                Text("第一次去：\(report.newCountries.map { String.flag(for: $0) }.joined(separator: " "))").font(.title2)
            }
            if !report.newCities.isEmpty {
                Text("新去的城市：\(report.newCities.prefix(6).joined(separator: "、"))")
                    .font(.title3).foregroundStyle(.secondary).multilineTextAlignment(.center)
            }
        }
    }

    private func standoutPage(_ report: YearReport) -> some View {
        ReportPage(tint: .purple, symbol: "flame.fill") {
            if let longest = report.longestDay {
                Text("移动最远的一天").font(.title2.weight(.semibold))
                Text(longest.date.formatted(.dateTime.month().day().weekday(.wide).locale(appLocale))).font(.title3).foregroundStyle(.secondary)
                BigNumber(Format.distance(longest.distance))
            }
            if let month = report.busiestMonth {
                Spacer().frame(height: 12)
                Text("最常在路上的月份：\(month.month.formatted(.dateTime.month(.wide).locale(appLocale)))，共 \(Format.distance(month.distance))")
                    .font(.title3).foregroundStyle(.secondary).multilineTextAlignment(.center)
            }
        }
    }

    private func favoritePage(_ report: YearReport) -> some View {
        ReportPage(tint: .pink, symbol: "heart.fill") {
            if let favorite = report.favoritePlace {
                Text("除了家，你最常去").font(.title2.weight(.semibold))
                Text(favorite.name).font(.system(size: 40, weight: .bold, design: .rounded)).multilineTextAlignment(.center)
                Text("去了 \(favorite.visits) 次").font(.title3).foregroundStyle(.secondary)
            }
            if let farthest = report.farthestPlace {
                Spacer().frame(height: 16)
                Text("离家最远到过\(farthest.name)，\(Format.distance(farthest.distance))")
                    .font(.title3).foregroundStyle(.secondary).multilineTextAlignment(.center)
            }
        }
    }

    private func sharePage(_ report: YearReport) -> some View {
        VStack(spacing: 20) {
            Spacer()
            YearShareCard(report: report)
                .clipShape(.rect(cornerRadius: 28, style: .continuous))
                .shadow(color: .black.opacity(0.15), radius: 20, y: 8)
                .padding(.horizontal, 24)
            if let shareImage {
                ShareLink(item: shareImage, preview: SharePreview(String(localized: "我的年度足迹", bundle: .appLanguage), image: shareImage)) {
                    Label("分享年度足迹", systemImage: "square.and.arrow.up")
                        .font(.headline)
                        .frame(maxWidth: .infinity)
                        .frame(height: 50)
                }
                .buttonStyle(.glassProminent)
                .tint(.orange)
                .padding(.horizontal, 24)
            }
            Spacer()
        }
        .background(Color(.systemGroupedBackground))
    }

    private func countStat(_ value: Int, _ label: LocalizedStringKey) -> some View {
        VStack(spacing: 2) {
            Text("\(value)").font(.system(size: 44, weight: .bold, design: .rounded))
            Text(label).font(.subheadline).foregroundStyle(.secondary)
        }
    }
}

private struct ReportPage<Content: View>: View {
    let tint: Color
    var symbol: String?
    @ViewBuilder let content: Content

    var body: some View {
        VStack(spacing: 12) {
            Spacer()
            if let symbol {
                Image(systemName: symbol)
                    .font(.system(size: 44, weight: .semibold))
                    .foregroundStyle(tint.gradient)
                    .padding(.bottom, 8)
            }
            content
            Spacer()
            Spacer()
        }
        .multilineTextAlignment(.center)
        .padding(.horizontal, 28)
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .background(LinearGradient(colors: [tint.opacity(0.22), Color(.systemBackground)], startPoint: .top, endPoint: .bottom))
    }
}

private struct BigNumber: View {
    let text: String
    init(_ text: String) { self.text = text }

    var body: some View {
        Text(text)
            .font(.system(size: 64, weight: .heavy, design: .rounded))
            .minimumScaleFactor(0.5)
            .lineLimit(1)
            .monospacedDigit()
    }
}

/// The card shared at the end: the year's numbers on one picture.
private struct YearShareCard: View {
    let report: YearReport

    var body: some View {
        VStack(alignment: .leading, spacing: 18) {
            HStack(alignment: .firstTextBaseline) {
                Text(verbatim: String(report.year)).font(.system(size: 44, weight: .heavy, design: .rounded)).foregroundStyle(.orange)
                Text("年度足迹").font(.title2.bold())
                Spacer()
                Text(AppInfo.name).font(.subheadline.weight(.semibold)).foregroundStyle(.secondary)
            }
            Grid(alignment: .leading, horizontalSpacing: 24, verticalSpacing: 14) {
                GridRow {
                    stat(Format.distance(report.distance), String(localized: "移动距离", bundle: .appLanguage))
                    stat("\(report.daysRecorded)", String(localized: "记录天数", bundle: .appLanguage))
                }
                GridRow {
                    stat("\(report.countries.count)", String(localized: "国家和地区", bundle: .appLanguage))
                    stat("\(report.cities.count)", String(localized: "城市", bundle: .appLanguage))
                }
                if report.steps > 0 || !report.provinces.isEmpty {
                    GridRow {
                        if report.steps > 0 { stat(Format.steps(report.steps), String(localized: "步数", bundle: .appLanguage)) }
                        if !report.provinces.isEmpty { stat("\(report.provinces.count)", String(localized: "省份", bundle: .appLanguage)) }
                    }
                }
            }
            if !report.countries.isEmpty {
                Text(report.countries.prefix(12).map { String.flag(for: $0) }.joined(separator: " ")).font(.title2)
            }
        }
        .padding(24)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(Color(.secondarySystemGroupedBackground))
    }

    private func stat(_ value: String, _ label: String) -> some View {
        VStack(alignment: .leading, spacing: 2) {
            Text(value).font(.system(.title, design: .rounded, weight: .bold)).monospacedDigit()
            Text(label).font(.subheadline).foregroundStyle(.secondary)
        }
    }
}

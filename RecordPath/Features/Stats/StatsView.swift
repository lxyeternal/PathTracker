import SwiftUI
import SwiftData
import Charts

struct StatsView: View {
    @Binding var showingSettings: Bool
    @Environment(ActivityProvider.self) private var activityProvider
    private var summaries = PlaceSummaries.shared

    enum Period: String, CaseIterable, Identifiable {
        case week, month, year
        var id: String { rawValue }
        var title: LocalizedStringKey {
            switch self {
            case .week: "周"
            case .month: "月"
            case .year: "年"
            }
        }
        var days: Int {
            switch self {
            case .week: 7
            case .month: 30
            case .year: 365
            }
        }
    }

    @State private var period: Period = .week
    @State private var daily: [DailyActivity] = []
    @State private var movement: [Date: [MovementMode: Double]] = [:]
    @State private var selectedDay: Date?
    @State private var distanceSelection: Date?
    @State private var modeAngle: Double?
    @State private var selectedMode: MovementMode?
    @State private var isLoading = true
    private var lifetime: WorldInsights { summaries.world }
    @State private var showingYearReport = false
    @State private var showingRoutes = false
    private var milestones: MilestoneProgress { summaries.milestones }
    @Environment(Notifier.self) private var notifier
    @Environment(\.modelContext) private var context

    private var rangeStart: Date {
        let today = Calendar.current.startOfDay(for: Date())
        return Calendar.current.date(byAdding: .day, value: -(period.days - 1), to: today) ?? today
    }

    /// Where the chart's axis starts: for the year, the start of the first month, so its bar
    /// isn't cut off by the axis.
    private var chartStart: Date {
        period == .year ? (Calendar.current.dateInterval(of: .month, for: rangeStart)?.start ?? rangeStart) : rangeStart
    }

    private var rangeEnd: Date {
        let today = Calendar.current.startOfDay(for: Date())
        return Calendar.current.date(byAdding: period == .year ? .month : .day, value: 1,
                                     to: period == .year ? (Calendar.current.dateInterval(of: .month, for: today)?.start ?? today) : today) ?? Date()
    }

    private var usedModes: [MovementMode] {
        MovementMode.allCases.filter { mode in groundMovement.values.contains { ($0[mode] ?? 0) > 0 } }
    }

    /// Year view groups into months so the bars stay readable.
    private var bucketUnit: Calendar.Component { period == .year ? .month : .day }

    private var averageSteps: Double {
        let counted = daily.filter { $0.steps > 0 }
        return counted.isEmpty ? 0 : counted.reduce(0) { $0 + $1.steps } / Double(counted.count)
    }

    /// Ground travel only: one flight would otherwise dwarf every other day.
    private var groundMovement: [Date: [MovementMode: Double]] {
        movement.mapValues { $0.filter { $0.key != .flying } }
    }

    private var totalMovement: Double { groundMovement.values.flatMap(\.values).reduce(0, +) }

    private var modeTotals: [(mode: MovementMode, distance: Double)] {
        var totals: [MovementMode: Double] = [:]
        for day in movement.values { for (mode, value) in day { totals[mode, default: 0] += value } }
        return totals.map { ($0.key, $0.value) }.filter { $0.distance > 0 }.sorted { $0.distance > $1.distance }
    }

    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(alignment: .leading, spacing: 16) {
                    Picker("时间范围", selection: $period.animation(.smooth)) {
                        ForEach(Period.allCases) { Text($0.title).tag($0) }
                    }
                    .pickerStyle(.segmented)

                    routesCard
                    yearReportCard
                    stepsCard
                    distanceCard
                    if !groundModeTotals.isEmpty { modesCard }
                    lifetimeCard
                    storiesSection
                    milestonesCard
                }
                .padding(.horizontal)
                .padding(.bottom, 24)
            }
            .navigationTitle("统计")
            .toolbar {
                ToolbarItem(placement: .topBarTrailing) {
                    ProfileToolbarButton(showingSettings: $showingSettings)
                }
            }
            .task(id: period) {
                selectedDay = nil
                distanceSelection = nil
                await load()
            }
            .fullScreenCover(isPresented: $showingYearReport) { YearReportView() }
            .fullScreenCover(isPresented: $showingRoutes) { RouteAtlasScreen(span: routeSpan) }
            .navigationDestination(for: MilestonesRoute.self) { _ in MilestonesView(progress: milestones) }
            .navigationDestination(for: FirstsRoute.self) { _ in FirstsView(firsts: summaries.firsts, extremes: summaries.extremes) }
            .navigationDestination(for: JourneyRoute.self) { _ in JourneyView(distance: groundLifetime, home: summaries.home) }
            .navigationDestination(for: DayRoute.self) { DayPage(day: $0.day) }
            .navigationDestination(for: ParallelRoute.self) { _ in ParallelView() }
            .refreshable { await load() }
        }
    }

    private func load() async {
        isLoading = true
        let start = rangeStart
        let activity = await activityProvider.activity(from: start, days: period.days)
        let descriptor = FetchDescriptor<TrackChunk>(predicate: #Predicate { $0.endDate >= start })
        var byDay: [Date: [MovementMode: Double]] = [:]
        for chunk in (try? context.fetch(descriptor)) ?? [] {
            let calendar = Calendar.current
            var day = calendar.startOfDay(for: max(chunk.startDate, start))
            if period == .year { day = calendar.dateInterval(of: .month, for: day)?.start ?? day }
            byDay[day, default: [:]][chunk.mode, default: 0] += chunk.distance
        }
        withAnimation(.smooth) {
            daily = activity
            movement = byDay
            isLoading = false
        }
    }

    // MARK: Cards

    private var stepsCard: some View {
        Card {
            VStack(alignment: .leading, spacing: 12) {
                header(title: "步数", symbol: "shoeprints.fill", tint: .orange,
                       value: selectedValue(\.steps).map(Format.steps) ?? Format.steps(averageSteps),
                       caption: snapped(selectedDay).map(dayLabel) ?? String(localized: "日均", bundle: .appLanguage))
                Chart {
                    ForEach(bucketed(\.steps), id: \.date) { item in
                        BarMark(x: .value("日期", item.date, unit: bucketUnit), y: .value("步数", item.value), width: .ratio(0.55))
                            .foregroundStyle(Color.orange.gradient)
                            .cornerRadius(6, style: .continuous)
                            .opacity(selectedDay == nil || Calendar.current.isDate(item.date, equalTo: selectedDay!, toGranularity: bucketUnit) ? 1 : 0.35)
                    }
                    if averageSteps > 0 && period != .year && selectedDay == nil {
                        RuleMark(y: .value("日均", averageSteps))
                            .lineStyle(StrokeStyle(lineWidth: 1, dash: [4, 4]))
                            .foregroundStyle(.secondary)
                    }
                    if let day = snapped(selectedDay) {
                        RuleMark(x: .value("日期", day, unit: bucketUnit))
                            .foregroundStyle(Color.orange.opacity(0.25))
                            .lineStyle(StrokeStyle(lineWidth: 1))
                    }
                }
                .chartXSelection(value: $selectedDay)
                .sensoryFeedback(.selection, trigger: snapped(selectedDay))
                .chartYAxis { yAxis }
                .chartXAxis { xAxis }
                .frame(height: 180)
                .overlay { if daily.allSatisfy({ $0.steps == 0 }) && !isLoading { activityProvider.isAuthorizationRequested
                    ? noData("还没有步数记录", detail: "步数来自“健康”App，带着 iPhone 或 Apple Watch 走动后就会出现。")
                    : noData("没有步数数据", detail: "在“设置”中允许读取“健康”数据。") } }
            }
        }
    }

    private var distanceCard: some View {
        Card {
            VStack(alignment: .leading, spacing: 12) {
                header(title: "移动距离", symbol: "point.topright.arrow.triangle.backward.to.point.bottomleft.scurvepath",
                       tint: .blue, value: Format.distance(snapped(distanceSelection).map(groundTotal) ?? totalMovement),
                       caption: snapped(distanceSelection).map(dayLabel) ?? String(localized: "合计 · 不含飞行", bundle: .appLanguage))
                modeChips(snapped(distanceSelection).map(breakdown)
                          ?? modeTotals.filter { $0.mode != .flying })
                Chart {
                    ForEach(Array(groundMovement.keys), id: \.self) { day in
                        ForEach(MovementMode.allCases, id: \.self) { mode in
                            if let value = groundMovement[day]?[mode], value > 0 {
                                BarMark(x: .value("日期", day, unit: bucketUnit), y: .value("距离", value / 1000), width: .ratio(0.55))
                                    .foregroundStyle(by: .value("方式", mode.title))
                                    .cornerRadius(4, style: .continuous)
                                    .opacity(snapped(distanceSelection).map { Calendar.current.isDate($0, equalTo: day, toGranularity: bucketUnit) } ?? true ? 1 : 0.3)
                            }
                        }
                    }
                    if let day = snapped(distanceSelection) {
                        RuleMark(x: .value("日期", day, unit: bucketUnit))
                            .foregroundStyle(Color.blue.opacity(0.2))
                    }
                }
                .chartXSelection(value: $distanceSelection)
                .sensoryFeedback(.selection, trigger: snapped(distanceSelection))
                .chartForegroundStyleScale(domain: usedModes.map(\.title), range: usedModes.map(\.color))
                .chartLegend(.hidden)
                .chartYAxis {
                    AxisMarks(values: .automatic(desiredCount: 3)) { value in
                        AxisGridLine(stroke: StrokeStyle(lineWidth: 0.5)).foregroundStyle(.quaternary)
                        AxisValueLabel { if let km = value.as(Double.self) { Text(Measurement(value: km, unit: UnitLength.kilometers).formatted(.measurement(width: .abbreviated, usage: .asProvided, numberFormatStyle: .number.precision(.fractionLength(0))).locale(appLocale))) } }
                    }
                }
                .chartXScale(domain: chartStart...rangeEnd)
                .chartXAxis { xAxis }
                .frame(height: 200)
                .overlay { if movement.isEmpty && !isLoading { noData("还没有轨迹", detail: "开启自动记录后，这里会显示每天的移动距离。") } }
            }
        }
    }

    /// Ground travel by mode; a single flight would otherwise fill the whole ring.
    private var groundModeTotals: [(mode: MovementMode, distance: Double)] { modeTotals.filter { $0.mode != .flying } }

    private var modesCard: some View {
        let ground = groundModeTotals
        let total = ground.reduce(0) { $0 + $1.distance }
        let flight = modeTotals.first { $0.mode == .flying }
        let focus = selectedMode.flatMap { mode in ground.first { $0.mode == mode } }
        return Card {
            VStack(alignment: .leading, spacing: 14) {
                Text("出行方式").font(.headline)
                HStack(spacing: 20) {
                    Chart(ground, id: \.mode) { item in
                        SectorMark(angle: .value("距离", item.distance),
                                   innerRadius: .ratio(0.64),
                                   outerRadius: .ratio(selectedMode == item.mode ? 1 : 0.9),
                                   angularInset: 2)
                            .foregroundStyle(item.mode.color.gradient)
                            .cornerRadius(5)
                            .opacity(selectedMode == nil || selectedMode == item.mode ? 1 : 0.3)
                    }
                    .chartAngleSelection(value: $modeAngle)
                    .chartBackground { _ in
                        VStack(spacing: 0) {
                            if let focus {
                                Image(systemName: focus.mode.symbol).font(.caption.bold()).foregroundStyle(focus.mode.color)
                                Text((focus.distance / max(total, 1)).formatted(.percent.precision(.fractionLength(0)).locale(appLocale)))
                                    .font(.system(.title3, design: .rounded, weight: .bold))
                                    .contentTransition(.numericText())
                            } else {
                                Text(Format.distance(total))
                                    .font(.system(.subheadline, design: .rounded, weight: .bold))
                                    .multilineTextAlignment(.center)
                                    .minimumScaleFactor(0.6)
                                Text("地面合计").font(.caption2).foregroundStyle(.secondary)
                            }
                        }
                        .frame(width: 70)
                    }
                    .frame(width: 130, height: 130)
                    VStack(spacing: 4) {
                        ForEach(ground, id: \.mode) { item in
                            Button {
                                withAnimation(.snappy) { selectedMode = selectedMode == item.mode ? nil : item.mode }
                            } label: {
                                HStack(spacing: 10) {
                                    Image(systemName: item.mode.symbol)
                                        .font(.caption.bold())
                                        .foregroundStyle(.white)
                                        .frame(width: 26, height: 26)
                                        .background(Circle().fill(item.mode.color.gradient))
                                    Text(item.mode.title).foregroundStyle(.primary)
                                    Spacer(minLength: 4)
                                    Text(Format.distance(item.distance)).foregroundStyle(.secondary).monospacedDigit()
                                }
                                .font(.subheadline)
                                .padding(.horizontal, 8).padding(.vertical, 5)
                                .background(RoundedRectangle(cornerRadius: 10, style: .continuous)
                                    .fill(selectedMode == item.mode ? item.mode.color.opacity(0.14) : .clear))
                                .contentShape(.rect)
                            }
                            .buttonStyle(.plain)
                            .opacity(selectedMode == nil || selectedMode == item.mode ? 1 : 0.5)
                        }
                    }
                }
                if let flight {
                    Divider()
                    HStack(spacing: 10) {
                        Image(systemName: MovementMode.flying.symbol)
                            .font(.caption.bold())
                            .foregroundStyle(.white)
                            .frame(width: 26, height: 26)
                            .background(Circle().fill(MovementMode.flying.color.gradient))
                        Text("另有飞行")
                        Spacer(minLength: 4)
                        Text(Format.distance(flight.distance)).foregroundStyle(.secondary).monospacedDigit()
                    }
                    .font(.subheadline)
                    .padding(.horizontal, 8)
                }
            }
        }
        .onChange(of: modeAngle) { _, angle in
            guard let angle else { return }
            var running = 0.0
            let mode = groundModeTotals.first { running += $0.distance; return angle <= running }?.mode
            withAnimation(.snappy) { selectedMode = mode == selectedMode ? nil : mode }
        }
        .sensoryFeedback(.selection, trigger: selectedMode)
    }

    // MARK: Chart selection

    /// The bar a scrub position falls on.
    private func snapped(_ date: Date?) -> Date? {
        guard let date else { return nil }
        return Calendar.current.dateInterval(of: bucketUnit, for: date)?.start
    }

    private func dayLabel(_ date: Date) -> String {
        period == .year ? date.formatted(.dateTime.year().month(.wide).locale(appLocale))
                        : date.formatted(.dateTime.month().day().weekday(.abbreviated).locale(appLocale))
    }

    private func breakdown(_ day: Date) -> [(mode: MovementMode, distance: Double)] {
        let modes = groundMovement.first { Calendar.current.isDate($0.key, equalTo: day, toGranularity: bucketUnit) }?.value ?? [:]
        return modes.filter { $0.value > 0 }.map { ($0.key, $0.value) }.sorted { $0.distance > $1.distance }
    }

    private func groundTotal(_ day: Date) -> Double { breakdown(day).reduce(0) { $0 + $1.distance } }

    /// Distance by travel mode as small chips; doubles as the chart's legend.
    private func modeChips(_ items: [(mode: MovementMode, distance: Double)]) -> some View {
        ScrollView(.horizontal) {
            HStack(spacing: 6) {
                ForEach(items, id: \.mode) { item in
                    HStack(spacing: 4) {
                        Image(systemName: item.mode.symbol).font(.caption2.bold())
                        Text(Format.distance(item.distance)).font(.caption.weight(.semibold)).monospacedDigit()
                            .contentTransition(.numericText())
                    }
                    .foregroundStyle(item.mode.color)
                    .padding(.horizontal, 8).padding(.vertical, 4)
                    .background(item.mode.color.opacity(0.12), in: .capsule)
                }
            }
        }
        .scrollIndicators(.hidden)
        .frame(height: 24)
        .animation(.snappy, value: items.map(\.distance))
    }

    /// Badges earned so far as a row of medals, with the closest one still to go.
    private var milestonesCard: some View {
        NavigationLink(value: MilestonesRoute()) {
            VStack(alignment: .leading, spacing: 14) {
                HStack(alignment: .firstTextBaseline) {
                    Text("里程碑").font(.title3.bold()).foregroundStyle(.primary)
                    Spacer()
                    Text("\(milestones.reached.count) / \(milestones.all.count)")
                        .font(.subheadline).foregroundStyle(.secondary).monospacedDigit()
                    Image(systemName: "chevron.forward").font(.footnote.weight(.semibold)).foregroundStyle(.tertiary)
                }
                HStack(alignment: .top, spacing: 6) {
                    ForEach(milestones.reached.prefix(4), id: \.id) { item in
                        MilestoneBadge(milestone: item.milestone, size: 58)
                    }
                    if let next = milestones.next.first {
                        MilestoneBadge(milestone: next.milestone, isReached: false, progress: next.fraction, size: 58)
                            .padding(.leading, milestones.reached.isEmpty ? 0 : 10)
                    }
                    Spacer(minLength: 0)
                }
                if let next = milestones.next.first {
                    HStack(spacing: 6) {
                        Text("下一个").foregroundStyle(.secondary)
                        Text(next.milestone.title).fontWeight(.semibold).foregroundStyle(.primary)
                        Spacer()
                        Text(progressText(next)).foregroundStyle(.secondary).monospacedDigit()
                    }
                    .font(.subheadline)
                }
            }
            .padding(16)
            .background(.background.secondary, in: .rect(cornerRadius: 24, style: .continuous))
        }
        .buttonStyle(PressableStyle())
    }

    private func progressText(_ item: MilestoneProgress.Next) -> String {
        let current = item.milestone.kind == .distance ? Int(item.current.rounded(.down)) : Int(item.current)
        return "\(current.formatted(.number.locale(appLocale))) / \(item.milestone.threshold.formatted(.number.locale(appLocale)))"
    }

    /// The atlas opens on the stretch of time this page is showing.
    private var routeSpan: RouteSpan {
        switch period {
        case .week: .week
        case .month: .month
        case .year: .year
        }
    }

    /// The way in to every road on one map: a strip of night with a few of them glowing.
    private var routesCard: some View {
        Button { showingRoutes = true } label: {
            HStack(spacing: 14) {
                VStack(alignment: .leading, spacing: 4) {
                    Text("走过的路").font(.system(.title3, design: .serif, weight: .bold)).foregroundStyle(.white)
                    Text("今天、本周、本月、今年，所有轨迹叠在一张地图上")
                        .font(.subheadline).foregroundStyle(.white.opacity(0.7))
                        .multilineTextAlignment(.leading)
                        .fixedSize(horizontal: false, vertical: true)
                }
                // The roads glow to the right of the words, not under them.
                Spacer(minLength: 96)
                Image(systemName: "chevron.right").font(.caption.weight(.semibold)).foregroundStyle(.white.opacity(0.5))
            }
            .padding(.horizontal, 18).padding(.vertical, 18)
            .frame(maxWidth: .infinity, alignment: .leading)
            .background {
                ZStack {
                    LinearGradient(colors: [Color(red: 0.04, green: 0.05, blue: 0.13), Color(red: 0.10, green: 0.09, blue: 0.22)],
                                   startPoint: .topLeading, endPoint: .bottomTrailing)
                    RouteGlow()
                }
            }
            .clipShape(.rect(cornerRadius: 24, style: .continuous))
        }
        .buttonStyle(PressableStyle())
        .accessibilityHint("打开全部轨迹的地图")
    }

    private var yearReportCard: some View {
        Button { showingYearReport = true } label: {
            HStack(spacing: 14) {
                Text(verbatim: String(Calendar.current.component(.year, from: Date())))
                    .font(.system(.title2, design: .rounded, weight: .heavy))
                    .foregroundStyle(.white)
                    .frame(width: 76, height: 56)
                    .background(RoundedRectangle(cornerRadius: 16, style: .continuous).fill(Color.orange.gradient))
                VStack(alignment: .leading, spacing: 2) {
                    Text("年度足迹").font(.headline)
                    Text("这一年走了多远、去了哪里，可以分享").font(.subheadline).foregroundStyle(.secondary)
                }
                Spacer(minLength: 0)
                Image(systemName: "chevron.right").font(.caption.weight(.semibold)).foregroundStyle(.tertiary)
            }
            .padding(14)
            .background(.background.secondary, in: .rect(cornerRadius: 24, style: .continuous))
        }
        .buttonStyle(PressableStyle())
    }

    /// Every metre travelled on the ground, ever, as the distance milestones count it.
    private var groundLifetime: Double {
        (milestones.all.first { $0.milestone.kind == .distance }?.current ?? 0) * 1000
    }

    /// The portrait, the virtual road, the firsts and the footprints shared with friends.
    @ViewBuilder private var storiesSection: some View {
        if !summaries.stays.isEmpty {
            VStack(alignment: .leading, spacing: 12) {
                SectionHeader(title: "你的故事")
                // A month of days and some distance before the portrait says who you are.
                if lifetime.trackedDays >= 30 && summaries.portrait.distance >= 20_000 {
                    PortraitCard(portrait: summaries.portrait)
                } else {
                    PortraitPlaceholderCard()
                }
                JourneyCard(distance: groundLifetime, home: summaries.home)
                if !summaries.firsts.isEmpty { FirstsCard(firsts: summaries.firsts) }
                ParallelCard()
            }
        }
    }

    private var lifetimeCard: some View {
        let insights = lifetime
        return VStack(alignment: .leading, spacing: 10) {
            SectionHeader(title: "一直以来")
            MetricGrid {
                MetricTile(title: "国家与地区", value: "\(insights.countries.count)", symbol: "flag.fill", tint: .red)
                MetricTile(title: "城市", value: "\(insights.cityCount)", symbol: "building.2.fill", tint: .indigo)
                MetricTile(title: "记录天数", value: "\(insights.trackedDays)", symbol: "calendar", tint: .teal)
                MetricTile(title: "到访次数", value: "\(summaries.stays.count)", symbol: "mappin.and.ellipse", tint: .pink)
            }
            if let first = insights.firstDay {
                Text("从 \(first.formatted(Date.FormatStyle(date: .long, time: .omitted, locale: appLocale))) 开始记录")
                    .font(.footnote).foregroundStyle(.secondary).padding(.horizontal, 4)
            }
        }
    }

    // MARK: Helpers

    /// A few fine rules across, faint, with their values beside them.
    private var yAxis: some AxisContent {
        AxisMarks(values: .automatic(desiredCount: 3)) { _ in
            AxisGridLine(stroke: StrokeStyle(lineWidth: 0.5)).foregroundStyle(.quaternary)
            AxisValueLabel()
        }
    }

    private var xAxis: some AxisContent {
        // No vertical rules: the bars mark the days well enough on their own.
        AxisMarks(values: .automatic(desiredCount: period == .week ? 7 : 5)) { value in
            AxisValueLabel(centered: period != .month, collisionResolution: .greedy) {
                if let date = value.as(Date.self) {
                    let format: Date.FormatStyle = period == .year ? .dateTime.month(.abbreviated)
                        : period == .week ? .dateTime.weekday(.narrow) : .dateTime.day()
                    Text(date.formatted(format.locale(appLocale)))
                }
            }
        }
    }

    private func header(title: LocalizedStringKey, symbol: String, tint: Color, value: String, caption: String) -> some View {
        VStack(alignment: .leading, spacing: 2) {
            Label(title, systemImage: symbol).font(.subheadline.weight(.semibold)).foregroundStyle(tint)
            HStack(alignment: .firstTextBaseline, spacing: 6) {
                Text(value).font(.system(.largeTitle, design: .rounded, weight: .bold)).contentTransition(.numericText())
                Text(caption).font(.subheadline).foregroundStyle(.secondary)
            }
        }
    }

    private func noData(_ title: LocalizedStringKey, detail: LocalizedStringKey) -> some View {
        VStack(spacing: 4) {
            Text(title).font(.subheadline.weight(.semibold))
            Text(detail).font(.caption).foregroundStyle(.secondary).multilineTextAlignment(.center)
        }
        .padding()
        .background(.background.secondary.opacity(0.9), in: .rect(cornerRadius: 14))
    }

    private func bucketed(_ keyPath: KeyPath<DailyActivity, Double>) -> [(date: Date, value: Double)] {
        guard period == .year else { return daily.map { ($0.day, $0[keyPath: keyPath]) } }
        let calendar = Calendar.current
        let grouped = Dictionary(grouping: daily) { calendar.dateInterval(of: .month, for: $0.day)?.start ?? $0.day }
        // Monthly bars show the daily average for that month.
        return grouped.map { month, days in
            let counted = days.filter { $0[keyPath: keyPath] > 0 }
            return (month, counted.isEmpty ? 0 : counted.reduce(0) { $0 + $1[keyPath: keyPath] } / Double(counted.count))
        }
        .sorted { $0.date < $1.date }
    }

    private func selectedValue(_ keyPath: KeyPath<DailyActivity, Double>) -> Double? {
        guard let selectedDay else { return nil }
        return bucketed(keyPath).first { Calendar.current.isDate($0.date, equalTo: selectedDay, toGranularity: bucketUnit) }?.value
    }
}

/// A few roads drawn in light across the card: faint alone, brighter where they cross.
private struct RouteGlow: View {
    var body: some View {
        Canvas { context, size in
            let warm = Color(red: 1, green: 0.80, blue: 0.42)
            let roads: [[CGPoint]] = [
                [CGPoint(x: 0.42, y: 1.1), CGPoint(x: 0.55, y: 0.62), CGPoint(x: 0.74, y: 0.5), CGPoint(x: 1.05, y: 0.2)],
                [CGPoint(x: 0.5, y: -0.1), CGPoint(x: 0.62, y: 0.4), CGPoint(x: 0.74, y: 0.5), CGPoint(x: 0.86, y: 1.1)],
                [CGPoint(x: 0.6, y: 1.1), CGPoint(x: 0.7, y: 0.78), CGPoint(x: 0.9, y: 0.7), CGPoint(x: 1.05, y: 0.82)],
                [CGPoint(x: 0.66, y: -0.1), CGPoint(x: 0.74, y: 0.5), CGPoint(x: 0.7, y: 0.78)],
            ]
            for road in roads {
                var path = Path()
                let points = road.map { CGPoint(x: $0.x * size.width, y: $0.y * size.height) }
                path.move(to: points[0])
                for index in 1..<points.count {
                    let previous = points[index - 1], next = points[index]
                    path.addQuadCurve(to: next, control: CGPoint(x: (previous.x + next.x) / 2 + 8, y: (previous.y + next.y) / 2 - 8))
                }
                context.stroke(path, with: .color(warm.opacity(0.10)), style: StrokeStyle(lineWidth: 7, lineCap: .round, lineJoin: .round))
                context.stroke(path, with: .color(warm.opacity(0.45)), style: StrokeStyle(lineWidth: 1.4, lineCap: .round, lineJoin: .round))
            }
            let crossing = CGPoint(x: 0.74 * size.width, y: 0.5 * size.height)
            context.fill(Path(ellipseIn: CGRect(x: crossing.x - 14, y: crossing.y - 14, width: 28, height: 28)), with: .color(warm.opacity(0.16)))
            context.fill(Path(ellipseIn: CGRect(x: crossing.x - 3, y: crossing.y - 3, width: 6, height: 6)), with: .color(warm))
        }
        // Fades out under the words.
        .mask(LinearGradient(colors: [.clear, .black.opacity(0.9), .black], startPoint: .init(x: 0.52, y: 0.5), endPoint: .init(x: 0.82, y: 0.5)))
        .accessibilityHidden(true)
    }
}

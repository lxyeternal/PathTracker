import SwiftUI
import SwiftData
import Charts

struct StatsView: View {
    @Binding var showingSettings: Bool
    @Environment(ActivityProvider.self) private var activityProvider
    @Query(sort: \Stay.arrival) private var stays: [Stay]

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
    @State private var lifetime = WorldInsights()
    @State private var showingYearReport = false
    @State private var milestones = MilestoneProgress()
    @Environment(Notifier.self) private var notifier
    @Environment(\.modelContext) private var context

    private var rangeStart: Date {
        let today = Calendar.current.startOfDay(for: Date())
        return Calendar.current.date(byAdding: .day, value: -(period.days - 1), to: today) ?? today
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

                    yearReportCard
                    stepsCard
                    distanceCard
                    if !modeTotals.isEmpty { modesCard }
                    lifetimeCard
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
            .task(id: stays.count) {
                lifetime = WorldInsights(stays: stays)
                milestones = notifier.currentMilestones()
            }
            .fullScreenCover(isPresented: $showingYearReport) { YearReportView() }
            .navigationDestination(for: MilestonesRoute.self) { _ in MilestonesView(progress: milestones) }
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
                        BarMark(x: .value("日期", item.date, unit: bucketUnit), y: .value("步数", item.value))
                            .foregroundStyle(Color.orange.gradient)
                            .cornerRadius(4)
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
                                BarMark(x: .value("日期", day, unit: bucketUnit), y: .value("距离", value / 1000))
                                    .foregroundStyle(by: .value("方式", mode.title))
                                    .cornerRadius(3)
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
                    AxisMarks { value in
                        AxisGridLine()
                        AxisValueLabel { if let km = value.as(Double.self) { Text(Measurement(value: km, unit: UnitLength.kilometers).formatted(.measurement(width: .abbreviated, usage: .asProvided, numberFormatStyle: .number.precision(.fractionLength(0))).locale(appLocale))) } }
                    }
                }
                .chartXScale(domain: rangeStart...rangeEnd)
                .chartXAxis { xAxis }
                .frame(height: 200)
                .overlay { if movement.isEmpty && !isLoading { noData("还没有轨迹", detail: "开启自动记录后，这里会显示每天的移动距离。") } }
            }
        }
    }

    private var modesCard: some View {
        let total = modeTotals.reduce(0) { $0 + $1.distance }
        let focus = selectedMode.flatMap { mode in modeTotals.first { $0.mode == mode } }
        return Card {
            VStack(alignment: .leading, spacing: 14) {
                Text("出行方式").font(.headline)
                HStack(spacing: 20) {
                    Chart(modeTotals, id: \.mode) { item in
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
                                    .minimumScaleFactor(0.6)
                                Text("合计").font(.caption2).foregroundStyle(.secondary)
                            }
                        }
                        .frame(width: 70)
                    }
                    .frame(width: 130, height: 130)
                    VStack(spacing: 4) {
                        ForEach(modeTotals, id: \.mode) { item in
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
            }
        }
        .onChange(of: modeAngle) { _, angle in
            guard let angle else { return }
            var running = 0.0
            let mode = modeTotals.first { running += $0.distance; return angle <= running }?.mode
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

    private var lifetimeCard: some View {
        let insights = lifetime
        return VStack(alignment: .leading, spacing: 10) {
            SectionHeader(title: "一直以来")
            MetricGrid {
                MetricTile(title: "国家与地区", value: "\(insights.countries.count)", symbol: "flag.fill", tint: .red)
                MetricTile(title: "城市", value: "\(insights.cityCount)", symbol: "building.2.fill", tint: .indigo)
                MetricTile(title: "记录天数", value: "\(insights.trackedDays)", symbol: "calendar", tint: .teal)
                MetricTile(title: "到访地点", value: "\(stays.count)", symbol: "mappin.and.ellipse", tint: .pink)
            }
            if let first = insights.firstDay {
                Text("从 \(first.formatted(Date.FormatStyle(date: .long, time: .omitted, locale: appLocale))) 开始记录")
                    .font(.footnote).foregroundStyle(.secondary).padding(.horizontal, 4)
            }
        }
    }

    // MARK: Helpers

    private var xAxis: some AxisContent {
        AxisMarks(values: .automatic(desiredCount: period == .week ? 7 : 5)) { value in
            AxisGridLine()
            AxisValueLabel(format: period == .year ? .dateTime.month(.abbreviated) : period == .week ? .dateTime.weekday(.narrow) : .dateTime.day(),
                           centered: period != .month, collisionResolution: .greedy)
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

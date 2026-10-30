import SwiftUI
import SwiftData

/// A month calendar that marks the days with recorded tracks or stays, so the user can
/// see at a glance which days have something to look at.
struct RecordedDayCalendar: View {
    @Binding var selection: Date
    @Environment(\.modelContext) private var context
    @State private var month: Date
    @State private var recorded: Set<Date> = []
    /// Showing every month at once, to jump years back without paging month by month.
    @State private var choosingMonth = false
    /// The first day of every month with something recorded, for the month chooser.
    @State private var recordedMonths: Set<Date> = []

    private let calendar: Calendar = {
        var calendar = Calendar.current
        calendar.locale = appLocale
        return calendar
    }()

    init(selection: Binding<Date>) {
        _selection = selection
        _month = State(initialValue: Calendar.current.dateInterval(of: .month, for: selection.wrappedValue)?.start ?? Date())
    }

    private var isCurrentMonth: Bool { calendar.isDate(month, equalTo: Date(), toGranularity: .month) }

    private var weekdaySymbols: [String] {
        let symbols = calendar.veryShortStandaloneWeekdaySymbols
        let first = calendar.firstWeekday - 1
        return Array(symbols[first...] + symbols[..<first])
    }

    private var cells: [Date?] {
        guard let range = calendar.range(of: .day, in: .month, for: month) else { return [] }
        let leading = (calendar.component(.weekday, from: month) - calendar.firstWeekday + 7) % 7
        let days = range.compactMap { calendar.date(byAdding: .day, value: $0 - 1, to: month) }
        return Array(repeating: nil, count: leading) + days
    }

    var body: some View {
        VStack(spacing: 14) {
            HStack {
                Button {
                    withAnimation(.snappy) { choosingMonth.toggle() }
                } label: {
                    HStack(spacing: 6) {
                        Text(month.formatted(.dateTime.year().month(.wide).locale(appLocale)))
                            .contentTransition(.numericText())
                        Image(systemName: "chevron.forward")
                            .font(.subheadline.weight(.bold))
                            .rotationEffect(.degrees(choosingMonth ? 90 : 0))
                            .foregroundStyle(Color.accentColor)
                    }
                    .font(.title3.bold())
                    .foregroundStyle(choosingMonth ? Color.accentColor : Color.primary)
                    .contentShape(.rect)
                }
                .buttonStyle(.plain)
                .accessibilityHint(Text("选择年份和月份"))
                Spacer()
                if !choosingMonth {
                    Button("上个月", systemImage: "chevron.left") { shiftMonth(-1) }
                        .labelStyle(.iconOnly)
                    Button("下个月", systemImage: "chevron.right") { shiftMonth(1) }
                        .labelStyle(.iconOnly)
                        .disabled(isCurrentMonth)
                }
            }
            .font(.title3.weight(.semibold))
            .padding(.horizontal, 4)

            if choosingMonth {
                MonthChooser(selected: month, recorded: recordedMonths, calendar: calendar) { picked in
                    withAnimation(.snappy) {
                        month = picked
                        choosingMonth = false
                    }
                }
                .transition(.opacity.combined(with: .move(edge: .top)))
            } else {
                dayGrid
                    .transition(.opacity)
            }
        }
        .task(id: month) { loadRecordedDays() }
        .task { loadRecordedMonths() }
    }

    private var dayGrid: some View {
        VStack(spacing: 14) {
            let columns = Array(repeating: GridItem(.flexible(), spacing: 0), count: 7)
            LazyVGrid(columns: columns, spacing: 6) {
                ForEach(weekdaySymbols, id: \.self) { symbol in
                    Text(symbol).font(.caption.weight(.semibold)).foregroundStyle(.secondary)
                }
                ForEach(Array(cells.enumerated()), id: \.offset) { _, day in
                    if let day { dayCell(day) } else { Color.clear.frame(height: 44) }
                }
            }

            HStack(spacing: 6) {
                Circle().fill(.orange).frame(width: 6, height: 6)
                Text("有记录的日子").font(.caption).foregroundStyle(.secondary)
                Spacer()
                Text("这个月 \(recorded.count) 天").font(.caption).foregroundStyle(.secondary)
            }
            .padding(.horizontal, 4)
        }
        .contentShape(.rect)
        .gesture(
            DragGesture(minimumDistance: 30).onEnded { value in
                guard abs(value.translation.width) > 60 else { return }
                shiftMonth(value.translation.width > 0 ? -1 : 1)
            }
        )
    }

    private func dayCell(_ day: Date) -> some View {
        let isSelected = calendar.isDate(day, inSameDayAs: selection)
        let isToday = calendar.isDateInToday(day)
        let isFuture = day > Date()
        let hasData = recorded.contains(day)
        return Button {
            selection = day
        } label: {
            VStack(spacing: 3) {
                Text("\(calendar.component(.day, from: day))")
                    .font(.body.weight(isSelected || isToday ? .semibold : .regular))
                    .foregroundStyle(isSelected ? Color.white : isToday ? Color.accentColor : isFuture ? Color.secondary.opacity(0.4) : Color.primary)
                    .frame(width: 36, height: 36)
                    .background(Circle().fill(isSelected ? Color.accentColor : .clear))
                Circle()
                    .fill(hasData ? Color.orange : .clear)
                    .frame(width: 5, height: 5)
            }
            .frame(maxWidth: .infinity)
            .contentShape(.rect)
        }
        .buttonStyle(.plain)
        .disabled(isFuture)
        .accessibilityLabel(day.formatted(Date.FormatStyle(date: .complete, time: .omitted, locale: appLocale)))
        .accessibilityValue(hasData ? String(localized: "有记录", bundle: .appLanguage) : "")
        .accessibilityAddTraits(isSelected ? .isSelected : [])
    }

    private func shiftMonth(_ value: Int) {
        guard let next = calendar.date(byAdding: .month, value: value, to: month), next <= Date() else { return }
        withAnimation(.snappy) { month = next }
    }

    private func loadRecordedDays() {
        guard let end = calendar.date(byAdding: .month, value: 1, to: month) else { return }
        let start = month
        var days = Set<Date>()
        let chunks = FetchDescriptor<TrackChunk>(predicate: #Predicate { $0.startDate >= start && $0.startDate < end })
        for chunk in (try? context.fetch(chunks)) ?? [] { days.insert(calendar.startOfDay(for: chunk.startDate)) }
        let stays = FetchDescriptor<Stay>(predicate: #Predicate { $0.arrival >= start && $0.arrival < end })
        for stay in (try? context.fetch(stays)) ?? [] { days.insert(calendar.startOfDay(for: stay.arrival)) }
        recorded = days
    }

    private func loadRecordedMonths() {
        var months = Set<Date>()
        func add(_ date: Date) {
            if let start = calendar.dateInterval(of: .month, for: date)?.start { months.insert(start) }
        }
        var chunks = FetchDescriptor<TrackChunk>()
        chunks.propertiesToFetch = [\.startDate]
        for chunk in (try? context.fetch(chunks)) ?? [] { add(chunk.startDate) }
        var stays = FetchDescriptor<Stay>()
        stays.propertiesToFetch = [\.arrival]
        for stay in (try? context.fetch(stays)) ?? [] { add(stay.arrival) }
        recordedMonths = months
    }
}

/// Every month from the first one with a record to this one, a year to a row of twelve, so
/// any month is one tap away. Months with records are marked.
private struct MonthChooser: View {
    let selected: Date
    let recorded: Set<Date>
    let calendar: Calendar
    let pick: (Date) -> Void

    private var years: [Int] {
        let now = calendar.component(.year, from: Date())
        let first = recorded.map { calendar.component(.year, from: $0) }.min() ?? now
        return Array((min(first, calendar.component(.year, from: selected))...now).reversed())
    }

    var body: some View {
        ScrollViewReader { proxy in
            ScrollView {
                LazyVStack(alignment: .leading, spacing: 18) {
                    ForEach(years, id: \.self) { year in
                        VStack(alignment: .leading, spacing: 8) {
                            HStack(alignment: .firstTextBaseline) {
                                Text(verbatim: String(year)).font(.headline)
                                Spacer()
                                let count = months(of: year).filter { recorded.contains($0) }.count
                                if count > 0 {
                                    Text("\(count) 个月有记录").font(.caption).foregroundStyle(.secondary)
                                }
                            }
                            let columns = Array(repeating: GridItem(.flexible(), spacing: 6), count: 6)
                            LazyVGrid(columns: columns, spacing: 6) {
                                ForEach(months(of: year), id: \.self) { cell($0) }
                            }
                        }
                        .id(year)
                    }
                }
                .padding(.horizontal, 4)
                .padding(.bottom, 8)
            }
            .scrollIndicators(.hidden)
            .onAppear { proxy.scrollTo(calendar.component(.year, from: selected), anchor: .top) }
        }
    }

    private func months(of year: Int) -> [Date] {
        (1...12).compactMap { calendar.date(from: DateComponents(year: year, month: $0, day: 1)) }
    }

    private func cell(_ month: Date) -> some View {
        let isSelected = calendar.isDate(month, equalTo: selected, toGranularity: .month)
        let isFuture = month > Date()
        let hasData = recorded.contains(month)
        return Button { pick(month) } label: {
            VStack(spacing: 3) {
                Text(month.formatted(.dateTime.month(.abbreviated).locale(appLocale)))
                    .font(.subheadline.weight(isSelected || hasData ? .semibold : .regular))
                    .lineLimit(1)
                    .minimumScaleFactor(0.7)
                    .foregroundStyle(isSelected ? Color.white : isFuture ? Color.secondary.opacity(0.4) : hasData ? Color.primary : Color.secondary)
                Circle()
                    .fill(hasData ? (isSelected ? Color.white : Color.orange) : .clear)
                    .frame(width: 4, height: 4)
            }
            .frame(maxWidth: .infinity)
            .frame(height: 44)
            .background(
                RoundedRectangle(cornerRadius: 12, style: .continuous)
                    .fill(isSelected ? Color.accentColor : hasData ? Color.orange.opacity(0.12) : Color.secondary.opacity(0.06))
            )
            .contentShape(.rect)
        }
        .buttonStyle(.plain)
        .disabled(isFuture)
        .accessibilityLabel(month.formatted(.dateTime.year().month(.wide).locale(appLocale)))
        .accessibilityValue(hasData ? String(localized: "有记录", bundle: .appLanguage) : "")
        .accessibilityAddTraits(isSelected ? .isSelected : [])
    }
}

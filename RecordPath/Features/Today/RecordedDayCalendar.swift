import SwiftUI
import SwiftData

/// A month calendar that marks the days with recorded tracks or stays, so the user can
/// see at a glance which days have something to look at.
struct RecordedDayCalendar: View {
    @Binding var selection: Date
    @Environment(\.modelContext) private var context
    @State private var month: Date
    @State private var recorded: Set<Date> = []

    private let calendar = Calendar.current

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
                Text(month.formatted(.dateTime.year().month(.wide)))
                    .font(.title3.bold())
                    .contentTransition(.numericText())
                Spacer()
                Button("上个月", systemImage: "chevron.left") { shiftMonth(-1) }
                    .labelStyle(.iconOnly)
                Button("下个月", systemImage: "chevron.right") { shiftMonth(1) }
                    .labelStyle(.iconOnly)
                    .disabled(isCurrentMonth)
            }
            .font(.title3.weight(.semibold))
            .padding(.horizontal, 4)

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
        .task(id: month) { loadRecordedDays() }
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
        .accessibilityLabel(day.formatted(date: .complete, time: .omitted))
        .accessibilityValue(hasData ? String(localized: "有记录") : "")
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
}

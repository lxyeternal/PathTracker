import SwiftUI

struct FirstsRoute: Hashable {}

extension LifeFirst.Kind {
    var tint: Color {
        switch self {
        case .beginning: .yellow
        case .abroad, .country: .red
        case .city: .indigo
        case .mustSee: .orange
        case .flight: .purple
        case .longWalk: .green
        case .lateNight: .blue
        case .nightAway: .teal
        }
    }
}

/// The latest few firsts, opening the whole list.
struct FirstsCard: View {
    let firsts: [LifeFirst]

    var body: some View {
        NavigationLink(value: FirstsRoute()) {
            VStack(alignment: .leading, spacing: 14) {
                HStack(alignment: .firstTextBaseline) {
                    Text("第一次").font(.title3.bold()).foregroundStyle(.primary)
                    Spacer()
                    Text("\(firsts.count) 个").font(.subheadline).foregroundStyle(.secondary).monospacedDigit()
                    Image(systemName: "chevron.forward").font(.footnote.weight(.semibold)).foregroundStyle(.tertiary)
                }
                VStack(alignment: .leading, spacing: 10) {
                    ForEach(firsts.suffix(3).reversed()) { first in
                        HStack(spacing: 12) {
                            FirstIcon(kind: first.kind, size: 30)
                            VStack(alignment: .leading, spacing: 1) {
                                Text(first.title).font(.subheadline.weight(.semibold)).foregroundStyle(.primary).lineLimit(1)
                                Text(first.date.formatted(.dateTime.year().month().day().locale(appLocale)))
                                    .font(.caption).foregroundStyle(.secondary)
                            }
                        }
                    }
                }
            }
            .padding(16)
            .background(.background.secondary, in: .rect(cornerRadius: 24, style: .continuous))
        }
        .buttonStyle(PressableStyle())
    }
}

struct FirstIcon: View {
    let kind: LifeFirst.Kind
    var size: CGFloat = 36

    var body: some View {
        Image(systemName: kind.symbol)
            .font(.system(size: size * 0.42, weight: .bold))
            .foregroundStyle(.white)
            .frame(width: size, height: size)
            .background(Circle().fill(kind.tint.gradient))
    }
}

/// Every first, year by year, with the ends of the map on top.
struct FirstsView: View {
    let firsts: [LifeFirst]
    let extremes: LifeExtremes
    @State private var appeared = false

    private var years: [(year: Int, items: [LifeFirst])] {
        let calendar = Calendar.current
        let grouped = Dictionary(grouping: firsts) { calendar.component(.year, from: $0.date) }
        return grouped.keys.sorted(by: >).map { year in (year, grouped[year]!.sorted { $0.date > $1.date }) }
    }

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 28) {
                Text("这些第一次，是你自己一步一步走出来的。")
                    .font(.subheadline).foregroundStyle(.secondary)
                if extremes.north != nil { ends }
                ForEach(years, id: \.year) { group in
                    VStack(alignment: .leading, spacing: 0) {
                        Text(verbatim: String(group.year))
                            .font(.system(.title, design: .rounded, weight: .bold))
                            .padding(.bottom, 12)
                        ForEach(Array(group.items.enumerated()), id: \.element.id) { index, first in
                            NavigationLink(value: DayRoute(day: Calendar.current.startOfDay(for: first.date))) {
                                row(first, isLast: index == group.items.count - 1)
                            }
                            .buttonStyle(.plain)
                        }
                    }
                    .opacity(appeared ? 1 : 0)
                    .offset(y: appeared ? 0 : 16)
                }
            }
            .padding(.horizontal)
            .padding(.bottom, 32)
        }
        .navigationTitle("第一次")
        .onAppear { withAnimation(.smooth(duration: 0.6)) { appeared = true } }
    }

    private func row(_ first: LifeFirst, isLast: Bool) -> some View {
        HStack(alignment: .top, spacing: 14) {
            VStack(spacing: 0) {
                FirstIcon(kind: first.kind)
                if !isLast {
                    Rectangle().fill(Color.secondary.opacity(0.2)).frame(width: 2).frame(maxHeight: .infinity)
                }
            }
            VStack(alignment: .leading, spacing: 3) {
                Text(first.title).font(.body.weight(.semibold))
                Text([first.place, first.date.formatted(.dateTime.month().day().locale(appLocale))].compactMap { $0 }.joined(separator: " · "))
                    .font(.subheadline).foregroundStyle(.secondary)
            }
            .padding(.top, 6)
            .padding(.bottom, 20)
            Spacer(minLength: 0)
            Image(systemName: "chevron.right").font(.caption.weight(.semibold)).foregroundStyle(.tertiary).padding(.top, 12)
        }
        .contentShape(.rect)
    }

    /// The furthest north, south, east and west as four tiles, and the furthest from home.
    private var ends: some View {
        VStack(alignment: .leading, spacing: 12) {
            Text("你到过的天涯海角").font(.headline)
            LazyVGrid(columns: [GridItem(.flexible(), spacing: 10), GridItem(.flexible(), spacing: 10)], spacing: 10) {
                ForEach(endPoints, id: \.label) { item in
                    VStack(alignment: .leading, spacing: 6) {
                        HStack {
                            Text(item.label).font(.caption.weight(.semibold)).foregroundStyle(.secondary)
                            Spacer()
                            Image(systemName: item.symbol)
                                .font(.caption.weight(.heavy))
                                .foregroundStyle(.white)
                                .frame(width: 24, height: 24)
                                .background(Circle().fill(Color.orange.gradient))
                        }
                        Text(item.point.name).font(.subheadline.weight(.semibold)).lineLimit(2)
                            .fixedSize(horizontal: false, vertical: true)
                        Spacer(minLength: 0)
                        Text(item.point.detail).font(.caption).foregroundStyle(.secondary).lineLimit(1)
                        Text(coordinate(item.point, vertical: item.vertical)).font(.caption2).foregroundStyle(.tertiary).monospacedDigit()
                    }
                    .padding(12)
                    .frame(maxWidth: .infinity, minHeight: 118, alignment: .topLeading)
                    .background(Color(uiColor: .systemBackground), in: .rect(cornerRadius: 16, style: .continuous))
                }
            }
            if let far = extremes.farthest, extremes.farthestDistance > 50_000 {
                HStack(spacing: 12) {
                    Image(systemName: "house.and.flag.fill").foregroundStyle(.orange)
                    VStack(alignment: .leading, spacing: 1) {
                        Text("离家最远").font(.caption.weight(.semibold)).foregroundStyle(.secondary)
                        Text(far.name).font(.subheadline.weight(.semibold)).lineLimit(1)
                        Text(far.detail).font(.caption).foregroundStyle(.secondary).lineLimit(1)
                    }
                    Spacer(minLength: 8)
                    Text(Format.distance(extremes.farthestDistance)).font(.headline).monospacedDigit()
                }
                .padding(12)
                .background(Color(uiColor: .systemBackground), in: .rect(cornerRadius: 16, style: .continuous))
            }
        }
        .padding(16)
        .background(.background.secondary, in: .rect(cornerRadius: 24, style: .continuous))
    }

    /// "北纬 65.7°" for north and south, "东经 140.4°" for east and west.
    private func coordinate(_ point: LifeExtremes.Point, vertical: Bool) -> String {
        let value = vertical ? point.latitude : point.longitude
        let degrees = abs(value).formatted(.number.precision(.fractionLength(1)).locale(appLocale))
        return switch (vertical, value >= 0) {
        case (true, true): String(localized: "北纬 \(degrees)°", bundle: .appLanguage)
        case (true, false): String(localized: "南纬 \(degrees)°", bundle: .appLanguage)
        case (false, true): String(localized: "东经 \(degrees)°", bundle: .appLanguage)
        case (false, false): String(localized: "西经 \(degrees)°", bundle: .appLanguage)
        }
    }

    private var endPoints: [(label: String, symbol: String, vertical: Bool, point: LifeExtremes.Point)] {
        [(String(localized: "最北", bundle: .appLanguage), "arrow.up", true, extremes.north),
         (String(localized: "最南", bundle: .appLanguage), "arrow.down", true, extremes.south),
         (String(localized: "最西", bundle: .appLanguage), "arrow.left", false, extremes.west),
         (String(localized: "最东", bundle: .appLanguage), "arrow.right", false, extremes.east)]
            .compactMap { label, symbol, vertical, point in point.map { (label, symbol, vertical, $0) } }
    }
}

import SwiftUI
import MapKit
import Photos

struct FirstsRoute: Hashable {}

extension LifeFirst.Kind {
    var tint: Color {
        switch self {
        case .beginning: Color(red: 0.95, green: 0.68, blue: 0.15)
        case .abroad, .country: Color(red: 0.88, green: 0.3, blue: 0.32)
        case .city: .indigo
        case .mustSee: .orange
        }
    }

    var label: String {
        switch self {
        case .beginning: String(localized: "开始", bundle: .appLanguage)
        case .abroad: String(localized: "出国", bundle: .appLanguage)
        case .country: String(localized: "新的国家", bundle: .appLanguage)
        case .city: String(localized: "新的城市", bundle: .appLanguage)
        case .mustSee: String(localized: "此生必去", bundle: .appLanguage)
        }
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

/// A ticket with a torn-off stub: two half-circle notches where the perforation runs.
struct TicketShape: Shape {
    var stub: CGFloat = 78
    var notch: CGFloat = 9

    func path(in rect: CGRect) -> Path {
        var notches = Path()
        notches.addEllipse(in: CGRect(x: rect.minX + stub - notch, y: rect.minY - notch, width: notch * 2, height: notch * 2))
        notches.addEllipse(in: CGRect(x: rect.minX + stub - notch, y: rect.maxY - notch, width: notch * 2, height: notch * 2))
        return Path(roundedRect: rect, cornerRadius: 18, style: .continuous).subtracting(notches)
    }
}

/// One first as a ticket: the date on the stub, what happened on the ticket.
struct FirstTicket: View {
    let first: LifeFirst

    var body: some View {
        let tint = first.kind.tint
        HStack(spacing: 0) {
            VStack(spacing: 0) {
                Text(first.date.formatted(.dateTime.month(.abbreviated).locale(appLocale)))
                    .font(.caption.weight(.bold)).foregroundStyle(tint)
                Text(verbatim: String(Calendar.current.component(.day, from: first.date)))
                    .font(.system(size: 34, weight: .bold, design: .serif))
                    .foregroundStyle(.primary)
                Text(verbatim: String(Calendar.current.component(.year, from: first.date)))
                    .font(.caption2.weight(.medium)).foregroundStyle(.secondary)
            }
            .frame(width: 78)
            // The perforation.
            Perforation()
                .stroke(tint.opacity(0.45), style: StrokeStyle(lineWidth: 1.5, dash: [3, 4]))
                .frame(width: 2)
                .padding(.vertical, 12)
            VStack(alignment: .leading, spacing: 4) {
                Label(first.kind.label, systemImage: first.kind.symbol)
                    .font(.caption2.weight(.bold))
                    .foregroundStyle(tint)
                Text(first.title)
                    .font(.system(.headline, design: .serif))
                    .foregroundStyle(.primary)
                    .lineLimit(2)
                    .multilineTextAlignment(.leading)
                if let place = first.place {
                    Text(place).font(.caption).foregroundStyle(.secondary).lineLimit(1)
                }
            }
            .padding(.horizontal, 16)
            .padding(.vertical, 14)
            Spacer(minLength: 0)
        }
        .background(TicketShape().fill(LinearGradient(colors: [tint.opacity(0.18), tint.opacity(0.07)], startPoint: .leading, endPoint: .trailing)))
    }

    private struct Perforation: Shape {
        func path(in rect: CGRect) -> Path {
            Path { $0.move(to: CGPoint(x: rect.midX, y: rect.minY)); $0.addLine(to: CGPoint(x: rect.midX, y: rect.maxY)) }
        }
    }
}

/// The newest first as a ticket, the others as a row of little badges.
struct FirstsCard: View {
    let firsts: [LifeFirst]

    var body: some View {
        NavigationLink(value: FirstsRoute()) {
            VStack(alignment: .leading, spacing: 14) {
                HStack(alignment: .firstTextBaseline, spacing: 4) {
                    Text("第一次").font(.system(.title2, design: .serif, weight: .bold)).foregroundStyle(.primary)
                    Spacer()
                    Text(verbatim: "\(firsts.count)").font(.system(size: 26, weight: .bold, design: .rounded)).foregroundStyle(.primary)
                    Image(systemName: "chevron.forward").font(.footnote.weight(.semibold)).foregroundStyle(.tertiary).padding(.leading, 4)
                }
                if let latest = firsts.last {
                    FirstTicket(first: latest)
                }
                if firsts.count > 1 {
                    HStack(spacing: 10) {
                        HStack(spacing: -8) {
                            ForEach(Array(firsts.dropLast().suffix(5).reversed())) { first in
                                FirstIcon(kind: first.kind, size: 28)
                                    .overlay(Circle().stroke(Color(uiColor: .secondarySystemBackground), lineWidth: 2))
                            }
                        }
                        Text("还有 \(firsts.count - 1) 个第一次").font(.footnote).foregroundStyle(.secondary)
                    }
                }
            }
            .padding(18)
            .background(.background.secondary, in: .rect(cornerRadius: 28, style: .continuous))
        }
        .buttonStyle(PressableStyle())
    }
}

/// Every first, year by year, with the ends of the map on a compass at the top.
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
            // Lazy, so pictures are only looked for when their year comes into view.
            LazyVStack(alignment: .leading, spacing: 26) {
                VStack(alignment: .leading, spacing: 6) {
                    Text("第一次").font(.system(size: 40, weight: .bold, design: .serif))
                    Text("这些第一次，是你自己一步一步走出来的。").font(.subheadline).foregroundStyle(.secondary)
                }
                if extremes.north != nil { CompassCard(extremes: extremes) }
                ForEach(Array(years.enumerated()), id: \.element.year) { offset, group in
                    VStack(alignment: .leading, spacing: 4) {
                        HStack(alignment: .lastTextBaseline, spacing: 10) {
                            Text(verbatim: String(group.year))
                                .font(.system(size: 54, weight: .heavy, design: .serif))
                                .foregroundStyle(LinearGradient(colors: [.primary.opacity(0.85), .primary.opacity(0.2)], startPoint: .top, endPoint: .bottom))
                            Text("\(group.items.count) 个第一次").font(.footnote).foregroundStyle(.secondary)
                        }
                        ForEach(Array(group.items.enumerated()), id: \.element.id) { index, first in
                            NavigationLink(value: DayRoute(day: Calendar.current.startOfDay(for: first.date))) {
                                row(first, isLast: index == group.items.count - 1)
                            }
                            .buttonStyle(PressableStyle())
                        }
                    }
                    .opacity(appeared ? 1 : 0)
                    .offset(y: appeared ? 0 : 20)
                    .animation(.smooth(duration: 0.6).delay(Double(min(offset, 5)) * 0.08), value: appeared)
                }
            }
            .padding(.horizontal)
            .padding(.bottom, 32)
        }
        .navigationBarTitleDisplayMode(.inline)
        .onAppear { appeared = true }
    }

    /// Date on the left, the kind as a dot on the line, the moment in a card.
    private func row(_ first: LifeFirst, isLast: Bool) -> some View {
        HStack(alignment: .top, spacing: 12) {
            VStack(alignment: .trailing, spacing: 0) {
                Text(first.date.formatted(.dateTime.month(.abbreviated).locale(appLocale)))
                    .font(.caption2.weight(.semibold)).foregroundStyle(.secondary)
                Text(verbatim: String(Calendar.current.component(.day, from: first.date)))
                    .font(.system(.title3, design: .rounded, weight: .bold)).foregroundStyle(.primary)
            }
            .frame(width: 40, alignment: .trailing)
            .padding(.top, 10)
            VStack(spacing: 0) {
                FirstIcon(kind: first.kind, size: 30).padding(.top, 10)
                if !isLast {
                    Rectangle().fill(Color.secondary.opacity(0.18)).frame(width: 2).frame(maxHeight: .infinity)
                }
            }
            VStack(alignment: .leading, spacing: 4) {
                Text(first.kind.label).font(.caption2.weight(.bold)).foregroundStyle(first.kind.tint)
                Text(first.title).font(.system(.body, design: .serif, weight: .semibold)).foregroundStyle(.primary)
                    .multilineTextAlignment(.leading)
                if let place = first.place {
                    Text(place).font(.footnote).foregroundStyle(.secondary).lineLimit(1)
                }
            }
            .padding(.trailing, 64)
            .frame(maxWidth: .infinity, alignment: .leading)
            .padding(14)
            .overlay(alignment: .trailing) { FirstPicture(first: first).padding(.trailing, 12) }
            .background(.background.secondary, in: .rect(cornerRadius: 18, style: .continuous))
            .padding(.bottom, 10)
        }
    }
}

/// The picture beside a first, so every one has one: the place's own photograph when it's
/// worth a lifetime, otherwise a photo the person took there, otherwise the country's flag or
/// a small map of the town.
private struct FirstPicture: View {
    let first: LifeFirst
    @State private var image: UIImage?
    @State private var asset: PHAsset?
    @Environment(\.colorScheme) private var colorScheme

    private static let side: CGFloat = 56
    private static let maps = NSCache<NSString, UIImage>()

    private var isCountry: Bool { first.kind == .country || first.kind == .abroad }

    var body: some View {
        Group {
            if let asset {
                AssetThumbnail(asset: asset, side: Self.side)
            } else if let image {
                Image(uiImage: image).resizable().scaledToFill()
            } else if isCountry, let code = first.countryCode {
                Text(verbatim: String.flag(for: code)).font(.system(size: 30))
                    .frame(maxWidth: .infinity, maxHeight: .infinity)
                    .background(first.kind.tint.opacity(0.12))
            } else {
                Image(systemName: first.kind.symbol).font(.title3).foregroundStyle(first.kind.tint)
                    .frame(maxWidth: .infinity, maxHeight: .infinity)
                    .background(first.kind.tint.opacity(0.12))
            }
        }
        .frame(width: Self.side, height: Self.side)
        .clipShape(.rect(cornerRadius: 12, style: .continuous))
        .task(id: "\(first.id)|\(colorScheme == .dark)") {
            if let id = first.mustSeeID {
                image = await MustSeePhotos.thumb(id)
                return
            }
            guard let latitude = first.latitude, let longitude = first.longitude else { return }
            let location = CLLocation(latitude: latitude, longitude: longitude)
            // A country is the days after landing, anywhere in it; a town is that day, in town.
            let days: Double = isCountry ? 3 : 1
            let interval = DateInterval(start: first.date.addingTimeInterval(-600),
                                        end: max(first.until ?? first.date, first.date.addingTimeInterval(days * 86_400)))
            if let found = PlacePhotos.cover(for: "first|\(first.id)", interval: interval, near: location, within: isCountry ? 400_000 : 40_000) {
                asset = found
            } else if !isCountry {
                image = await Self.map(of: location.coordinate, dark: colorScheme == .dark)
            }
        }
    }

    /// The town from above, small.
    private static func map(of coordinate: CLLocationCoordinate2D, dark: Bool) async -> UIImage? {
        let key = String(format: "%.3f,%.3f,%d", coordinate.latitude, coordinate.longitude, dark ? 1 : 0) as NSString
        if let cached = maps.object(forKey: key) { return cached }
        let options = MKMapSnapshotter.Options()
        options.region = MKCoordinateRegion(center: coordinate.onMap, latitudinalMeters: 6_000, longitudinalMeters: 6_000)
        options.size = CGSize(width: side * 2, height: side * 2)
        options.traitCollection = UITraitCollection(userInterfaceStyle: dark ? .dark : .light)
        let configuration = MKStandardMapConfiguration(elevationStyle: .flat, emphasisStyle: .muted)
        configuration.pointOfInterestFilter = .excludingAll
        options.preferredConfiguration = configuration
        guard let image = try? await MKMapSnapshotter(options: options).start().image else { return nil }
        maps.setObject(image, forKey: key)
        return image
    }
}

/// The four ends of your map around a compass rose, and how far from home you've been.
struct CompassCard: View {
    let extremes: LifeExtremes
    @State private var turn = -40.0

    var body: some View {
        VStack(spacing: 16) {
            HStack {
                Text("你到过的天涯海角").font(.system(.headline, design: .serif))
                Spacer()
            }
            .foregroundStyle(.white)
            ZStack {
                FirstsCompassRose()
                    .frame(width: 140, height: 140)
                    .rotationEffect(.degrees(turn))
                VStack {
                    end(extremes.north, label: String(localized: "最北", bundle: .appLanguage), vertical: true)
                    Spacer()
                    end(extremes.south, label: String(localized: "最南", bundle: .appLanguage), vertical: true)
                }
                HStack {
                    end(extremes.west, label: String(localized: "最西", bundle: .appLanguage), vertical: false)
                    Spacer()
                    end(extremes.east, label: String(localized: "最东", bundle: .appLanguage), vertical: false)
                }
            }
            .frame(height: 320)
            if let far = extremes.farthest, extremes.farthestDistance > 50_000 {
                HStack(spacing: 12) {
                    Image(systemName: "house.and.flag.fill").font(.title3).foregroundStyle(gold)
                    VStack(alignment: .leading, spacing: 2) {
                        Text("离家最远").font(.caption.weight(.semibold)).foregroundStyle(.white.opacity(0.6))
                        Text(far.name).font(.subheadline.weight(.semibold)).foregroundStyle(.white).lineLimit(1)
                        Text(far.detail).font(.caption).foregroundStyle(.white.opacity(0.6)).lineLimit(1)
                    }
                    Spacer(minLength: 8)
                    Text(Format.distance(extremes.farthestDistance))
                        .font(.system(.title3, design: .rounded, weight: .bold)).foregroundStyle(gold)
                        .monospacedDigit()
                }
                .padding(14)
                .background(.white.opacity(0.08), in: .rect(cornerRadius: 16, style: .continuous))
            }
        }
        .padding(18)
        .background {
            ZStack {
                LinearGradient(colors: [Color(red: 0.07, green: 0.09, blue: 0.18), Color(red: 0.13, green: 0.12, blue: 0.24)], startPoint: .top, endPoint: .bottom)
                RadialGradient(colors: [gold.opacity(0.18), .clear], center: .center, startRadius: 10, endRadius: 220)
            }
        }
        .clipShape(.rect(cornerRadius: 28, style: .continuous))
        .onAppear { withAnimation(.spring(response: 1.6, dampingFraction: 0.55)) { turn = 0 } }
    }

    private var gold: Color { Color(red: 1, green: 0.8, blue: 0.45) }

    private func end(_ point: LifeExtremes.Point?, label: String, vertical: Bool) -> some View {
        VStack(spacing: 2) {
            if let point {
                Text(label).font(.caption2.weight(.bold)).foregroundStyle(gold).tracking(1)
                Text(point.name).font(.footnote.weight(.semibold)).foregroundStyle(.white).lineLimit(2)
                Text(point.detail).font(.caption2).foregroundStyle(.white.opacity(0.6)).lineLimit(1)
                Text(coordinate(point, vertical: vertical)).font(.caption2.monospacedDigit()).foregroundStyle(.white.opacity(0.45))
            }
        }
        .multilineTextAlignment(.center)
        .frame(width: vertical ? 220 : 84)
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
}

/// A drawn compass rose: rings, ticks, and an eight-pointed star in gold.
struct FirstsCompassRose: View {
    var body: some View {
        Canvas { context, size in
            let c = CGPoint(x: size.width / 2, y: size.height / 2)
            let r = min(size.width, size.height) / 2
            let gold = Color(red: 1, green: 0.8, blue: 0.45)
            for (scale, opacity) in [(1.0, 0.35), (0.82, 0.2), (0.4, 0.2)] as [(CGFloat, Double)] {
                context.stroke(Path(ellipseIn: CGRect(x: c.x - r * scale, y: c.y - r * scale, width: r * 2 * scale, height: r * 2 * scale)),
                               with: .color(gold.opacity(opacity)), lineWidth: 1)
            }
            for i in 0..<72 {
                let a = Double(i) / 72 * 2 * .pi
                let inner = r * (i % 9 == 0 ? 0.86 : 0.93)
                var tick = Path()
                tick.move(to: CGPoint(x: c.x + cos(a) * inner, y: c.y + sin(a) * inner))
                tick.addLine(to: CGPoint(x: c.x + cos(a) * r * 0.99, y: c.y + sin(a) * r * 0.99))
                context.stroke(tick, with: .color(gold.opacity(i % 9 == 0 ? 0.6 : 0.25)), lineWidth: 1)
            }
            // Eight points: long ones to the cardinal directions, short between.
            for i in 0..<8 {
                let a = Double(i) / 8 * 2 * .pi - .pi / 2
                let length = i % 2 == 0 ? r * 0.8 : r * 0.42
                let width = i % 2 == 0 ? r * 0.12 : r * 0.08
                let tip = CGPoint(x: c.x + cos(a) * length, y: c.y + sin(a) * length)
                let left = CGPoint(x: c.x + cos(a - .pi / 2) * width, y: c.y + sin(a - .pi / 2) * width)
                let right = CGPoint(x: c.x + cos(a + .pi / 2) * width, y: c.y + sin(a + .pi / 2) * width)
                var half1 = Path(); half1.move(to: c); half1.addLine(to: left); half1.addLine(to: tip); half1.closeSubpath()
                var half2 = Path(); half2.move(to: c); half2.addLine(to: right); half2.addLine(to: tip); half2.closeSubpath()
                context.fill(half1, with: .color(i == 0 ? gold : gold.opacity(i % 2 == 0 ? 0.75 : 0.45)))
                context.fill(half2, with: .color(i == 0 ? gold.opacity(0.7) : gold.opacity(i % 2 == 0 ? 0.4 : 0.25)))
            }
            context.fill(Path(ellipseIn: CGRect(x: c.x - 5, y: c.y - 5, width: 10, height: 10)), with: .color(gold))
            context.fill(Path(ellipseIn: CGRect(x: c.x - 2, y: c.y - 2, width: 4, height: 4)), with: .color(Color(red: 0.07, green: 0.09, blue: 0.18)))
        }
    }
}

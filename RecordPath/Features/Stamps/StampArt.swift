import SwiftUI
import SwiftData
import CoreLocation

/// Draws a stamp as it would look pressed onto paper: the outline, the words, the ink worn in
/// places. Laid out at a fixed size and scaled to fit, so it looks the same everywhere.
struct StampArt: View {
    let stamp: Stamp
    /// The path walked on the first day in a city, drawn in the middle of its stamp.
    var route: [CGPoint] = []
    /// False for a stamp not yet pressed, shown as a faint outline only.
    var inked = true

    var body: some View {
        let base = Self.size(for: stamp)
        GeometryReader { proxy in
            let scale = min(proxy.size.width / base.width, proxy.size.height / base.height)
            art
                .frame(width: base.width, height: base.height)
                .scaleEffect(scale)
                .frame(width: proxy.size.width, height: proxy.size.height)
        }
        .aspectRatio(base.width / base.height, contentMode: .fit)
        .accessibilityElement()
        .accessibilityLabel(accessibilityText)
    }

    @ViewBuilder
    private var art: some View {
        switch stamp.kind {
        case .entry, .exit: BorderStamp(stamp: stamp).inkWorn(seed: stamp.seed, inked: inked)
        case .province: ProvinceSealArt(id: stamp.provinceID ?? "").inkWorn(seed: stamp.seed, inked: inked, wear: 0.6)
        case .city: CityStampArt(stamp: stamp, route: route).inkWorn(seed: stamp.seed, inked: inked)
        case .special: SpecialStampArt(stamp: stamp).inkWorn(seed: stamp.seed, inked: inked)
        case .set:
            // Solid seals show every speck; they wear less.
            let isSeal = if case .seal = StampSet.named(stamp.code)?.layout { true } else { false }
            SetStampArt(stamp: stamp).inkWorn(seed: stamp.seed, inked: inked, wear: isSeal ? 0.45 : 1)
        }
    }

    static func size(for stamp: Stamp) -> CGSize {
        switch stamp.kind {
        case .province: CGSize(width: 100, height: 100)
        case .city:
            CGSize(width: 140, height: 140)
        case .set:
            SetStampArt.size(StampSet.named(stamp.code))
        case .special where stamp.code == "record.high":
            CGSize(width: 150, height: 140)
        case .special where (stamp.code ?? "").hasPrefix("record."):
            CGSize(width: 110, height: 110)
        case .special:
            switch SpecialStampStyle.of(stamp.code ?? "").shape {
            case .ticket, .hexagon: CGSize(width: 172, height: 110)
            default: CGSize(width: 140, height: 140)
            }
        case .entry, .exit:
            switch CountryStampStyle.of(stamp.countryCode ?? "").shape {
            case .circle, .octagon, .scalloped: CGSize(width: 140, height: 140)
            case .oval: CGSize(width: 180, height: 118)
            default: CGSize(width: 172, height: 110)
            }
        }
    }

    private var accessibilityText: String {
        let date = stamp.date.formatted(.dateTime.year().month().day().locale(appLocale))
        switch stamp.kind {
        case .entry: return String(localized: "入境章，\(WorldInsights.countryName(code: stamp.countryCode ?? "", fallback: nil))，\(date)", bundle: .appLanguage)
        case .exit: return String(localized: "出境章，\(WorldInsights.countryName(code: stamp.countryCode ?? "", fallback: nil))，\(date)", bundle: .appLanguage)
        case .province: return String(localized: "\(stamp.province?.name ?? "")省份印，\(date)", bundle: .appLanguage)
        case .city: return String(localized: "\(stamp.city ?? "")城市章，\(date)", bundle: .appLanguage)
        case .special: return "\(SpecialStampStyle.of(stamp.code ?? "").label), \(stamp.value ?? ""), \(stamp.city ?? ""), \(date)"
        case .set: return String(localized: "\(StampSet.named(stamp.code)?.title ?? "")套章，\(date)", bundle: .appLanguage)
        }
    }
}

// MARK: - Border stamps

private struct BorderStamp: View {
    let stamp: Stamp

    private var style: CountryStampStyle { CountryStampStyle.of(stamp.countryCode ?? "") }
    private var ink: Color { style.ink.color }
    private var isEntry: Bool { stamp.kind == .entry }
    private var symbol: String {
        stamp.byAir ? (isEntry ? "airplane.arrival" : "airplane.departure") : (isEntry ? "arrow.down.right" : "arrow.up.right")
    }
    private var label: String {
        isEntry ? String(localized: "入境 · ARRIVAL", bundle: .appLanguage) : String(localized: "出境 · DEPARTURE", bundle: .appLanguage)
    }
    private var detail: String? {
        if isEntry { return stamp.port?.uppercased() }
        let stayed = String(localized: "停留 \(stamp.days) 天", bundle: .appLanguage)
        return [stayed, stamp.port?.uppercased()].compactMap { $0 }.joined(separator: " · ")
    }

    var body: some View {
        ZStack {
            StampOutline(shape: style.shape).stroke(ink, lineWidth: 2.8)
            StampOutline(shape: style.shape, inset: 5.5).stroke(ink, style: StrokeStyle(lineWidth: 0.9, dash: isEntry ? [] : [3, 2]))
            switch style.shape {
            case .circle, .octagon, .scalloped: round
            default: flat
            }
        }
        .foregroundStyle(ink)
    }

    /// Name across the top, the date large in the middle, how and where along the bottom.
    private var flat: some View {
        VStack(spacing: 3) {
            Text(style.native)
                .font(.custom("AvenirNextCondensed-Heavy", fixedSize: 15))
                .tracking(1.2)
                .lineLimit(1)
                .minimumScaleFactor(0.5)
            Rectangle().frame(height: 0.9).padding(.horizontal, 6)
            HStack(spacing: 4) {
                Image(systemName: symbol).font(.system(size: 10, weight: .bold))
                Text(label).font(.custom("AvenirNextCondensed-DemiBold", fixedSize: 9.5)).tracking(0.8)
            }
            Text(Self.date(stamp.date))
                .font(.system(size: 19, weight: .heavy, design: .monospaced))
                .lineLimit(1)
                .minimumScaleFactor(0.7)
            if let detail {
                Text(detail)
                    .font(.custom("AvenirNextCondensed-DemiBold", fixedSize: 9))
                    .tracking(0.5)
                    .lineLimit(1)
                    .minimumScaleFactor(0.6)
            }
        }
        .padding(.horizontal, style.shape == .oval ? 26 : (style.shape == .hexagon ? 24 : 14))
        .padding(.vertical, 10)
    }

    /// The name and the label run round the rim; the date sits in the middle.
    private var round: some View {
        ZStack {
            Circle().inset(by: 26).stroke(ink, lineWidth: 0.8)
            ArcText(text: style.native, radius: 56, font: .custom("AvenirNextCondensed-Heavy", fixedSize: 12.5), color: ink, tracking: 1.5)
            ArcText(text: label, radius: 56, font: .custom("AvenirNextCondensed-DemiBold", fixedSize: 9), color: ink, bottom: true, tracking: 1)
            VStack(spacing: 2) {
                Image(systemName: symbol).font(.system(size: 13, weight: .bold))
                Text(Self.shortDate(stamp.date))
                    .font(.system(size: 15, weight: .heavy, design: .monospaced))
                Text(Self.year(stamp.date))
                    .font(.system(size: 11, weight: .bold, design: .monospaced))
                if let port = isEntry ? stamp.port : String(localized: "\(stamp.days) 天", bundle: .appLanguage) {
                    Text(port.uppercased())
                        .font(.custom("AvenirNextCondensed-DemiBold", fixedSize: 7.5))
                        .lineLimit(1)
                        .minimumScaleFactor(0.6)
                        .frame(width: 66)
                }
            }
        }
    }

    /// "28 OCT 2026", the way border stamps print it.
    static func date(_ date: Date) -> String { StampDate.long(date) }
    static func shortDate(_ date: Date) -> String {
        date.formatted(.verbatim("\(day: .twoDigits) \(month: .abbreviated)", locale: StampDate.english, timeZone: .current,
                                 calendar: Calendar(identifier: .gregorian))).uppercased()
    }
    static func year(_ date: Date) -> String { StampDate.year(date) }
}

enum StampDate {
    static let english = Locale(identifier: "en_US_POSIX")

    static func long(_ date: Date) -> String {
        date.formatted(.verbatim("\(day: .twoDigits) \(month: .abbreviated) \(year: .defaultDigits)", locale: english,
                                 timeZone: .current, calendar: Calendar(identifier: .gregorian))).uppercased()
    }

    static func year(_ date: Date) -> String {
        date.formatted(.verbatim("\(year: .defaultDigits)", timeZone: .current, calendar: Calendar(identifier: .gregorian)))
    }
}

// MARK: - Special stamps

/// Crossing the equator or the date line, the Arctic Circle, a New Year's Eve, the farthest
/// north you've been: each with its own shape and ink.
private struct SpecialStampArt: View {
    let stamp: Stamp

    @ViewBuilder
    var body: some View {
        switch stamp.code ?? "" {
        case "record.high": PeakStamp(stamp: stamp)
        case let code where code.hasPrefix("record."): DirectionSeal(direction: String(code.dropFirst("record.".count)))
        default: crossing
        }
    }

    private var crossing: some View {
        let style = SpecialStampStyle.of(stamp.code ?? "")
        let ink = style.ink.color
        let isNewYear = (stamp.code ?? "").hasPrefix("newyear")
        return ZStack {
            StampOutline(shape: style.shape).stroke(ink, lineWidth: 2.8)
            switch style.shape {
            case .ticket, .hexagon:
                StampOutline(shape: style.shape, inset: 5.5).stroke(ink, lineWidth: 0.9)
                VStack(spacing: 3) {
                    Text(verbatim: style.label)
                        .font(.custom("AvenirNextCondensed-Heavy", fixedSize: 11)).tracking(1)
                        .lineLimit(1).minimumScaleFactor(0.5)
                    Rectangle().frame(height: 0.9).padding(.horizontal, 8)
                    HStack(spacing: 6) {
                        Image(systemName: style.symbol).font(.system(size: 15, weight: .bold))
                        Text(verbatim: stamp.value ?? "").font(.system(size: 24, weight: .heavy, design: .monospaced))
                    }
                    Text(verbatim: [stamp.city, stamp.date == .distantPast ? nil : StampDate.long(stamp.date)]
                            .compactMap { $0 }.joined(separator: " · ").uppercased())
                        .font(.custom("AvenirNextCondensed-DemiBold", fixedSize: 9))
                        .lineLimit(1).minimumScaleFactor(0.5)
                }
                .padding(.horizontal, style.shape == .hexagon ? 28 : 16)
            default:
                Circle().inset(by: 26).stroke(ink, lineWidth: 0.8)
                ArcText(text: style.label, radius: 56, font: Self.font(style.label, size: 11), color: ink, tracking: 1.2)
                if stamp.date != .distantPast {
                    ArcText(text: StampDate.long(stamp.date), radius: 56, font: .custom("AvenirNextCondensed-DemiBold", fixedSize: 9),
                            color: ink, bottom: true, tracking: 1)
                }
                if stamp.code == "equator" {
                    // The line itself, straight through the middle.
                    Rectangle().frame(width: 92, height: 1.4).offset(y: 12)
                    Rectangle().frame(width: 92, height: 0.6).offset(y: 15)
                }
                VStack(spacing: 2) {
                    Image(systemName: style.symbol).font(.system(size: isNewYear ? 11 : 13, weight: .bold))
                    Text(verbatim: stamp.value ?? "")
                        .font(isNewYear ? .system(size: 28, weight: .black, design: .rounded) : .system(size: 16, weight: .heavy, design: .monospaced))
                        .lineLimit(1).minimumScaleFactor(0.6)
                    if let city = stamp.city {
                        Text(verbatim: city.uppercased())
                            .font(Self.font(city, size: 8))
                            .lineLimit(1).minimumScaleFactor(0.6)
                            .frame(width: 70)
                            // Below the equator's line.
                            .padding(.top, stamp.code == "equator" ? 9 : 0)
                    }
                }
            }
        }
        .foregroundStyle(ink)
    }

    static func font(_ text: String, size: CGFloat) -> Font {
        text.unicodeScalars.allSatisfy { $0.value < 0x0250 || $0.value == 0x00B7 }
            ? .custom("AvenirNextCondensed-Heavy", fixedSize: size) : .system(size: size, weight: .heavy)
    }
}

/// A completed set, drawn in its own layout: a carved seal of its name, its cities as a route
/// on a little map, or a luggage label.
private struct SetStampArt: View {
    let stamp: Stamp

    var body: some View {
        let set = StampSet.named(stamp.code)
        let ink = (set?.ink ?? .crimson).color
        Group {
            if let set {
                switch set.layout {
                case .seal(let carved): SetSeal(set: set, carved: carved)
                case .map(let shape): SetRouteStamp(set: set, shape: shape, date: stamp.date)
                case .label(let shape): SetLabel(set: set, shape: shape, date: stamp.date)
                }
            }
        }
        .foregroundStyle(ink)
    }

    static func size(_ set: StampSet?) -> CGSize {
        switch set?.layout {
        case .seal:
            (set?.title.count ?? 0) >= 4 ? CGSize(width: 160, height: 160) : CGSize(width: 116, height: 176)
        case .map(let shape), .label(let shape):
            switch shape {
            case .circle, .scalloped, .octagon: CGSize(width: 176, height: 176)
            case .oval: CGSize(width: 196, height: 134)
            default: CGSize(width: 196, height: 128)
            }
        case nil: CGSize(width: 176, height: 176)
        }
    }

    static func font(_ text: String, size: CGFloat) -> Font {
        text.unicodeScalars.allSatisfy { $0.value < 0x0250 || $0.value == 0x00B7 }
            ? .custom("AvenirNextCondensed-Heavy", fixedSize: size) : .system(size: size, weight: .heavy)
    }

    static func date(_ date: Date) -> String {
        date == .distantPast ? "" : StampDate.long(date)
    }
}

/// The set's name cut into a seal: four characters in two columns read right to left, or two
/// or three down a tall stone. White characters cut into red, or red characters left standing.
private struct SetSeal: View {
    let set: StampSet
    let carved: Bool

    var body: some View {
        GeometryReader { geo in
            let w = geo.size.width, h = geo.size.height
            let chars = set.title.map(String.init)
            ZStack {
                if carved {
                    // Cut out of the stone, so the paper shows through, inked or not.
                    RoundedRectangle(cornerRadius: w * 0.07, style: .continuous).fill(.foreground)
                    RoundedRectangle(cornerRadius: w * 0.04, style: .continuous).inset(by: w * 0.05).stroke(.black, lineWidth: w * 0.012)
                        .blendMode(.destinationOut)
                } else {
                    RoundedRectangle(cornerRadius: w * 0.06, style: .continuous).inset(by: w * 0.02).stroke(.foreground, lineWidth: w * 0.055)
                    RoundedRectangle(cornerRadius: w * 0.03, style: .continuous).inset(by: w * 0.1).stroke(.foreground, lineWidth: w * 0.012)
                }
                Group {
                    if chars.count >= 4 {
                        // Right column first, top to bottom, the way seals are read.
                        HStack(spacing: w * 0.02) {
                            column([chars[2], chars[3]], size: w * 0.34)
                            column([chars[0], chars[1]], size: w * 0.34)
                        }
                    } else {
                        column(chars, size: min(w * 0.62, h * 0.78 / CGFloat(max(chars.count, 1))))
                    }
                }
                .foregroundStyle(carved ? AnyShapeStyle(Color.black) : AnyShapeStyle(.foreground))
                .blendMode(carved ? .destinationOut : .normal)
            }
            .compositingGroup()
        }
    }

    private func column(_ chars: [String], size: CGFloat) -> some View {
        VStack(spacing: -size * 0.08) {
            ForEach(Array(chars.enumerated()), id: \.offset) { _, char in
                Text(verbatim: char).font(.system(size: size, weight: .black))
            }
        }
    }
}

/// The set's cities where they really are, joined in order by a dashed route.
private struct SetRouteStamp: View {
    let set: StampSet
    let shape: StampShape
    let date: Date

    private var round: Bool { shape == .circle || shape == .scalloped || shape == .octagon }

    var body: some View {
        GeometryReader { geo in
            let w = geo.size.width, h = geo.size.height
            ZStack {
                StampOutline(shape: shape).stroke(.foreground, lineWidth: 2.8)
                StampOutline(shape: shape, inset: 6.5).stroke(.foreground, lineWidth: 0.9)
                if round {
                    ArcText(text: set.title, radius: w / 2 - 22, font: SetStampArt.font(set.title, size: 14), color: .primary,
                            tracking: 2).foregroundStyle(.foreground)
                    ArcText(text: set.motto, radius: w / 2 - 22, font: SetStampArt.font(set.motto, size: 9), color: .primary,
                            bottom: true, tracking: 1.4)
                    route.frame(width: w * 0.48, height: h * 0.38)
                    Text(verbatim: SetStampArt.date(date)).font(.system(size: 7.5, weight: .bold, design: .monospaced))
                        .offset(y: h * 0.25)
                } else {
                    VStack(spacing: 4) {
                        Text(verbatim: set.title).font(SetStampArt.font(set.title, size: 15)).tracking(1.5)
                            .lineLimit(1).minimumScaleFactor(0.5)
                        route.frame(width: w * 0.62, height: h * 0.34)
                        HStack(spacing: 5) {
                            Image(systemName: set.symbol).font(.system(size: 8, weight: .bold))
                            Text(verbatim: set.motto).font(SetStampArt.font(set.motto, size: 8.5)).tracking(1)
                            if !SetStampArt.date(date).isEmpty {
                                Text(verbatim: "· " + SetStampArt.date(date)).font(.system(size: 7.5, weight: .bold, design: .monospaced))
                            }
                        }
                        .lineLimit(1).minimumScaleFactor(0.6)
                    }
                    .padding(.horizontal, shape == .hexagon ? w * 0.16 : w * 0.09)
                }
            }
            .frame(width: w, height: h)
        }
    }

    /// The member cities, projected flat and fitted to the box keeping their shape.
    private var route: some View {
        Canvas { context, size in
            let entries = set.members.compactMap { title in CityStampStyle.catalog.first { $0.title == title } }
            guard entries.count > 1 else { return }
            let k = cos(entries[0].latitude * .pi / 180)
            let xs = entries.map { $0.longitude * k }, ys = entries.map { -$0.latitude }
            let minX = xs.min()!, maxX = xs.max()!, minY = ys.min()!, maxY = ys.max()!
            let scale = min(size.width / max(maxX - minX, 0.01), size.height / max(maxY - minY, 0.01)) * 0.86
            let ox = (size.width - (maxX - minX) * scale) / 2, oy = (size.height - (maxY - minY) * scale) / 2
            let points = zip(xs, ys).map { CGPoint(x: ox + ($0 - minX) * scale, y: oy + ($1 - minY) * scale) }
            var line = Path()
            line.addLines(points)
            context.stroke(line, with: .foreground, style: StrokeStyle(lineWidth: 1.3, lineCap: .round, dash: [3, 2.5]))
            for (index, point) in points.enumerated() {
                let r: CGFloat = index == 0 || index == points.count - 1 ? 3.6 : 2.8
                context.fill(Path(ellipseIn: CGRect(x: point.x - r, y: point.y - r, width: r * 2, height: r * 2)), with: .foreground)
                if index == 0 {
                    let ring = r + 2.4
                    context.stroke(Path(ellipseIn: CGRect(x: point.x - ring, y: point.y - ring, width: ring * 2, height: ring * 2)),
                                   with: .foreground, lineWidth: 0.9)
                }
            }
        }
    }
}

/// A luggage label: the set's name large, a rule with its emblem, the cities along the foot.
private struct SetLabel: View {
    let set: StampSet
    let shape: StampShape
    let date: Date

    var body: some View {
        GeometryReader { geo in
            let w = geo.size.width
            ZStack {
                StampOutline(shape: shape).stroke(.foreground, lineWidth: 3.2)
                StampOutline(shape: shape, inset: 7).stroke(.foreground, style: StrokeStyle(lineWidth: 1, dash: [2, 2]))
                VStack(spacing: 3) {
                    Text(verbatim: set.motto).font(SetStampArt.font(set.motto, size: 8)).tracking(2.5)
                        .lineLimit(1).minimumScaleFactor(0.6)
                    Text(verbatim: set.title).font(SetStampArt.font(set.title, size: 26)).tracking(1)
                        .lineLimit(1).minimumScaleFactor(0.5)
                    HStack(spacing: 6) {
                        Rectangle().frame(height: 0.9)
                        Image(systemName: set.symbol).font(.system(size: 10, weight: .bold))
                        Rectangle().frame(height: 0.9)
                    }
                    .frame(width: w * 0.5)
                    Text(verbatim: set.members.joined(separator: " · "))
                        .font(SetStampArt.font(set.members.joined(), size: 7.5)).tracking(0.6)
                        .lineLimit(1).minimumScaleFactor(0.5)
                    if !SetStampArt.date(date).isEmpty {
                        Text(verbatim: SetStampArt.date(date)).font(.system(size: 7, weight: .bold, design: .monospaced))
                    }
                }
                .padding(.horizontal, shape == .oval ? w * 0.17 : (shape == .hexagon ? w * 0.18 : w * 0.11))
            }
        }
    }
}

/// One of the four corners as a seal: the direction's character, cut white into red for north
/// and south, standing red for east and west.
struct DirectionSeal: View {
    let direction: String

    static func character(_ direction: String) -> String {
        let chinese = appLocale.language.languageCode == .chinese
        switch direction {
        case "north": return chinese ? "北" : "N"
        case "south": return chinese ? "南" : "S"
        case "east": return chinese ? "东" : "E"
        default: return chinese ? "西" : "W"
        }
    }

    var body: some View {
        GeometryReader { geo in
            let side = min(geo.size.width, geo.size.height)
            let carved = direction == "north" || direction == "south"
            let ink = Ink.cinnabar.color
            let char = Self.character(direction)
            let latin = char.count == 1 && char.unicodeScalars.first!.isASCII
            ZStack {
                if carved {
                    RoundedRectangle(cornerRadius: side * 0.1, style: .continuous).fill(ink)
                    RoundedRectangle(cornerRadius: side * 0.06, style: .continuous).inset(by: side * 0.07).stroke(.black, lineWidth: side * 0.015)
                        .blendMode(.destinationOut)
                } else {
                    RoundedRectangle(cornerRadius: side * 0.08, style: .continuous).inset(by: side * 0.03).stroke(ink, lineWidth: side * 0.07)
                }
                Text(verbatim: char)
                    .font(latin ? .system(size: side * 0.6, weight: .black, design: .serif) : .system(size: side * 0.62, weight: .black))
                    .foregroundStyle(carved ? .black : ink)
                    .blendMode(carved ? .destinationOut : .normal)
                    .offset(y: -side * 0.01)
            }
            .compositingGroup()
            .frame(width: side, height: side)
            .frame(width: geo.size.width, height: geo.size.height)
        }
    }
}

/// The highest point reached: a stamp shaped like a peak.
private struct PeakStamp: View {
    let stamp: Stamp

    var body: some View {
        GeometryReader { geo in
            let w = geo.size.width
            ZStack {
                Peak().stroke(.foreground, lineWidth: 2.8)
                Peak(inset: 6.5).stroke(.foreground, lineWidth: 0.9)
                VStack(spacing: 2) {
                    Image(systemName: "mountain.2.fill").font(.system(size: 15, weight: .bold))
                    Text(verbatim: stamp.value ?? "").font(.system(size: 20, weight: .heavy, design: .monospaced))
                        .lineLimit(1).minimumScaleFactor(0.6)
                    Text(verbatim: String(localized: "最高 · HIGHEST", bundle: .appLanguage).uppercased())
                        .font(.custom("AvenirNextCondensed-DemiBold", fixedSize: 8.5)).tracking(1.5)
                    if let city = stamp.city {
                        Text(verbatim: city).font(SpecialStampArt.font(city, size: 8)).lineLimit(1).minimumScaleFactor(0.6)
                    }
                }
                .padding(.top, w * 0.12)
                .padding(.horizontal, w * 0.12)
            }
            .foregroundStyle(Ink.slate.color)
        }
    }

    /// A wide base rising to a summit.
    private struct Peak: Shape {
        var inset: CGFloat = 1.5
        func path(in full: CGRect) -> Path {
            let r = full.insetBy(dx: inset, dy: inset)
            var path = Path()
            path.move(to: CGPoint(x: r.minX, y: r.maxY))
            path.addLine(to: CGPoint(x: r.minX, y: r.minY + r.height * 0.42))
            path.addLine(to: CGPoint(x: r.midX, y: r.minY))
            path.addLine(to: CGPoint(x: r.maxX, y: r.minY + r.height * 0.42))
            path.addLine(to: CGPoint(x: r.maxX, y: r.maxY))
            path.closeSubpath()
            return path
        }
    }
}

// MARK: - Province seals

/// A square seal with the province's one-character name.
struct ProvinceSealArt: View {
    let id: String

    private let ink = Ink.cinnabar.color

    var body: some View {
        let character = ProvinceSeal.character(for: id)
        if ProvinceSeal.isCarved(id) {
            // 白文: the character cut out of solid red.
            // Cut out of the stone, so the paper shows through, inked or not.
            ZStack {
                RoundedRectangle(cornerRadius: 9, style: .continuous).fill(ink)
                RoundedRectangle(cornerRadius: 6, style: .continuous).inset(by: 6).stroke(.black, lineWidth: 1.4)
                    .blendMode(.destinationOut)
                Text(character)
                    .font(.system(size: 60, weight: .black))
                    .foregroundStyle(.black)
                    .offset(y: -1)
                    .blendMode(.destinationOut)
            }
            .compositingGroup()
        } else {
            // 朱文: the character standing out in red inside a red frame.
            RoundedRectangle(cornerRadius: 8, style: .continuous)
                .inset(by: 3)
                .stroke(ink, lineWidth: 6)
                .overlay {
                    Text(character)
                        .font(.system(size: 58, weight: .heavy))
                        .foregroundStyle(ink)
                        .offset(y: -1)
                }
        }
    }
}

// MARK: - City stamps

private struct CityStampArt: View {
    let stamp: Stamp
    let route: [CGPoint]

    private var style: CityStampStyle {
        CityStampStyle.of(city: stamp.city ?? "", countryCode: stamp.countryCode, coordinate: stamp.coordinate)
    }

    var body: some View {
        let style = style
        let ink = style.ink.color
        ZStack {
            StampOutline(shape: style.shape).stroke(ink, lineWidth: 2.6)
            if style.shape == .circle || style.shape == .scalloped {
                Circle().inset(by: 9).stroke(ink, lineWidth: 0.9)
                Circle().inset(by: 30).stroke(ink, lineWidth: 0.9)
                ArcText(text: style.title, radius: 50, font: titleFont(style.title, size: 13), color: ink, tracking: 1.6)
                ArcText(text: style.motto ?? Self.date(stamp.date), radius: 50,
                        font: titleFont(style.motto ?? "", size: 9), color: ink, bottom: true, tracking: 1.2)
                Image(systemName: "star.fill").font(.system(size: 5)).offset(x: -50)
                Image(systemName: "star.fill").font(.system(size: 5)).offset(x: 50)
                center(style: style, routeSize: CGSize(width: 50, height: 36))
            } else {
                StampOutline(shape: style.shape, inset: 7).stroke(ink, lineWidth: 0.9)
                VStack(spacing: 3) {
                    Text(style.title)
                        .font(titleFont(style.title, size: 15))
                        .tracking(1.2)
                        .lineLimit(1)
                        .minimumScaleFactor(0.5)
                    if let motto = style.motto {
                        Text(motto).font(titleFont(motto, size: 8.5)).tracking(1).lineLimit(1).minimumScaleFactor(0.6)
                    }
                    Rectangle().frame(width: 60, height: 0.8)
                    center(style: style, routeSize: CGSize(width: 64, height: 40))
                }
                .padding(.horizontal, style.shape == .hexagon ? 26 : 18)
            }
        }
        .foregroundStyle(ink)
    }

    private func center(style: CityStampStyle, routeSize: CGSize) -> some View {
        VStack(spacing: 3) {
            if route.count > 1 {
                RouteGlyph(points: route)
                    .stroke(style.ink.color, style: StrokeStyle(lineWidth: 2.2, lineCap: .round, lineJoin: .round))
                    .frame(width: routeSize.width, height: routeSize.height)
                Image(systemName: style.symbol).font(.system(size: 9, weight: .bold))
            } else {
                Image(systemName: style.symbol).font(.system(size: 26, weight: .semibold))
                    .frame(height: routeSize.height)
            }
            Text(Self.date(stamp.date)).font(.system(size: 8.5, weight: .bold, design: .monospaced))
        }
    }

    /// Latin names in the condensed face stamps use; anything else in the system face.
    private func titleFont(_ text: String, size: CGFloat) -> Font {
        let latin = text.unicodeScalars.allSatisfy { $0.value < 0x0250 }
        return latin ? .custom("AvenirNextCondensed-Heavy", fixedSize: size) : .system(size: size, weight: .heavy)
    }

    /// "2026.10.08", the way date stamps print.
    static func date(_ date: Date) -> String {
        date.formatted(.verbatim("\(year: .defaultDigits).\(month: .twoDigits).\(day: .twoDigits)",
                                 timeZone: .current, calendar: Calendar(identifier: .gregorian)))
    }
}

/// A walked path, scaled to fit its box.
struct RouteGlyph: Shape {
    /// In 0...1 on both axes, y down.
    let points: [CGPoint]

    func path(in rect: CGRect) -> Path {
        var path = Path()
        guard let first = points.first else { return path }
        path.move(to: map(first, rect))
        for point in points.dropFirst() { path.addLine(to: map(point, rect)) }
        return path
    }

    private func map(_ p: CGPoint, _ rect: CGRect) -> CGPoint {
        CGPoint(x: rect.minX + p.x * rect.width, y: rect.minY + p.y * rect.height)
    }
}

// MARK: - Outline shapes

struct StampOutline: Shape {
    let shape: StampShape
    var inset: CGFloat = 1.5

    func path(in full: CGRect) -> Path {
        let rect = full.insetBy(dx: inset, dy: inset)
        let m = min(rect.width, rect.height)
        switch shape {
        case .rectangle:
            return Path(roundedRect: rect, cornerRadius: 3)
        case .rounded:
            return Path(roundedRect: rect, cornerRadius: m * 0.2, style: .continuous)
        case .circle:
            return Path(ellipseIn: CGRect(x: rect.midX - m / 2, y: rect.midY - m / 2, width: m, height: m))
        case .oval:
            return Path(ellipseIn: rect)
        case .octagon:
            let c = m * 0.29
            return polygon([CGPoint(x: rect.minX + c, y: rect.minY), CGPoint(x: rect.maxX - c, y: rect.minY),
                            CGPoint(x: rect.maxX, y: rect.minY + c), CGPoint(x: rect.maxX, y: rect.maxY - c),
                            CGPoint(x: rect.maxX - c, y: rect.maxY), CGPoint(x: rect.minX + c, y: rect.maxY),
                            CGPoint(x: rect.minX, y: rect.maxY - c), CGPoint(x: rect.minX, y: rect.minY + c)])
        case .hexagon:
            let c = rect.height * 0.3
            return polygon([CGPoint(x: rect.minX + c, y: rect.minY), CGPoint(x: rect.maxX - c, y: rect.minY),
                            CGPoint(x: rect.maxX, y: rect.midY), CGPoint(x: rect.maxX - c, y: rect.maxY),
                            CGPoint(x: rect.minX + c, y: rect.maxY), CGPoint(x: rect.minX, y: rect.midY)])
        case .ticket:
            let r = m * 0.13
            var path = Path()
            path.move(to: CGPoint(x: rect.minX + r, y: rect.minY))
            path.addLine(to: CGPoint(x: rect.maxX - r, y: rect.minY))
            path.addArc(center: CGPoint(x: rect.maxX, y: rect.minY), radius: r, startAngle: .degrees(180), endAngle: .degrees(90), clockwise: true)
            path.addLine(to: CGPoint(x: rect.maxX, y: rect.maxY - r))
            path.addArc(center: CGPoint(x: rect.maxX, y: rect.maxY), radius: r, startAngle: .degrees(270), endAngle: .degrees(180), clockwise: true)
            path.addLine(to: CGPoint(x: rect.minX + r, y: rect.maxY))
            path.addArc(center: CGPoint(x: rect.minX, y: rect.maxY), radius: r, startAngle: .degrees(0), endAngle: .degrees(270), clockwise: true)
            path.addLine(to: CGPoint(x: rect.minX, y: rect.minY + r))
            path.addArc(center: CGPoint(x: rect.minX, y: rect.minY), radius: r, startAngle: .degrees(90), endAngle: .degrees(0), clockwise: true)
            path.closeSubpath()
            return path
        case .scalloped:
            let center = CGPoint(x: rect.midX, y: rect.midY)
            let radius = m / 2
            var path = Path()
            let steps = 240
            for i in 0...steps {
                let a = Double(i) / Double(steps) * 2 * .pi
                let r = radius - 2.2 + 2.2 * cos(a * 28)
                let point = CGPoint(x: center.x + r * sin(a), y: center.y - r * cos(a))
                if i == 0 { path.move(to: point) } else { path.addLine(to: point) }
            }
            path.closeSubpath()
            return path
        }
    }

    private func polygon(_ points: [CGPoint]) -> Path {
        var path = Path()
        path.addLines(points)
        path.closeSubpath()
        return path
    }
}

/// Words running round a circle: along the top reading clockwise, or along the bottom
/// reading left to right, the way postmarks are cut.
struct ArcText: View {
    let text: String
    let radius: CGFloat
    let font: Font
    let color: Color
    var bottom = false
    var tracking: CGFloat = 1
    /// How far round the words may run, in radii: 2.1 is about a third of the circle.
    var span: CGFloat = 2.1
    /// Repeats the words until they go all the way round.
    var fillsRing = false

    var body: some View {
        Canvas { context, size in
            let center = CGPoint(x: size.width / 2, y: size.height / 2)
            var glyphs = text.map { context.resolve(Text(String($0)).font(font).foregroundStyle(color)) }
            var widths = glyphs.map { $0.measure(in: CGSize(width: 100, height: 100)).width + tracking }
            if fillsRing, let once = Optional(widths.reduce(0, +)), once > 0 {
                let times = max(1, Int((radius * span / once).rounded()))
                glyphs = Array(Array(repeating: glyphs, count: times).joined())
                widths = Array(Array(repeating: widths, count: times).joined())
            }
            // Never more than two thirds of the way round.
            let total = fillsRing ? radius * span : min(widths.reduce(0, +), radius * span)
            let squeeze = total / max(widths.reduce(0, +), 1)
            var arc = -total / 2
            for (glyph, width) in zip(glyphs, widths) {
                let w = width * squeeze
                let mid = (arc + w / 2) / radius
                var copy = context
                if bottom {
                    copy.translateBy(x: center.x + radius * sin(mid), y: center.y + radius * cos(mid))
                    copy.rotate(by: .radians(-mid))
                } else {
                    copy.translateBy(x: center.x + radius * sin(mid), y: center.y - radius * cos(mid))
                    copy.rotate(by: .radians(mid))
                }
                copy.scaleBy(x: squeeze, y: 1)
                copy.draw(glyph, at: .zero, anchor: .center)
                arc += w
            }
        }
        .allowsHitTesting(false)
    }
}

// MARK: - Ink

/// Rubber on paper never prints evenly: specks where the ink missed and a lighter patch or
/// two. Seeded, so each stamp always wears the same way.
private struct InkWorn: ViewModifier {
    let seed: UInt64
    let inked: Bool
    let wear: Double

    @ViewBuilder
    func body(content: Content) -> some View {
        if inked {
            var random = SeededRandom(seed)
            let density = 0.82 + random.unit() * 0.12
            content
                .mask {
                    Canvas { context, size in
                        var random = SeededRandom(seed &+ 7)
                        context.fill(Path(CGRect(origin: .zero, size: size)), with: .color(.black))
                        context.blendMode = .destinationOut
                        // Specks stay fine-grained whatever the stamp's size.
                        let grain = min(size.width, size.height) / 140
                        for _ in 0..<Int(size.width * size.height / 70 * wear) {
                            let r = (0.3 + random.unit() * 0.9) * grain
                            let point = CGPoint(x: random.unit() * size.width, y: random.unit() * size.height)
                            context.fill(Path(ellipseIn: CGRect(x: point.x - r, y: point.y - r, width: r * 2, height: r * 2)), with: .color(.black))
                        }
                        // Soft-edged, like ink that ran thin there.
                        for _ in 0..<2 {
                            let r = min(size.width, size.height) * (0.06 + random.unit() * 0.08)
                            let point = CGPoint(x: random.unit() * size.width, y: random.unit() * size.height)
                            context.fill(Path(ellipseIn: CGRect(x: point.x - r, y: point.y - r, width: r * 2, height: r * 2)),
                                         with: .radialGradient(Gradient(colors: [.black.opacity(0.2), .clear]), center: point,
                                                               startRadius: 0, endRadius: r))
                        }
                    }
                }
                .opacity(density)
                .drawingGroup()
        } else {
            // Not earned yet: pressed into the paper without ink, a blind stamp. Every line
            // still reads, lit from the top left like a real impression.
            ZStack {
                Color.white.opacity(0.85).mask(content).offset(x: -0.8, y: -0.8)
                BlindStamp.shade.mask(content).offset(x: 0.8, y: 0.8)
                BlindStamp.face.mask(content)
            }
            .drawingGroup()
        }
    }
}

enum BlindStamp {
    static let face = Color(red: 0.75, green: 0.71, blue: 0.62)
    static let shade = Color(red: 0.52, green: 0.47, blue: 0.40).opacity(0.55)
}

extension View {
    func inkWorn(seed: UInt64, inked: Bool = true, wear: Double = 1) -> some View {
        modifier(InkWorn(seed: seed, inked: inked, wear: wear))
    }
}

/// SplitMix64: small and fast, and the same numbers every time for the same seed.
struct SeededRandom {
    private var state: UInt64
    init(_ seed: UInt64) { state = seed }

    mutating func next() -> UInt64 {
        state &+= 0x9E3779B97F4A7C15
        var z = state
        z = (z ^ (z >> 30)) &* 0xBF58476D1CE4E5B9
        z = (z ^ (z >> 27)) &* 0x94D049BB133111EB
        return z ^ (z >> 31)
    }

    mutating func unit() -> Double { Double(next() >> 11) / Double(1 << 53) }
}

// MARK: - Paper

/// The page stamps are pressed on. Warm paper in light and dark mode alike: it's an object.
struct StampPaper: View {
    enum Style { case passport, seals, book }
    var style: Style = .passport

    static let color = Color(red: 0.965, green: 0.945, blue: 0.895)
    static let line = Color(red: 0.86, green: 0.82, blue: 0.72)

    var body: some View {
        Canvas { context, size in
            context.fill(Path(CGRect(origin: .zero, size: size)), with: .color(Self.color))
            switch style {
            case .passport:
                // The fine wavy lines printed on passport pages.
                for row in stride(from: 0, through: size.height, by: 9) {
                    var wave = Path()
                    for x in stride(from: 0, through: size.width, by: 4) {
                        let y = row + 3 * sin(x / 26 + row / 40) + 1.5 * sin(x / 9 + row)
                        if x == 0 { wave.move(to: CGPoint(x: x, y: y)) } else { wave.addLine(to: CGPoint(x: x, y: y)) }
                    }
                    context.stroke(wave, with: .color(Self.line.opacity(0.35)), lineWidth: 0.5)
                }
            case .seals:
                for x in stride(from: size.width / 6, to: size.width, by: size.width / 6) {
                    context.stroke(Path { $0.move(to: CGPoint(x: x, y: 0)); $0.addLine(to: CGPoint(x: x, y: size.height)) },
                                   with: .color(Ink.cinnabar.color.opacity(0.08)), lineWidth: 0.6)
                }
            case .book:
                for y in stride(from: 12, to: size.height, by: 16) {
                    for x in stride(from: 12, to: size.width, by: 16) {
                        context.fill(Path(ellipseIn: CGRect(x: x, y: y, width: 1.4, height: 1.4)), with: .color(Self.line.opacity(0.6)))
                    }
                }
            }
        }
    }
}

// MARK: - First-day routes

/// The track on the day a city was first visited, near the city, ready to draw on its stamp.
@MainActor
enum StampRoute {
    private static var cache: [String: [CGPoint]] = [:]

    static func cached(_ stamp: Stamp) -> [CGPoint]? { cache[stamp.id] }

    static func load(_ stamp: Stamp, context: ModelContext) -> [CGPoint] {
        if let known = cache[stamp.id] { return known }
        let start = Calendar.current.startOfDay(for: stamp.date)
        let end = start.addingTimeInterval(86_400)
        let chunks = (try? context.fetch(FetchDescriptor<TrackChunk>(predicate: #Predicate { $0.endDate >= start && $0.startDate < end },
                                                                     sortBy: [SortDescriptor(\.startDate)]))) ?? []
        let center = CLLocation(latitude: stamp.latitude, longitude: stamp.longitude)
        let near = chunks.filter { $0.mode != .flying }.flatMap(\.points).filter {
            abs($0.latitude - stamp.latitude) < 0.3 && CLLocation(latitude: $0.latitude, longitude: $0.longitude).distance(from: center) < 25_000
        }
        let result = normalize(near.map { CLLocationCoordinate2D(latitude: $0.latitude, longitude: $0.longitude) })
        cache[stamp.id] = result
        return result
    }

    /// Projected flat, fitted into the unit square keeping its shape, at most 160 points.
    static func normalize(_ coordinates: [CLLocationCoordinate2D]) -> [CGPoint] {
        guard coordinates.count >= 5 else { return [] }
        let k = cos(coordinates[0].latitude * .pi / 180)
        let xs = coordinates.map { $0.longitude * k }, ys = coordinates.map { -$0.latitude }
        guard let minX = xs.min(), let maxX = xs.max(), let minY = ys.min(), let maxY = ys.max() else { return [] }
        let span = max(maxX - minX, maxY - minY)
        // Under 300 m of walking isn't a shape worth drawing.
        guard span > 0.003 else { return [] }
        let offsetX = (span - (maxX - minX)) / 2, offsetY = (span - (maxY - minY)) / 2
        let step = max(1, coordinates.count / 160)
        return stride(from: 0, to: coordinates.count, by: step).map {
            CGPoint(x: (xs[$0] - minX + offsetX) / span, y: (ys[$0] - minY + offsetY) / span)
        }
    }
}

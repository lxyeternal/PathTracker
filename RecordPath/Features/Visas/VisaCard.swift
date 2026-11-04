import SwiftUI

/// A visa laid out the way the real one is — the US foil, the Schengen sticker, Japan's label,
/// Australia's grant notice — in their colours, with the countdown the real ones lack. No
/// seals, emblems or security features are copied, and a faint mark says whose it is.
struct VisaCard: View {
    let document: TravelDocument

    /// Close to a machine-readable visa's 120 × 80 mm.
    static let aspect: CGFloat = 1.52

    var body: some View {
        GeometryReader { proxy in
            let u = proxy.size.width / 360
            ZStack(alignment: .topLeading) {
                switch VisaTemplate(document) {
                case .passport: PassportFace(document: document, u: u)
                case .unitedStates: UnitedStatesFace(document: document, u: u)
                case .schengen: StickerFace(document: document, u: u, style: .schengen)
                case .japan: JapanFace(document: document, u: u)
                case .grantNotice: GrantNoticeFace(document: document, u: u)
                case .generic: StickerFace(document: document, u: u, style: .generic)
                }
                Countdown(document: document, u: u)
                    .frame(maxWidth: .infinity, alignment: .topTrailing)
                    .padding(.top, 10 * u)
                    .padding(.trailing, 12 * u)
                if document.isExpired { ExpiredStamp(u: u) }
            }
            .frame(width: proxy.size.width, height: proxy.size.height, alignment: .topLeading)
            .clipShape(.rect(cornerRadius: 16 * u, style: .continuous))
            .overlay {
                RoundedRectangle(cornerRadius: 16 * u, style: .continuous)
                    .strokeBorder(.white.opacity(document.kind == .passport ? 0.08 : 0.6), lineWidth: 0.8)
            }
            .saturation(document.isExpired ? 0.3 : 1)
        }
        .aspectRatio(Self.aspect, contentMode: .fit)
        .accessibilityElement(children: .ignore)
        .accessibilityLabel(accessibilityText)
    }

    private var accessibilityText: String {
        let days = document.daysLeft()
        let left = days < 0 ? String(localized: "已过期", bundle: .appLanguage) : String(localized: "还剩 \(days) 天", bundle: .appLanguage)
        return "\(document.kind == .passport ? String(localized: "护照", bundle: .appLanguage) : document.countryName) \(document.category) \(left)"
    }
}

enum VisaTemplate {
    case passport, unitedStates, schengen, japan, grantNotice, generic

    init(_ document: TravelDocument) {
        if document.kind == .passport { self = .passport }
        else if document.kind == .eVisa || ["AU", "NZ"].contains(document.country) { self = .grantNotice }
        else if document.country == "US" { self = .unitedStates }
        else if document.isSchengen { self = .schengen }
        else if document.country == "JP" { self = .japan }
        else { self = .generic }
    }
}

// MARK: - Shared pieces

/// Dates the way visas print them.
enum VisaDate {
    private static let months = ["JAN", "FEB", "MAR", "APR", "MAY", "JUN", "JUL", "AUG", "SEP", "OCT", "NOV", "DEC"]

    private static func parts(_ date: Date) -> (Int, Int, Int) {
        let c = Calendar(identifier: .gregorian).dateComponents([.year, .month, .day], from: date)
        return (c.day ?? 1, c.month ?? 1, c.year ?? 2000)
    }

    /// 15MAR2034, as on a US visa.
    static func compact(_ date: Date?) -> String {
        guard let date else { return "" }
        let (d, m, y) = parts(date)
        return String(format: "%02d%@%04d", d, months[m - 1], y)
    }

    /// 15-03-34, as on a Schengen sticker.
    static func short(_ date: Date?) -> String {
        guard let date else { return "" }
        let (d, m, y) = parts(date)
        return String(format: "%02d-%02d-%02d", d, m, y % 100)
    }

    /// 15 MAR 2034.
    static func spaced(_ date: Date?) -> String {
        guard let date else { return "" }
        let (d, m, y) = parts(date)
        return String(format: "%02d %@ %04d", d, months[m - 1], y)
    }
}

/// The two machine-readable lines, built from the card's own details.
private struct MachineLines: View {
    let document: TravelDocument
    let u: CGFloat
    var color: Color = .black

    var body: some View {
        let lines = Self.lines(document)
        VStack(alignment: .leading, spacing: 1.5 * u) {
            Text(verbatim: lines.0)
            Text(verbatim: lines.1)
        }
        .font(.system(size: 9.6 * u, weight: .semibold, design: .monospaced))
        .tracking(0.2 * u)
        .lineLimit(1)
        .minimumScaleFactor(0.5)
        .foregroundStyle(color.opacity(0.78))
    }

    static func lines(_ document: TravelDocument) -> (String, String) {
        func pad(_ text: String) -> String { String((text + String(repeating: "<", count: 44)).prefix(44)) }
        let type = document.kind == .passport ? "P<" : document.isSchengen ? "VC" : "VN"
        let issuer = document.isSchengen ? "EUE" : (VisaScanner.alpha3(document.country) ?? document.country)
        let parts = document.holder.uppercased().split(separator: " ").map(String.init)
        let name = parts.isEmpty ? "WAYTRACE<<TRAVELLER" : parts[0] + "<<" + parts.dropFirst().joined(separator: "<")
        let number = String((document.number.uppercased().filter { $0.isLetter || $0.isNumber } + "<<<<<<<<<").prefix(9))
        let nationality = VisaScanner.alpha3(Nationality.code ?? "CN") ?? "CHN"
        let expiry = document.expires.formatted(.verbatim("\(year: .twoDigits)\(month: .twoDigits)\(day: .twoDigits)",
                                                          timeZone: .current, calendar: Calendar(identifier: .gregorian)))
        return (pad(type + issuer + name),
                pad(number + String(VisaScanner.check(number)) + nationality + "<<<<<<<<" + expiry + String(VisaScanner.check(expiry))))
    }
}

/// A label over its value, the way visa fields are printed.
private struct Field: View {
    let label: String
    let value: String
    let u: CGFloat
    var ink: Color = .black
    var valueSize: CGFloat = 11

    var body: some View {
        VStack(alignment: .leading, spacing: 0.5 * u) {
            Text(verbatim: label)
                .font(.system(size: 6.4 * u, weight: .medium))
                .foregroundStyle(ink.opacity(0.62))
                .lineLimit(1)
            Text(verbatim: value.isEmpty ? " " : value)
                .font(.system(size: valueSize * u, weight: .bold, design: .monospaced))
                .foregroundStyle(ink)
                .lineLimit(1)
                .minimumScaleFactor(0.6)
        }
    }
}

/// Where a photo is glued on a real one; here an outline of a person, never a face.
private struct PhotoSlot: View {
    let u: CGFloat
    var tint: Color = .black

    var body: some View {
        ZStack(alignment: .bottom) {
            RoundedRectangle(cornerRadius: 3 * u).fill(tint.opacity(0.07))
            Image(systemName: "person.fill")
                .resizable().scaledToFit()
                .padding(.horizontal, 10 * u)
                .padding(.top, 14 * u)
                .offset(y: 6 * u)
                .foregroundStyle(tint.opacity(0.16))
            RoundedRectangle(cornerRadius: 3 * u).stroke(tint.opacity(0.18), lineWidth: 0.6)
        }
        .clipShape(.rect(cornerRadius: 3 * u))
    }
}

/// How long it has left: the one thing a real visa doesn't print.
private struct Countdown: View {
    let document: TravelDocument
    let u: CGFloat

    var body: some View {
        let days = document.daysLeft()
        if days >= 0 {
            let leather = document.kind == .passport
            let tint: Color = document.isExpiringSoon ? .orange : leather ? Color(red: 0.95, green: 0.86, blue: 0.62) : .green
            HStack(alignment: .firstTextBaseline, spacing: 2 * u) {
                Text(days == 0 ? String(localized: "今天到期", bundle: .appLanguage) : String(localized: "还剩", bundle: .appLanguage))
                    .font(.system(size: 8.5 * u, weight: .semibold))
                if days > 0 {
                    Text(days.formatted()).font(.system(size: 13 * u, weight: .bold, design: .rounded)).monospacedDigit()
                    Text("天").font(.system(size: 8.5 * u, weight: .semibold))
                }
            }
            .foregroundStyle(leather ? tint : tint.mix(with: .black, by: 0.35))
            .padding(.horizontal, 8 * u)
            .padding(.vertical, 3.5 * u)
            .background(.white.opacity(leather ? 0.10 : 0.85), in: .capsule)
            .overlay(Capsule().stroke(tint.opacity(0.5), lineWidth: 0.6))
        }
    }
}

private struct ExpiredStamp: View {
    let u: CGFloat

    var body: some View {
        let red = Color(red: 0.75, green: 0.12, blue: 0.14)
        VStack(spacing: 0) {
            Text("已过期").font(.system(size: 20 * u, weight: .black)).tracking(4 * u)
            Text(verbatim: "EXPIRED").font(.system(size: 9 * u, weight: .heavy)).tracking(3 * u)
        }
        .foregroundStyle(red)
        .padding(.horizontal, 14 * u).padding(.vertical, 6 * u)
        .overlay(RoundedRectangle(cornerRadius: 6 * u).stroke(red, lineWidth: 2.2 * u))
        .rotationEffect(.degrees(-14))
        .opacity(0.8)
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .offset(x: 70 * u, y: 10 * u)
    }
}

/// Fine wavy lines over the whole ground.
private struct Guilloche: View {
    let ink: Color
    let u: CGFloat
    var spacing: CGFloat = 5.5
    var slope: CGFloat = 0.12

    var body: some View {
        Canvas { context, size in
            for row in stride(from: -size.height * 0.5, through: size.height * 1.2, by: spacing * u) {
                var path = Path()
                for x in stride(from: 0, through: size.width, by: 3) {
                    let y = row + x * slope + 2.6 * u * sin(x / (13 * u) + row / (19 * u))
                    if x == 0 { path.move(to: CGPoint(x: x, y: y)) } else { path.addLine(to: CGPoint(x: x, y: y)) }
                }
                context.stroke(path, with: .color(ink), lineWidth: 0.45)
            }
        }
    }
}

/// The app's mark, faint, so a card can't pass for the document it pictures.
private struct Watermark: View {
    let u: CGFloat
    var color: Color = .black

    var body: some View {
        Text(verbatim: "WAYTRACE · 漫迹")
            .font(.system(size: 7 * u, weight: .heavy))
            .tracking(2.5 * u)
            .foregroundStyle(color.opacity(0.22))
    }
}

/// The header strip every visa starts with; it's what shows while the card is stacked.
private struct Header<Content: View>: View {
    let u: CGFloat
    @ViewBuilder var content: Content

    var body: some View {
        HStack(alignment: .firstTextBaseline, spacing: 7 * u) { content }
            .frame(height: 30 * u, alignment: .bottom)
            .padding(.leading, 14 * u)
    }
}

/// Photo on the left, fields on the right, remarks, the mark and machine lines at the foot.
private struct StickerLayout<Fields: View, Foot: View>: View {
    let document: TravelDocument
    let u: CGFloat
    let ink: Color
    @ViewBuilder var fields: Fields
    @ViewBuilder var foot: Foot

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            HStack(alignment: .top, spacing: 10 * u) {
                PhotoSlot(u: u, tint: ink).frame(width: 64 * u, height: 84 * u)
                VStack(alignment: .leading, spacing: 4 * u) { fields }
            }
            .padding(.horizontal, 14 * u)
            .padding(.top, 7 * u)
            Spacer(minLength: 0)
            HStack(alignment: .bottom) {
                foot
                Spacer()
                Watermark(u: u, color: ink)
            }
            .padding(.horizontal, 14 * u)
            MachineLines(document: document, u: u, color: ink)
                .padding(.horizontal, 14 * u)
                .padding(.top, 4 * u)
                .padding(.bottom, 9 * u)
        }
    }
}

// MARK: - United States

/// The US foil: the country across the top, photo on the left, fields in two columns, the
/// red visa number and the machine-readable lines along the foot, over a pastel ground with
/// a bridge drawn faintly behind.
private struct UnitedStatesFace: View {
    let document: TravelDocument
    let u: CGFloat

    private let ink = Color(red: 0.10, green: 0.13, blue: 0.24)

    var body: some View {
        ZStack(alignment: .topLeading) {
            LinearGradient(colors: [Color(red: 0.99, green: 0.86, blue: 0.86), Color(red: 0.99, green: 0.93, blue: 0.86),
                                    Color(red: 0.86, green: 0.95, blue: 0.90), Color(red: 0.84, green: 0.90, blue: 0.99)],
                           startPoint: .topLeading, endPoint: .bottomTrailing)
            Guilloche(ink: Color(red: 0.55, green: 0.35, blue: 0.55).opacity(0.13), u: u)
            Bridge(u: u).stroke(Color(red: 0.70, green: 0.25, blue: 0.20).opacity(0.14), lineWidth: 1.1 * u)
            VStack(alignment: .leading, spacing: 0) {
                Header(u: u) {
                    Text(verbatim: "UNITED STATES OF AMERICA").font(.custom("Georgia-Bold", fixedSize: 12.5 * u)).tracking(0.8 * u)
                    Text(document.flag).font(.system(size: 11 * u))
                }
                .foregroundStyle(ink)
                StickerLayout(document: document, u: u, ink: ink) {
                    HStack(alignment: .top) {
                        Field(label: "Issuing Post Name", value: document.post ?? "", u: u, ink: ink)
                        Spacer()
                        Field(label: "Control Number", value: controlNumber, u: u, ink: ink)
                    }
                    Field(label: "Surname", value: surname, u: u, ink: ink)
                    Field(label: "Given Name", value: given, u: u, ink: ink)
                    HStack(alignment: .top, spacing: 14 * u) {
                        Field(label: "Visa Type/Class", value: "R " + (document.category.isEmpty ? "—" : document.category), u: u, ink: ink)
                        Field(label: "Entries", value: entries, u: u, ink: ink)
                    }
                    HStack(alignment: .top, spacing: 14 * u) {
                        Field(label: "Issue Date", value: VisaDate.compact(document.issued), u: u, ink: ink)
                        Field(label: "Expiration Date", value: VisaDate.compact(document.expires), u: u, ink: ink)
                    }
                } foot: {
                    Field(label: "Annotation", value: document.notes.uppercased(), u: u, ink: ink, valueSize: 9)
                    Spacer()
                    Text(verbatim: document.number.uppercased())
                        .font(.system(size: 13 * u, weight: .bold, design: .monospaced))
                        .foregroundStyle(Color(red: 0.78, green: 0.10, blue: 0.12))
                }
            }
        }
    }

    private var parts: [String] { document.holder.uppercased().split(separator: " ").map(String.init) }
    private var surname: String { parts.first ?? "" }
    private var given: String { parts.dropFirst().joined(separator: " ") }
    private var entries: String { document.entries == .multiple ? "M" : document.entries == .double ? "2" : "1" }
    private var controlNumber: String {
        guard let issued = document.issued else { return "" }
        return issued.formatted(.verbatim("\(year: .defaultDigits)\(dayOfYear: .threeDigits)", timeZone: .current,
                                          calendar: Calendar(identifier: .gregorian))) + "0000"
    }
}

/// A suspension bridge in a few lines: towers, the main cable's sag, hangers and the deck.
private struct Bridge: Shape {
    let u: CGFloat

    func path(in rect: CGRect) -> Path {
        var path = Path()
        let deck = rect.height * 0.70
        let left = rect.width * 0.50, right = rect.width * 0.86
        let top = rect.height * 0.24
        for x in [left, right] {
            path.addRect(CGRect(x: x - 3 * u, y: top, width: 6 * u, height: rect.height - top))
            for level in stride(from: top + 12 * u, to: deck, by: 22 * u) {
                path.move(to: CGPoint(x: x - 3 * u, y: level)); path.addLine(to: CGPoint(x: x + 3 * u, y: level))
            }
        }
        let sag = deck * 1.05
        path.move(to: CGPoint(x: rect.width * 0.30, y: deck))
        path.addQuadCurve(to: CGPoint(x: left, y: top), control: CGPoint(x: left - 20 * u, y: deck - 4 * u))
        path.addQuadCurve(to: CGPoint(x: right, y: top), control: CGPoint(x: (left + right) / 2, y: sag))
        path.addQuadCurve(to: CGPoint(x: rect.width * 1.02, y: deck), control: CGPoint(x: right + 20 * u, y: deck - 4 * u))
        path.move(to: CGPoint(x: rect.width * 0.28, y: deck)); path.addLine(to: CGPoint(x: rect.width, y: deck))
        path.move(to: CGPoint(x: rect.width * 0.28, y: deck + 4 * u)); path.addLine(to: CGPoint(x: rect.width, y: deck + 4 * u))
        for x in stride(from: left + 12 * u, to: right, by: 12 * u) {
            let t = (x - left) / (right - left)
            // The quadratic between the towers: top at both ends, deepest in the middle.
            let cable = (1 - t) * (1 - t) * top + 2 * (1 - t) * t * sag + t * t * top
            path.move(to: CGPoint(x: x, y: cable)); path.addLine(to: CGPoint(x: x, y: deck))
        }
        return path
    }
}

// MARK: - Schengen and other stickers

/// The uniform Schengen sticker: VISA across the top, the validity, type, entries and length
/// of stay in printed fields, the holder below, a ring of stars in the ground. Other
/// countries' stickers follow the same plan in a colour of their own.
private struct StickerFace: View {
    enum Style { case schengen, generic }
    let document: TravelDocument
    let u: CGFloat
    let style: Style

    private var hue: Double {
        Double(document.country.unicodeScalars.reduce(0) { $0 &* 31 &+ Int($1.value) } % 360) / 360
    }

    private var ink: Color {
        style == .schengen ? Color(red: 0.12, green: 0.15, blue: 0.38) : Color(hue: hue, saturation: 0.6, brightness: 0.28)
    }

    private var ground: [Color] {
        style == .schengen
            ? [Color(red: 0.97, green: 0.88, blue: 0.93), Color(red: 0.88, green: 0.90, blue: 0.99), Color(red: 0.88, green: 0.97, blue: 0.93)]
            : [Color(hue: hue, saturation: 0.12, brightness: 0.99), Color(hue: (hue + 0.1).truncatingRemainder(dividingBy: 1), saturation: 0.14, brightness: 0.96)]
    }

    var body: some View {
        ZStack(alignment: .topLeading) {
            LinearGradient(colors: ground, startPoint: .topLeading, endPoint: .bottomTrailing)
            Guilloche(ink: ink.opacity(0.10), u: u, spacing: 5, slope: -0.08)
            if style == .schengen {
                StarRing(u: u)
                    .frame(width: 96 * u, height: 96 * u)
                    .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .trailing)
                    .padding(.trailing, 22 * u)
                    .offset(y: -4 * u)
            }
            VStack(alignment: .leading, spacing: 0) {
                Header(u: u) {
                    Text(verbatim: "VISA").font(.system(size: 17 * u, weight: .heavy)).tracking(3 * u)
                    Text(verbatim: style == .schengen ? "SCHENGEN" : document.englishName)
                        .font(.system(size: 8 * u, weight: .bold)).tracking(1.5 * u).opacity(0.7)
                    Text(document.flag).font(.system(size: 11 * u))
                }
                .foregroundStyle(ink)
                StickerLayout(document: document, u: u, ink: ink) {
                    Field(label: "VALID FOR / VALABLE POUR", value: style == .schengen ? "ETATS SCHENGEN" : document.englishName, u: u, ink: ink)
                    HStack(spacing: 14 * u) {
                        Field(label: "FROM / DU", value: VisaDate.short(document.issued), u: u, ink: ink)
                        Field(label: "UNTIL / AU", value: VisaDate.short(document.expires), u: u, ink: ink)
                    }
                    HStack(spacing: 12 * u) {
                        Field(label: "TYPE OF VISA", value: document.category.isEmpty ? "C" : document.category.uppercased(), u: u, ink: ink)
                        Field(label: "NUMBER OF ENTRIES", value: entries, u: u, ink: ink)
                        Field(label: "DURATION OF STAY", value: document.stayDays.map { "\($0) DAYS" } ?? "", u: u, ink: ink)
                    }
                    HStack(spacing: 14 * u) {
                        Field(label: "ISSUED IN / DELIVRE A", value: document.post ?? "", u: u, ink: ink)
                        Field(label: "ON / LE", value: VisaDate.short(document.issued), u: u, ink: ink)
                    }
                    Field(label: "SURNAME, NAME / NOM, PRENOMS", value: holder, u: u, ink: ink)
                } foot: {
                    Field(label: "REMARKS / REMARQUES", value: document.notes.uppercased(), u: u, ink: ink, valueSize: 9)
                }
            }
        }
    }

    private var entries: String { document.entries == .multiple ? "MULT" : document.entries == .double ? "02" : "01" }
    private var holder: String {
        let parts = document.holder.uppercased().split(separator: " ")
        guard let first = parts.first else { return "" }
        return parts.count > 1 ? "\(first), \(parts.dropFirst().joined(separator: " "))" : String(first)
    }
}

/// Twelve stars in a ring, in the soft gold of the sticker's print.
private struct StarRing: View {
    let u: CGFloat

    var body: some View {
        Canvas { context, size in
            let center = CGPoint(x: size.width / 2, y: size.height / 2)
            let radius = min(size.width, size.height) * 0.40
            for i in 0..<12 {
                let angle = Double(i) / 12 * 2 * .pi - .pi / 2
                let p = CGPoint(x: center.x + cos(angle) * radius, y: center.y + sin(angle) * radius)
                var star = Path()
                for k in 0..<10 {
                    let r = (k % 2 == 0 ? 5.5 : 2.3) * u
                    let a = Double(k) / 10 * 2 * .pi - .pi / 2
                    let q = CGPoint(x: p.x + r * cos(a), y: p.y + r * sin(a))
                    if k == 0 { star.move(to: q) } else { star.addLine(to: q) }
                }
                star.closeSubpath()
                context.fill(star, with: .color(Color(red: 0.86, green: 0.66, blue: 0.12).opacity(0.38)))
            }
        }
    }
}

// MARK: - Japan

/// Japan's visa label: 査証 VISA, the type, entries and permitted stay in Japanese and
/// English, over pale pink and lilac with blossoms drifting across.
private struct JapanFace: View {
    let document: TravelDocument
    let u: CGFloat

    private let ink = Color(red: 0.28, green: 0.12, blue: 0.26)

    var body: some View {
        ZStack(alignment: .topLeading) {
            LinearGradient(colors: [Color(red: 1, green: 0.91, blue: 0.94), Color(red: 0.94, green: 0.90, blue: 0.99),
                                    Color(red: 0.90, green: 0.95, blue: 1)], startPoint: .topLeading, endPoint: .bottomTrailing)
            Guilloche(ink: ink.opacity(0.08), u: u, spacing: 6, slope: 0.05)
            Blossoms(u: u)
            VStack(alignment: .leading, spacing: 0) {
                Header(u: u) {
                    Text(verbatim: "査証").font(.custom("HiraMinProN-W6", fixedSize: 17 * u))
                    Text(verbatim: "VISA").font(.system(size: 13 * u, weight: .heavy)).tracking(3 * u)
                    Text(verbatim: "日本国 JAPAN").font(.system(size: 8 * u, weight: .bold)).tracking(1.2 * u).opacity(0.7)
                }
                .foregroundStyle(ink)
                StickerLayout(document: document, u: u, ink: ink) {
                    Field(label: "種類 / TYPE", value: type, u: u, ink: ink)
                    HStack(spacing: 14 * u) {
                        Field(label: "回数 / ENTRIES", value: entries, u: u, ink: ink)
                        Field(label: "在留期間 / DURATION", value: document.stayDays.map { "\($0) DAYS" } ?? "", u: u, ink: ink)
                    }
                    HStack(spacing: 14 * u) {
                        Field(label: "発給日 / DATE OF ISSUE", value: VisaDate.spaced(document.issued), u: u, ink: ink)
                        Field(label: "有効期限 / VALID UNTIL", value: VisaDate.spaced(document.expires), u: u, ink: ink)
                    }
                    HStack(spacing: 14 * u) {
                        Field(label: "発給地 / PLACE", value: document.post ?? "", u: u, ink: ink)
                        Field(label: "氏名 / NAME", value: document.holder.uppercased(), u: u, ink: ink)
                    }
                } foot: {
                    Field(label: "備考 / REMARKS", value: document.notes.uppercased(), u: u, ink: ink, valueSize: 9)
                }
            }
        }
    }

    private var type: String {
        let category = document.category.uppercased()
        if category.isEmpty || category.contains("短期") { return "TEMPORARY VISITOR" }
        return category
    }
    private var entries: String { document.entries == .multiple ? "MULTIPLE" : document.entries == .double ? "DOUBLE" : "SINGLE" }
}

private struct Blossoms: View {
    let u: CGFloat

    var body: some View {
        Canvas { context, size in
            var random = SeededRandom(11)
            for _ in 0..<11 {
                let center = CGPoint(x: size.width * (0.45 + random.unit() * 0.6), y: size.height * random.unit())
                let radius = (7 + random.unit() * 10) * u
                let rotation = random.unit() * .pi
                for i in 0..<5 {
                    let angle = rotation + Double(i) / 5 * 2 * .pi
                    let petal = Path(ellipseIn: CGRect(x: -radius * 0.32, y: -radius, width: radius * 0.64, height: radius))
                        .applying(CGAffineTransform(rotationAngle: angle).concatenating(CGAffineTransform(translationX: center.x, y: center.y)))
                    context.fill(petal, with: .color(Color(red: 0.95, green: 0.55, blue: 0.68).opacity(0.15)))
                }
            }
        }
    }
}

// MARK: - Grant notice

/// Australia and New Zealand print nothing in the passport: the visa is a grant notice, so
/// it looks like one — a letter with a coloured band and the grant's details in rows.
private struct GrantNoticeFace: View {
    let document: TravelDocument
    let u: CGFloat

    private var band: [Color] {
        switch document.country {
        case "AU": [Color(red: 0.86, green: 0.55, blue: 0.20), Color(red: 0.12, green: 0.45, blue: 0.42)]
        case "NZ": [Color(red: 0.05, green: 0.12, blue: 0.14), Color(red: 0.10, green: 0.42, blue: 0.38)]
        default: [Color(red: 0.20, green: 0.30, blue: 0.55), Color(red: 0.35, green: 0.55, blue: 0.75)]
        }
    }
    private let ink = Color(red: 0.12, green: 0.13, blue: 0.16)

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            ZStack(alignment: .leading) {
                LinearGradient(colors: band, startPoint: .leading, endPoint: .trailing)
                HStack(spacing: 7 * u) {
                    Text(document.flag).font(.system(size: 13 * u))
                    VStack(alignment: .leading, spacing: 0) {
                        Text(verbatim: document.country == "NZ" ? "Visa approval notice" : "Visa grant notice")
                            .font(.system(size: 12.5 * u, weight: .bold))
                        Text(verbatim: "\(document.englishName) · ELECTRONIC VISA")
                            .font(.system(size: 6.5 * u, weight: .bold)).tracking(1.2 * u).opacity(0.8)
                    }
                }
                .foregroundStyle(.white)
                .padding(.leading, 14 * u)
            }
            .frame(height: 40 * u)
            ZStack(alignment: .topLeading) {
                Color(red: 0.995, green: 0.99, blue: 0.98)
                Guilloche(ink: band[1].opacity(0.06), u: u, spacing: 7, slope: 0.02)
                VStack(alignment: .leading, spacing: 0) {
                    row("Visa holder", document.holder.isEmpty ? "—" : document.holder.uppercased())
                    row("Visa", visa)
                    row("Visa grant number", document.number.isEmpty ? "—" : document.number.uppercased())
                    row("Date of grant", VisaDate.spaced(document.issued))
                    row("Must not arrive after", VisaDate.spaced(document.expires))
                    row("Period of stay", document.stayDays.map { "\($0) days from each arrival" } ?? "—")
                    row("Travel", document.entries == .multiple ? "Multiple entries" : document.entries == .double ? "Two entries" : "Single entry",
                        last: true)
                    Spacer(minLength: 0)
                    HStack {
                        Text(verbatim: "No label is placed in the passport. Keep this notice.")
                            .font(.system(size: 6.5 * u, weight: .medium))
                            .foregroundStyle(ink.opacity(0.45))
                        Spacer()
                        Watermark(u: u, color: ink)
                    }
                    .padding(.bottom, 9 * u)
                }
                .padding(.horizontal, 14 * u)
                .padding(.top, 6 * u)
            }
        }
    }

    private var visa: String {
        let category = document.category
        if category.isEmpty { return "Visitor" }
        return category.allSatisfy(\.isNumber) ? "Visitor (subclass \(category))" : category
    }

    private func row(_ label: String, _ value: String, last: Bool = false) -> some View {
        VStack(spacing: 0) {
            HStack(alignment: .firstTextBaseline) {
                Text(verbatim: label).font(.system(size: 8 * u, weight: .medium)).foregroundStyle(ink.opacity(0.55))
                    .frame(width: 104 * u, alignment: .leading)
                Text(verbatim: value).font(.system(size: 9.5 * u, weight: .semibold)).foregroundStyle(ink)
                    .lineLimit(1).minimumScaleFactor(0.6)
                Spacer(minLength: 0)
            }
            .padding(.vertical, 3.6 * u)
            if !last { Rectangle().fill(ink.opacity(0.08)).frame(height: 0.5) }
        }
    }
}

// MARK: - Passport

/// The passport as a card: the cover's leather and foil, and its data page's essentials.
private struct PassportFace: View {
    let document: TravelDocument
    let u: CGFloat

    var body: some View {
        let theme = PassportStyle.shared.theme
        let foil = Color(red: 0.95, green: 0.86, blue: 0.62)
        ZStack(alignment: .topLeading) {
            LinearGradient(colors: [theme.leather.mix(with: .white, by: 0.08), theme.leather.mix(with: .black, by: 0.3)],
                           startPoint: .topLeading, endPoint: .bottomTrailing)
            Canvas { context, size in
                var random = SeededRandom(3)
                for _ in 0..<Int(size.width * size.height / 40) {
                    let p = CGPoint(x: random.unit() * size.width, y: random.unit() * size.height)
                    context.fill(Path(ellipseIn: CGRect(x: p.x, y: p.y, width: 1.1, height: 1.1)),
                                 with: .color(random.unit() > 0.5 ? .white.opacity(0.07) : .black.opacity(0.18)))
                }
            }
            Image(systemName: theme.emblem)
                .resizable().scaledToFit()
                .frame(width: 110 * u, height: 110 * u)
                .foregroundStyle(theme.foil)
                .opacity(0.16)
                .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .trailing)
                .padding(.trailing, 24 * u)
            VStack(alignment: .leading, spacing: 0) {
                HStack(alignment: .firstTextBaseline, spacing: 8 * u) {
                    Text("护照").font(.system(size: 16 * u, weight: .semibold)).tracking(4 * u)
                    Text(verbatim: "PASSPORT").font(.custom("AcademyEngravedLetPlain", fixedSize: 12 * u)).tracking(3 * u)
                }
                .foregroundStyle(theme.foil)
                .frame(height: 30 * u, alignment: .bottom)
                Rectangle().fill(foil.opacity(0.35)).frame(height: 0.7).padding(.top, 6 * u)
                Spacer(minLength: 0)
                HStack(alignment: .bottom, spacing: 22 * u) {
                    Field(label: "TYPE / 类型", value: "P", u: u, ink: foil, valueSize: 13)
                    Field(label: "ISSUING STATE / 签发国", value: VisaScanner.alpha3(document.country) ?? document.country, u: u, ink: foil, valueSize: 13)
                    Field(label: "PASSPORT NO. / 护照号", value: document.number.uppercased(), u: u, ink: foil, valueSize: 13)
                }
                .padding(.bottom, 10 * u)
                HStack(alignment: .bottom, spacing: 22 * u) {
                    Field(label: "DATE OF ISSUE / 签发日期", value: VisaDate.spaced(document.issued), u: u, ink: foil, valueSize: 12)
                    Field(label: "DATE OF EXPIRY / 有效期至", value: VisaDate.spaced(document.expires), u: u, ink: foil, valueSize: 12)
                }
                Spacer(minLength: 0)
                MachineLines(document: document, u: u, color: foil)
                    .padding(.bottom, 9 * u)
            }
            .padding(.horizontal, 16 * u)
        }
    }
}

import SwiftUI
import UIKit

// MARK: - The passport

/// A passport you leaf through: the cover, the holder's page, then the border stamps in the
/// order they were earned, four to a page. Pages turn with a real page curl.
struct PassportBook: View {
    let book: StampBook
    var onSelect: (Stamp) -> Void = { _ in }
    @State private var page = 0

    static let perPage = 4

    private var stampPages: [[Stamp]] {
        stride(from: 0, to: book.passport.count, by: Self.perPage).map { Array(book.passport[$0..<min($0 + Self.perPage, book.passport.count)]) }
    }

    var body: some View {
        let stampPages = stampPages
        // An empty page waits at the back for the next stamp, unless the last one has room.
        let blankAtBack = stampPages.last.map { $0.count == Self.perPage } ?? true
        let pages: [AnyView] = [AnyView(PassportCover())]
            + [AnyView(PassportDataPage(book: book))]
            + stampPages.enumerated().map { index, stamps in
                AnyView(PassportStampPage(stamps: stamps, number: index + 1, onSelect: onSelect))
            }
            + (blankAtBack ? [AnyView(PassportStampPage(stamps: [], number: stampPages.count + 1, onSelect: onSelect))] : [])
        VStack(spacing: 10) {
            PageCurl(pages: pages, current: $page)
                .aspectRatio(0.70, contentMode: .fit)
                .padding(.horizontal, 18)
                .shadow(color: .black.opacity(0.18), radius: 14, y: 8)
                .id(pages.count)
            Text(page == 0 ? String(localized: "向左轻扫，翻开护照", bundle: .appLanguage)
                           : String(localized: "第 \(page) / \(pages.count - 1) 页", bundle: .appLanguage))
                .font(.footnote)
                .foregroundStyle(.secondary)
                .monospacedDigit()
                .contentTransition(.numericText())
                .animation(.smooth, value: page)
        }
    }
}

/// The burgundy cover, gold foil catching the light now and then.
struct PassportCover: View {
    var compact = false
    @State private var shine = false

    static let leather = Color(red: 0.37, green: 0.08, blue: 0.13)
    static let gold = LinearGradient(colors: [Color(red: 0.93, green: 0.80, blue: 0.50), Color(red: 0.75, green: 0.58, blue: 0.30),
                                              Color(red: 0.95, green: 0.84, blue: 0.56)], startPoint: .topLeading, endPoint: .bottomTrailing)

    var body: some View {
        GeometryReader { proxy in
            let unit = proxy.size.width / 300
            ZStack {
                UnevenRoundedRectangle(cornerRadii: .init(topLeading: 4 * unit, bottomLeading: 4 * unit, bottomTrailing: 18 * unit, topTrailing: 18 * unit),
                                       style: .continuous)
                    .fill(Self.leather.gradient)
                    .overlay { Grain().opacity(0.25).clipShape(.rect(cornerRadius: 18 * unit)) }
                foil(unit: unit)
                    .foregroundStyle(Self.gold)
                // A slow glint across the foil.
                ZStack {
                    LinearGradient(colors: [.clear, .white.opacity(0.75), .clear], startPoint: .leading, endPoint: .trailing)
                        .frame(width: proxy.size.width * 0.35, height: proxy.size.height * 1.4)
                        .rotationEffect(.degrees(20))
                        .offset(x: shine ? proxy.size.width : -proxy.size.width)
                }
                .frame(width: proxy.size.width, height: proxy.size.height)
                .clipped()
                .mask { foil(unit: unit) }
                .allowsHitTesting(false)
                // The spine's stitching.
                Rectangle().fill(.black.opacity(0.18)).frame(width: 6 * unit).frame(maxWidth: .infinity, alignment: .leading)
            }
        }
        .onAppear {
            guard !compact else { return }
            withAnimation(.easeInOut(duration: 2.6).delay(0.8).repeatForever(autoreverses: false)) { shine = true }
        }
    }

    private func foil(unit: CGFloat) -> some View {
        VStack(spacing: 0) {
            Spacer(minLength: 0)
            Text(verbatim: "护照").font(.system(size: 34 * unit, weight: .semibold)).tracking(14 * unit)
            Text(verbatim: "PASSPORT").font(.custom("AcademyEngravedLetPlain", fixedSize: 22 * unit)).tracking(7 * unit).padding(.top, 4 * unit)
            ZStack {
                Circle().stroke(lineWidth: 2.2 * unit)
                Circle().inset(by: 9 * unit).stroke(lineWidth: 0.8 * unit)
                Image(systemName: "globe.asia.australia.fill").font(.system(size: 58 * unit, weight: .light))
                ForEach(0..<12) { i in
                    Image(systemName: "star.fill").font(.system(size: 6 * unit))
                        .offset(y: -63 * unit)
                        .rotationEffect(.degrees(Double(i) * 30))
                }
            }
            .frame(width: 142 * unit, height: 142 * unit)
            .padding(.vertical, 30 * unit)
            Text(AppInfo.name).font(.system(size: 17 * unit, weight: .semibold)).tracking(6 * unit)
            Text(verbatim: "WAYTRACE").font(.custom("AcademyEngravedLetPlain", fixedSize: 12 * unit)).tracking(5 * unit).padding(.top, 2 * unit)
            Spacer(minLength: 0)
            Image(systemName: "dot.radiowaves.left.and.right")
                .font(.system(size: 16 * unit))
                .padding(.bottom, 22 * unit)
        }
    }
}

/// Leather grain for the cover.
private struct Grain: View {
    var body: some View {
        Canvas { context, size in
            var random = SeededRandom(42)
            for _ in 0..<Int(size.width * size.height / 30) {
                let point = CGPoint(x: random.unit() * size.width, y: random.unit() * size.height)
                context.fill(Path(ellipseIn: CGRect(x: point.x, y: point.y, width: 1.2, height: 1.2)),
                             with: .color(random.unit() > 0.5 ? .white.opacity(0.25) : .black.opacity(0.35)))
            }
        }
    }
}

/// The holder's page: issued by home, since the first day recorded, with the machine-readable
/// lines along the bottom.
private struct PassportDataPage: View {
    let book: StampBook

    private var countries: Int { Set(book.passport.compactMap(\.countryCode)).count + (book.home == nil ? 0 : 1) }

    var body: some View {
        GeometryReader { proxy in
            let unit = proxy.size.width / 300
            ZStack(alignment: .topLeading) {
                StampPaper(style: .passport)
                VStack(alignment: .leading, spacing: 12 * unit) {
                    HStack {
                        Text(verbatim: "漫迹护照 · WAYTRACE PASSPORT")
                            .font(.custom("AvenirNextCondensed-DemiBold", fixedSize: 10 * unit)).tracking(1.5 * unit)
                        Spacer()
                        Text(verbatim: "P").font(.system(size: 12 * unit, weight: .bold, design: .monospaced))
                    }
                    .foregroundStyle(Self.printed)
                    HStack(alignment: .top, spacing: 14 * unit) {
                        Text(book.home.map { String.flag(for: $0) } ?? "🌏")
                            .font(.system(size: 54 * unit))
                            .frame(width: 92 * unit, height: 118 * unit)
                            .background(Self.printed.opacity(0.08), in: .rect(cornerRadius: 6 * unit))
                            .overlay(RoundedRectangle(cornerRadius: 6 * unit).stroke(Self.printed.opacity(0.3), lineWidth: 0.6))
                        VStack(alignment: .leading, spacing: 8 * unit) {
                            field("签发国 / ISSUED BY", book.home.map { WorldInsights.countryName(code: $0, fallback: nil) } ?? "—", unit: unit)
                            field("签发日期 / DATE OF ISSUE", book.since.map(Self.date) ?? "—", unit: unit)
                            field("国家和地区 / COUNTRIES", "\(countries)", unit: unit)
                            field("入境章 / ENTRY STAMPS", "\(book.passport.filter { $0.kind == .entry }.count)", unit: unit)
                        }
                    }
                    HStack(spacing: 18 * unit) {
                        field("省份 / PROVINCES", "\(book.provinces.count)", unit: unit)
                        field("城市 / CITIES", "\(book.cities.count)", unit: unit)
                    }
                    Spacer(minLength: 0)
                    VStack(alignment: .leading, spacing: 2 * unit) {
                        Text(verbatim: "持照人签名 / SIGNATURE")
                            .font(.custom("AvenirNextCondensed-Medium", fixedSize: 8 * unit)).foregroundStyle(Self.printed.opacity(0.6))
                        Text(verbatim: "Waytrace Traveller")
                            .font(.custom("SnellRoundhand-Bold", fixedSize: 24 * unit))
                            .foregroundStyle(Color(red: 0.12, green: 0.2, blue: 0.45))
                            .rotationEffect(.degrees(-3))
                        Rectangle().fill(Self.printed.opacity(0.3)).frame(width: 170 * unit, height: 0.6)
                    }
                    Spacer(minLength: 0)
                    VStack(alignment: .leading, spacing: 2 * unit) {
                        Text(mrz.0)
                        Text(mrz.1)
                    }
                    .font(.system(size: 10.5 * unit, weight: .medium, design: .monospaced))
                    .foregroundStyle(Self.printed.opacity(0.85))
                    .lineLimit(1)
                    .minimumScaleFactor(0.5)
                }
                .padding(20 * unit)
            }
        }
    }

    static let printed = Color(red: 0.25, green: 0.22, blue: 0.30)

    private func field(_ label: String, _ value: String, unit: CGFloat) -> some View {
        VStack(alignment: .leading, spacing: 1 * unit) {
            Text(verbatim: label).font(.custom("AvenirNextCondensed-Medium", fixedSize: 8 * unit)).foregroundStyle(Self.printed.opacity(0.6))
            Text(value).font(.system(size: 14 * unit, weight: .semibold)).foregroundStyle(Self.printed).lineLimit(1).minimumScaleFactor(0.6)
        }
    }

    private static func date(_ date: Date) -> String { StampDate.long(date) }

    /// The two lines at the foot of a passport's data page, 44 characters each.
    private var mrz: (String, String) {
        func pad(_ text: String) -> String { String((text + String(repeating: "<", count: 44)).prefix(44)) }
        let home = book.home ?? "XXX"
        let issued = book.since.map { $0.formatted(.verbatim("\(year: .twoDigits)\(month: .twoDigits)\(day: .twoDigits)", timeZone: .current, calendar: Calendar(identifier: .gregorian))) } ?? "000000"
        return (pad("P<\(home)<WAYTRACE<<TRAVELLER"), pad("\(String(format: "%04d", book.passport.count))<\(issued)<\(book.provinces.count)<\(book.cities.count)"))
    }
}

/// One page of border stamps, scattered the way officers press them wherever there's room.
private struct PassportStampPage: View {
    let stamps: [Stamp]
    let number: Int
    let onSelect: (Stamp) -> Void

    /// Where each of the four lands, as fractions of the page.
    private static let slots: [CGPoint] = [CGPoint(x: 0.30, y: 0.23), CGPoint(x: 0.70, y: 0.36), CGPoint(x: 0.32, y: 0.60), CGPoint(x: 0.69, y: 0.78)]

    private static func jitter(_ seed: UInt64) -> CGPoint {
        var random = SeededRandom(seed)
        return CGPoint(x: (random.unit() - 0.5) * 0.08, y: (random.unit() - 0.5) * 0.05)
    }

    var body: some View {
        GeometryReader { proxy in
            let unit = proxy.size.width / 300
            ZStack {
                StampPaper(style: .passport)
                VStack {
                    Text(verbatim: "签证 · VISAS").font(.custom("AvenirNextCondensed-DemiBold", fixedSize: 9 * unit)).tracking(3 * unit)
                    Spacer()
                    Text(verbatim: "— \(number) —").font(.system(size: 9 * unit, design: .monospaced))
                }
                .foregroundStyle(StampPaper.line)
                .padding(.vertical, 12 * unit)

                if stamps.isEmpty {
                    VStack(spacing: 8 * unit) {
                        RoundedRectangle(cornerRadius: 10 * unit)
                            .stroke(StampPaper.line, style: StrokeStyle(lineWidth: 1, dash: [5, 4]))
                            .frame(width: 150 * unit, height: 96 * unit)
                        Text("出国旅行时，入境的那一刻会自动盖在这里")
                            .font(.system(size: 11 * unit))
                            .multilineTextAlignment(.center)
                            .foregroundStyle(StampPaper.line.mix(with: .black, by: 0.3))
                            .frame(width: 180 * unit)
                    }
                }

                ForEach(Array(stamps.enumerated()), id: \.element.id) { index, stamp in
                    let slot = Self.slots[index % Self.slots.count]
                    let jitter = Self.jitter(stamp.seed)
                    Button { onSelect(stamp) } label: {
                        StampArt(stamp: stamp)
                            .frame(width: 138 * unit, height: 118 * unit)
                    }
                    .buttonStyle(.plain)
                    .stampIn(stamp, delay: 0.35 + Double(index) * 0.45)
                    .position(x: (slot.x + jitter.x) * proxy.size.width, y: (slot.y + jitter.y) * proxy.size.height)
                }
            }
            .clipShape(UnevenRoundedRectangle(cornerRadii: .init(topLeading: 3, bottomLeading: 3, bottomTrailing: 16 * unit, topTrailing: 16 * unit)))
        }
    }
}

/// Pages that turn with a page curl, like a book in your hands.
private struct PageCurl: UIViewControllerRepresentable {
    let pages: [AnyView]
    @Binding var current: Int

    func makeCoordinator() -> Coordinator { Coordinator(self) }

    func makeUIViewController(context: Context) -> UIPageViewController {
        let controller = UIPageViewController(transitionStyle: .pageCurl, navigationOrientation: .horizontal,
                                              options: [.spineLocation: NSNumber(value: UIPageViewController.SpineLocation.min.rawValue)])
        controller.dataSource = context.coordinator
        controller.delegate = context.coordinator
        controller.isDoubleSided = false
        controller.view.backgroundColor = .clear
        controller.setViewControllers([context.coordinator.page(min(current, pages.count - 1))], direction: .forward, animated: false)
        return controller
    }

    func updateUIViewController(_ controller: UIPageViewController, context: Context) {
        context.coordinator.parent = self
    }

    /// A page, remembering which one it is.
    final class Page: UIHostingController<AnyView> {
        var index = 0
    }

    /// Pages are made as they're turned to, so a passport of hundreds of pages opens at once.
    final class Coordinator: NSObject, UIPageViewControllerDataSource, UIPageViewControllerDelegate {
        var parent: PageCurl
        private var made: [Int: Page] = [:]

        init(_ parent: PageCurl) {
            self.parent = parent
        }

        func page(_ index: Int) -> Page {
            if let page = made[index] { return page }
            let page = Page(rootView: AnyView(parent.pages[index].environment(\.locale, appLocale)))
            page.index = index
            page.view.backgroundColor = .clear
            // Keep only the pages near the one open.
            made = made.filter { abs($0.key - index) <= 3 }
            made[index] = page
            return page
        }

        func pageViewController(_ controller: UIPageViewController, viewControllerBefore viewController: UIViewController) -> UIViewController? {
            guard let index = (viewController as? Page)?.index, index > 0 else { return nil }
            return page(index - 1)
        }

        func pageViewController(_ controller: UIPageViewController, viewControllerAfter viewController: UIViewController) -> UIViewController? {
            guard let index = (viewController as? Page)?.index, index + 1 < parent.pages.count else { return nil }
            return page(index + 1)
        }

        func pageViewController(_ controller: UIPageViewController, didFinishAnimating finished: Bool,
                                previousViewControllers: [UIViewController], transitionCompleted completed: Bool) {
            guard completed, let index = (controller.viewControllers?.first as? Page)?.index else { return }
            parent.current = index
            UIImpactFeedbackGenerator(style: .soft).impactOccurred(intensity: 0.5)
        }
    }
}

// MARK: - City stamps

/// Every city's stamp, gathered by country like a stamp-rally book.
struct CityStampBook: View {
    let book: StampBook

    private var groups: [(code: String, stamps: [Stamp])] {
        var order: [String] = []
        var byCountry: [String: [Stamp]] = [:]
        for stamp in book.cities {
            let code = stamp.countryCode ?? ""
            if byCountry[code] == nil { order.append(code) }
            byCountry[code, default: []].append(stamp)
        }
        // Home first, then most cities.
        return order.map { ($0, byCountry[$0] ?? []) }
            .sorted { ($0.code == book.home ? 1 : 0, $0.stamps.count) > ($1.code == book.home ? 1 : 0, $1.stamps.count) }
    }

    var body: some View {
        LazyVStack(alignment: .leading, spacing: 18) {
            ForEach(groups, id: \.code) { group in
                VStack(alignment: .leading, spacing: 10) {
                    HStack {
                        Text("\(String.flag(for: group.code)) \(WorldInsights.countryName(code: group.code, fallback: nil))").font(.headline)
                        Spacer()
                        Text("\(group.stamps.count) 枚").font(.subheadline).foregroundStyle(.secondary).monospacedDigit()
                    }
                    .padding(.horizontal, 4)
                    CityStampGrid(stamps: group.stamps.reversed())
                }
            }
        }
    }
}

/// City stamps three to a row on dotted paper, each with its name and when it was first visited.
struct CityStampGrid: View {
    let stamps: [Stamp]
    var detail: (Stamp) -> String? = { _ in nil }

    var body: some View {
        LazyVGrid(columns: [GridItem(.flexible(), spacing: 6), GridItem(.flexible(), spacing: 6), GridItem(.flexible(), spacing: 6)], spacing: 14) {
            ForEach(Array(stamps.enumerated()), id: \.element.id) { index, stamp in
                NavigationLink(value: DayRoute(day: stamp.date)) {
                    VStack(spacing: 6) {
                        StampWithRoute(stamp: stamp)
                            .frame(height: 92)
                            .stampIn(stamp, delay: 0.2 + Double(index % 9) * 0.14, tilt: stamp.tilt * 0.6)
                        Text(stamp.city ?? "")
                            .font(.footnote.weight(.semibold))
                            .foregroundStyle(Color(red: 0.25, green: 0.22, blue: 0.2))
                            .lineLimit(1)
                        Text(detail(stamp) ?? stamp.date.formatted(.dateTime.year().month().day().locale(appLocale)))
                            .font(.caption2)
                            .foregroundStyle(Color(red: 0.45, green: 0.42, blue: 0.38))
                            .lineLimit(1)
                    }
                    .contentShape(.rect)
                }
                .buttonStyle(PressableStyle())
            }
        }
        .padding(.vertical, 16)
        .padding(.horizontal, 10)
        .background { StampPaper(style: .book) }
        .clipShape(.rect(cornerRadius: 22, style: .continuous))
    }
}

// MARK: - The Places card

/// The way into the passport from Places: the closed passport with the latest stamps fanned
/// beside it.
struct PassportCard: View {
    let book: StampBook

    private var latest: [Stamp] {
        Array((book.passport.filter { $0.kind == .entry } + book.provinces + book.cities).sorted { $0.date > $1.date }.prefix(3))
    }

    var body: some View {
        HStack(spacing: 16) {
            PassportCover(compact: true)
                .frame(width: 74, height: 104)
                .shadow(color: .black.opacity(0.2), radius: 6, y: 3)
            VStack(alignment: .leading, spacing: 4) {
                Text("护照与印章").font(.headline)
                Text("入境 \(book.passport.filter { $0.kind == .entry }.count) · 省份 \(book.provinces.count) · 城市 \(book.cities.count)")
                    .font(.subheadline).foregroundStyle(.secondary)
                    .fixedSize(horizontal: false, vertical: true)
                ZStack(alignment: .leading) {
                    ForEach(Array(latest.enumerated()), id: \.element.id) { index, stamp in
                        StampWithRoute(stamp: stamp)
                            .frame(width: 52, height: 46)
                            .rotationEffect(.degrees(stamp.tilt))
                            .offset(x: CGFloat(index) * 40)
                    }
                }
                .frame(height: 48)
                .padding(.top, 2)
            }
            Spacer(minLength: 0)
            Image(systemName: "chevron.right").font(.caption.weight(.semibold)).foregroundStyle(.tertiary)
        }
        .padding(14)
        .background(.background.secondary, in: .rect(cornerRadius: 24, style: .continuous))
    }
}

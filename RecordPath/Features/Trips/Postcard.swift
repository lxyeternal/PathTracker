import SwiftUI
import SwiftData
import Photos
import PhotosUI
import CoreLocation
import CoreText
import UserNotifications

// MARK: - What goes on a postcard

/// How a card is made up: which design, which photo and how it's framed, and the hand and ink
/// on the back. Kept per trip while you work on it, and sent along with the card.
struct PostcardDesign: Codable, Equatable {
    enum Template: String, Codable, CaseIterable, Identifiable {
        case classic, film, editorial, vintage
        var id: String { rawValue }

        var name: LocalizedStringKey {
            switch self {
            case .classic: "经典"
            case .film: "胶片"
            case .editorial: "留白"
            case .vintage: "复古"
            }
        }
    }

    /// The writing on the back, each in a font that looks written rather than typed.
    enum Hand: String, Codable, CaseIterable, Identifiable {
        case pen, brush, serif, typewriter
        var id: String { rawValue }

        var name: LocalizedStringKey {
            switch self {
            case .pen: "钢笔"
            case .brush: "楷书"
            case .serif: "宋体"
            case .typewriter: "打字机"
            }
        }

        /// Chinese fonts are downloaded by iOS the first time; Latin ones come with it.
        var chinese: String {
            switch self {
            case .pen: "HanziPenSC-W3"
            case .brush: "STKaitiSC-Regular"
            case .serif: "STSongti-SC-Regular"
            case .typewriter: "PingFangSC-Light"
            }
        }

        var latin: String {
            switch self {
            case .pen: "BradleyHandITCTT-Bold"
            case .brush: "SnellRoundhand"
            case .serif: "Georgia-Italic"
            case .typewriter: "AmericanTypewriter"
            }
        }

        func font(for text: String, size: CGFloat) -> Font {
            let cjk = text.unicodeScalars.contains { (0x3000...0x9FFF).contains($0.value) }
            // Snell's letters are small for their size; lift it to sit with the others.
            let scale: CGFloat = !cjk && self == .brush ? 1.25 : 1
            return .custom(cjk ? chinese : latin, fixedSize: size * scale)
        }
    }

    enum Ink: String, Codable, CaseIterable, Identifiable {
        case navy, black, brick, forest
        var id: String { rawValue }

        var color: Color {
            switch self {
            case .navy: Color(red: 0.16, green: 0.2, blue: 0.4)
            case .black: Color(red: 0.13, green: 0.13, blue: 0.14)
            case .brick: Color(red: 0.62, green: 0.2, blue: 0.16)
            case .forest: Color(red: 0.14, green: 0.36, blue: 0.27)
            }
        }
    }

    var template = Template.classic
    var hand = Hand.pen
    var ink = Ink.navy
    /// "asset:<id>", "trip:<id>", "file" (picked from the library) or "route"; nil is the recommended one.
    var photoID: String?
    /// How the photo sits in its frame: zoom from 1, and the shift as a share of the frame.
    var zoom: CGFloat = 1
    var shift: CGSize = .zero

    private static func key(_ tripID: UUID) -> String { "postcard.design.\(tripID)" }

    static func saved(for tripID: UUID) -> PostcardDesign? {
        UserDefaults.standard.data(forKey: key(tripID)).flatMap { try? JSONDecoder().decode(PostcardDesign.self, from: $0) }
    }

    func save(for tripID: UUID) {
        if let data = try? JSONEncoder().encode(self) { UserDefaults.standard.set(data, forKey: Self.key(tripID)) }
    }
}

/// Everything a trip's postcard shows: a picture on the front; on the back, a few lines, a
/// postage stamp and the city's own stamp as the postmark.
struct PostcardContent {
    var title: String
    var subtitle: String
    var image: UIImage?
    var message: String
    var postmark: Stamp
    var countryCode: String?
    var sent: Date
    var design = PostcardDesign()

    /// Home and airports are how you got there, not where you went: they're left out of the
    /// words, and the most memorable stop is a sight if there was one.
    @MainActor
    static func make(trip: Trip, stays: [Stay], chunks: [TrackChunk], home: CLLocation? = nil) -> PostcardContent {
        let away = stays.filter { stay in home.map { stay.location.distance(from: $0) > 30_000 } ?? true }
        let visited = away.filter { $0.category != .airport && $0.category != .transport }
        let named = (visited.isEmpty ? stays : visited).compactMap(\.city)
        let counts = Dictionary(named.map { ($0, 1) }, uniquingKeysWith: +)
        let city = counts.max { $0.value < $1.value }?.key ?? trip.title
        let code = stays.first { $0.city == city }?.countryCode
        let stamp = PlaceSummaries.shared.stamps.cities.first { $0.city == city && $0.countryCode == code }
            ?? Stamp(id: "postmark.\(trip.id)", kind: .city, date: trip.startDate, countryCode: code, city: city,
                     latitude: stays.first?.latitude ?? 0, longitude: stays.first?.longitude ?? 0)
        let distance = chunks.filter { $0.mode != .flying }.reduce(0) { $0 + $1.distance }
        let cities = named.removingDuplicates()
        let memorable = visited.filter(\.isLandmark).max { $0.duration < $1.duration }
            ?? visited.filter { $0.category != .hotel && $0.category != .home && $0.city != nil }.max { $0.duration < $1.duration }
        var lines = [trip.dateRangeText]
        if distance > 500 { lines.append(String(localized: "走过 \(Format.distance(distance))", bundle: .appLanguage)) }
        if cities.count > 1 { lines.append(cities.prefix(4).joined(separator: " → ")) }
        if let memorable { lines.append(String(localized: "最难忘的是\(memorable.displayName)。", bundle: .appLanguage)) }
        return PostcardContent(title: city, subtitle: trip.dateRangeText, image: nil, message: lines.joined(separator: "\n"),
                               postmark: stamp, countryCode: code, sent: Date(), design: PostcardDesign.saved(for: trip.id) ?? PostcardDesign())
    }

    /// The photo the design names, or else the recommended one.
    static func picture(trip: Trip, chunks: [TrackChunk], assets: [PHAsset], home: CLLocation? = nil,
                        design: PostcardDesign? = nil) async -> UIImage? {
        if let id = design?.photoID, let image = await PostcardPhoto.image(id: id, trip: trip, chunks: chunks, home: home) {
            return image
        }
        for source in await PostcardPhoto.recommended(trip: trip, assets: assets).prefix(1) {
            if let image = await PostcardPhoto.image(id: source.id, trip: trip, chunks: chunks, home: home) { return image }
        }
        return await PostcardPhoto.image(id: PostcardPhoto.route.id, trip: trip, chunks: chunks, home: home)
    }
}

/// A photo the card can carry: one added to the trip, one from the library taken on it, one
/// picked from anywhere in the library, or the trip's route drawn on a map.
struct PostcardPhoto: Identifiable, Equatable {
    let id: String
    var asset: PHAsset?
    var tripPhoto: TripPhoto?

    static let route = PostcardPhoto(id: "route")
    static let file = PostcardPhoto(id: "file")

    static func == (a: PostcardPhoto, b: PostcardPhoto) -> Bool { a.id == b.id }

    /// Photos added to the trip first (you chose those), then the best of the library's.
    static func recommended(trip: Trip, assets: [PHAsset]) async -> [PostcardPhoto] {
        let own = (trip.photos ?? []).sorted { $0.takenAt < $1.takenAt }
            .map { PostcardPhoto(id: "trip:\($0.id)", tripPhoto: $0) }
        let ranked = await PhotoCurator.rank(assets, limit: 30).prefix(12)
            .map { PostcardPhoto(id: "asset:\($0.localIdentifier)", asset: $0) }
        return own + ranked
    }

    static var fileURL: (UUID) -> URL = { URL.applicationSupportDirectory.appending(path: "postcard-\($0).jpg") }

    static func image(id: String, trip: Trip, chunks: [TrackChunk], home: CLLocation?) async -> UIImage? {
        let size = CGSize(width: 1500, height: 1000)
        if id.hasPrefix("asset:") {
            let local = String(id.dropFirst(6))
            guard let asset = PHAsset.fetchAssets(withLocalIdentifiers: [local], options: nil).firstObject else { return nil }
            return await AssetLoader.image(for: asset, size: size, exact: false)
        }
        if id.hasPrefix("trip:") {
            return (trip.photos ?? []).first { "trip:\($0.id)" == id }?.imageData.flatMap(UIImage.init(data:))
        }
        if id == file.id {
            return (try? Data(contentsOf: fileURL(trip.id))).flatMap(UIImage.init(data:))
        }
        // The trip itself, not the ride to the airport.
        let away = chunks.filter { chunk in
            guard let home, let first = chunk.points.first else { return true }
            return CLLocation(latitude: first.latitude, longitude: first.longitude).distance(from: home) > 30_000
        }
        let lines = (away.isEmpty ? chunks : away).filter { $0.mode != .flying }.map {
            RouteImage.Line(coordinates: $0.points.simplified(tolerance: 20).map(\.coordinate), color: .orange)
        }
        return await RouteImage.render(lines, size: CGSize(width: 450, height: 300), dark: false, key: "postcard-\(trip.id)",
                                       minimumSpan: 2_000, lineWidth: 4)
    }
}

/// The Chinese handwriting fonts aren't on the phone until asked for; iOS fetches them once.
@MainActor
enum HandFonts {
    private static var asked: Set<String> = []

    static func isReady(_ name: String) -> Bool { UIFont(name: name, size: 12) != nil }

    static func fetch(_ name: String) async -> Bool {
        if isReady(name) { return true }
        guard asked.insert(name).inserted else { return false }
        let descriptor = CTFontDescriptorCreateWithAttributes([kCTFontNameAttribute: name] as CFDictionary)
        return await withCheckedContinuation { continuation in
            let once = Once()
            CTFontDescriptorMatchFontDescriptorsWithProgressHandler([descriptor] as CFArray, nil) { state, _ in
                switch state {
                case .didFinish: once.run { continuation.resume(returning: true) }
                case .didFailWithError: once.run { continuation.resume(returning: false) }
                default: break
                }
                return true
            }
        }
    }

    private final class Once: @unchecked Sendable {
        private var done = false
        private let lock = NSLock()
        func run(_ work: () -> Void) {
            lock.lock()
            defer { lock.unlock() }
            guard !done else { return }
            done = true
            work()
        }
    }
}

// MARK: - The card

/// A postcard that turns over when tapped. With `editing`, the photo can be dragged and
/// pinched into place.
struct PostcardView: View {
    let content: PostcardContent
    @Binding var flipped: Bool
    var recipient: String = String(localized: "一年后的我", bundle: .appLanguage)
    var editing: Binding<PostcardDesign>?

    var body: some View {
        ZStack {
            PostcardFront(content: content, editing: flipped ? nil : editing)
                .modifier(FaceUp(angle: flipped ? 180 : 0))
            PostcardBack(content: content, recipient: recipient)
                .modifier(FaceUp(angle: flipped ? 0 : -180))
        }
        .aspectRatio(1.5, contentMode: .fit)
        .animation(.spring(response: 0.75, dampingFraction: 0.78), value: flipped)
        .contentShape(.rect)
        .onTapGesture { flipped.toggle() }
        .sensoryFeedback(.impact(weight: .light), trigger: flipped)
        .accessibilityAction(named: Text("翻面")) { flipped.toggle() }
    }
}

/// Turns a face with the card and hides it once it faces away.
private struct FaceUp: ViewModifier, Animatable {
    var angle: Double
    var animatableData: Double {
        get { angle }
        set { angle = newValue }
    }

    func body(content: Content) -> some View {
        content
            .rotation3DEffect(.degrees(angle), axis: (x: 0, y: 1, z: 0), perspective: 0.45)
            .opacity(abs(angle) < 90 ? 1 : 0)
    }
}

/// The photo filling its frame, zoomed and shifted the way the design says, never leaving a gap.
private struct FramedPhoto: View {
    let image: UIImage?
    let design: PostcardDesign
    var editing: Binding<PostcardDesign>?
    var tone: PostcardDesign.Template = .classic
    @GestureState private var drag = CGSize.zero
    @GestureState private var pinch: CGFloat = 1

    var body: some View {
        GeometryReader { proxy in
            let frame = proxy.size
            let zoom = min(max(design.zoom * pinch, 1), 4)
            let shift = Self.clamp(CGSize(width: design.shift.width + drag.width / max(frame.width, 1),
                                          height: design.shift.height + drag.height / max(frame.height, 1)),
                                   zoom: zoom, image: image?.size, frame: frame)
            Group {
                if let image {
                    Image(uiImage: image)
                        .resizable()
                        .scaledToFill()
                        .frame(width: frame.width, height: frame.height)
                        .scaleEffect(zoom)
                        .offset(x: shift.width * frame.width, y: shift.height * frame.height)
                        .modifier(Tone(template: tone))
                } else {
                    // Paper while the photo loads.
                    Color(red: 0.9, green: 0.88, blue: 0.84)
                }
            }
            .frame(width: frame.width, height: frame.height)
            .clipped()
            .contentShape(.rect)
            .gesture(editing == nil ? nil : adjust(frame: frame))
        }
    }

    private func adjust(frame: CGSize) -> some Gesture {
        let move = DragGesture(minimumDistance: 6)
            .updating($drag) { value, state, _ in state = value.translation }
            .onEnded { value in
                guard let editing else { return }
                let moved = CGSize(width: editing.wrappedValue.shift.width + value.translation.width / max(frame.width, 1),
                                   height: editing.wrappedValue.shift.height + value.translation.height / max(frame.height, 1))
                editing.wrappedValue.shift = Self.clamp(moved, zoom: editing.wrappedValue.zoom, image: image?.size, frame: frame)
            }
        let zoom = MagnifyGesture()
            .updating($pinch) { value, state, _ in state = value.magnification }
            .onEnded { value in
                guard let editing else { return }
                let zoom = min(max(editing.wrappedValue.zoom * value.magnification, 1), 4)
                editing.wrappedValue.zoom = zoom
                editing.wrappedValue.shift = Self.clamp(editing.wrappedValue.shift, zoom: zoom, image: image?.size, frame: frame)
            }
        return move.simultaneously(with: zoom)
    }

    /// As far as the photo can move before an edge shows, as a share of the frame.
    static func clamp(_ shift: CGSize, zoom: CGFloat, image: CGSize?, frame: CGSize) -> CGSize {
        guard let image, image.width > 0, image.height > 0, frame.width > 0, frame.height > 0 else { return .zero }
        let fill = max(frame.width / image.width, frame.height / image.height)
        let spareX = (image.width * fill * zoom - frame.width) / 2 / frame.width
        let spareY = (image.height * fill * zoom - frame.height) / 2 / frame.height
        return CGSize(width: min(max(shift.width, -spareX), spareX), height: min(max(shift.height, -spareY), spareY))
    }

    /// Each design's colour: the vintage card warm and faded, the film one a touch warm.
    private struct Tone: ViewModifier {
        let template: PostcardDesign.Template

        func body(content: Content) -> some View {
            switch template {
            case .vintage:
                content.saturation(0.55).contrast(0.92).brightness(0.02)
                    .overlay { Rectangle().fill(Color(red: 0.75, green: 0.5, blue: 0.25, opacity: 0.22)).blendMode(.multiply) }
            case .film:
                content.saturation(0.9).overlay { Rectangle().fill(Color(red: 1, green: 0.6, blue: 0.2, opacity: 0.06)).blendMode(.softLight) }
            default:
                content
            }
        }
    }
}

private struct PostcardFront: View {
    let content: PostcardContent
    var editing: Binding<PostcardDesign>?

    private let paper = Color(red: 0.99, green: 0.98, blue: 0.96)
    private let ink = Color(red: 0.13, green: 0.13, blue: 0.15)

    var body: some View {
        GeometryReader { proxy in
            let unit = proxy.size.width / 360
            Group {
                switch content.design.template {
                case .classic: classic(unit)
                case .film: film(unit)
                case .editorial: editorial(unit)
                case .vintage: vintage(unit)
                }
            }
            .frame(width: proxy.size.width, height: proxy.size.height)
            .clipShape(.rect(cornerRadius: 10 * unit, style: .continuous))
            .shadow(color: .black.opacity(0.2), radius: 12, y: 6)
        }
    }

    private func photo(_ tone: PostcardDesign.Template = .classic) -> FramedPhoto {
        FramedPhoto(image: content.image, design: editing?.wrappedValue ?? content.design, editing: editing, tone: tone)
    }

    private var latin: Bool { Self.latin(content.title) }

    /// "Greetings from" over the photo, the city in big letters: the card from every kiosk.
    private func classic(_ unit: CGFloat) -> some View {
        ZStack(alignment: .bottomLeading) {
            photo()
            LinearGradient(colors: [.clear, .black.opacity(0.55)], startPoint: .center, endPoint: .bottom)
                .allowsHitTesting(false)
            VStack(alignment: .leading, spacing: -4 * unit) {
                Text(verbatim: "Greetings from")
                    .font(.custom("SnellRoundhand-Bold", fixedSize: 24 * unit))
                Text(verbatim: Self.lettering(content.title))
                    .font(latin ? .custom("AvenirNextCondensed-Heavy", fixedSize: 52 * unit) : .system(size: 46 * unit, weight: .black))
                    .lineLimit(1).minimumScaleFactor(0.4)
                    .shadow(color: .black.opacity(0.35), radius: 0, x: 2 * unit, y: 2 * unit)
                Text(verbatim: content.subtitle)
                    .font(.system(size: 11 * unit, weight: .semibold))
                    .opacity(0.85)
                    .padding(.top, 8 * unit)
            }
            .foregroundStyle(.white)
            .padding(18 * unit)
            .allowsHitTesting(false)
        }
        // The white border of a printed card.
        .clipShape(.rect(cornerRadius: 4 * unit))
        .padding(9 * unit)
        .background(paper)
    }

    /// A print with a wide margin: the date burnt in orange in the corner, the place written below.
    private func film(_ unit: CGFloat) -> some View {
        VStack(spacing: 0) {
            ZStack(alignment: .bottomTrailing) {
                photo(.film)
                Text(verbatim: Self.filmDate(content.postmark.date))
                    .font(.system(size: 11 * unit, weight: .semibold, design: .monospaced))
                    .foregroundStyle(Color(red: 1, green: 0.55, blue: 0.2))
                    .shadow(color: Color(red: 1, green: 0.4, blue: 0.1).opacity(0.8), radius: 2 * unit)
                    .padding(10 * unit)
                    .allowsHitTesting(false)
            }
            .clipShape(.rect(cornerRadius: 2 * unit))
            HStack(alignment: .lastTextBaseline) {
                Text(verbatim: content.title)
                    .font(latin ? .custom("Didot-Italic", fixedSize: 24 * unit) : .system(size: 20 * unit, weight: .medium, design: .serif))
                    .lineLimit(1).minimumScaleFactor(0.5)
                Spacer(minLength: 8 * unit)
                Text(verbatim: content.subtitle)
                    .font(.system(size: 9 * unit, weight: .medium, design: .monospaced))
                    .opacity(0.55)
                    .lineLimit(1).minimumScaleFactor(0.6)
            }
            .foregroundStyle(ink)
            .frame(height: 44 * unit)
            .padding(.horizontal, 4 * unit)
        }
        .padding([.horizontal, .top], 12 * unit)
        .padding(.bottom, 2 * unit)
        .background(paper)
    }

    /// A magazine page: the photo on the right, the place set quietly in the margin with where on
    /// earth it is.
    private func editorial(_ unit: CGFloat) -> some View {
        HStack(spacing: 0) {
            VStack(alignment: .leading, spacing: 0) {
                Text(verbatim: AppInfo.name.uppercased())
                    .font(.system(size: 7 * unit, weight: .semibold)).tracking(2.5 * unit)
                    .opacity(0.5)
                Spacer()
                Text(verbatim: content.title)
                    .font(latin ? .custom("Didot", fixedSize: 30 * unit) : .system(size: 26 * unit, weight: .semibold, design: .serif))
                    .lineLimit(3).minimumScaleFactor(0.45)
                Rectangle().fill(ink.opacity(0.6)).frame(width: 22 * unit, height: 1).padding(.vertical, 9 * unit)
                Text(verbatim: Self.coordinates(content.postmark))
                    .font(.system(size: 7.5 * unit, weight: .medium, design: .monospaced))
                    .opacity(0.6)
                Text(verbatim: content.subtitle)
                    .font(.system(size: 8 * unit, weight: .medium))
                    .opacity(0.6)
                    .lineLimit(2).minimumScaleFactor(0.7)
                    .padding(.top, 3 * unit)
            }
            .foregroundStyle(ink)
            .padding(.vertical, 18 * unit)
            .padding(.leading, 18 * unit)
            .padding(.trailing, 12 * unit)
            .frame(width: 128 * unit, alignment: .leading)
            photo()
                .padding([.vertical, .trailing], 14 * unit)
        }
        .background(Color(red: 0.96, green: 0.95, blue: 0.92))
    }

    /// A faded card from a shop drawer: warm photo, a thin double frame, the name in engraved capitals.
    private func vintage(_ unit: CGFloat) -> some View {
        ZStack {
            photo(.vintage)
            RadialGradient(colors: [.clear, Color(red: 0.25, green: 0.15, blue: 0.05).opacity(0.45)], center: .center,
                           startRadius: 90 * unit, endRadius: 260 * unit)
                .allowsHitTesting(false)
            ZStack {
                RoundedRectangle(cornerRadius: 3 * unit).stroke(paper.opacity(0.9), lineWidth: 1.4 * unit).padding(12 * unit)
                RoundedRectangle(cornerRadius: 2 * unit).stroke(paper.opacity(0.7), lineWidth: 0.6 * unit).padding(16 * unit)
                VStack(spacing: 4 * unit) {
                    Text(verbatim: "\(AppInfo.name.uppercased()) · \(String(Calendar.current.component(.year, from: content.postmark.date)))")
                        .font(.custom("Copperplate", fixedSize: 9 * unit)).tracking(2 * unit)
                    Text(verbatim: Self.lettering(content.title))
                        .font(latin ? .custom("Copperplate-Bold", fixedSize: 38 * unit) : .system(size: 36 * unit, weight: .heavy, design: .serif))
                        .tracking(latin ? 2 * unit : 6 * unit)
                        .lineLimit(1).minimumScaleFactor(0.4)
                }
                .foregroundStyle(paper)
                .shadow(color: .black.opacity(0.5), radius: 3 * unit, y: 1 * unit)
                .padding(.horizontal, 28 * unit)
                .frame(maxHeight: .infinity, alignment: .bottom)
                .padding(.bottom, 30 * unit)
            }
            .allowsHitTesting(false)
        }
    }

    static func latin(_ text: String) -> Bool { text.unicodeScalars.allSatisfy { $0.value < 0x0250 || $0 == " " } }
    static func lettering(_ text: String) -> String { latin(text) ? text.uppercased() : text }

    /// "'26 10 29", the way a film camera prints it.
    static func filmDate(_ date: Date) -> String {
        let c = Calendar.current.dateComponents([.year, .month, .day], from: date)
        return String(format: "'%02d %2d %02d", (c.year ?? 0) % 100, c.month ?? 0, c.day ?? 0)
    }

    static func coordinates(_ stamp: Stamp) -> String {
        guard stamp.latitude != 0 || stamp.longitude != 0 else { return "" }
        return String(format: "%.2f°%@  %.2f°%@", abs(stamp.latitude), stamp.latitude >= 0 ? "N" : "S",
                      abs(stamp.longitude), stamp.longitude >= 0 ? "E" : "W")
    }
}

private struct PostcardBack: View {
    let content: PostcardContent
    let recipient: String

    private let line = Color(red: 0.8, green: 0.76, blue: 0.68)
    private var ink: Color { content.design.ink.color }

    var body: some View {
        GeometryReader { proxy in
            let unit = proxy.size.width / 360
            let hand = content.design.hand
            ZStack(alignment: .topLeading) {
                Color(red: 0.98, green: 0.96, blue: 0.91)
                HStack(spacing: 0) {
                    // The message side, written by hand and not quite straight.
                    VStack(alignment: .leading, spacing: 8 * unit) {
                        Text(verbatim: content.message)
                            .font(hand.font(for: content.message, size: (hand == .typewriter ? 11.5 : 13) * unit))
                            .foregroundStyle(ink)
                            .lineSpacing(4 * unit)
                            .minimumScaleFactor(0.6)
                            .rotationEffect(.degrees(hand == .typewriter ? 0 : -1.2), anchor: .topLeading)
                            .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
                        Text(verbatim: "— \(AppInfo.name) · \(content.sent.formatted(.dateTime.year().month().day().locale(appLocale)))")
                            .font(hand.font(for: AppInfo.name, size: 9.5 * unit))
                            .foregroundStyle(ink.opacity(0.65))
                    }
                    .padding(16 * unit)
                    .frame(width: proxy.size.width * 0.56)
                    Rectangle().fill(line).frame(width: 1).padding(.vertical, 18 * unit)
                    // The address side.
                    VStack(alignment: .trailing, spacing: 0) {
                        PostageStamp(countryCode: content.countryCode, year: Calendar.current.component(.year, from: content.sent))
                            .frame(width: 58 * unit, height: 70 * unit)
                        Spacer()
                        VStack(alignment: .leading, spacing: 4 * unit) {
                            Text(verbatim: "TO").font(.custom("AvenirNextCondensed-DemiBold", fixedSize: 9 * unit)).foregroundStyle(ink.opacity(0.5))
                            Text(verbatim: recipient)
                                .font(hand.font(for: recipient, size: 14 * unit))
                                .foregroundStyle(ink)
                                .lineLimit(1).minimumScaleFactor(0.6)
                                .frame(height: 20 * unit, alignment: .bottom)
                            Rectangle().fill(line).frame(height: 0.8)
                            Rectangle().fill(line).frame(height: 0.8).padding(.top, 18 * unit)
                        }
                    }
                    .padding(14 * unit)
                }
                // The postmark lands across the postage stamp, the way the post office franks it.
                StampArt(stamp: content.postmark)
                    .frame(width: 92 * unit, height: 92 * unit)
                    .rotationEffect(.degrees(-14))
                    .opacity(0.88)
                    .position(x: proxy.size.width * 0.74, y: 58 * unit)
                Cancellation()
                    .stroke(content.postmark.kind == .city ? Color.black.opacity(0.35) : .clear, lineWidth: 1.2)
                    .frame(width: 70 * unit, height: 26 * unit)
                    .position(x: proxy.size.width * 0.62, y: 58 * unit)
            }
            .clipShape(.rect(cornerRadius: 10 * unit, style: .continuous))
            .shadow(color: .black.opacity(0.2), radius: 12, y: 6)
        }
    }
}

/// The wavy lines a franking machine prints beside the postmark.
private struct Cancellation: Shape {
    func path(in rect: CGRect) -> Path {
        var path = Path()
        for row in 0..<4 {
            let y = rect.minY + rect.height * CGFloat(row) / 3
            path.move(to: CGPoint(x: rect.minX, y: y))
            for x in stride(from: rect.minX, through: rect.maxX, by: 2) {
                path.addLine(to: CGPoint(x: x, y: y + 2.5 * sin((x - rect.minX) / 6)))
            }
        }
        return path
    }
}

/// A postage stamp with perforated edges.
private struct PostageStamp: View {
    let countryCode: String?
    let year: Int

    var body: some View {
        GeometryReader { proxy in
            let unit = proxy.size.width / 58
            ZStack {
                // Even-odd, so the bites are cut out of the paper.
                Perforated(radius: 2.2 * unit).fill(.white, style: FillStyle(eoFill: true)).shadow(color: .black.opacity(0.15), radius: 1)
                VStack(spacing: 2 * unit) {
                    Text(countryCode.map { String.flag(for: $0) } ?? "🌏").font(.system(size: 22 * unit))
                    Text(verbatim: AppInfo.name).font(.system(size: 7 * unit, weight: .bold))
                    Text(verbatim: String(year)).font(.system(size: 7 * unit, weight: .bold, design: .monospaced))
                }
                .foregroundStyle(Color(red: 0.5, green: 0.12, blue: 0.16))
                .frame(width: proxy.size.width - 10 * unit, height: proxy.size.height - 10 * unit)
                .background(Color(red: 0.98, green: 0.9, blue: 0.82))
            }
        }
    }
}

/// A rectangle with half-circle bites along every edge.
private struct Perforated: Shape {
    let radius: CGFloat

    func path(in rect: CGRect) -> Path {
        var path = Path(rect)
        let step = radius * 3
        for x in stride(from: rect.minX + step / 2, to: rect.maxX, by: step) {
            path.addEllipse(in: CGRect(x: x - radius, y: rect.minY - radius, width: radius * 2, height: radius * 2))
            path.addEllipse(in: CGRect(x: x - radius, y: rect.maxY - radius, width: radius * 2, height: radius * 2))
        }
        for y in stride(from: rect.minY + step / 2, to: rect.maxY, by: step) {
            path.addEllipse(in: CGRect(x: rect.minX - radius, y: y - radius, width: radius * 2, height: radius * 2))
            path.addEllipse(in: CGRect(x: rect.maxX - radius, y: y - radius, width: radius * 2, height: radius * 2))
        }
        return path
    }
}

// MARK: - Making and sending one

/// The postcard for a trip: pick a design and a photo, frame it, write on the back, then share
/// it or send it to yourself a year from now.
struct PostcardSheet: View {
    let trip: Trip
    let stays: [Stay]
    let chunks: [TrackChunk]
    let assets: [PHAsset]

    @Environment(\.dismiss) private var dismiss
    @Environment(\.modelContext) private var context
    @State private var content: PostcardContent?
    @State private var design = PostcardDesign()
    @State private var flipped = false
    @State private var message = ""
    @State private var sending = false
    @State private var sent: Postcard?
    @State private var share: Image?
    @State private var photos: [PostcardPhoto] = []
    @State private var thumbnails: [String: UIImage] = [:]
    @State private var picked: PhotosPickerItem?
    @State private var loadingPhoto: String?
    @State private var fontsReady = 0
    @FocusState private var writing: Bool

    private var home: CLLocation? { TripSuggestionCard.homeBase(in: context) }

    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(spacing: 20) {
                    if let content {
                        PostcardView(content: current(content), flipped: $flipped, editing: sent == nil ? $design : nil)
                            .id(fontsReady)
                            .padding(.horizontal, 20)
                            .scaleEffect(sending ? 0.35 : 1)
                            .rotationEffect(.degrees(sending ? -10 : 0))
                            .offset(y: sending ? -700 : 0)
                            .opacity(sending ? 0 : 1)
                    } else {
                        ProgressView().frame(height: 240)
                    }

                    if sent == nil {
                        Picker("", selection: $flipped) {
                            Text("正面").tag(false)
                            Text("背面").tag(true)
                        }
                        .pickerStyle(.segmented)
                        .padding(.horizontal, 20)

                        Group {
                            if flipped { backEditor } else { frontEditor }
                        }
                        .transition(.opacity)
                    } else {
                        Label(flipped ? "轻点翻回正面" : "轻点翻到背面", systemImage: "hand.tap")
                            .font(.footnote).foregroundStyle(.secondary)
                        if let sent {
                            Label("已寄出，\(sent.deliver.formatted(.dateTime.year().month().day().locale(appLocale)))送达", systemImage: "envelope.badge.fill")
                                .font(.subheadline.weight(.semibold))
                                .foregroundStyle(.orange)
                                .transition(.scale.combined(with: .opacity))
                        }
                    }

                    actions
                }
                .padding(.vertical, 16)
                .animation(.smooth, value: flipped)
            }
            .scrollDismissesKeyboard(.interactively)
            .navigationTitle("旅行明信片")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("关闭", systemImage: "xmark") { dismiss() }
                }
            }
            .task { await prepare() }
            .onChange(of: message) { renderShare() }
            .onChange(of: design) { _, design in
                design.save(for: trip.id)
                renderShare()
            }
            .onChange(of: design.photoID) { Task { await loadPhoto() } }
            .onChange(of: design.hand) { Task { await fetchFont() } }
            .onChange(of: picked) { Task { await usePicked() } }
        }
    }

    // MARK: Editors

    private var frontEditor: some View {
        VStack(alignment: .leading, spacing: 18) {
            section("样式") {
                ScrollView(.horizontal) {
                    HStack(spacing: 12) {
                        ForEach(PostcardDesign.Template.allCases) { template in
                            templateTile(template)
                        }
                    }
                    .padding(.horizontal, 20)
                }
                .scrollIndicators(.hidden)
            }
            section("照片") {
                ScrollView(.horizontal) {
                    HStack(spacing: 10) {
                        PhotosPicker(selection: $picked, matching: .images) {
                            VStack(spacing: 4) {
                                Image(systemName: "photo.badge.plus").font(.title3)
                                Text("相册").font(.caption2.weight(.semibold))
                            }
                            .foregroundStyle(.secondary)
                            .frame(width: 66, height: 66)
                            .background(.background.secondary, in: .rect(cornerRadius: 12, style: .continuous))
                            .overlay {
                                if design.photoID == PostcardPhoto.file.id {
                                    RoundedRectangle(cornerRadius: 12, style: .continuous).stroke(Color.orange, lineWidth: 2.5)
                                }
                            }
                        }
                        ForEach(photos) { photo in photoTile(photo) }
                    }
                    .padding(.horizontal, 20)
                }
                .scrollIndicators(.hidden)
            }
            HStack {
                Label("在明信片上拖动、双指缩放，调整构图", systemImage: "hand.draw")
                Spacer()
                if design.zoom != 1 || design.shift != .zero {
                    Button("复原") {
                        withAnimation(.smooth) {
                            design.zoom = 1
                            design.shift = .zero
                        }
                    }
                    .font(.footnote.weight(.semibold))
                }
            }
            .font(.footnote).foregroundStyle(.secondary)
            .padding(.horizontal, 20)
        }
    }

    private var backEditor: some View {
        VStack(alignment: .leading, spacing: 18) {
            section("写在背面") {
                TextField("写几句话", text: $message, axis: .vertical)
                    .lineLimit(3...6)
                    .focused($writing)
                    .padding(12)
                    .background(.background.secondary, in: .rect(cornerRadius: 16, style: .continuous))
                    .padding(.horizontal, 20)
            }
            section("字迹") {
                HStack(spacing: 8) {
                    ForEach(PostcardDesign.Hand.allCases) { hand in
                        let selected = design.hand == hand
                        Button {
                            withAnimation(.snappy) { design.hand = hand }
                        } label: {
                            Text(hand.name)
                                .font(hand.font(for: "字", size: 16))
                                .frame(maxWidth: .infinity).frame(height: 40)
                                .foregroundStyle(selected ? Color.white : design.ink.color)
                                .background(selected ? AnyShapeStyle(design.ink.color) : AnyShapeStyle(.background.secondary),
                                            in: .rect(cornerRadius: 12, style: .continuous))
                        }
                        .buttonStyle(.plain)
                        .id("\(hand.rawValue)-\(fontsReady)")
                    }
                }
                .padding(.horizontal, 20)
                .sensoryFeedback(.selection, trigger: design.hand)
            }
            section("墨水") {
                HStack(spacing: 14) {
                    ForEach(PostcardDesign.Ink.allCases) { ink in
                        Button {
                            withAnimation(.snappy) { design.ink = ink }
                        } label: {
                            Circle().fill(ink.color)
                                .frame(width: 30, height: 30)
                                .padding(4)
                                .overlay(Circle().stroke(design.ink == ink ? ink.color : .clear, lineWidth: 2))
                        }
                        .buttonStyle(.plain)
                    }
                }
                .padding(.horizontal, 20)
                .sensoryFeedback(.selection, trigger: design.ink)
            }
        }
    }

    private func section(_ title: LocalizedStringKey, @ViewBuilder content: () -> some View) -> some View {
        VStack(alignment: .leading, spacing: 10) {
            Text(title).font(.headline).padding(.horizontal, 20)
            content()
        }
    }

    private func templateTile(_ template: PostcardDesign.Template) -> some View {
        let selected = design.template == template
        return Button {
            withAnimation(.smooth) { design.template = template }
        } label: {
            VStack(spacing: 6) {
                if let content {
                    var sample = current(content)
                    let _ = sample.design.template = template
                    PostcardFront(content: sample)
                        .frame(width: 120, height: 80)
                        .allowsHitTesting(false)
                }
                Text(template.name)
                    .font(.caption.weight(selected ? .bold : .medium))
                    .foregroundStyle(selected ? Color.primary : Color.secondary)
            }
            .padding(4)
            .overlay(alignment: .top) {
                RoundedRectangle(cornerRadius: 12, style: .continuous)
                    .stroke(selected ? Color.orange : .clear, lineWidth: 2.5)
                    .frame(width: 128, height: 88)
            }
            // The preview takes no touches, so the whole tile is the button.
            .contentShape(.rect)
        }
        .buttonStyle(.plain)
        .sensoryFeedback(.selection, trigger: design.template)
    }

    private func photoTile(_ photo: PostcardPhoto) -> some View {
        let selected = (design.photoID ?? photos.first?.id) == photo.id
        return Button {
            guard !selected else { return }
            design.zoom = 1
            design.shift = .zero
            design.photoID = photo.id
        } label: {
            ZStack {
                if let thumb = thumbnails[photo.id] {
                    Image(uiImage: thumb).resizable().scaledToFill()
                } else {
                    Rectangle().fill(.quaternary)
                }
                if photo.id == PostcardPhoto.route.id {
                    Image(systemName: "point.topleft.down.to.point.bottomright.curvepath.fill")
                        .font(.caption.weight(.bold)).foregroundStyle(.white)
                        .padding(5).background(.black.opacity(0.35), in: .circle)
                }
                if loadingPhoto == photo.id { ProgressView().tint(.white) }
            }
            .frame(width: 66, height: 66)
            .clipShape(.rect(cornerRadius: 12, style: .continuous))
            .overlay {
                RoundedRectangle(cornerRadius: 12, style: .continuous).stroke(selected ? Color.orange : .clear, lineWidth: 2.5)
            }
        }
        .buttonStyle(.plain)
        .task(id: photo.id) { await thumbnail(photo) }
    }

    private var actions: some View {
        VStack(spacing: 10) {
            if sent == nil {
                Button(action: send) {
                    Label("寄给一年后的自己", systemImage: "paperplane.fill")
                        .font(.headline).frame(maxWidth: .infinity).frame(height: 50)
                }
                .buttonStyle(.glassProminent)
                .tint(.orange)
                .disabled(content == nil)
            }
            if let share {
                ShareLink(item: share, preview: SharePreview(trip.title, image: share)) {
                    Label("分享明信片", systemImage: "square.and.arrow.up")
                        .font(.headline).frame(maxWidth: .infinity).frame(height: 50)
                }
                .buttonStyle(.glass)
            }
            #if DEBUG
            Button("调试：一分钟后送达") { send(after: 60) }.font(.footnote)
            #endif
        }
        .padding(.horizontal, 20)
    }

    // MARK: Work

    private func current(_ content: PostcardContent) -> PostcardContent {
        var copy = content
        copy.message = message
        copy.design = design
        return copy
    }

    private func prepare() async {
        sent = PostcardMail.scheduled(for: trip.id)
        let made = PostcardContent.make(trip: trip, stays: stays, chunks: chunks, home: home)
        design = sent?.design ?? made.design
        message = sent?.message ?? made.message
        withAnimation(.smooth) { content = made }
        await fetchFont()
        photos = await PostcardPhoto.recommended(trip: trip, assets: assets) + [PostcardPhoto.route]
        await loadPhoto()
    }

    private func loadPhoto() async {
        guard content != nil else { return }
        let id = design.photoID ?? photos.first?.id ?? PostcardPhoto.route.id
        loadingPhoto = id
        let image = await PostcardPhoto.image(id: id, trip: trip, chunks: chunks, home: home)
        if loadingPhoto == id { loadingPhoto = nil }
        withAnimation(.smooth) { content?.image = image }
        renderShare()
    }

    private func thumbnail(_ photo: PostcardPhoto) async {
        guard thumbnails[photo.id] == nil else { return }
        if let asset = photo.asset {
            thumbnails[photo.id] = await AssetLoader.image(for: asset, size: CGSize(width: 200, height: 200), exact: false)
        } else {
            thumbnails[photo.id] = await PostcardPhoto.image(id: photo.id, trip: trip, chunks: chunks, home: home)
        }
    }

    /// A photo from anywhere in the library is kept as a file, so the card keeps it whatever
    /// access to Photos the app has later.
    private func usePicked() async {
        guard let picked, let data = try? await picked.loadTransferable(type: Data.self),
              let image = UIImage(data: data) else { return }
        let scaled = image.preparingThumbnail(of: Self.fit(image.size, within: 2000)) ?? image
        try? scaled.jpegData(compressionQuality: 0.88)?.write(to: PostcardPhoto.fileURL(trip.id), options: .atomic)
        design.zoom = 1
        design.shift = .zero
        if design.photoID == PostcardPhoto.file.id {
            await loadPhoto()
        } else {
            design.photoID = PostcardPhoto.file.id
        }
        self.picked = nil
    }

    private static func fit(_ size: CGSize, within side: CGFloat) -> CGSize {
        let scale = min(1, side / max(size.width, size.height))
        return CGSize(width: size.width * scale, height: size.height * scale)
    }

    /// Fetches the chosen hand's Chinese font if the phone doesn't have it yet, then redraws.
    private func fetchFont() async {
        let name = design.hand.chinese
        guard !HandFonts.isReady(name) else { return }
        if await HandFonts.fetch(name) {
            fontsReady += 1
            renderShare()
        }
    }

    private func renderShare() {
        guard let content else { return }
        share = PostcardImage.render(current(content))
    }

    private func send() { send(after: nil) }

    private func send(after seconds: TimeInterval?) {
        guard sent == nil else { return }
        writing = false
        Task {
            // Turned over to the address, then off it goes.
            if !flipped {
                flipped = true
                try? await Task.sleep(for: .seconds(0.7))
            }
            UIImpactFeedbackGenerator(style: .medium).impactOccurred()
            withAnimation(.easeIn(duration: 0.6)) { sending = true }
            try? await Task.sleep(for: .seconds(0.65))
            let card = await PostcardMail.send(trip: trip, message: message, design: design, after: seconds)
            UINotificationFeedbackGenerator().notificationOccurred(.success)
            withAnimation(.spring(response: 0.6, dampingFraction: 0.8)) {
                sent = card
                sending = false
                flipped = false
            }
        }
    }
}

/// Both sides of the card, one above the other, as a picture to share.
enum PostcardImage {
    @MainActor
    static func render(_ content: PostcardContent) -> Image? {
        let view = VStack(spacing: 24) {
            PostcardView(content: content, flipped: .constant(false), recipient: "")
            PostcardView(content: content, flipped: .constant(true), recipient: "")
        }
        .padding(28)
        .frame(width: 420)
        .background(Color(red: 0.93, green: 0.91, blue: 0.87))
        .environment(\.locale, appLocale)
        let renderer = ImageRenderer(content: view)
        renderer.scale = 3
        return renderer.uiImage.map { Image(uiImage: $0) }
    }
}

// MARK: - The post

/// A postcard on its way to the future.
struct Postcard: Codable, Identifiable, Equatable {
    var id = UUID()
    let tripID: UUID
    let sent: Date
    let deliver: Date
    var message: String
    var delivered = false
    /// How the card looked when it was sent; older cards have none and use the defaults.
    var design: PostcardDesign?
}

/// Postcards sent to yourself. Kept in iCloud's key-value store, so one sent from this phone
/// still arrives if you've moved to another by then.
@MainActor
enum PostcardMail {
    private static let key = "postcards.mail"
    private static var cloud: NSUbiquitousKeyValueStore { .default }

    static var all: [Postcard] {
        let data = cloud.data(forKey: key) ?? UserDefaults.standard.data(forKey: key)
        return data.flatMap { try? JSONDecoder().decode([Postcard].self, from: $0) } ?? []
    }

    private static func save(_ cards: [Postcard]) {
        guard let data = try? JSONEncoder().encode(cards) else { return }
        cloud.set(data, forKey: key)
        UserDefaults.standard.set(data, forKey: key)
    }

    static func scheduled(for tripID: UUID) -> Postcard? { all.first { $0.tripID == tripID } }

    /// Sends it a year from now, at ten in the morning. `seconds` is for trying it out.
    static func send(trip: Trip, message: String, design: PostcardDesign? = nil, after seconds: TimeInterval? = nil) async -> Postcard {
        let calendar = Calendar.current
        var deliver = calendar.date(byAdding: .year, value: 1, to: Date()) ?? Date()
        deliver = calendar.date(bySettingHour: 10, minute: 0, second: 0, of: deliver) ?? deliver
        if let seconds { deliver = Date().addingTimeInterval(seconds) }
        let card = Postcard(tripID: trip.id, sent: Date(), deliver: deliver, message: message, design: design)
        save(all.filter { $0.tripID != trip.id } + [card])

        let content = UNMutableNotificationContent()
        content.title = String(localized: "一年前的你寄来一张明信片", bundle: .appLanguage)
        content.body = String(localized: "来自“\(trip.title)”。", bundle: .appLanguage)
        content.sound = .default
        let trigger = UNTimeIntervalNotificationTrigger(timeInterval: max(deliver.timeIntervalSinceNow, 5), repeats: false)
        try? await UNUserNotificationCenter.current().add(UNNotificationRequest(identifier: "postcard.\(card.id)", content: content, trigger: trigger))
        return card
    }

    /// Cards whose day has come, opened the next time the app is in front.
    static func deliverDue() {
        var cards = all
        var changed = false
        for index in cards.indices where !cards[index].delivered && cards[index].deliver <= Date() {
            cards[index].delivered = true
            changed = true
            let card = cards[index]
            Celebrations.shared.add(Celebrations.Item(id: "postcard.\(card.id)", kind: .postcard,
                                                      title: String(localized: "一年前的你寄来一张明信片", bundle: .appLanguage),
                                                      subtitle: card.sent.formatted(.dateTime.year().month().day().locale(appLocale)),
                                                      date: card.sent, code: card.tripID.uuidString, value: card.message))
        }
        if changed { save(cards) }
    }
}

// MARK: - The trip page's card

/// On a finished trip's page: the postcard, small and tilted, inviting a tap.
struct PostcardInvite: View {
    @Environment(\.modelContext) private var context
    let trip: Trip
    let stays: [Stay]
    let chunks: [TrackChunk]
    let assets: [PHAsset]
    @State private var picture: UIImage?
    @State private var open = false

    var body: some View {
        Button { open = true } label: {
            HStack(spacing: 16) {
                ZStack {
                    RoundedRectangle(cornerRadius: 6, style: .continuous)
                        .fill(Color(red: 0.98, green: 0.96, blue: 0.91))
                        .frame(width: 96, height: 64)
                        .rotationEffect(.degrees(6))
                        .shadow(color: .black.opacity(0.12), radius: 3, y: 2)
                    Group {
                        if let picture {
                            Image(uiImage: picture).resizable().scaledToFill()
                        } else {
                            Color(red: 0.9, green: 0.88, blue: 0.84)
                        }
                    }
                    .frame(width: 88, height: 58)
                    .clipShape(.rect(cornerRadius: 3))
                    .padding(4)
                    .background(.white, in: .rect(cornerRadius: 6))
                    .rotationEffect(.degrees(-5))
                    .shadow(color: .black.opacity(0.18), radius: 4, y: 3)
                }
                .frame(width: 110, height: 80)
                VStack(alignment: .leading, spacing: 3) {
                    Text("旅行明信片").font(.headline)
                    Text(PostcardMail.scheduled(for: trip.id) == nil ? "做成一张明信片，分享出去，或寄给一年后的自己。" : "已经寄给一年后的自己。")
                        .font(.subheadline).foregroundStyle(.secondary)
                        .fixedSize(horizontal: false, vertical: true)
                }
                Spacer(minLength: 0)
                Image(systemName: "chevron.right").font(.caption.weight(.semibold)).foregroundStyle(.tertiary)
            }
            .padding(14)
            .background(.background.secondary, in: .rect(cornerRadius: 24, style: .continuous))
        }
        .buttonStyle(PressableStyle())
        // Again when photos are added to the trip, since one of them may now lead.
        .task(id: "\(trip.id)-\(trip.photos?.count ?? 0)") {
            let design = PostcardMail.scheduled(for: trip.id)?.design ?? PostcardDesign.saved(for: trip.id)
            picture = await PostcardContent.picture(trip: trip, chunks: chunks, assets: assets, home: TripSuggestionCard.homeBase(in: context),
                                                    design: design)
        }
        .sheet(isPresented: $open) { PostcardSheet(trip: trip, stays: stays, chunks: chunks, assets: assets) }
        .onChange(of: open) { _, isOpen in
            // Show the card as it was left.
            guard !isOpen else { return }
            Task {
                picture = await PostcardContent.picture(trip: trip, chunks: chunks, assets: assets, home: TripSuggestionCard.homeBase(in: context),
                                                        design: PostcardDesign.saved(for: trip.id))
            }
        }
    }
}

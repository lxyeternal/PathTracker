import SwiftUI
import SwiftData
import Photos
import CoreLocation
import UserNotifications

// MARK: - What goes on a postcard

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
                               postmark: stamp, countryCode: code, sent: Date())
    }

    /// The trip's own photo if it has one, else one from the library, else its route on a map.
    static func picture(trip: Trip, chunks: [TrackChunk], assets: [PHAsset], home: CLLocation? = nil) async -> UIImage? {
        let size = CGSize(width: 900, height: 600)
        if let data = (trip.photos ?? []).sorted(by: { $0.takenAt < $1.takenAt }).first?.imageData, let image = UIImage(data: data) {
            return image
        }
        if let asset = assets.first(where: { $0.mediaType == .image && !$0.mediaSubtypes.contains(.photoScreenshot) }),
           let image = await AssetLoader.image(for: asset, size: size, exact: false) {
            return image
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

// MARK: - The card

/// A postcard that turns over when tapped.
struct PostcardView: View {
    let content: PostcardContent
    @Binding var flipped: Bool
    var recipient: String = String(localized: "一年后的我", bundle: .appLanguage)

    var body: some View {
        ZStack {
            PostcardFront(content: content)
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

private struct PostcardFront: View {
    let content: PostcardContent

    var body: some View {
        GeometryReader { proxy in
            let unit = proxy.size.width / 360
            ZStack(alignment: .bottomLeading) {
                Group {
                    if let image = content.image {
                        Image(uiImage: image).resizable().scaledToFill()
                    } else {
                        LinearGradient(colors: [.orange, .pink, .purple], startPoint: .topLeading, endPoint: .bottomTrailing)
                    }
                }
                .frame(width: proxy.size.width, height: proxy.size.height)
                .clipped()
                LinearGradient(colors: [.clear, .black.opacity(0.55)], startPoint: .center, endPoint: .bottom)
                VStack(alignment: .leading, spacing: -4 * unit) {
                    Text(verbatim: "Greetings from")
                        .font(.custom("SnellRoundhand-Bold", fixedSize: 24 * unit))
                    Text(verbatim: Self.lettering(content.title))
                        .font(Self.latin(content.title) ? .custom("AvenirNextCondensed-Heavy", fixedSize: 52 * unit)
                                                       : .system(size: 46 * unit, weight: .black))
                        .lineLimit(1).minimumScaleFactor(0.4)
                        .shadow(color: .black.opacity(0.35), radius: 0, x: 2 * unit, y: 2 * unit)
                    Text(verbatim: content.subtitle)
                        .font(.system(size: 11 * unit, weight: .semibold))
                        .opacity(0.85)
                        .padding(.top, 8 * unit)
                }
                .foregroundStyle(.white)
                .padding(18 * unit)
            }
            // The white border of a printed card.
            .clipShape(.rect(cornerRadius: 4 * unit))
            .padding(9 * unit)
            .background(Color(red: 0.99, green: 0.98, blue: 0.96))
            .clipShape(.rect(cornerRadius: 10 * unit, style: .continuous))
            .shadow(color: .black.opacity(0.2), radius: 12, y: 6)
        }
    }

    static func latin(_ text: String) -> Bool { text.unicodeScalars.allSatisfy { $0.value < 0x0250 || $0 == " " } }
    static func lettering(_ text: String) -> String { latin(text) ? text.uppercased() : text }
}

private struct PostcardBack: View {
    let content: PostcardContent
    let recipient: String

    private let ink = Color(red: 0.16, green: 0.2, blue: 0.38)
    private let line = Color(red: 0.8, green: 0.76, blue: 0.68)

    var body: some View {
        GeometryReader { proxy in
            let unit = proxy.size.width / 360
            ZStack(alignment: .topLeading) {
                Color(red: 0.98, green: 0.96, blue: 0.91)
                HStack(spacing: 0) {
                    // The message side.
                    VStack(alignment: .leading, spacing: 8 * unit) {
                        Text(verbatim: content.message)
                            .font(.system(size: 12.5 * unit, weight: .regular, design: .serif))
                            .foregroundStyle(ink)
                            .lineSpacing(5 * unit)
                            .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
                        Text(verbatim: "— \(AppInfo.name) · \(content.sent.formatted(.dateTime.year().month().day().locale(appLocale)))")
                            .font(.system(size: 9 * unit, weight: .medium))
                            .foregroundStyle(ink.opacity(0.6))
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
                                .font(.system(size: 14 * unit, weight: .medium, design: .serif))
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

/// The postcard for a trip: turn it over, write on it, share it, or send it to yourself a year
/// from now.
struct PostcardSheet: View {
    let trip: Trip
    let stays: [Stay]
    let chunks: [TrackChunk]
    let assets: [PHAsset]

    @Environment(\.dismiss) private var dismiss
    @Environment(\.modelContext) private var context
    @State private var content: PostcardContent?
    @State private var flipped = false
    @State private var message = ""
    @State private var sending = false
    @State private var sent: Postcard?
    @State private var share: Image?
    @FocusState private var writing: Bool

    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(spacing: 22) {
                    if let content {
                        let card = PostcardView(content: withMessage(content), flipped: $flipped)
                            .padding(.horizontal, 20)
                        card
                            .scaleEffect(sending ? 0.35 : 1)
                            .rotationEffect(.degrees(sending ? -10 : 0))
                            .offset(y: sending ? -700 : 0)
                            .opacity(sending ? 0 : 1)
                        Label(flipped ? "轻点翻回正面" : "轻点翻到背面", systemImage: "hand.tap")
                            .font(.footnote).foregroundStyle(.secondary)
                            .contentTransition(.opacity)
                    } else {
                        ProgressView().frame(height: 240)
                    }

                    VStack(alignment: .leading, spacing: 8) {
                        Text("写在背面").font(.headline)
                        TextField("写几句话", text: $message, axis: .vertical)
                            .lineLimit(3...6)
                            .focused($writing)
                            .padding(12)
                            .background(.background.secondary, in: .rect(cornerRadius: 16, style: .continuous))
                            .onChange(of: writing) { _, isWriting in if isWriting { flipped = true } }
                    }
                    .padding(.horizontal, 20)

                    if let sent {
                        Label("已寄出，\(sent.deliver.formatted(.dateTime.year().month().day().locale(appLocale)))送达", systemImage: "envelope.badge.fill")
                            .font(.subheadline.weight(.semibold))
                            .foregroundStyle(.orange)
                            .transition(.scale.combined(with: .opacity))
                    }

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
                .padding(.vertical, 16)
            }
            .scrollDismissesKeyboard(.interactively)
            .navigationTitle("旅行明信片")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("关闭", systemImage: "xmark") { dismiss() }
                }
            }
            .task {
                sent = PostcardMail.scheduled(for: trip.id)
                var made = PostcardContent.make(trip: trip, stays: stays, chunks: chunks, home: TripSuggestionCard.homeBase(in: context))
                message = sent?.message ?? made.message
                withAnimation(.smooth) { content = made }
                made.image = await PostcardContent.picture(trip: trip, chunks: chunks, assets: assets, home: TripSuggestionCard.homeBase(in: context))
                withAnimation(.smooth) { content = made }
                renderShare()
            }
            .onChange(of: message) { renderShare() }
        }
    }

    private func withMessage(_ content: PostcardContent) -> PostcardContent {
        var copy = content
        copy.message = message
        return copy
    }

    private func renderShare() {
        guard let content else { return }
        share = PostcardImage.render(withMessage(content))
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
            let card = await PostcardMail.send(trip: trip, message: message, after: seconds)
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
    static func send(trip: Trip, message: String, after seconds: TimeInterval? = nil) async -> Postcard {
        let calendar = Calendar.current
        var deliver = calendar.date(byAdding: .year, value: 1, to: Date()) ?? Date()
        deliver = calendar.date(bySettingHour: 10, minute: 0, second: 0, of: deliver) ?? deliver
        if let seconds { deliver = Date().addingTimeInterval(seconds) }
        let card = Postcard(tripID: trip.id, sent: Date(), deliver: deliver, message: message)
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
                            LinearGradient(colors: [.orange, .pink], startPoint: .topLeading, endPoint: .bottomTrailing)
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
        .task(id: trip.id) {
            picture = await PostcardContent.picture(trip: trip, chunks: chunks, assets: assets, home: TripSuggestionCard.homeBase(in: context))
        }
        .sheet(isPresented: $open) { PostcardSheet(trip: trip, stays: stays, chunks: chunks, assets: assets) }
    }
}

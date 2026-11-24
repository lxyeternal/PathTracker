import SwiftUI
import Photos

/// The day as a story: each place a card, and between them the way you went, drawn as a line in
/// the colour of how you travelled with a small map of the route.
struct TimelineList: View {
    let entries: [TimelineEntry]
    var day: Date = Date()
    /// The entries come latest first, so what's above a move is where it ended.
    var newestFirst = false
    var onSelect: (Stay) -> Void
    var onSelectMove: (MoveSelection) -> Void = { _ in }

    var body: some View {
        VStack(spacing: 0) {
            ForEach(Array(entries.enumerated()), id: \.element.id) { index, entry in
                switch entry {
                case .stay(let stay, let rest):
                    if index > 0, case .stay = entries[index - 1] { GapConnector() }
                    // Not a Button: the photos inside the card take their own taps.
                    StayRow(stay: stay, rest: rest, showsCity: stay.city != neighbourStay(before: index)?.city,
                            day: day, isFirst: index == 0, isLast: index == entries.count - 1)
                        .onTapGesture { onSelect(stay) }
                        .accessibilityAddTraits(.isButton)
                        .accessibilityAction { onSelect(stay) }
                        .transition(.opacity.combined(with: .move(edge: .bottom)))
                case .move(let move):
                    Button {
                        let above = neighbourStay(before: index), below = neighbourStay(after: index)
                        onSelectMove(MoveSelection(move: move, from: newestFirst ? below : above, to: newestFirst ? above : below))
                    } label: {
                        MoveRow(move: move, isFirst: index == 0, isLast: index == entries.count - 1)
                    }
                    .buttonStyle(PressableStyle())
                }
            }
        }
        .animation(.smooth, value: entries.map(\.id))
    }

    private func neighbourStay(before index: Int) -> Stay? {
        entries[..<index].reversed().lazy.compactMap { if case .stay(let s, _) = $0 { s } else { nil } }.first
    }

    private func neighbourStay(after index: Int) -> Stay? {
        entries[(index + 1)...].lazy.compactMap { if case .stay(let s, _) = $0 { s } else { nil } }.first
    }
}

/// The day's spine: times on the left, a fine line with each place as a node on it, and the
/// cards to its right.
private enum Rail {
    static let times: CGFloat = 46
    /// Room between the times and the line, so a time never touches a node.
    static let afterTimes: CGFloat = 6
    /// Wide enough that a node and the ring around the place you're at stay inside it.
    static let width: CGFloat = 44
    /// Between the line and the cards.
    static let beforeCard: CGFloat = 8
    static let node: CGFloat = 26
    /// Where a node sits: level with the card's first line.
    static let nodeTop: CGFloat = 13
    static let line = Color.secondary.opacity(0.22)
}

/// The fine line through a row, fading out where the day starts and ends.
private struct RailLine: View {
    var color: Color = Rail.line
    var width: CGFloat = 2
    var dashed = false
    var fadesIn = false
    var fadesOut = false

    var body: some View {
        GeometryReader { proxy in
            Path { $0.move(to: CGPoint(x: proxy.size.width / 2, y: 0)); $0.addLine(to: CGPoint(x: proxy.size.width / 2, y: proxy.size.height)) }
                .stroke(color, style: StrokeStyle(lineWidth: width, lineCap: .round, dash: dashed ? [2, 5] : []))
                .mask {
                    LinearGradient(stops: [.init(color: fadesIn ? .clear : .black, location: 0), .init(color: .black, location: fadesIn ? 0.35 : 0),
                                           .init(color: .black, location: fadesOut ? 0.65 : 1), .init(color: fadesOut ? .clear : .black, location: 1)],
                                   startPoint: .top, endPoint: .bottom)
                }
        }
        .frame(width: Rail.width)
    }
}

// MARK: - Places

private struct StayRow: View {
    let stay: Stay
    /// Later stays of the same visit; the visit ends when the last of them does.
    var rest: [Stay] = []
    /// Only where the day reaches another city: a day in Shanghai says "上海" once.
    var showsCity = true
    let day: Date
    let isFirst: Bool
    let isLast: Bool
    @Environment(\.dynamicTypeSize) private var typeSize
    @State private var libraryPhotos: [PHAsset] = []
    @State private var viewingAsset: AssetPagerStart?
    @State private var viewingPhoto: TripPhoto?

    private var departure: Date? { (rest.last ?? stay).departure }
    private var isHere: Bool { departure == nil }
    private var duration: TimeInterval { (departure ?? Date()).timeIntervalSince(stay.arrival) }
    private var posted: [TripPhoto] { ([stay] + rest).flatMap { $0.photos ?? [] }.sorted { $0.takenAt < $1.takenAt } }
    private var notes: [String] { ([stay] + rest).compactMap { $0.note?.nilIfEmpty } }

    var body: some View {
        HStack(alignment: .top, spacing: 0) {
            times
            ZStack(alignment: .top) {
                RailLine(fadesIn: isFirst, fadesOut: isLast && !isHere)
                node.padding(.top, Rail.nodeTop - (Rail.node - 22) / 2)
            }
            .padding(.leading, Rail.afterTimes)
            card
                .padding(.leading, Rail.beforeCard)
                .padding(.bottom, 10)
        }
        .foregroundStyle(.primary)
        .task(id: "\(stay.arrival.timeIntervalSince1970)-\(departure?.timeIntervalSince1970 ?? 0)") {
            libraryPhotos = DayPhotos.assets(in: DateInterval(start: stay.arrival, end: max(departure ?? Date(), stay.arrival)), near: stay.location)
        }
        .accessibilityElement(children: .combine)
    }

    /// When it began, large; when it ended, quietly beneath; another day's time with its date.
    private var times: some View {
        let zone = stay.localTimeZone
        return VStack(alignment: .trailing, spacing: 1) {
            Text(Self.clock(stay.arrival, zone: zone))
                .font(.subheadline.weight(.semibold))
            if let date = otherDay(stay.arrival) {
                Text(date).font(.caption2).foregroundStyle(.tertiary)
            }
            if let departure {
                Text(Self.clock(departure, zone: zone))
                    .font(.caption)
                    .foregroundStyle(.secondary)
                    .padding(.top, 2)
                if let date = otherDay(departure) {
                    Text(date).font(.caption2).foregroundStyle(.tertiary)
                }
            }
        }
        .monospacedDigit()
        .lineLimit(1)
        .minimumScaleFactor(0.8)
        .frame(width: Rail.times, alignment: .trailing)
        .padding(.top, Rail.nodeTop)
    }

    /// 24-hour in the margin: "14:37" reads at a glance and lines up, where "下午 2:37" crowds it.
    private static func clock(_ date: Date, zone: TimeZone?) -> String {
        date.formatted(.verbatim("\(hour: .twoDigits(clock: .twentyFourHour, hourCycle: .zeroBased)):\(minute: .twoDigits)",
                                 timeZone: zone ?? .current, calendar: .current))
    }

    private func otherDay(_ date: Date) -> String? {
        Calendar.current.isDate(date, inSameDayAs: day) ? nil
            : date.formatted(Date.FormatStyle(locale: appLocale, timeZone: stay.localTimeZone ?? .current).month(.defaultDigits).day())
    }

    /// The place on the line: its icon, ringed in the page's colour so the line seems to pass behind.
    private var node: some View {
        PlaceIcon(category: stay.category, isLandmark: stay.isLandmark, size: Rail.node)
            .padding(3)
            .background(Circle().fill(Color(.systemBackground)))
            .overlay {
                if isHere { NowRing(color: stay.category.tint) }
            }
            .overlay(alignment: .bottomTrailing) {
                if stay.isFromPhotos {
                    Image(systemName: "photo.fill")
                        .font(.system(size: 7, weight: .bold))
                        .foregroundStyle(.white)
                        .frame(width: 14, height: 14)
                        .background(Circle().fill(Color.pink.gradient))
                        .overlay(Circle().stroke(Color(.systemBackground), lineWidth: 1.5))
                        .offset(x: 2, y: 2)
                        .accessibilityLabel("来自照片")
                }
            }
    }

    private var card: some View {
        VStack(alignment: .leading, spacing: 10) {
            // Two lines: the place and how long; then what kind of place it is and, when the day
            // has moved to another city, which.
            VStack(alignment: .leading, spacing: 3) {
                HStack(alignment: .firstTextBaseline, spacing: 6) {
                    Text(stay.displayName)
                        .font(.headline)
                        .lineLimit(typeSize.isAccessibilitySize ? 3 : 1)
                    if stay.isLandmark {
                        Image(systemName: "star.fill").font(.caption2).foregroundStyle(.yellow)
                    }
                    Spacer(minLength: 6)
                    if isHere {
                        HStack(spacing: 5) {
                            PulsingDot(color: tint)
                            Text("现在").font(.caption.weight(.semibold))
                        }
                        .foregroundStyle(tint)
                    } else if stay.tagState != .pending {
                        Text(Format.duration(duration))
                            .font(.footnote)
                            .foregroundStyle(.secondary)
                            .monospacedDigit()
                            .fixedSize()
                    }
                }
                if let meta { meta.font(.footnote).lineLimit(1) }
            }
            ForEach(notes, id: \.self) { note in
                Text(note)
                    .font(.subheadline)
                    .foregroundStyle(.primary.opacity(0.85))
                    .lineLimit(4)
                    .frame(maxWidth: .infinity, alignment: .leading)
            }
            if !posted.isEmpty || !libraryPhotos.isEmpty { photos }
        }
        .padding(.horizontal, 14)
        .padding(.vertical, 11)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background {
            RoundedRectangle(cornerRadius: 18, style: .continuous)
                .fill(.background.secondary)
                // A breath of the place's colour, so a day reads by what kind of places it had.
                .overlay(RoundedRectangle(cornerRadius: 18, style: .continuous).fill(tint.opacity(0.06)))
                .overlay {
                    if isHere {
                        RoundedRectangle(cornerRadius: 18, style: .continuous)
                            .strokeBorder(tint.opacity(0.35), lineWidth: 1)
                    }
                }
        }
        .clipShape(.rect(cornerRadius: 18, style: .continuous))
        .contentShape(.rect(cornerRadius: 18, style: .continuous))
    }

    private var tint: Color { stay.isLandmark ? PlaceCategory.landmark.tint : stay.category.tint }

    /// "景点", "学校": left out when the name already says it.
    private var kind: String? {
        let label = stay.isLandmark ? PlaceCategory.landmark.label : stay.category.label
        return label == stay.displayName ? nil : label
    }

    /// "学校 · 上海": the kind in its colour, then whatever else is worth saying, quietly.
    private var meta: Text? {
        if stay.tagState == .pending { return Text("正在识别地点…").foregroundStyle(.secondary) }
        var rest: [String] = []
        if showsCity, let city = stay.city { rest.append(city) }
        if isHere { rest.append(String(localized: "已停留 \(Format.duration(duration))", bundle: .appLanguage)) }
        if stay.localTimeZone != nil { rest.append(String(localized: "当地时间", bundle: .appLanguage)) }
        let tail = rest.joined(separator: " · ")
        switch (kind, tail.isEmpty) {
        case (nil, true): return nil
        case (nil, false): return Text(tail).foregroundStyle(.secondary)
        case (let kind?, true): return Text(kind).fontWeight(.medium).foregroundStyle(tint)
        case (let kind?, false):
            return Text("\(Text(kind).fontWeight(.medium).foregroundStyle(tint))\(Text(verbatim: " · \(tail)").foregroundStyle(.secondary))")
        }
    }

    /// Posted photos, else the ones taken here, as a filmstrip.
    private var photos: some View {
        ScrollView(.horizontal) {
            HStack(spacing: 6) {
                if posted.isEmpty {
                    ForEach(libraryPhotos.prefix(10), id: \.localIdentifier) { asset in
                        Button { viewingAsset = AssetPagerStart(id: asset.localIdentifier) } label: { AssetThumbnail(asset: asset, side: 64) }
                            .buttonStyle(PressableStyle())
                    }
                } else {
                    ForEach(posted.prefix(10)) { photo in
                        Button { viewingPhoto = photo } label: {
                            PhotoThumbnail(photo: photo, cornerRadius: 12).frame(width: 64, height: 64)
                        }
                        .buttonStyle(PressableStyle())
                    }
                }
            }
        }
        .scrollIndicators(.hidden)
        .keepsDaySwipe()
        // The strip runs to the card's edges and stops there: photos scrolled past them used
        // to slide out over the times in the margin.
        .contentMargins(.horizontal, 16, for: .scrollContent)
        .padding(.horizontal, -16)
        .fullScreenCover(item: $viewingAsset) { AssetPager(assets: libraryPhotos, selection: $0.id) }
        .fullScreenCover(item: $viewingPhoto) { PhotoPager(photos: posted, selection: $0.id) }
    }
}

// MARK: - The way between

/// The way between two places, kept light: the line takes the colour of how you went, and a
/// single line of text says how far and how long, with the route traced beside it.
private struct MoveRow: View {
    let move: Move
    let isFirst: Bool
    let isLast: Bool

    var body: some View {
        HStack(spacing: 0) {
            Color.clear.frame(width: Rail.times + Rail.afterTimes)
            RailLine(color: move.mode.color.opacity(0.75), width: 3, dashed: move.mode == .subway, fadesIn: isFirst, fadesOut: isLast)
            HStack(spacing: 8) {
                Image(systemName: move.mode.symbol)
                    .font(.caption.weight(.bold))
                    .foregroundStyle(move.mode.color)
                    .frame(width: 24, height: 24)
                    .background(move.mode.color.opacity(0.12), in: .circle)
                Text(move.mode.title)
                    .font(.footnote.weight(.semibold))
                    .fixedSize()
                Text("\(Format.distance(move.distance)) · \(Format.duration(move.duration))")
                    .font(.footnote)
                    .foregroundStyle(.secondary)
                    .monospacedDigit()
                    .lineLimit(1)
                    .minimumScaleFactor(0.75)
                    .layoutPriority(1)
                Spacer(minLength: 4)
                // The route's shape says it can be opened; no chevron, like the cards.
                RouteSketch(lines: lines, tint: move.mode.color, bare: true)
                    .frame(width: 44, height: 30)
            }
            // Lined up with the cards' text.
            .padding(.leading, Rail.beforeCard + 12)
            .padding(.trailing, 14)
            .padding(.vertical, 10)
        }
        .frame(minHeight: 52)
        .contentShape(.rect)
        .foregroundStyle(.primary)
        .accessibilityElement(children: .combine)
    }

    private var lines: [RouteImage.Line] {
        move.chunks.map { RouteImage.Line(coordinates: $0.points.simplified(tolerance: 8).map(\.coordinate), color: $0.mode.color) }
    }
}

/// Between two places with no recorded travel: the line continues, dotted.
private struct GapConnector: View {
    var body: some View {
        HStack(spacing: 0) {
            Color.clear.frame(width: Rail.times + Rail.afterTimes)
            RailLine(dashed: true)
            Spacer()
        }
        .frame(height: 14)
    }
}

/// A soft ring breathing around the place you're at now.
private struct NowRing: View {
    let color: Color
    @State private var breathe = false

    var body: some View {
        Circle()
            .stroke(color.opacity(breathe ? 0 : 0.55), lineWidth: 2)
            // Stays within the rail: it never reaches the card or the times.
            .scaleEffect(breathe ? 1.3 : 1)
            .onAppear { withAnimation(.easeOut(duration: 1.8).repeatForever(autoreverses: false)) { breathe = true } }
            .allowsHitTesting(false)
    }
}

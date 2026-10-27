import SwiftUI
import Photos

/// The day as a story: each place a card, and between them the way you went, drawn as a line in
/// the colour of how you travelled with a small map of the route.
struct TimelineList: View {
    let entries: [TimelineEntry]
    var day: Date = Date()
    var onSelect: (Stay) -> Void
    var onSelectMove: (MoveSelection) -> Void = { _ in }

    var body: some View {
        VStack(spacing: 0) {
            ForEach(Array(entries.enumerated()), id: \.element.id) { index, entry in
                switch entry {
                case .stay(let stay):
                    if index > 0, case .stay = entries[index - 1] { GapConnector() }
                    Button { onSelect(stay) } label: { StayCard(stay: stay, day: day) }
                        .buttonStyle(PressableStyle())
                        .transition(.opacity.combined(with: .move(edge: .bottom)))
                case .move(let move):
                    Button {
                        onSelectMove(MoveSelection(move: move, from: neighbourStay(before: index), to: neighbourStay(after: index)))
                    } label: {
                        MoveConnector(move: move, isFirst: index == 0, isLast: index == entries.count - 1)
                    }
                    .buttonStyle(PressableStyle())
                }
            }
        }
        .animation(.smooth, value: entries.map(\.id))
    }

    private func neighbourStay(before index: Int) -> Stay? {
        entries[..<index].reversed().lazy.compactMap { if case .stay(let s) = $0 { s } else { nil } }.first
    }

    private func neighbourStay(after index: Int) -> Stay? {
        entries[(index + 1)...].lazy.compactMap { if case .stay(let s) = $0 { s } else { nil } }.first
    }
}

/// Where the connecting line runs: under the centre of each card's icon.
private enum Rail {
    static let cardPadding: CGFloat = 14
    static let icon: CGFloat = 42
    static var x: CGFloat { cardPadding + icon / 2 }
}

// MARK: - Places

private struct StayCard: View {
    let stay: Stay
    let day: Date
    @Environment(\.dynamicTypeSize) private var typeSize
    @State private var libraryPhotos: [PHAsset] = []

    private var isHere: Bool { stay.departure == nil }
    private var posted: [TripPhoto] { (stay.photos ?? []).sorted { $0.takenAt < $1.takenAt } }

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack(alignment: .center, spacing: 12) {
                PlaceIcon(category: stay.category, isLandmark: stay.isLandmark, size: Rail.icon)
                    .overlay {
                        if isHere {
                            Circle().stroke(stay.category.tint.opacity(0.5), lineWidth: 2).padding(-4)
                        }
                    }
                    .overlay(alignment: .bottomTrailing) {
                        if stay.isFromPhotos {
                            Image(systemName: "photo.fill")
                                .font(.system(size: 9, weight: .bold))
                                .foregroundStyle(.white)
                                .frame(width: 18, height: 18)
                                .background(Circle().fill(Color.pink.gradient))
                                .overlay(Circle().stroke(Color(.secondarySystemBackground), lineWidth: 2))
                                .offset(x: 3, y: 3)
                                .accessibilityLabel("来自照片")
                        }
                    }
                VStack(alignment: .leading, spacing: 3) {
                    HStack(spacing: 5) {
                        Text(stay.displayName)
                            .font(.body.weight(.semibold))
                            .lineLimit(typeSize.isAccessibilitySize ? 3 : 1)
                        if stay.isLandmark {
                            Image(systemName: "star.fill").font(.caption2).foregroundStyle(.yellow)
                        }
                    }
                    Text(detail)
                        .font(.subheadline)
                        .foregroundStyle(.secondary)
                        .lineLimit(2)
                }
                Spacer(minLength: 6)
                durationChip
            }

            if let note = stay.note, !note.isEmpty {
                Text(note)
                    .font(.subheadline)
                    .foregroundStyle(.primary.opacity(0.85))
                    .lineLimit(4)
                    .frame(maxWidth: .infinity, alignment: .leading)
            }
            if !posted.isEmpty || !libraryPhotos.isEmpty { photos }
        }
        .padding(Rail.cardPadding)
        .background {
            RoundedRectangle(cornerRadius: 22, style: .continuous)
                .fill(.background.secondary)
                .overlay {
                    if isHere {
                        RoundedRectangle(cornerRadius: 22, style: .continuous)
                            .strokeBorder(stay.category.tint.opacity(0.45), lineWidth: 1.5)
                    }
                }
        }
        .contentShape(.rect(cornerRadius: 22, style: .continuous))
        .foregroundStyle(.primary)
        .task(id: "\(stay.arrival.timeIntervalSince1970)-\(stay.departure?.timeIntervalSince1970 ?? 0)") {
            libraryPhotos = DayPhotos.assets(in: DayPhotos.interval(of: stay))
        }
        .accessibilityElement(children: .combine)
    }

    @ViewBuilder
    private var durationChip: some View {
        if isHere {
            HStack(spacing: 5) {
                PulsingDot(color: stay.category.tint)
                Text("现在").font(.caption.weight(.bold))
            }
            .foregroundStyle(stay.category.tint)
            .padding(.horizontal, 9).padding(.vertical, 5)
            .background(stay.category.tint.opacity(0.12), in: .capsule)
        } else {
            Text(Format.duration(stay.duration))
                .font(.caption.weight(.semibold).monospacedDigit())
                .foregroundStyle(.secondary)
                .padding(.horizontal, 9).padding(.vertical, 5)
                .background(Color.secondary.opacity(0.1), in: .capsule)
        }
    }

    /// "11:19 – 14:37 · 上海"
    private var detail: String {
        func label(_ date: Date) -> String {
            Calendar.current.isDate(date, inSameDayAs: day)
                ? Format.time(date)
                : date.formatted(.dateTime.month().day().hour().minute().locale(appLocale))
        }
        let end = stay.departure.map(label) ?? String(localized: "现在", bundle: .appLanguage)
        let times = "\(label(stay.arrival)) – \(end)"
        if stay.tagState == .pending { return times + " · " + String(localized: "正在识别地点…", bundle: .appLanguage) }
        return [times, stay.city].compactMap { $0 }.joined(separator: " · ")
    }

    /// Posted photos, else the ones taken here, as a filmstrip.
    private var photos: some View {
        ScrollView(.horizontal) {
            HStack(spacing: 6) {
                if posted.isEmpty {
                    ForEach(libraryPhotos.prefix(10), id: \.localIdentifier) { AssetThumbnail(asset: $0, side: 76) }
                } else {
                    ForEach(posted.prefix(10)) { PhotoThumbnail(photo: $0, cornerRadius: 14).frame(width: 76, height: 76) }
                }
            }
        }
        .scrollIndicators(.hidden)
        .scrollClipDisabled()
    }
}

// MARK: - The way between

private struct MoveConnector: View {
    let move: Move
    let isFirst: Bool
    let isLast: Bool
    var body: some View {
        HStack(spacing: 0) {
            line
                .frame(width: Rail.x * 2)
            HStack(spacing: 10) {
                Image(systemName: move.mode.symbol)
                    .font(.footnote.weight(.bold))
                    .foregroundStyle(.white)
                    .frame(width: 30, height: 30)
                    .background(Circle().fill(move.mode.color.gradient))
                VStack(alignment: .leading, spacing: 1) {
                    Text(move.mode.title).font(.subheadline.weight(.semibold))
                    Text("\(Format.distance(move.distance)) · \(Format.duration(move.duration))")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                        .monospacedDigit()
                }
                Spacer(minLength: 6)
                thumbnail
            }
            .padding(.vertical, 12)
            .padding(.trailing, 4)
        }
        .frame(minHeight: 78)
        .contentShape(.rect)
        .foregroundStyle(.primary)
        .accessibilityElement(children: .combine)
    }

    /// The route in the travel mode's colour, fading where it meets a card.
    private var line: some View {
        Capsule()
            .fill(LinearGradient(colors: [move.mode.color.opacity(isFirst ? 0 : 0.5), move.mode.color, move.mode.color.opacity(isLast ? 0 : 0.5)],
                                 startPoint: .top, endPoint: .bottom))
            .frame(width: 5)
            .padding(.vertical, 2)
    }

    private var thumbnail: some View {
        RouteSketch(lines: lines, tint: move.mode.color)
            .frame(width: 84, height: 54)
            .clipShape(.rect(cornerRadius: 12, style: .continuous))
            .overlay(RoundedRectangle(cornerRadius: 12, style: .continuous).stroke(move.mode.color.opacity(0.15)))
    }

    private var lines: [RouteImage.Line] {
        move.chunks.map { RouteImage.Line(coordinates: $0.points.simplified(tolerance: 8).map(\.coordinate), color: $0.mode.color) }
    }
}

/// Between two places with no recorded travel: a short dotted line.
private struct GapConnector: View {
    var body: some View {
        HStack(spacing: 0) {
            DotLine()
                .stroke(Color.secondary.opacity(0.35), style: StrokeStyle(lineWidth: 2.5, lineCap: .round, dash: [0.5, 6]))
                .frame(width: Rail.x * 2, height: 22)
            Spacer()
        }
    }

    private struct DotLine: Shape {
        func path(in rect: CGRect) -> Path {
            Path { $0.move(to: CGPoint(x: rect.midX, y: rect.minY)); $0.addLine(to: CGPoint(x: rect.midX, y: rect.maxY)) }
        }
    }
}

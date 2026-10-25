import SwiftUI
import Photos

/// The day as a vertical story on one continuous line: places as stops, the way between them
/// drawn in the colour of how you travelled. Times sit in the margin, like a train timetable.
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
                    Button { onSelect(stay) } label: {
                        StayRow(stay: stay, day: day, isFirst: index == 0, isLast: index == entries.count - 1)
                    }
                    .buttonStyle(TimelineRowStyle())
                case .move(let move):
                    Button {
                        onSelectMove(MoveSelection(move: move, from: neighbourStay(before: index), to: neighbourStay(after: index)))
                    } label: {
                        MoveRow(move: move)
                    }
                    .buttonStyle(TimelineRowStyle())
                }
            }
        }
    }

    private func neighbourStay(before index: Int) -> Stay? {
        entries[..<index].reversed().lazy.compactMap { if case .stay(let s) = $0 { s } else { nil } }.first
    }

    private func neighbourStay(after index: Int) -> Stay? {
        entries[(index + 1)...].lazy.compactMap { if case .stay(let s) = $0 { s } else { nil } }.first
    }
}

/// Rows highlight softly while pressed instead of showing a chevron on every line.
private struct TimelineRowStyle: ButtonStyle {
    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .background(
                RoundedRectangle(cornerRadius: 16, style: .continuous)
                    .fill(Color.primary.opacity(configuration.isPressed ? 0.06 : 0))
            )
            .scaleEffect(configuration.isPressed ? 0.985 : 1)
            .animation(.snappy(duration: 0.18), value: configuration.isPressed)
    }
}

/// Column widths shared by both kinds of row, so the line runs straight.
private enum Rail {
    static let time: CGFloat = 52
    static let node: CGFloat = 40
    static let line: CGFloat = 4
}

private struct StayRow: View {
    let stay: Stay
    let day: Date
    let isFirst: Bool
    let isLast: Bool
    @Environment(\.dynamicTypeSize) private var typeSize
    @State private var libraryPhotos: [PHAsset] = []

    private var posted: [TripPhoto] { (stay.photos ?? []).sorted { $0.takenAt < $1.takenAt } }

    var body: some View {
        HStack(alignment: .top, spacing: 10) {
            timeColumn
            rail
            VStack(alignment: .leading, spacing: 8) {
                VStack(alignment: .leading, spacing: 3) {
                    HStack(spacing: 6) {
                        Text(stay.displayName)
                            .font(.body.weight(.semibold))
                            .lineLimit(typeSize.isAccessibilitySize ? 3 : 1)
                        if stay.isLandmark {
                            Image(systemName: "star.fill").font(.caption2).foregroundStyle(.yellow)
                        }
                    }
                    HStack(spacing: 6) {
                        Text(Format.duration(stay.duration))
                            .font(.caption.weight(.semibold))
                            .foregroundStyle(stay.category.tint)
                            .padding(.horizontal, 7).padding(.vertical, 2)
                            .background(stay.category.tint.opacity(0.12), in: .capsule)
                        if let subtitle = stay.subtitle {
                            Text(subtitle).font(.caption).foregroundStyle(.secondary).lineLimit(1)
                        } else if stay.tagState == .pending {
                            Text("正在识别地点…").font(.caption).foregroundStyle(.tertiary)
                        }
                    }
                }
                if let note = stay.note, !note.isEmpty {
                    Text(note)
                        .font(.subheadline)
                        .foregroundStyle(.primary.opacity(0.85))
                        .lineLimit(3)
                }
                if !posted.isEmpty || !libraryPhotos.isEmpty { photoStrip }
            }
            .padding(.vertical, 10)
            .frame(maxWidth: .infinity, alignment: .leading)
        }
        .padding(.trailing, 8)
        .fixedSize(horizontal: false, vertical: true)
        .contentShape(.rect)
        .task(id: "\(stay.arrival.timeIntervalSince1970)-\(stay.departure?.timeIntervalSince1970 ?? 0)") {
            libraryPhotos = DayPhotos.assets(in: DayPhotos.interval(of: stay))
        }
        .accessibilityElement(children: .combine)
    }

    private var timeColumn: some View {
        VStack(alignment: .trailing, spacing: 2) {
            Text(timeLabel(stay.arrival))
                .font(.caption.weight(.semibold).monospacedDigit())
                .lineLimit(1)
                .fixedSize()
            if !Calendar.current.isDate(stay.arrival, inSameDayAs: day) {
                Text(stay.arrival.formatted(.dateTime.month().day().locale(appLocale)))
                    .font(.caption2).foregroundStyle(.tertiary)
            }
        }
        .foregroundStyle(.secondary)
        .frame(width: Rail.time, alignment: .trailing)
        .padding(.top, 21)
    }

    private var rail: some View {
        ZStack(alignment: .top) {
            VStack(spacing: 0) {
                Rectangle().fill(isFirst ? Color.clear : Color.secondary.opacity(0.25)).frame(width: Rail.line, height: 12)
                Rectangle().fill(isLast ? Color.clear : Color.secondary.opacity(0.25))
                    .frame(width: Rail.line)
                    .frame(maxHeight: .infinity)
            }
            PlaceIcon(category: stay.category, isLandmark: stay.isLandmark, size: Rail.node)
                .overlay(Circle().stroke(Color(.systemBackground), lineWidth: 3))
                .padding(.top, 8)
        }
        .frame(width: Rail.node)
    }

    /// Posted photos first, then ones from the library taken here.
    private var photoStrip: some View {
        ScrollView(.horizontal) {
            HStack(spacing: 6) {
                ForEach(posted.prefix(8)) { photo in
                    PhotoThumbnail(photo: photo, cornerRadius: 12).frame(width: 64, height: 64)
                }
                if posted.isEmpty {
                    ForEach(libraryPhotos.prefix(8), id: \.localIdentifier) { AssetThumbnail(asset: $0, side: 64) }
                }
            }
        }
        .scrollIndicators(.hidden)
        .scrollClipDisabled()
    }

    private func timeLabel(_ date: Date) -> String {
        date.formatted(.dateTime.hour(.twoDigits(amPM: .omitted)).minute(.twoDigits).locale(Locale(identifier: "en_GB")))
    }
}

private struct MoveRow: View {
    let move: Move

    var body: some View {
        HStack(alignment: .center, spacing: 10) {
            Color.clear.frame(width: Rail.time)
            Rectangle()
                .fill(move.mode.color.gradient)
                .frame(width: Rail.line + 1)
                .frame(maxHeight: .infinity)
                .frame(width: Rail.node)
            HStack(spacing: 8) {
                Image(systemName: move.mode.symbol)
                    .font(.caption.weight(.bold))
                    .foregroundStyle(.white)
                    .frame(width: 24, height: 24)
                    .background(Circle().fill(move.mode.color.gradient))
                Text(move.mode.title).font(.footnote.weight(.semibold))
                Text("\(Format.distance(move.distance)) · \(Format.duration(move.duration))")
                    .font(.footnote)
                    .foregroundStyle(.secondary)
                    .monospacedDigit()
            }
            .padding(.vertical, 14)
            Spacer(minLength: 0)
        }
        .fixedSize(horizontal: false, vertical: true)
        .contentShape(.rect)
        .accessibilityElement(children: .combine)
    }
}

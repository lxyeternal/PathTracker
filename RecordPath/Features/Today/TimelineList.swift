import SwiftUI
import Photos

/// The day as a vertical story: places you stayed, joined by how you got between them.
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
                        StayRow(stay: stay, day: day)
                    }
                    .buttonStyle(.plain)
                case .move(let move):
                    Button {
                        onSelectMove(MoveSelection(move: move, from: neighbourStay(before: index), to: neighbourStay(after: index)))
                    } label: {
                        MoveRow(move: move)
                    }
                    .buttonStyle(.plain)
                }
            }
        }
        .padding(.vertical, 6)
        .background(.background.secondary, in: .rect(cornerRadius: 24, style: .continuous))
    }

    private func neighbourStay(before index: Int) -> Stay? {
        entries[..<index].reversed().lazy.compactMap { if case .stay(let s) = $0 { s } else { nil } }.first
    }

    private func neighbourStay(after index: Int) -> Stay? {
        entries[(index + 1)...].lazy.compactMap { if case .stay(let s) = $0 { s } else { nil } }.first
    }
}

private struct StayRow: View {
    let stay: Stay
    let day: Date
    @Environment(\.dynamicTypeSize) private var typeSize
    @State private var photos: [PHAsset] = []

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            mainRow
            if !photos.isEmpty { photoStrip }
        }
        .padding(.horizontal, 16)
        .padding(.vertical, 12)
        .contentShape(.rect)
        .task(id: "\(stay.arrival.timeIntervalSince1970)-\(stay.departure?.timeIntervalSince1970 ?? 0)") {
            photos = DayPhotos.assets(in: DayPhotos.interval(of: stay))
        }
    }

    /// The first few photos taken here, lined up under the place's name.
    private var photoStrip: some View {
        HStack(spacing: 6) {
            ForEach(photos.prefix(4), id: \.localIdentifier) { AssetThumbnail(asset: $0, side: 48) }
            if photos.count > 4 {
                Text("+\(photos.count - 4)")
                    .font(.footnote.weight(.semibold))
                    .foregroundStyle(.secondary)
                    .frame(width: 48, height: 48)
                    .background(.background.tertiary, in: .rect(cornerRadius: 9, style: .continuous))
            }
        }
        .padding(.leading, 52)
    }

    private var mainRow: some View {
        HStack(spacing: 14) {
            PlaceIcon(category: stay.category, isLandmark: stay.isLandmark)
            VStack(alignment: .leading, spacing: 3) {
                HStack(spacing: 6) {
                    Text(stay.displayName)
                        .font(.body.weight(.semibold))
                        .lineLimit(typeSize.isAccessibilitySize ? 3 : 1)
                    if stay.isLandmark {
                        Image(systemName: "star.fill").font(.caption).foregroundStyle(.yellow)
                    }
                }
                Text(timeRange)
                    .font(.subheadline)
                    .foregroundStyle(.secondary)
                if typeSize.isAccessibilitySize {
                    Text(Format.duration(stay.duration))
                        .font(.subheadline)
                        .foregroundStyle(.secondary)
                }
                if let subtitle = stay.subtitle {
                    Text(subtitle).font(.caption).foregroundStyle(.tertiary)
                } else if stay.tagState == .pending {
                    Text("正在识别地点…").font(.caption).foregroundStyle(.tertiary)
                }
            }
            Spacer(minLength: 8)
            if !typeSize.isAccessibilitySize {
                Text(Format.duration(stay.duration))
                    .font(.subheadline.monospacedDigit())
                    .foregroundStyle(.secondary)
            }
            Image(systemName: "chevron.right")
                .font(.caption.weight(.semibold))
                .foregroundStyle(.tertiary)
        }
    }

    /// Times on the day being viewed show just the time; anything on another day gets its date.
    private var timeRange: String {
        func label(_ date: Date) -> String {
            Calendar.current.isDate(date, inSameDayAs: day)
                ? Format.time(date)
                : date.formatted(.dateTime.month().day().hour().minute().locale(appLocale))
        }
        let end = stay.departure.map(label) ?? String(localized: "现在", bundle: .appLanguage)
        return "\(label(stay.arrival)) – \(end)"
    }
}

private struct MoveRow: View {
    let move: Move

    var body: some View {
        HStack(spacing: 14) {
            ZStack {
                Capsule()
                    .fill(move.mode.color.opacity(0.35))
                    .frame(width: 4)
                    .frame(maxHeight: .infinity)
            }
            .frame(width: 36)

            Label {
                Text("\(move.mode.title) · \(Format.distance(move.distance)) · \(Format.duration(move.duration))")
            } icon: {
                Image(systemName: move.mode.symbol).foregroundStyle(move.mode.color)
            }
            .font(.footnote.weight(.medium))
            .foregroundStyle(.secondary)
            Spacer()
            Image(systemName: "chevron.right")
                .font(.caption2.weight(.semibold))
                .foregroundStyle(.quaternary)
        }
        .contentShape(.rect)
        .frame(minHeight: 40)
        .padding(.horizontal, 16)
        .accessibilityElement(children: .combine)
    }
}

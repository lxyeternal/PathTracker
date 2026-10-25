import SwiftUI

extension MovementMode {
    var color: Color {
        switch self {
        case .walking: .green
        case .running: .orange
        case .cycling: .teal
        case .automotive: .blue
        case .flying: .purple
        case .unknown: .gray
        }
    }
}

/// A rounded, grouped card in the style of Health and Fitness summaries.
struct Card<Content: View>: View {
    var padding: CGFloat = 16
    @ViewBuilder var content: Content

    var body: some View {
        content
            .padding(padding)
            .frame(maxWidth: .infinity, alignment: .leading)
            .background(.background.secondary, in: .rect(cornerRadius: 24, style: .continuous))
    }
}

struct SectionHeader: View {
    let title: LocalizedStringKey
    var trailing: LocalizedStringKey?

    var body: some View {
        HStack(alignment: .firstTextBaseline) {
            Text(title).font(.title3.bold())
            Spacer()
            if let trailing {
                Text(trailing).font(.subheadline).foregroundStyle(.secondary)
            }
        }
        .padding(.horizontal, 4)
        .padding(.top, 8)
    }
}

/// Metrics in one card, two to a row, divided by hairlines rather than boxed one by one.
/// One column at accessibility text sizes.
struct MetricGrid<Content: View>: View {
    @ViewBuilder var content: Content
    @Environment(\.dynamicTypeSize) private var typeSize

    var body: some View {
        Group(subviews: content) { subviews in
            let columns = typeSize.isAccessibilitySize ? 1 : 2
            let items = Array(subviews)
            let rows = stride(from: 0, to: items.count, by: columns).map { Array(items[$0..<min($0 + columns, items.count)]) }
            VStack(spacing: 0) {
                ForEach(rows.indices, id: \.self) { row in
                    if row > 0 { Divider().padding(.horizontal, 16) }
                    HStack(spacing: 0) {
                        ForEach(rows[row].indices, id: \.self) { column in
                            if column > 0 { Divider().padding(.vertical, 14) }
                            rows[row][column].frame(maxWidth: .infinity, alignment: .leading)
                        }
                        if rows[row].count < columns {
                            Divider().padding(.vertical, 14)
                            Color.clear.frame(maxWidth: .infinity)
                        }
                    }
                    .fixedSize(horizontal: false, vertical: true)
                }
            }
            .background(.background.secondary, in: .rect(cornerRadius: 24, style: .continuous))
        }
    }
}

struct MetricTile: View {
    let title: LocalizedStringKey
    let value: String
    let symbol: String
    let tint: Color

    var body: some View {
        VStack(alignment: .leading, spacing: 4) {
            HStack(spacing: 5) {
                Image(systemName: symbol)
                    .font(.caption.weight(.bold))
                    .foregroundStyle(tint)
                Text(title)
                    .font(.footnote.weight(.medium))
                    .foregroundStyle(.secondary)
                    .lineLimit(1)
            }
            Text(value)
                .font(.system(.title2, design: .rounded, weight: .semibold))
                .contentTransition(.numericText())
                .lineLimit(1)
                .minimumScaleFactor(0.6)
        }
        .padding(.horizontal, 16)
        .padding(.vertical, 14)
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
        .accessibilityElement(children: .combine)
    }
}

/// Round category badge used for places on lists and maps.
struct PlaceIcon: View {
    let category: PlaceCategory
    var isLandmark = false
    var size: CGFloat = 36

    var body: some View {
        Image(systemName: isLandmark ? "star.fill" : category.symbol)
            .font(.system(size: size * 0.42, weight: .semibold))
            .foregroundStyle(.white)
            .frame(width: size, height: size)
            .background(Circle().fill((isLandmark ? Color.yellow : category.tint).gradient))
    }
}

/// Small pulsing dot for "recording now".
struct PulsingDot: View {
    var color: Color = .green
    @State private var animate = false

    var body: some View {
        Circle()
            .fill(color)
            .frame(width: 8, height: 8)
            .background(
                Circle()
                    .fill(color.opacity(0.4))
                    .scaleEffect(animate ? 2.6 : 1)
                    .opacity(animate ? 0 : 1)
            )
            .onAppear {
                withAnimation(.easeOut(duration: 1.4).repeatForever(autoreverses: false)) { animate = true }
            }
    }
}

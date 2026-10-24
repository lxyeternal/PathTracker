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

/// Two columns of metric tiles, or one column at accessibility text sizes.
struct MetricGrid<Content: View>: View {
    @ViewBuilder var content: Content
    @Environment(\.dynamicTypeSize) private var typeSize

    var body: some View {
        let columns = typeSize.isAccessibilitySize ? 1 : 2
        LazyVGrid(columns: Array(repeating: GridItem(.flexible(), spacing: 12), count: columns), spacing: 12) {
            content
        }
    }
}

struct MetricTile: View {
    let title: LocalizedStringKey
    let value: String
    let symbol: String
    let tint: Color
    @ScaledMetric(relativeTo: .title2) private var minHeight: CGFloat = 84

    var body: some View {
        VStack(alignment: .leading, spacing: 6) {
            Label(title, systemImage: symbol)
                .font(.subheadline.weight(.medium))
                .foregroundStyle(tint)
                .labelStyle(.titleAndIcon)
            Text(value)
                .font(.system(.title2, design: .rounded, weight: .semibold))
                .contentTransition(.numericText())
                .lineLimit(1)
                .minimumScaleFactor(0.7)
        }
        .padding(14)
        .frame(maxWidth: .infinity, minHeight: minHeight, alignment: .topLeading)
        .background(.background.secondary, in: .rect(cornerRadius: 20, style: .continuous))
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

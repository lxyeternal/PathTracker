import SwiftUI

/// "过去一年，你是……" as a small travel poster: the archetype's painted scene, its name set
/// large in serif over the bottom, the reason in the person's own numbers.
struct PortraitFace: View {
    let portrait: TravellerPortrait
    var large = false

    var body: some View {
        let archetype = portrait.archetype
        ZStack(alignment: .bottomLeading) {
            PortraitScene(archetype: archetype)
            LinearGradient(stops: [.init(color: .clear, location: 0.35), .init(color: .black.opacity(0.62), location: 1)],
                           startPoint: .top, endPoint: .bottom)
            VStack(alignment: .leading, spacing: large ? 10 : 7) {
                // The portrait covers the past 365 days, not the calendar year.
                Text(verbatim: "\(String(localized: "旅人画像", bundle: .appLanguage)) · \(String(localized: "过去一年", bundle: .appLanguage))")
                    .font(.caption.weight(.semibold))
                    .tracking(2)
                    .opacity(0.85)
                Spacer(minLength: 0)
                Text("过去一年，你是").font(.subheadline.weight(.medium)).opacity(0.85)
                Text(archetype.title)
                    .font(.system(size: large ? 40 : 32, weight: .bold, design: .serif))
                    .minimumScaleFactor(0.7)
                    .lineLimit(1)
                    .shadow(color: .black.opacity(0.25), radius: 8, y: 2)
                Text(portrait.reason)
                    .font(large ? .callout : .footnote)
                    .opacity(0.92)
                    .fixedSize(horizontal: false, vertical: true)
                if !portrait.traits.isEmpty {
                    HStack(spacing: 6) {
                        ForEach(portrait.traits, id: \.self) { trait in
                            Label(trait.title, systemImage: trait.symbol)
                                .font(.caption2.weight(.semibold))
                                .padding(.horizontal, 9).padding(.vertical, 5)
                                // A plain tint: ImageRenderer drops materials from the share image.
                                .background(Color.white.opacity(0.18), in: .capsule)
                        }
                    }
                    .lineLimit(1)
                    .minimumScaleFactor(0.8)
                    .padding(.top, 2)
                }
            }
            .foregroundStyle(.white)
            .padding(large ? 24 : 20)
        }
        .frame(height: large ? 460 : 340)
        .clipShape(.rect(cornerRadius: large ? 32 : 28, style: .continuous))
        .overlay(RoundedRectangle(cornerRadius: large ? 32 : 28, style: .continuous).strokeBorder(.white.opacity(0.12), lineWidth: 1))
    }
}

/// Stands in for the portrait until there's enough of the year to draw one from.
struct PortraitPlaceholderCard: View {
    var body: some View {
        HStack(spacing: 14) {
            Image(systemName: TravellerPortrait.Archetype.explorer.symbol)
                .font(.system(size: 24, weight: .semibold))
                .foregroundStyle(.secondary)
                .frame(width: 56, height: 72)
                .background(RoundedRectangle(cornerRadius: 14, style: .continuous).fill(.background.tertiary))
            VStack(alignment: .leading, spacing: 3) {
                Text("旅人画像").font(.system(.headline, design: .serif)).foregroundStyle(.primary)
                Text("再走一阵子，画像就会出现。").font(.subheadline).foregroundStyle(.secondary)
                    .multilineTextAlignment(.leading)
            }
            Spacer(minLength: 0)
        }
        .padding(14)
        .background(.background.secondary, in: .rect(cornerRadius: 24, style: .continuous))
    }
}

struct PortraitCard: View {
    let portrait: TravellerPortrait
    @State private var showing = false

    var body: some View {
        Button { showing = true } label: { PortraitFace(portrait: portrait) }
            .buttonStyle(PressableStyle())
            .sheet(isPresented: $showing) { PortraitSheet(portrait: portrait) }
    }
}

/// The portrait large, the numbers behind it, and a way to share it.
struct PortraitSheet: View {
    let portrait: TravellerPortrait
    @Environment(\.dismiss) private var dismiss
    @State private var image: Image?
    @State private var appeared = false

    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(alignment: .leading, spacing: 24) {
                    PortraitFace(portrait: portrait, large: true)
                        .scaleEffect(appeared ? 1 : 0.92)
                        .opacity(appeared ? 1 : 0)
                    YearInTiles(portrait: portrait, appeared: appeared)
                    Text("画像根据过去一年的轨迹和地点算出，只在你的手机上计算。")
                        .font(.footnote).foregroundStyle(.secondary)
                }
                .padding()
            }
            .navigationTitle("旅人画像")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("关闭", systemImage: "xmark") { dismiss() }
                }
                if let image {
                    ToolbarItem(placement: .primaryAction) {
                        ShareLink(item: image, preview: SharePreview(portrait.archetype.title, image: image))
                    }
                }
            }
        }
        .onAppear {
            withAnimation(.spring(response: 0.6, dampingFraction: 0.75)) { appeared = true }
            let renderer = ImageRenderer(content: PortraitFace(portrait: portrait, large: true)
                .frame(width: 360)
                .padding(20)
                .background(Color.black)
                .environment(\.locale, appLocale))
            renderer.scale = 3
            image = renderer.uiImage.map { Image(uiImage: $0) }
        }
    }
}

/// "你的过去一年" as a set of tiles: night and dawn as two skies, how you got around as one
/// bar, new places and home as two rings, and the cities and countries as big numbers.
struct YearInTiles: View {
    let portrait: TravellerPortrait
    let appeared: Bool

    private func percent(_ value: Double) -> String { value.formatted(.percent.precision(.fractionLength(0)).locale(appLocale)) }

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            Text("你的过去一年").font(.system(.title3, design: .serif, weight: .bold))
            HStack(spacing: 12) {
                skyTile(title: "夜里九点以后", value: portrait.night, symbol: "moon.stars.fill",
                        colors: [Color(red: 0.1, green: 0.1, blue: 0.3), Color(red: 0.35, green: 0.25, blue: 0.6)])
                skyTile(title: "早上八点以前", value: portrait.early, symbol: "sunrise.fill",
                        colors: [Color(red: 0.98, green: 0.55, blue: 0.4), Color(red: 1, green: 0.82, blue: 0.55)],
                        ink: Color(red: 0.4, green: 0.16, blue: 0.1))
            }
            modesTile
            HStack(spacing: 12) {
                ringTile(title: "新去的地方", detail: "最近三个月", value: portrait.newPlaces, tint: .mint, symbol: "binoculars.fill")
                ringTile(title: "在家的时间", detail: "最近三个月", value: portrait.atHome, tint: .pink, symbol: "house.fill")
            }
            HStack(spacing: 12) {
                numberTile(value: portrait.cities, unit: "座城市", symbol: "building.2.fill", tint: .indigo)
                numberTile(value: portrait.countries, unit: "个国家和地区", symbol: "globe.asia.australia.fill", tint: .blue)
            }
        }
    }

    /// A share of the year's walking as a little sky, the number set large on it.
    private func skyTile(title: LocalizedStringKey, value: Double, symbol: String, colors: [Color], ink: Color = .white) -> some View {
        VStack(alignment: .leading, spacing: 6) {
            Image(systemName: symbol).font(.title2).symbolRenderingMode(.hierarchical)
            Spacer(minLength: 8)
            Text(percent(appeared ? value : 0))
                .font(.system(size: 34, weight: .bold, design: .rounded))
                .contentTransition(.numericText())
            Text(title).font(.caption.weight(.semibold)).opacity(0.85)
            Text("的路").font(.caption2).opacity(0.7)
        }
        .foregroundStyle(ink)
        .padding(16)
        .frame(maxWidth: .infinity, alignment: .leading)
        .frame(height: 156)
        .background(LinearGradient(colors: colors, startPoint: .topLeading, endPoint: .bottomTrailing),
                    in: .rect(cornerRadius: 22, style: .continuous))
        .animation(.smooth(duration: 0.9).delay(0.2), value: appeared)
    }

    /// Walking, cycling and riding as the parts of one bar.
    private var modesTile: some View {
        let parts: [(LocalizedStringKey, Double, Color, String)] = [
            ("步行", portrait.onFoot, .green, "figure.walk"),
            ("骑行", portrait.cycling, .teal, "bicycle"),
            ("乘车和地铁", portrait.riding, .blue, "tram.fill"),
        ]
        return VStack(alignment: .leading, spacing: 12) {
            Text("怎么走的").font(.caption.weight(.semibold)).foregroundStyle(.secondary)
            GeometryReader { geo in
                HStack(spacing: 3) {
                    ForEach(Array(parts.enumerated()), id: \.offset) { _, part in
                        if part.1 > 0.005 {
                            Capsule().fill(part.2.gradient)
                                .frame(width: max(6, (geo.size.width - 6) * (appeared ? part.1 : 1 / 3)))
                        }
                    }
                    Spacer(minLength: 0)
                }
            }
            .frame(height: 14)
            .animation(.spring(response: 0.9, dampingFraction: 0.85).delay(0.2), value: appeared)
            HStack(spacing: 16) {
                ForEach(Array(parts.enumerated()), id: \.offset) { _, part in
                    VStack(alignment: .leading, spacing: 2) {
                        Label(part.0, systemImage: part.3).font(.caption).foregroundStyle(part.2)
                        Text(percent(part.1)).font(.system(.headline, design: .rounded)).monospacedDigit()
                    }
                }
            }
        }
        .padding(16)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(.background.secondary, in: .rect(cornerRadius: 22, style: .continuous))
    }

    /// A share as a ring filling up, the number in the middle.
    private func ringTile(title: LocalizedStringKey, detail: LocalizedStringKey, value: Double, tint: Color, symbol: String) -> some View {
        VStack(spacing: 10) {
            ZStack {
                Circle().stroke(tint.opacity(0.15), lineWidth: 10)
                Circle()
                    .trim(from: 0, to: appeared ? value : 0)
                    .stroke(tint.gradient, style: StrokeStyle(lineWidth: 10, lineCap: .round))
                    .rotationEffect(.degrees(-90))
                VStack(spacing: 0) {
                    Image(systemName: symbol).font(.caption).foregroundStyle(tint)
                    Text(percent(value)).font(.system(.title3, design: .rounded, weight: .bold)).monospacedDigit()
                }
            }
            .frame(width: 92, height: 92)
            .animation(.spring(response: 1.1, dampingFraction: 0.85).delay(0.3), value: appeared)
            VStack(spacing: 1) {
                Text(title).font(.subheadline.weight(.semibold))
                Text(detail).font(.caption2).foregroundStyle(.secondary)
            }
        }
        .padding(.vertical, 18)
        .frame(maxWidth: .infinity)
        .background(.background.secondary, in: .rect(cornerRadius: 22, style: .continuous))
    }

    private func numberTile(value: Int, unit: LocalizedStringKey, symbol: String, tint: Color) -> some View {
        HStack(alignment: .center, spacing: 12) {
            Image(systemName: symbol)
                .font(.title3).foregroundStyle(.white)
                .frame(width: 42, height: 42)
                .background(RoundedRectangle(cornerRadius: 12, style: .continuous).fill(tint.gradient))
            VStack(alignment: .leading, spacing: 0) {
                Text(verbatim: "\(value)").font(.system(size: 28, weight: .bold, design: .rounded))
                Text(unit).font(.caption).foregroundStyle(.secondary).lineLimit(1).minimumScaleFactor(0.8)
            }
            Spacer(minLength: 0)
        }
        .padding(14)
        .background(.background.secondary, in: .rect(cornerRadius: 22, style: .continuous))
    }
}

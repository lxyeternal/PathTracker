import SwiftUI

/// "这一年，你是……" as a small travel poster: the archetype's painted scene, its name set
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
                Text(verbatim: "\(Calendar.current.component(.year, from: Date())) · \(String(localized: "旅人画像", bundle: .appLanguage))")
                    .font(.caption.weight(.semibold))
                    .tracking(2)
                    .opacity(0.85)
                Spacer(minLength: 0)
                Text("这一年，你是").font(.subheadline.weight(.medium)).opacity(0.85)
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
                                .background(.ultraThinMaterial.opacity(0.9), in: .capsule)
                                .environment(\.colorScheme, .dark)
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
                    VStack(alignment: .leading, spacing: 14) {
                        Text("你的这一年").font(.headline)
                        bar("夜里九点以后走的路", portrait.night, symbol: "moon.stars.fill", tint: .indigo)
                        bar("早上八点以前走的路", portrait.early, symbol: "sunrise.fill", tint: .orange)
                        bar("步行和跑步", portrait.onFoot, symbol: "figure.walk", tint: .green)
                        bar("骑行", portrait.cycling, symbol: "bicycle", tint: .teal)
                        bar("乘车和地铁", portrait.riding, symbol: "tram.fill", tint: .blue)
                        bar("最近三个月的新地方", portrait.newPlaces, symbol: "binoculars.fill", tint: .mint)
                        bar("最近三个月在家的时间", portrait.atHome, symbol: "house.fill", tint: .pink)
                        HStack {
                            Label("\(portrait.cities) 座城市", systemImage: "building.2.fill")
                            Spacer()
                            Label("\(portrait.countries) 个国家和地区", systemImage: "globe.asia.australia.fill")
                        }
                        .font(.subheadline).foregroundStyle(.secondary)
                    }
                    .padding(18)
                    .background(.background.secondary, in: .rect(cornerRadius: 24, style: .continuous))
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

    private func bar(_ title: LocalizedStringKey, _ value: Double, symbol: String, tint: Color) -> some View {
        VStack(alignment: .leading, spacing: 6) {
            HStack {
                Label(title, systemImage: symbol).font(.subheadline)
                Spacer()
                Text(value.formatted(.percent.precision(.fractionLength(0)).locale(appLocale)))
                    .font(.subheadline.weight(.semibold)).monospacedDigit()
            }
            GeometryReader { geo in
                ZStack(alignment: .leading) {
                    Capsule().fill(tint.opacity(0.15))
                    Capsule().fill(tint.gradient).frame(width: geo.size.width * (appeared ? value : 0))
                }
            }
            .frame(height: 6)
            .animation(.spring(response: 0.8, dampingFraction: 0.8).delay(0.2), value: appeared)
        }
    }
}

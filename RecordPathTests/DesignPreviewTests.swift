import Testing
import SwiftUI
@testable import RecordPath

/// Renders design work to images for looking at; does nothing unless asked.
@MainActor
struct DesignPreviewTests {
    private var folder: String? { ProcessInfo.processInfo.environment["DESIGN_PREVIEW_DIR"] }

    @Test func portraits() throws {
        guard let folder else { return }
        var portrait = TravellerPortrait()
        portrait.night = 0.42; portrait.cities = 18; portrait.countries = 9; portrait.newPlaces = 0.6
        let all = TravellerPortrait.Archetype.allCases
        let grid = VStack(spacing: 12) {
            ForEach(0..<5) { row in
                HStack(spacing: 12) {
                    ForEach(0..<2) { col in
                        PreviewPortrait(archetype: all[row * 2 + col]).frame(width: 340)
                    }
                }
            }
        }
        .padding(12)
        .background(Color.white)
        let renderer = ImageRenderer(content: grid)
        renderer.scale = 1.5
        let data = try #require(renderer.uiImage?.pngData())
        try data.write(to: URL(fileURLWithPath: folder).appending(path: "portraits.png"))
    }
}

extension DesignPreviewTests {
    @Test func yearTiles() throws {
        guard let folder else { return }
        var portrait = TravellerPortrait()
        portrait.night = 0.42; portrait.early = 0.12; portrait.onFoot = 0.35; portrait.cycling = 0.2; portrait.riding = 0.45
        portrait.newPlaces = 0.62; portrait.atHome = 0.48; portrait.cities = 18; portrait.countries = 9
        let view = YearInTiles(portrait: portrait, appeared: true).frame(width: 360)
        .padding(16)
        .background(Color(white: 0.96))
        let renderer = ImageRenderer(content: view)
        renderer.scale = 1.5
        let data = try #require(renderer.uiImage?.pngData())
        try data.write(to: URL(fileURLWithPath: folder).appending(path: "tiles.png"))
    }
}

private struct PreviewPortrait: View {
    let archetype: TravellerPortrait.Archetype
    var body: some View {
        ZStack(alignment: .bottomLeading) {
            PortraitScene(archetype: archetype)
            LinearGradient(stops: [.init(color: .clear, location: 0.35), .init(color: .black.opacity(0.62), location: 1)], startPoint: .top, endPoint: .bottom)
            Text(archetype.title).font(.system(size: 30, weight: .bold, design: .serif)).foregroundStyle(.white).padding(18)
        }
        .frame(height: 300)
        .clipShape(.rect(cornerRadius: 26, style: .continuous))
    }
}

extension DesignPreviewTests {
    @Test func journeyPage() throws {
        guard let folder else { return }
        let progress = JourneyProgress(route: .canal, travelled: 420_000)
        let view = HStack(alignment: .top, spacing: 24) {
            VStack(alignment: .leading, spacing: 12) {
                HStack(spacing: 12) {
                    ForEach(ClassicRoute.all.prefix(2)) { RoutePosterCard(route: $0, travelled: 420_000, selected: $0.id == "canal") }
                }
                HStack(spacing: 12) {
                    ForEach(ClassicRoute.all.dropFirst(2)) { RoutePosterCard(route: $0, travelled: 420_000, selected: false) }
                }
            }
            JourneyStops(progress: progress).frame(width: 360)
        }
        .padding(20)
        .background(Color.white)
        .environment(\.locale, Locale(identifier: "zh-Hans"))
        let renderer = ImageRenderer(content: view)
        renderer.scale = 1.5
        let data = try #require(renderer.uiImage?.pngData())
        try data.write(to: URL(fileURLWithPath: folder).appending(path: "journey.png"))
    }
}

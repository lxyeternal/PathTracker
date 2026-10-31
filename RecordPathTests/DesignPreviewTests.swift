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
    @Test func tilesAndPoster() throws {
        guard let folder else { return }
        var portrait = TravellerPortrait()
        portrait.night = 0.42; portrait.early = 0.12; portrait.onFoot = 0.35; portrait.cycling = 0.2; portrait.riding = 0.45
        portrait.newPlaces = 0.62; portrait.atHome = 0.48; portrait.cities = 18; portrait.countries = 9
        var painting = LightPainting()
        var lines: [(points: [CGPoint], mode: MovementMode)] = []
        for i in 0..<60 {
            let a = Double(i) * 0.7
            let pts = (0..<30).map { j -> CGPoint in
                let t = Double(j) / 29
                return CGPoint(x: 0.5 + cos(a) * 0.35 * t + sin(t * 6 + a) * 0.03, y: 0.42 + sin(a) * 0.3 * t + cos(t * 5) * 0.02)
            }
            lines.append((pts, [.walking, .cycling, .automotive][i % 3]))
        }
        painting.lines = lines
        painting.places = (0..<25).map { i in CGPoint(x: 0.3 + Double(i % 5) * 0.1, y: 0.25 + Double(i / 5) * 0.08) }
        painting.center = .init(latitude: 31.23, longitude: 121.47)
        let view = HStack(alignment: .top, spacing: 16) {
            YearInTiles(portrait: portrait, appeared: true).frame(width: 360)
            VStack(spacing: 12) {
                ForEach(LightPainting.Palette.allCases) { palette in
                    LightPoster(painting: painting, title: "上海", subtitle: "2026 · 441 公里", palette: palette).frame(width: 220)
                }
            }
        }
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

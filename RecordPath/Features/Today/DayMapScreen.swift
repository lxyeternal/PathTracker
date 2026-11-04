import SwiftUI
import CoreLocation

/// Full-screen, zoomable map of a day or trip.
struct DayMapScreen: View {
    let title: String
    let chunks: [TrackChunk]
    let stays: [Stay]
    var livePoints: [TrackPoint] = []
    var subtitle: String = ""

    @Environment(\.dismiss) private var dismiss
    @Environment(AppNavigator.self) private var navigator
    @AppStorage("map.style") private var styleChoice: MapStyleChoice = .standard
    @State private var selectedStay: Stay?
    @AppStorage("map.pastRoutes") private var showsPast = false
    @State private var pastLines: [AtlasLine] = []

    private var modes: [MovementMode] {
        MovementMode.allCases.filter { mode in chunks.contains { $0.mode == mode } }
    }

    var body: some View {
        NavigationStack {
            TrackMap(chunks: chunks, stays: stays, livePoints: livePoints, pastLines: showsPast ? pastLines : [], interactive: true,
                     showsUser: !livePoints.isEmpty, mapStyle: styleChoice.style,
                     onSelectStay: { selectedStay = $0 })
                .ignoresSafeArea()
                .safeAreaInset(edge: .bottom) {
                    summary
                }
                .navigationTitle(title)
                .navigationBarTitleDisplayMode(.inline)
                .toolbar {
                    ToolbarItem(placement: .cancellationAction) {
                        Button("关闭", systemImage: "xmark") { dismiss() }
                    }
                    ToolbarItem(placement: .primaryAction) {
                        ShareCardButton(makeContent: {
                            ShareCardContent(title: title, subtitle: subtitle, chunks: chunks, stays: stays,
                                             stats: [(String(localized: "距离", bundle: .appLanguage), Format.distance(chunks.reduce(0) { $0 + $1.distance })),
                                                     (String(localized: "地点", bundle: .appLanguage), "\(stays.count)")])
                        })
                    }
                    ToolbarItem(placement: .primaryAction) {
                        Toggle(isOn: $showsPast) {
                            Label("以往路线", systemImage: "clock.arrow.trianglehead.counterclockwise.rotate.90")
                        }
                        .toggleStyle(.button)
                        .accessibilityHint(Text("在这天的路线下面显示以前走过的路"))
                    }
                    ToolbarItem(placement: .primaryAction) {
                        Menu("地图样式", systemImage: "square.3.layers.3d") {
                            Picker("地图样式", selection: $styleChoice.animation()) {
                                ForEach(MapStyleChoice.allCases) { choice in
                                    Text(choice.title).tag(choice)
                                }
                            }
                        }
                    }
                }
                .task(id: showsPast) { await loadPast() }
                .animation(.smooth, value: showsPast)
                .sensoryFeedback(.selection, trigger: showsPast)
                .sheet(item: $selectedStay) { StayDetailView(stay: $0) }
                .onChange(of: navigator.jumpCount) { dismiss() }
        }
    }

    /// The roads from other days around this one's; the newest win when there are too many.
    private func loadPast() async {
        guard showsPast, !chunks.isEmpty || !stays.isEmpty else { return }
        let atlas = RouteAtlas.shared
        await atlas.load()
        // A still day has no track: the places it was spent at say where to look.
        let coordinates = chunks.flatMap { [CLLocationCoordinate2D(latitude: $0.minLatitude, longitude: $0.minLongitude),
                                             CLLocationCoordinate2D(latitude: $0.maxLatitude, longitude: $0.maxLongitude)].map(\.onMap) }
            + stays.map(\.coordinate.onMap)
        // The day's own track is left out: it's already drawn on top.
        let own = chunks.isEmpty ? nil : DateInterval(start: chunks.map(\.startDate).min() ?? .now,
                                                      end: max(chunks.map(\.endDate).max() ?? .now, chunks.map(\.startDate).min() ?? .now))
        let box = AtlasBox(coordinates, padding: chunks.isEmpty ? 0.05 : 0.02)
        // A single flight would pull in half the world.
        guard box.span < 3 else { pastLines = []; return }
        pastLines = atlas.lines(near: box, excluding: own, limit: 400)
            .filter { $0.mode != .flying }
    }

    private var summary: some View {
        HStack(spacing: 16) {
            Label(Format.distance(chunks.reduce(0) { $0 + $1.distance }),
                  systemImage: "point.topright.arrow.triangle.backward.to.point.bottomleft.scurvepath")
            Label("\(stays.count)", systemImage: "mappin.and.ellipse")
            Spacer()
            ForEach(modes, id: \.self) { mode in
                Image(systemName: mode.symbol)
                    .foregroundStyle(mode.color)
                    .accessibilityLabel(mode.title)
            }
        }
        .font(.subheadline.weight(.semibold))
        .padding(.horizontal, 20)
        .padding(.vertical, 14)
        .glassEffect(.regular, in: .capsule)
        .padding(.horizontal)
        .padding(.bottom, 8)
    }
}

import SwiftUI

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

    private var modes: [MovementMode] {
        MovementMode.allCases.filter { mode in chunks.contains { $0.mode == mode } }
    }

    var body: some View {
        NavigationStack {
            TrackMap(chunks: chunks, stays: stays, livePoints: livePoints, interactive: true,
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
                                             stats: [(String(localized: "距离"), Format.distance(chunks.reduce(0) { $0 + $1.distance })),
                                                     (String(localized: "地点"), "\(stays.count)")])
                        })
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
                .sheet(item: $selectedStay) { StayDetailView(stay: $0) }
                .onChange(of: navigator.jumpCount) { dismiss() }
        }
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

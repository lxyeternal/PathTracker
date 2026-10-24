import SwiftUI
import MapKit

/// Draws tracks (colored by how they were travelled) and stays on a map.
struct TrackMap: View {
    let chunks: [TrackChunk]
    let stays: [Stay]
    var livePoints: [TrackPoint] = []
    var interactive = true
    var showsUser = false
    var mapStyle: MapStyle = .standard(elevation: .realistic, pointsOfInterest: .excludingAll)
    var onSelectStay: ((Stay) -> Void)?

    @State private var position: MapCameraPosition = .automatic
    @State private var lines: [Line] = []

    struct Line: Identifiable {
        let id: Int
        let coordinates: [CLLocationCoordinate2D]
        let color: Color
    }

    var body: some View {
        Map(position: $position, interactionModes: interactive ? .all : []) {
            ForEach(lines) { line in
                MapPolyline(coordinates: line.coordinates)
                    .stroke(.white.opacity(0.9), style: StrokeStyle(lineWidth: 7, lineCap: .round, lineJoin: .round))
                MapPolyline(coordinates: line.coordinates)
                    .stroke(line.color.gradient, style: StrokeStyle(lineWidth: 4.5, lineCap: .round, lineJoin: .round))
            }
            if livePoints.count > 1 {
                MapPolyline(coordinates: livePoints.map(\.coordinate.onMap))
                    .stroke(.green, style: StrokeStyle(lineWidth: 4.5, lineCap: .round, lineJoin: .round, dash: [1, 7]))
            }
            ForEach(stays) { stay in
                Annotation(stay.displayName, coordinate: stay.coordinate.onMap, anchor: .center) {
                    Button {
                        onSelectStay?(stay)
                    } label: {
                        PlaceIcon(category: stay.category, isLandmark: stay.isLandmark, size: interactive ? 30 : 22)
                            .overlay(Circle().stroke(.white, lineWidth: 2))
                            .shadow(color: .black.opacity(0.2), radius: 3, y: 1)
                    }
                    .buttonStyle(.plain)
                    .disabled(onSelectStay == nil)
                }
                .annotationTitles(interactive ? .automatic : .hidden)
            }
            if showsUser { UserAnnotation() }
        }
        .mapStyle(mapStyle)
        .mapControls {
            if interactive {
                MapUserLocationButton()
                MapCompass()
                MapScaleView()
            }
        }
        .task(id: chunks.map(\.persistentModelID) + stays.map(\.persistentModelID)) {
            lines = Self.makeLines(chunks)
            position = framing
        }
        .onChange(of: livePoints.count / 15) {
            // Keep a live recording in view as it grows, unless the user is exploring the map.
            guard !interactive else { return }
            withAnimation(.smooth(duration: 0.8)) { position = framing }
        }
    }

    /// Frames everything with some breathing room, never zooming in closer than a few
    /// streets; with nothing to show it follows the user.
    private var framing: MapCameraPosition {
        let coordinates = lines.flatMap(\.coordinates) + stays.map(\.coordinate.onMap) + livePoints.map(\.coordinate.onMap)
        guard !coordinates.isEmpty else { return .userLocation(fallback: .automatic) }
        var rect = MKMapRect.null
        for coordinate in coordinates {
            rect = rect.union(MKMapRect(origin: MKMapPoint(coordinate), size: MKMapSize(width: 0, height: 0)))
        }
        let minimumSide = 1_600 * MKMapPointsPerMeterAtLatitude(coordinates[0].latitude)
        let side = max(rect.width, rect.height) * 0.35
        rect = rect.insetBy(dx: -side, dy: -side)
        if rect.width < minimumSide || rect.height < minimumSide {
            let width = max(rect.width, minimumSide), height = max(rect.height, minimumSide)
            rect = MKMapRect(x: rect.midX - width / 2, y: rect.midY - height / 2, width: width, height: height)
        }
        return .rect(rect)
    }

    /// Long days are simplified so thousands of points still pan smoothly.
    static func makeLines(_ chunks: [TrackChunk]) -> [Line] {
        let total = chunks.reduce(0) { $0 + $1.pointCount }
        let tolerance: Double = total > 20_000 ? 25 : total > 5_000 ? 10 : 3
        return chunks.enumerated().compactMap { index, chunk in
            let points = chunk.points.simplified(tolerance: tolerance)
            guard points.count > 1 else { return nil }
            return Line(id: index, coordinates: points.map(\.coordinate.onMap), color: chunk.mode.color)
        }
    }
}

extension MapStyleChoice {
    var style: MapStyle {
        switch self {
        case .standard: .standard(elevation: .realistic, pointsOfInterest: .excludingAll)
        case .hybrid: .hybrid(elevation: .realistic)
        case .imagery: .imagery(elevation: .realistic)
        }
    }
}

enum MapStyleChoice: String, CaseIterable, Identifiable {
    case standard, hybrid, imagery
    var id: String { rawValue }

    var title: LocalizedStringKey {
        switch self {
        case .standard: "标准"
        case .hybrid: "混合"
        case .imagery: "卫星"
        }
    }
}

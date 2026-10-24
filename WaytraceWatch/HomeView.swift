import SwiftUI
import MapKit

/// Opens on the map, like Maps and hiking apps on the Watch: where you are and today's route.
/// Everything else stays a tap away.
struct HomeView: View {
    @Environment(PhoneLink.self) private var link
    @Environment(WorkoutRecorder.self) private var recorder
    @State private var position: MapCameraPosition = .userLocation(fallback: .automatic)
    @State private var showingToday = false
    @State private var showingActivities = false

    var body: some View {
        if recorder.state == .idle {
            home
        } else {
            // In place of the map rather than as a cover, which would add a close button that
            // hides the recording without ending it.
            RecordingView()
                .transition(.opacity)
        }
    }

    private var home: some View {
        NavigationStack {
            RouteMap(snapshot: link.snapshot, position: $position)
                .navigationTitle(title)
                .navigationBarTitleDisplayMode(.inline)
                .toolbar {
                    ToolbarItemGroup(placement: .bottomBar) {
                        Button("今天", systemImage: "list.bullet") { showingToday = true }
                        Spacer()
                        Button("开始记录", systemImage: "record.circle") { showingActivities = true }
                            .tint(.orange)
                            .controlSize(.large)
                    }
                }
                .sheet(isPresented: $showingToday) { TodaySheet() }
                .sheet(isPresented: $showingActivities) {
                    ActivityPicker { activity in
                        // Let the sheet slide away before the recording screen replaces this one.
                        showingActivities = false
                        Task {
                            try? await Task.sleep(for: .milliseconds(400))
                            await recorder.start(activity)
                        }
                    }
                }
        }
        .onAppear {
            recorder.requestLocationPermission()
            link.refresh()
        }
        .alert("无法开始记录", isPresented: .constant(recorder.errorMessage != nil && recorder.state == .idle)) {
            Button("好") { recorder.clearError() }
        } message: {
            Text(recorder.errorMessage ?? "")
        }
    }

    /// The place you're at, or what the iPhone is doing when that's more useful to know.
    private var title: String {
        guard let snapshot = link.snapshot else { return String(localized: "漫迹", bundle: .appLanguage) }
        if snapshot.pausedUntil != nil { return String(localized: "记录已暂停", bundle: .appLanguage) }
        return snapshot.currentPlace?.name ?? String(localized: "今天", bundle: .appLanguage)
    }
}

/// Today's route from the iPhone, the places you stopped at, and your position.
struct RouteMap: View {
    let snapshot: WatchSnapshot?
    var livePoints: [TrackPoint] = []
    /// While recording the map only zooms (Digital Crown), so swipes turn the pages.
    var isFollowing = false
    @Binding var position: MapCameraPosition

    var body: some View {
        Map(position: $position, interactionModes: isFollowing ? [.zoom] : .all) {
            if let snapshot {
                ForEach(Array(snapshot.segments.enumerated()), id: \.offset) { _, segment in
                    MapPolyline(coordinates: segment.map(\.clCoordinate))
                        .stroke(.white.opacity(0.9), style: StrokeStyle(lineWidth: 6, lineCap: .round, lineJoin: .round))
                    MapPolyline(coordinates: segment.map(\.clCoordinate))
                        .stroke(Color.blue.gradient, style: StrokeStyle(lineWidth: 3.5, lineCap: .round, lineJoin: .round))
                }
                ForEach(Array(snapshot.places.enumerated()), id: \.offset) { _, place in
                    Annotation(place.name, coordinate: place.coordinate.clCoordinate, anchor: .center) {
                        Circle()
                            .fill(place.departure == nil ? Color.orange : Color.indigo)
                            .frame(width: 10, height: 10)
                            .overlay(Circle().stroke(.white, lineWidth: 2))
                    }
                    .annotationTitles(.hidden)
                }
            }
            if livePoints.count > 1 {
                MapPolyline(coordinates: livePoints.map(\.coordinate))
                    .stroke(.white.opacity(0.9), style: StrokeStyle(lineWidth: 7, lineCap: .round, lineJoin: .round))
                MapPolyline(coordinates: livePoints.map(\.coordinate))
                    .stroke(Color.orange.gradient, style: StrokeStyle(lineWidth: 4.5, lineCap: .round, lineJoin: .round))
            }
            UserAnnotation()
        }
        .mapStyle(.standard(pointsOfInterest: .excludingAll))
        .mapControls {
            if !isFollowing { MapUserLocationButton() }
        }
    }
}

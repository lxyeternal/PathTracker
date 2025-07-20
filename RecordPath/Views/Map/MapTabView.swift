import SwiftUI
import MapKit
import CoreLocation

struct MapTabView: View {
    @EnvironmentObject var authManager: AuthenticationManager
    @EnvironmentObject var pathTrackingManager: PathTrackingManager
    @State private var selectedJourney: Journey?
    @State private var showingJourneyList = false
    @State private var selectedTimeFilter: TimeFilter = .thisMonth
    @State private var mapRegion = MKCoordinateRegion(
        center: CLLocationCoordinate2D(latitude: 40.7128, longitude: -74.0060), // Default to NYC
        span: MKCoordinateSpan(latitudeDelta: 0.1, longitudeDelta: 0.1)
    )
    
    var body: some View {
        NavigationView {
            ZStack {
                // Main Map View
                MapView(
                    region: $mapRegion,
                    journeys: filteredJourneys,
                    selectedJourney: $selectedJourney,
                    currentLocation: pathTrackingManager.currentLocation
                )
                .ignoresSafeArea()
                
                // Overlay Controls
                VStack {
                    // Top Controls
                    mapControlsOverlay
                    
                    Spacer()
                    
                    // Bottom Journey Info
                    if let journey = selectedJourney {
                        selectedJourneyInfo(journey)
                    }
                }
            }
            .navigationTitle("Travel Map")
            .navigationBarTitleDisplayMode(.inline)
            .navigationBarItems(
                leading: Button(action: { showingJourneyList = true }) {
                    Image(systemName: "list.bullet")
                },
                trailing: Menu {
                    ForEach(TimeFilter.allCases, id: \.self) { filter in
                        Button(filter.rawValue) {
                            selectedTimeFilter = filter
                            updateMapRegion()
                        }
                    }
                } label: {
                    Image(systemName: "calendar")
                }
            )
        }
        .sheet(isPresented: $showingJourneyList) {
            JourneyListSheet(
                journeys: filteredJourneys,
                selectedJourney: $selectedJourney,
                onJourneySelected: { journey in
                    selectedJourney = journey
                    showingJourneyList = false
                    focusOnJourney(journey)
                }
            )
        }
        .onAppear {
            updateMapRegion()
        }
    }
    
    private var mapControlsOverlay: some View {
        HStack {
            VStack(spacing: 12) {
                // Zoom to Current Location
                Button(action: {
                    if let location = pathTrackingManager.currentLocation {
                        withAnimation {
                            mapRegion.center = location.coordinate
                            mapRegion.span = MKCoordinateSpan(latitudeDelta: 0.01, longitudeDelta: 0.01)
                        }
                    }
                }) {
                    Image(systemName: "location.fill")
                        .font(.title3)
                        .foregroundColor(.blue)
                        .frame(width: 44, height: 44)
                        .background(Color(.systemBackground))
                        .clipShape(Circle())
                        .shadow(color: .black.opacity(0.1), radius: 4, x: 0, y: 2)
                }
                
                // Zoom to All Journeys
                Button(action: {
                    fitAllJourneys()
                }) {
                    Image(systemName: "map")
                        .font(.title3)
                        .foregroundColor(.green)
                        .frame(width: 44, height: 44)
                        .background(Color(.systemBackground))
                        .clipShape(Circle())
                        .shadow(color: .black.opacity(0.1), radius: 4, x: 0, y: 2)
                }
                
                // Map Style Toggle (placeholder)
                Button(action: {
                    // Toggle between standard/satellite/hybrid
                }) {
                    Image(systemName: "layers.fill")
                        .font(.title3)
                        .foregroundColor(.purple)
                        .frame(width: 44, height: 44)
                        .background(Color(.systemBackground))
                        .clipShape(Circle())
                        .shadow(color: .black.opacity(0.1), radius: 4, x: 0, y: 2)
                }
            }
            
            Spacer()
            
            // Time Filter Indicator
            VStack {
                Text(selectedTimeFilter.rawValue)
                    .font(.caption)
                    .fontWeight(.medium)
                    .foregroundColor(.white)
                    .padding(.horizontal, 12)
                    .padding(.vertical, 6)
                    .background(Color.blue.opacity(0.8))
                    .cornerRadius(16)
                    .shadow(color: .black.opacity(0.2), radius: 4, x: 0, y: 2)
                
                Spacer()
            }
        }
        .padding()
    }
    
    private func selectedJourneyInfo(_ journey: Journey) -> some View {
        VStack(spacing: 16) {
            HStack {
                VStack(alignment: .leading, spacing: 4) {
                    Text(journey.title)
                        .font(.headline)
                        .fontWeight(.semibold)
                        .foregroundColor(.primary)
                    
                    Text(journey.endDate.formatted(date: .abbreviated, time: .shortened))
                        .font(.caption)
                        .foregroundColor(.secondary)
                }
                
                Spacer()
                
                Button("Dismiss") {
                    selectedJourney = nil
                }
                .font(.caption)
                .foregroundColor(.blue)
            }
            
            HStack(spacing: 20) {
                StatBadge(
                    title: "Distance",
                    value: journey.formattedDistance,
                    icon: "map.fill",
                    color: .blue
                )
                
                StatBadge(
                    title: "Duration",
                    value: journey.formattedDuration,
                    icon: "clock.fill",
                    color: .green
                )
                
                StatBadge(
                    title: "Countries",
                    value: "\(journey.visitedCountries.count)",
                    icon: "globe",
                    color: .orange
                )
                
                Spacer()
            }
        }
        .padding()
        .background(Color(.systemBackground).opacity(0.95))
        .cornerRadius(16)
        .shadow(color: .black.opacity(0.1), radius: 8, x: 0, y: 4)
        .padding()
    }
    
    private var filteredJourneys: [Journey] {
        guard let user = authManager.currentUser else { return [] }
        
        let (startDate, endDate) = selectedTimeFilter.dateRange()
        
        return user.journeys.filter { journey in
            journey.endDate >= startDate && journey.startDate <= endDate
        }
    }
    
    private func updateMapRegion() {
        let journeys = filteredJourneys
        guard !journeys.isEmpty else { return }
        
        var minLat = Double.greatestFiniteMagnitude
        var maxLat = -Double.greatestFiniteMagnitude
        var minLon = Double.greatestFiniteMagnitude
        var maxLon = -Double.greatestFiniteMagnitude
        
        for journey in journeys {
            for segment in journey.segments {
                let boundingBox = segment.boundingBox
                minLat = min(minLat, boundingBox.minLat)
                maxLat = max(maxLat, boundingBox.maxLat)
                minLon = min(minLon, boundingBox.minLon)
                maxLon = max(maxLon, boundingBox.maxLon)
            }
        }
        
        let center = CLLocationCoordinate2D(
            latitude: (minLat + maxLat) / 2,
            longitude: (minLon + maxLon) / 2
        )
        
        let span = MKCoordinateSpan(
            latitudeDelta: max(maxLat - minLat, 0.01) * 1.2,
            longitudeDelta: max(maxLon - minLon, 0.01) * 1.2
        )
        
        withAnimation {
            mapRegion = MKCoordinateRegion(center: center, span: span)
        }
    }
    
    private func fitAllJourneys() {
        updateMapRegion()
    }
    
    private func focusOnJourney(_ journey: Journey) {
        guard !journey.segments.isEmpty else { return }
        
        var minLat = Double.greatestFiniteMagnitude
        var maxLat = -Double.greatestFiniteMagnitude
        var minLon = Double.greatestFiniteMagnitude
        var maxLon = -Double.greatestFiniteMagnitude
        
        for segment in journey.segments {
            let boundingBox = segment.boundingBox
            minLat = min(minLat, boundingBox.minLat)
            maxLat = max(maxLat, boundingBox.maxLat)
            minLon = min(minLon, boundingBox.minLon)
            maxLon = max(maxLon, boundingBox.maxLon)
        }
        
        let center = CLLocationCoordinate2D(
            latitude: (minLat + maxLat) / 2,
            longitude: (minLon + maxLon) / 2
        )
        
        let span = MKCoordinateSpan(
            latitudeDelta: max(maxLat - minLat, 0.005) * 1.5,
            longitudeDelta: max(maxLon - minLon, 0.005) * 1.5
        )
        
        withAnimation {
            mapRegion = MKCoordinateRegion(center: center, span: span)
        }
    }
}

struct MapView: UIViewRepresentable {
    @Binding var region: MKCoordinateRegion
    let journeys: [Journey]
    @Binding var selectedJourney: Journey?
    let currentLocation: CLLocation?
    
    func makeUIView(context: Context) -> MKMapView {
        let mapView = MKMapView()
        mapView.delegate = context.coordinator
        mapView.showsUserLocation = true
        mapView.userTrackingMode = .none
        return mapView
    }
    
    func updateUIView(_ mapView: MKMapView, context: Context) {
        // Update region
        if !mapView.region.center.latitude.isEqual(to: region.center.latitude) ||
           !mapView.region.center.longitude.isEqual(to: region.center.longitude) {
            mapView.setRegion(region, animated: true)
        }
        
        // Clear existing overlays and annotations
        mapView.removeOverlays(mapView.overlays)
        mapView.removeAnnotations(mapView.annotations.filter { !($0 is MKUserLocation) })
        
        // Add journey polylines
        for journey in journeys {
            for segment in journey.segments {
                let coordinates = segment.trackPoints.map { $0.coordinate }
                if coordinates.count > 1 {
                    let polyline = MKPolyline(coordinates: coordinates, count: coordinates.count)
                    polyline.title = journey.id.uuidString
                    mapView.addOverlay(polyline)
                }
                
                // Add start and end annotations
                if let firstPoint = segment.trackPoints.first {
                    let annotation = JourneyPointAnnotation(
                        coordinate: firstPoint.coordinate,
                        title: journey.title,
                        subtitle: "Start: \(firstPoint.timestamp.formatted(date: .omitted, time: .shortened))",
                        journeyId: journey.id,
                        isStartPoint: true
                    )
                    mapView.addAnnotation(annotation)
                }
                
                if let lastPoint = segment.trackPoints.last, segment.trackPoints.count > 1 {
                    let annotation = JourneyPointAnnotation(
                        coordinate: lastPoint.coordinate,
                        title: journey.title,
                        subtitle: "End: \(lastPoint.timestamp.formatted(date: .omitted, time: .shortened))",
                        journeyId: journey.id,
                        isStartPoint: false
                    )
                    mapView.addAnnotation(annotation)
                }
            }
        }
    }
    
    func makeCoordinator() -> Coordinator {
        Coordinator(self)
    }
    
    class Coordinator: NSObject, MKMapViewDelegate {
        var parent: MapView
        
        init(_ parent: MapView) {
            self.parent = parent
        }
        
        func mapView(_ mapView: MKMapView, rendererFor overlay: MKOverlay) -> MKOverlayRenderer {
            if let polyline = overlay as? MKPolyline {
                let renderer = MKPolylineRenderer(polyline: polyline)
                
                // Color code by journey
                if let journeyIdString = polyline.title,
                   let journeyId = UUID(uuidString: journeyIdString),
                   let journey = parent.journeys.first(where: { $0.id == journeyId }) {
                    
                    if parent.selectedJourney?.id == journeyId {
                        renderer.strokeColor = .systemBlue
                        renderer.lineWidth = 6
                    } else {
                        renderer.strokeColor = .systemBlue.withAlphaComponent(0.6)
                        renderer.lineWidth = 4
                    }
                } else {
                    renderer.strokeColor = .systemBlue.withAlphaComponent(0.6)
                    renderer.lineWidth = 4
                }
                
                return renderer
            }
            return MKOverlayRenderer()
        }
        
        func mapView(_ mapView: MKMapView, viewFor annotation: MKAnnotation) -> MKAnnotationView? {
            if annotation is MKUserLocation { return nil }
            
            let identifier = "JourneyPoint"
            var annotationView = mapView.dequeueReusableAnnotationView(withIdentifier: identifier)
            
            if annotationView == nil {
                annotationView = MKMarkerAnnotationView(annotation: annotation, reuseIdentifier: identifier)
                annotationView?.canShowCallout = true
            } else {
                annotationView?.annotation = annotation
            }
            
            if let journeyAnnotation = annotation as? JourneyPointAnnotation {
                let markerView = annotationView as! MKMarkerAnnotationView
                markerView.markerTintColor = journeyAnnotation.isStartPoint ? .systemGreen : .systemRed
                markerView.glyphImage = UIImage(systemName: journeyAnnotation.isStartPoint ? "play.fill" : "stop.fill")
            }
            
            return annotationView
        }
        
        func mapView(_ mapView: MKMapView, didSelect view: MKAnnotationView) {
            if let journeyAnnotation = view.annotation as? JourneyPointAnnotation {
                parent.selectedJourney = parent.journeys.first { $0.id == journeyAnnotation.journeyId }
            }
        }
    }
}

class JourneyPointAnnotation: NSObject, MKAnnotation {
    let coordinate: CLLocationCoordinate2D
    let title: String?
    let subtitle: String?
    let journeyId: UUID
    let isStartPoint: Bool
    
    init(coordinate: CLLocationCoordinate2D, title: String?, subtitle: String?, journeyId: UUID, isStartPoint: Bool) {
        self.coordinate = coordinate
        self.title = title
        self.subtitle = subtitle
        self.journeyId = journeyId
        self.isStartPoint = isStartPoint
    }
}

struct StatBadge: View {
    let title: String
    let value: String
    let icon: String
    let color: Color
    
    var body: some View {
        VStack(spacing: 4) {
            Image(systemName: icon)
                .font(.caption)
                .foregroundColor(color)
            
            Text(value)
                .font(.caption)
                .fontWeight(.semibold)
                .foregroundColor(.primary)
            
            Text(title)
                .font(.caption2)
                .foregroundColor(.secondary)
        }
    }
}

struct JourneyListSheet: View {
    let journeys: [Journey]
    @Binding var selectedJourney: Journey?
    let onJourneySelected: (Journey) -> Void
    @Environment(\.dismiss) private var dismiss
    
    var body: some View {
        NavigationView {
            List(journeys) { journey in
                JourneyListRow(
                    journey: journey,
                    isSelected: selectedJourney?.id == journey.id
                ) {
                    onJourneySelected(journey)
                }
            }
            .navigationTitle("Journeys")
            .navigationBarTitleDisplayMode(.inline)
            .navigationBarItems(
                trailing: Button("Done") { dismiss() }
            )
        }
    }
}

struct JourneyListRow: View {
    let journey: Journey
    let isSelected: Bool
    let onTap: () -> Void
    
    var body: some View {
        Button(action: onTap) {
            HStack {
                VStack(alignment: .leading, spacing: 4) {
                    Text(journey.title)
                        .font(.headline)
                        .fontWeight(.semibold)
                        .foregroundColor(.primary)
                    
                    Text(journey.endDate.formatted(date: .abbreviated, time: .shortened))
                        .font(.caption)
                        .foregroundColor(.secondary)
                    
                    HStack {
                        Text(journey.formattedDistance)
                        Text("•")
                        Text(journey.formattedDuration)
                        Text("•")
                        Text("\(journey.visitedCountries.count) countries")
                    }
                    .font(.caption)
                    .foregroundColor(.secondary)
                }
                
                Spacer()
                
                if isSelected {
                    Image(systemName: "checkmark.circle.fill")
                        .foregroundColor(.blue)
                }
            }
        }
        .buttonStyle(PlainButtonStyle())
    }
}

#Preview {
    MapTabView()
        .environmentObject(AuthenticationManager())
        .environmentObject(PathTrackingManager())
}
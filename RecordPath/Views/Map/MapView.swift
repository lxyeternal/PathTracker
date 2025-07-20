import SwiftUI
import MapKit

struct LegacyMapTabView: View {
    @EnvironmentObject var authManager: AuthenticationManager
    @StateObject private var locationManager = LocationManager()
    @State private var region = MKCoordinateRegion(
        center: CLLocationCoordinate2D(latitude: 39.0, longitude: 116.0),
        span: MKCoordinateSpan(latitudeDelta: 50, longitudeDelta: 50)
    )
    @State private var selectedVisit: Visit?
    @State private var showingVisitDetail = false
    @State private var mapType: MKMapType = .standard
    
    var body: some View {
        NavigationView {
            ZStack {
                // Main Map
                Map(coordinateRegion: $region, 
                    interactionModes: .all,
                    showsUserLocation: true,
                    annotationItems: authManager.currentUser?.visits ?? []) { visit in
                    MapAnnotation(coordinate: visit.location.coordinate) {
                        LocationPin(visit: visit) {
                            selectedVisit = visit
                            showingVisitDetail = true
                        }
                    }
                }
                .ignoresSafeArea()
                
                // Control Panel
                VStack {
                    HStack {
                        Spacer()
                        
                        VStack(spacing: 12) {
                            // Map Type Toggle
                            MapTypeToggle(mapType: $mapType)
                            
                            // Current Location Button
                            Button(action: centerOnUserLocation) {
                                Image(systemName: "location.fill")
                                    .font(.title2)
                                    .foregroundColor(.blue)
                                    .frame(width: 44, height: 44)
                                    .background(Color(.systemBackground))
                                    .clipShape(Circle())
                                    .shadow(color: .black.opacity(0.1), radius: 4, x: 0, y: 2)
                            }
                            
                            // Zoom to All Locations
                            Button(action: zoomToAllLocations) {
                                Image(systemName: "scope")
                                    .font(.title2)
                                    .foregroundColor(.green)
                                    .frame(width: 44, height: 44)
                                    .background(Color(.systemBackground))
                                    .clipShape(Circle())
                                    .shadow(color: .black.opacity(0.1), radius: 4, x: 0, y: 2)
                            }
                        }
                        .padding(.trailing)
                    }
                    
                    Spacer()
                    
                    // Bottom Stats Panel
                    if let user = authManager.currentUser, !user.visits.isEmpty {
                        MapStatsPanel(user: user)
                            .padding(.horizontal)
                            .padding(.bottom, 90) // Account for tab bar
                    }
                }
            }
            .navigationTitle("Travel Map")
            .navigationBarTitleDisplayMode(.inline)
            .onAppear {
                setupInitialRegion()
            }
            .sheet(isPresented: $showingVisitDetail) {
                if let visit = selectedVisit {
                    VisitDetailSheet(visit: visit)
                }
            }
        }
    }
    
    private func setupInitialRegion() {
        guard let user = authManager.currentUser, !user.visits.isEmpty else { return }
        
        let coordinates = user.visits.map { $0.location.coordinate }
        let minLat = coordinates.map { $0.latitude }.min() ?? 0
        let maxLat = coordinates.map { $0.latitude }.max() ?? 0
        let minLon = coordinates.map { $0.longitude }.min() ?? 0
        let maxLon = coordinates.map { $0.longitude }.max() ?? 0
        
        let center = CLLocationCoordinate2D(
            latitude: (minLat + maxLat) / 2,
            longitude: (minLon + maxLon) / 2
        )
        
        let span = MKCoordinateSpan(
            latitudeDelta: max(maxLat - minLat, 0.5) * 1.3,
            longitudeDelta: max(maxLon - minLon, 0.5) * 1.3
        )
        
        region = MKCoordinateRegion(center: center, span: span)
    }
    
    private func centerOnUserLocation() {
        if let userLocation = locationManager.currentLocation {
            region = MKCoordinateRegion(
                center: userLocation.coordinate,
                span: MKCoordinateSpan(latitudeDelta: 0.1, longitudeDelta: 0.1)
            )
        }
    }
    
    private func zoomToAllLocations() {
        setupInitialRegion()
    }
}

struct LocationPin: View {
    let visit: Visit
    let onTap: () -> Void
    
    var body: some View {
        Button(action: onTap) {
            VStack(spacing: 0) {
                // Flag circle
                Circle()
                    .fill(getCountryColor(visit.location.country ?? ""))
                    .frame(width: 32, height: 32)
                    .overlay(
                        Text(getCountryFlag(visit.location.country ?? ""))
                            .font(.caption)
                    )
                    .overlay(
                        Circle()
                            .stroke(Color.white, lineWidth: 2)
                    )
                    .shadow(color: .black.opacity(0.2), radius: 4, x: 0, y: 2)
                
                // Pin point
                Circle()
                    .fill(getCountryColor(visit.location.country ?? ""))
                    .frame(width: 6, height: 6)
                    .offset(y: -3)
            }
        }
        .scaleEffect(1.0)
        .animation(.spring(response: 0.4, dampingFraction: 0.8), value: visit.id)
    }
    
    private func getCountryFlag(_ country: String) -> String {
        switch country.lowercased() {
        case "france": return "🇫🇷"
        case "japan": return "🇯🇵"
        case "china": return "🇨🇳"
        case "usa", "united states": return "🇺🇸"
        case "uk", "united kingdom": return "🇬🇧"
        default: return "🌍"
        }
    }
    
    private func getCountryColor(_ country: String) -> Color {
        switch country.lowercased() {
        case "france": return .blue
        case "japan": return .red
        case "china": return .red
        case "usa", "united states": return .blue
        case "uk", "united kingdom": return .indigo
        default: return .gray
        }
    }
}

struct MapTypeToggle: View {
    @Binding var mapType: MKMapType
    
    var body: some View {
        Menu {
            Button("Standard") {
                mapType = .standard
            }
            Button("Satellite") {
                mapType = .satellite
            }
            Button("Hybrid") {
                mapType = .hybrid
            }
        } label: {
            Image(systemName: "map")
                .font(.title2)
                .foregroundColor(.blue)
                .frame(width: 44, height: 44)
                .background(Color(.systemBackground))
                .clipShape(Circle())
                .shadow(color: .black.opacity(0.1), radius: 4, x: 0, y: 2)
        }
    }
}

struct MapStatsPanel: View {
    let user: User
    
    var body: some View {
        HStack(spacing: 20) {
            MapStatItem(
                icon: "location.fill",
                title: "Places",
                value: "\(user.visitCount)",
                color: .blue
            )
            
            Divider()
                .frame(height: 30)
            
            MapStatItem(
                icon: "globe",
                title: "Countries",
                value: "\(user.countriesVisited.count)",
                color: .green
            )
            
            Divider()
                .frame(height: 30)
            
            MapStatItem(
                icon: "building.2",
                title: "Cities",
                value: "\(user.citiesVisited.count)",
                color: .orange
            )
        }
        .padding()
        .background(
            RoundedRectangle(cornerRadius: 16)
                .fill(Color(.systemBackground))
                .shadow(color: .black.opacity(0.1), radius: 8, x: 0, y: 2)
        )
    }
}

struct VisitDetailSheet: View {
    let visit: Visit
    @Environment(\.dismiss) private var dismiss
    
    var body: some View {
        NavigationView {
            ScrollView {
                VStack(spacing: 20) {
                    // Header with flag and location
                    VStack(spacing: 16) {
                        Text(getCountryFlag(visit.location.country ?? ""))
                            .font(.system(size: 60))
                        
                        VStack(spacing: 8) {
                            Text(visit.locationName)
                                .font(.title)
                                .fontWeight(.bold)
                                .multilineTextAlignment(.center)
                            
                            Text(visit.location.fullAddress)
                                .font(.subheadline)
                                .foregroundColor(.secondary)
                                .multilineTextAlignment(.center)
                        }
                    }
                    .padding(.top)
                    
                    // Visit Details
                    LazyVGrid(columns: Array(repeating: GridItem(.flexible()), count: 2), spacing: 16) {
                        DetailCard(
                            title: "Visit Date",
                            value: visit.formattedVisitDate,
                            icon: "calendar",
                            color: .blue
                        )
                        
                        DetailCard(
                            title: "Rating",
                            value: visit.rating > 0 ? String(repeating: "⭐", count: visit.rating) : "No rating",
                            icon: "star.fill",
                            color: .yellow
                        )
                        
                        if let weather = visit.weather {
                            DetailCard(
                                title: "Weather",
                                value: weather,
                                icon: "cloud.sun",
                                color: .cyan
                            )
                        }
                        
                        DetailCard(
                            title: "Country",
                            value: visit.location.country ?? "Unknown",
                            icon: "flag",
                            color: .green
                        )
                    }
                    
                    // Comment
                    if visit.hasComment {
                        VStack(alignment: .leading, spacing: 8) {
                            Text("Comment")
                                .font(.headline)
                                .fontWeight(.semibold)
                            
                            Text(visit.displayComment)
                                .font(.body)
                                .padding()
                                .background(Color.gray.opacity(0.1))
                                .cornerRadius(12)
                        }
                        .frame(maxWidth: .infinity, alignment: .leading)
                    }
                }
                .padding()
            }
            .navigationTitle("Visit Details")
            .navigationBarTitleDisplayMode(.inline)
            .navigationBarItems(trailing: Button("Done") { dismiss() })
        }
    }
    
    private func getCountryFlag(_ country: String) -> String {
        switch country.lowercased() {
        case "france": return "🇫🇷"
        case "japan": return "🇯🇵"
        case "china": return "🇨🇳"
        case "usa", "united states": return "🇺🇸"
        case "uk", "united kingdom": return "🇬🇧"
        default: return "🌍"
        }
    }
}

struct MapStatItem: View {
    let icon: String
    let title: String
    let value: String
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

struct DetailCard: View {
    let title: String
    let value: String
    let icon: String
    let color: Color
    
    var body: some View {
        VStack(spacing: 8) {
            Image(systemName: icon)
                .font(.title2)
                .foregroundColor(color)
            
            Text(title)
                .font(.caption)
                .foregroundColor(.secondary)
                .fontWeight(.medium)
            
            Text(value)
                .font(.subheadline)
                .fontWeight(.semibold)
                .multilineTextAlignment(.center)
        }
        .frame(maxWidth: .infinity)
        .padding()
        .background(Color.gray.opacity(0.05))
        .cornerRadius(12)
    }
}

class LocationManager: NSObject, ObservableObject, CLLocationManagerDelegate {
    private let manager = CLLocationManager()
    @Published var currentLocation: CLLocation?
    
    override init() {
        super.init()
        manager.delegate = self
        manager.desiredAccuracy = kCLLocationAccuracyBest
        requestLocationPermission()
    }
    
    func requestLocationPermission() {
        manager.requestWhenInUseAuthorization()
    }
    
    func locationManager(_ manager: CLLocationManager, didUpdateLocations locations: [CLLocation]) {
        currentLocation = locations.last
    }
    
    func locationManager(_ manager: CLLocationManager, didChangeAuthorization status: CLAuthorizationStatus) {
        switch status {
        case .authorizedWhenInUse, .authorizedAlways:
            manager.startUpdatingLocation()
        default:
            break
        }
    }
}

#Preview {
    LegacyMapTabView()
        .environmentObject(AuthenticationManager())
}
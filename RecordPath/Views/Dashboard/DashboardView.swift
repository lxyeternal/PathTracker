import SwiftUI

struct DashboardView: View {
    @EnvironmentObject var authManager: AuthenticationManager
    @StateObject private var pathTrackingManager = PathTrackingManager()
    @State private var selectedTab = 0
    
    var body: some View {
        TabView(selection: $selectedTab) {
            // Dashboard Tab
            HomeTabView(selectedTab: $selectedTab)
                .environmentObject(authManager)
                .environmentObject(pathTrackingManager)
                .tabItem {
                    Image(systemName: "house.fill")
                    Text("Home")
                }
                .tag(0)
            
            // Map Tab
            MapTabView()
                .environmentObject(authManager)
                .environmentObject(pathTrackingManager)
                .tabItem {
                    Image(systemName: "map.fill")
                    Text("Map")
                }
                .tag(1)
            
            // Record Tab
            RecordingView()
                .environmentObject(pathTrackingManager)
                .tabItem {
                    Image(systemName: "plus.circle.fill")
                    Text("Record")
                }
                .tag(2)
            
            // Timeline Tab
            TimelineView()
                .environmentObject(authManager)
                .tabItem {
                    Image(systemName: "clock.fill")
                    Text("Timeline")
                }
                .tag(3)
            
            // Profile Tab
            ProfileTabView()
                .environmentObject(authManager)
                .tabItem {
                    Image(systemName: "person.fill")
                    Text("Profile")
                }
                .tag(4)
        }
        .accentColor(.blue)
    }
}

struct HomeTabView: View {
    @EnvironmentObject var authManager: AuthenticationManager
    @EnvironmentObject var pathTrackingManager: PathTrackingManager
    @Binding var selectedTab: Int
    
    var body: some View {
        NavigationView {
            ScrollView {
                VStack(spacing: 24) {
                    // Beautiful Header with Gradient
                    headerSection
                    
                    // Enhanced Quick Stats
                    statsSection
                    
                    // Recent Adventures Section
                    recentAdventuresSection
                    
                    // World Map Preview
                    worldMapPreview
                    
                    // Countries Collection
                    countriesCollectionSection
                }
                .padding(.horizontal)
            }
            .background(
                LinearGradient(
                    gradient: Gradient(colors: [
                        Color.blue.opacity(0.05),
                        Color.purple.opacity(0.05),
                        Color.clear
                    ]),
                    startPoint: .topLeading,
                    endPoint: .bottomTrailing
                )
            )
            .navigationTitle("")
            .navigationBarTitleDisplayMode(.inline)
        }
    }
    
    private var headerSection: some View {
        VStack(spacing: 16) {
            HStack {
                VStack(alignment: .leading, spacing: 8) {
                    Text("Hello, \(authManager.currentUser?.username ?? "Traveler")! 👋")
                        .font(.title)
                        .fontWeight(.bold)
                        .foregroundColor(.primary)
                    
                    Text("Ready for your next adventure?")
                        .font(.subheadline)
                        .foregroundColor(.secondary)
                }
                
                Spacer()
                
                // Profile Image Placeholder
                Circle()
                    .fill(
                        LinearGradient(
                            gradient: Gradient(colors: [.blue, .purple]),
                            startPoint: .topLeading,
                            endPoint: .bottomTrailing
                        )
                    )
                    .frame(width: 60, height: 60)
                    .overlay(
                        Image(systemName: "person.fill")
                            .font(.title2)
                            .foregroundColor(.white)
                    )
            }
        }
        .padding(.top, 10)
    }
    
    private var statsSection: some View {
        VStack(spacing: 16) {
            HStack {
                Text("Your Journey")
                    .font(.headline)
                    .fontWeight(.semibold)
                Spacer()
            }
            
            HStack(spacing: 12) {
                EnhancedStatCard(
                    title: "Journeys",
                    value: "\(authManager.currentUser?.totalJourneys ?? 0)",
                    icon: "location.fill",
                    gradient: [.blue, .cyan]
                )
                
                EnhancedStatCard(
                    title: "Countries",
                    value: "\(authManager.currentUser?.visitedCountries.count ?? 0)",
                    icon: "globe",
                    gradient: [.green, .mint]
                )
                
                EnhancedStatCard(
                    title: "Photos",
                    value: "\(authManager.currentUser?.totalPhotos ?? 0)",
                    icon: "camera.fill",
                    gradient: [.orange, .yellow]
                )
            }
        }
    }
    
    private var recentAdventuresSection: some View {
        VStack(alignment: .leading, spacing: 16) {
            HStack {
                Text("Recent Adventures")
                    .font(.headline)
                    .fontWeight(.semibold)
                
                Spacer()
                
                Button(action: {
                    selectedTab = 3 // Switch to Timeline tab
                }) {
                    Text("See All")
                        .font(.subheadline)
                        .foregroundColor(.blue)
                }
            }
            
            if let user = authManager.currentUser {
                let recentJourneys = user.recentJourneys.prefix(3)
                
                if recentJourneys.isEmpty {
                    BeautifulEmptyState(
                        title: "No adventures yet",
                        message: "Start exploring and create amazing memories!",
                        icon: "airplane.departure",
                        color: .blue
                    )
                } else {
                    VStack(spacing: 12) {
                        ForEach(Array(recentJourneys), id: \.id) { journey in
                            EnhancedJourneyCard(journey: journey)
                        }
                    }
                }
            }
        }
    }
    
    private var worldMapPreview: some View {
        VStack(alignment: .leading, spacing: 16) {
            HStack {
                Text("Your Travel Map")
                    .font(.headline)
                    .fontWeight(.semibold)
                
                Spacer()
                
                Button(action: {
                    selectedTab = 1 // Switch to Map tab
                }) {
                    Text("Open Map")
                        .font(.subheadline)
                        .foregroundColor(.blue)
                }
            }
            
            // Map Preview Placeholder
            RoundedRectangle(cornerRadius: 16)
                .fill(
                    LinearGradient(
                        gradient: Gradient(colors: [
                            Color.blue.opacity(0.1),
                            Color.green.opacity(0.1)
                        ]),
                        startPoint: .topLeading,
                        endPoint: .bottomTrailing
                    )
                )
                .frame(height: 180)
                .overlay(
                    VStack(spacing: 8) {
                        Image(systemName: "map.fill")
                            .font(.system(size: 40))
                            .foregroundColor(.blue.opacity(0.7))
                        
                        Text("Interactive World Map")
                            .font(.headline)
                            .foregroundColor(.primary)
                        
                        Text("Tap to explore your traveled locations")
                            .font(.caption)
                            .foregroundColor(.secondary)
                            .multilineTextAlignment(.center)
                    }
                )
        }
    }
    
    private var countriesCollectionSection: some View {
        VStack(alignment: .leading, spacing: 16) {
            HStack {
                Text("Countries Explored")
                    .font(.headline)
                    .fontWeight(.semibold)
                
                Spacer()
                
                Text("\(authManager.currentUser?.visitedCountries.count ?? 0) countries")
                    .font(.caption)
                    .foregroundColor(.secondary)
            }
            
            if let user = authManager.currentUser {
                let countries = user.visitedCountries
                
                if countries.isEmpty {
                    BeautifulEmptyState(
                        title: "No countries visited",
                        message: "Start your global journey today!",
                        icon: "globe.americas.fill",
                        color: .green
                    )
                } else {
                    LazyVGrid(columns: Array(repeating: GridItem(.flexible()), count: 2), spacing: 12) {
                        ForEach(countries, id: \.self) { country in
                            EnhancedCountryCard(country: country)
                        }
                    }
                }
            }
        }
    }
}

struct EnhancedStatCard: View {
    let title: String
    let value: String
    let icon: String
    let gradient: [Color]
    
    var body: some View {
        VStack(spacing: 8) {
            Image(systemName: icon)
                .font(.title2)
                .foregroundColor(.white)
            
            Text(value)
                .font(.title2)
                .fontWeight(.bold)
                .foregroundColor(.white)
            
            Text(title)
                .font(.caption)
                .foregroundColor(.white.opacity(0.9))
        }
        .frame(maxWidth: .infinity)
        .frame(height: 100)
        .background(
            LinearGradient(
                gradient: Gradient(colors: gradient),
                startPoint: .topLeading,
                endPoint: .bottomTrailing
            )
        )
        .cornerRadius(16)
        .shadow(color: gradient.first?.opacity(0.3) ?? .clear, radius: 8, x: 0, y: 4)
    }
}

struct EnhancedJourneyCard: View {
    let journey: Journey
    
    var body: some View {
        HStack(spacing: 16) {
            // Journey Icon
            VStack {
                Circle()
                    .fill(LinearGradient(
                        gradient: Gradient(colors: [.blue.opacity(0.8), .purple.opacity(0.8)]),
                        startPoint: .topLeading,
                        endPoint: .bottomTrailing
                    ))
                    .frame(width: 50, height: 50)
                    .overlay(
                        Image(systemName: "location.north.line.fill")
                            .font(.title3)
                            .foregroundColor(.white)
                    )
            }
            
            VStack(alignment: .leading, spacing: 6) {
                Text(journey.title)
                    .font(.headline)
                    .fontWeight(.semibold)
                    .foregroundColor(.primary)
                
                HStack {
                    Image(systemName: "map.fill")
                        .font(.caption)
                        .foregroundColor(.secondary)
                    
                    Text(journey.formattedDistance)
                        .font(.subheadline)
                        .foregroundColor(.secondary)
                    
                    Image(systemName: "clock.fill")
                        .font(.caption)
                        .foregroundColor(.secondary)
                    
                    Text(journey.formattedDuration)
                        .font(.subheadline)
                        .foregroundColor(.secondary)
                }
                
                HStack {
                    Image(systemName: "calendar")
                        .font(.caption)
                        .foregroundColor(.secondary)
                    
                    Text(journey.endDate.formatted(date: .abbreviated, time: .shortened))
                        .font(.caption)
                        .foregroundColor(.secondary)
                    
                    Spacer()
                    
                    // Show countries visited in this journey
                    HStack(spacing: 2) {
                        ForEach(journey.visitedCountries.prefix(3), id: \.self) { country in
                            Text(getCountryFlag(country))
                                .font(.caption2)
                        }
                        if journey.visitedCountries.count > 3 {
                            Text("+\(journey.visitedCountries.count - 3)")
                                .font(.caption2)
                                .foregroundColor(.secondary)
                        }
                    }
                }
            }
            
            Spacer()
        }
        .padding(16)
        .background(Color(.systemBackground))
        .cornerRadius(16)
        .shadow(color: .black.opacity(0.05), radius: 8, x: 0, y: 2)
        .overlay(
            RoundedRectangle(cornerRadius: 16)
                .stroke(Color.gray.opacity(0.1), lineWidth: 1)
        )
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

// Note: Visit struct is from SimpleModels.swift - this component works with legacy Visit model

struct EnhancedCountryCard: View {
    let country: String
    
    var body: some View {
        VStack(spacing: 12) {
            // Country Flag/Icon
            Text(getCountryFlag(country))
                .font(.system(size: 40))
            
            VStack(spacing: 4) {
                Text(country)
                    .font(.subheadline)
                    .fontWeight(.semibold)
                    .foregroundColor(.primary)
                
                Text(getCountryLandmark(country))
                    .font(.caption)
                    .foregroundColor(.secondary)
                    .multilineTextAlignment(.center)
            }
        }
        .frame(maxWidth: .infinity)
        .frame(height: 120)
        .padding()
        .background(Color(.systemBackground))
        .cornerRadius(16)
        .shadow(color: .black.opacity(0.05), radius: 6, x: 0, y: 2)
        .overlay(
            RoundedRectangle(cornerRadius: 16)
                .stroke(getCountryAccentColor(country).opacity(0.3), lineWidth: 2)
        )
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
    
    private func getCountryLandmark(_ country: String) -> String {
        switch country.lowercased() {
        case "france": return "Eiffel Tower"
        case "japan": return "Mount Fuji"
        case "china": return "Great Wall"
        case "usa", "united states": return "Statue of Liberty"
        case "uk", "united kingdom": return "Big Ben"
        default: return "Beautiful Places"
        }
    }
    
    private func getCountryAccentColor(_ country: String) -> Color {
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

struct BeautifulEmptyState: View {
    let title: String
    let message: String
    let icon: String
    let color: Color
    
    var body: some View {
        VStack(spacing: 16) {
            Circle()
                .fill(color.opacity(0.1))
                .frame(width: 80, height: 80)
                .overlay(
                    Image(systemName: icon)
                        .font(.system(size: 30))
                        .foregroundColor(color)
                )
            
            VStack(spacing: 8) {
                Text(title)
                    .font(.headline)
                    .fontWeight(.semibold)
                    .foregroundColor(.primary)
                
                Text(message)
                    .font(.subheadline)
                    .foregroundColor(.secondary)
                    .multilineTextAlignment(.center)
            }
        }
        .frame(maxWidth: .infinity)
        .padding(.vertical, 32)
        .background(Color(.systemBackground))
        .cornerRadius(16)
        .shadow(color: .black.opacity(0.05), radius: 8, x: 0, y: 2)
    }
}

// Keep old components for compatibility
struct StatCard: View {
    let title: String
    let value: String
    let icon: String
    let color: Color
    
    var body: some View {
        VStack(spacing: 8) {
            Image(systemName: icon)
                .font(.title2)
                .foregroundColor(color)
            
            Text(value)
                .font(.title2)
                .fontWeight(.bold)
            
            Text(title)
                .font(.caption)
                .foregroundColor(.secondary)
        }
        .frame(maxWidth: .infinity)
        .padding()
        .background(Color.gray.opacity(0.1))
        .cornerRadius(12)
    }
}

struct RecentVisitCard: View {
    let visit: Visit
    
    var body: some View {
        HStack {
            VStack(alignment: .leading, spacing: 4) {
                Text(visit.locationName)
                    .font(.subheadline)
                    .fontWeight(.medium)
                
                Text(visit.formattedVisitDate)
                    .font(.caption)
                    .foregroundColor(.secondary)
                
                if visit.hasComment {
                    Text(visit.displayComment)
                        .font(.caption)
                        .foregroundColor(.secondary)
                        .lineLimit(2)
                }
            }
            
            Spacer()
            
            if visit.rating > 0 {
                Text(visit.ratingStars)
                    .font(.caption)
            }
        }
        .padding()
        .background(Color.gray.opacity(0.05))
        .cornerRadius(8)
    }
}

struct CountryCard: View {
    let country: String
    
    var body: some View {
        HStack {
            Image(systemName: "flag.fill")
                .foregroundColor(.blue)
            
            Text(country)
                .font(.subheadline)
                .fontWeight(.medium)
            
            Spacer()
        }
        .padding()
        .background(Color.gray.opacity(0.05))
        .cornerRadius(8)
    }
}

struct EmptyStateView: View {
    let title: String
    let message: String
    let icon: String
    
    var body: some View {
        VStack(spacing: 12) {
            Image(systemName: icon)
                .font(.system(size: 40))
                .foregroundColor(.gray)
            
            Text(title)
                .font(.headline)
                .foregroundColor(.primary)
            
            Text(message)
                .font(.subheadline)
                .foregroundColor(.secondary)
                .multilineTextAlignment(.center)
        }
        .frame(maxWidth: .infinity)
        .padding()
        .background(Color.gray.opacity(0.05))
        .cornerRadius(12)
    }
}


#Preview {
    DashboardView()
        .environmentObject(AuthenticationManager())
}
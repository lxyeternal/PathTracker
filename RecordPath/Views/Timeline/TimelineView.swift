import SwiftUI

struct TimelineView: View {
    @EnvironmentObject var authManager: AuthenticationManager
    @State private var selectedTimeFilter: TimeFilter = .thisMonth
    
    var body: some View {
        NavigationView {
            VStack {
                // Time Filter Picker
                Picker("Time Filter", selection: $selectedTimeFilter) {
                    ForEach(TimeFilter.allCases, id: \.self) { filter in
                        Text(filter.rawValue).tag(filter)
                    }
                }
                .pickerStyle(SegmentedPickerStyle())
                .padding()
                
                // Journey List
                ScrollView {
                    LazyVStack(spacing: 16) {
                        if let user = authManager.currentUser {
                            let filteredJourneys = getFilteredJourneys(user.journeys)
                            
                            if filteredJourneys.isEmpty {
                                EmptyStateView(
                                    title: "No journeys found",
                                    message: "No journeys found for the selected time period",
                                    icon: "clock.fill"
                                )
                            } else {
                                ForEach(filteredJourneys, id: \.id) { journey in
                                    TimelineJourneyCard(journey: journey)
                                }
                            }
                        } else {
                            EmptyStateView(
                                title: "No data",
                                message: "Please log in to see your journey timeline",
                                icon: "person.fill"
                            )
                        }
                    }
                    .padding()
                }
            }
            .navigationTitle("Timeline")
            .navigationBarTitleDisplayMode(.large)
        }
    }
    
    private func getFilteredJourneys(_ journeys: [Journey]) -> [Journey] {
        let (startDate, endDate) = selectedTimeFilter.dateRange()
        
        return journeys.filter { journey in
            journey.endDate >= startDate && journey.startDate <= endDate
        }.sorted { $0.endDate > $1.endDate }
    }
}

struct TimelineJourneyCard: View {
    let journey: Journey
    
    var body: some View {
        VStack(alignment: .leading, spacing: 16) {
            // Header
            HStack {
                VStack(alignment: .leading, spacing: 4) {
                    Text(journey.title)
                        .font(.headline)
                        .fontWeight(.semibold)
                    
                    Text(journey.endDate.formatted(date: .abbreviated, time: .omitted))
                        .font(.caption)
                        .foregroundColor(.secondary)
                }
                
                Spacer()
                
                // Countries visited
                HStack(spacing: 4) {
                    ForEach(journey.visitedCountries.prefix(3), id: \.self) { country in
                        Text(getCountryFlag(country))
                            .font(.title2)
                    }
                    if journey.visitedCountries.count > 3 {
                        Text("+\(journey.visitedCountries.count - 3)")
                            .font(.caption)
                            .foregroundColor(.secondary)
                    }
                }
            }
            
            // Stats
            HStack(spacing: 20) {
                TimelineStatItem(
                    icon: "map.fill",
                    title: "Distance",
                    value: journey.formattedDistance,
                    color: .blue
                )
                
                TimelineStatItem(
                    icon: "clock.fill",
                    title: "Duration",
                    value: journey.formattedDuration,
                    color: .green
                )
                
                TimelineStatItem(
                    icon: "location.fill",
                    title: "Segments",
                    value: "\(journey.segments.count)",
                    color: .orange
                )
                
                Spacer()
            }
            
            // Notes
            if !journey.notes.isEmpty {
                VStack(alignment: .leading, spacing: 8) {
                    Text("Notes")
                        .font(.subheadline)
                        .fontWeight(.medium)
                    
                    Text(journey.notes)
                        .font(.body)
                        .foregroundColor(.secondary)
                        .fixedSize(horizontal: false, vertical: true)
                }
            }
        }
        .padding()
        .background(Color(.systemBackground))
        .cornerRadius(16)
        .shadow(color: .black.opacity(0.05), radius: 8, x: 0, y: 2)
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

struct TimelineStatItem: View {
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

#Preview {
    TimelineView()
        .environmentObject(AuthenticationManager())
}
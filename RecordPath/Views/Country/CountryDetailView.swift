//
//  CountryDetailView.swift
//  RecordPath
//
//  国家详情页面
//

import SwiftUI
import MapKit

struct CountryDetailView: View {
    let country: String
    let journeys: [Journey]
    @Environment(\.dismiss) private var dismiss
    @State private var selectedJourney: Journey?
    @State private var showingJourneyDetail = false
    
    var body: some View {
        ScrollView {
            VStack(spacing: 24) {
                // Header Section
                headerSection
                
                // Stats Section
                statsSection
                
                // Journeys List Section
                journeysSection
                
                // Cities Visited Section
                citiesSection
            }
            .padding()
        }
        .background(
            LinearGradient(
                gradient: Gradient(colors: [
                    getCountryAccentColor(country).opacity(0.05),
                    Color.clear
                ]),
                startPoint: .topLeading,
                endPoint: .bottomTrailing
            )
        )
        .navigationTitle(country)
        .navigationBarTitleDisplayMode(.large)
        .navigationBarBackButtonHidden(false)
        .sheet(isPresented: $showingJourneyDetail) {
            if let journey = selectedJourney {
                NavigationView {
                    JourneyDetailView(journey: journey)
                        .navigationBarItems(
                            trailing: Button("完成") {
                                showingJourneyDetail = false
                                selectedJourney = nil
                            }
                        )
                }
            }
        }
    }
    
    private var headerSection: some View {
        VStack(spacing: 20) {
            // Country Flag
            Text(getCountryFlag(country))
                .font(.system(size: 80))
                .shadow(color: .black.opacity(0.1), radius: 4, x: 0, y: 2)
            
            VStack(spacing: 8) {
                Text(country)
                    .font(.title)
                    .fontWeight(.bold)
                    .foregroundColor(.primary)
                
                Text(getCountryDescription(country))
                    .font(.subheadline)
                    .foregroundColor(.secondary)
                    .multilineTextAlignment(.center)
                    .padding(.horizontal)
            }
        }
        .frame(maxWidth: .infinity)
        .padding(.vertical, 30)
        .background(
            RoundedRectangle(cornerRadius: 24)
                .fill(Color(.systemBackground))
                .shadow(color: .black.opacity(0.05), radius: 15, x: 0, y: 8)
        )
    }
    
    private var statsSection: some View {
        VStack(spacing: 16) {
            HStack {
                Text("访问统计")
                    .font(.headline)
                    .fontWeight(.semibold)
                Spacer()
            }
            
            LazyVGrid(columns: Array(repeating: GridItem(.flexible()), count: 2), spacing: 16) {
                CountryStatCard(
                    title: "总行程",
                    value: "\(journeys.count)",
                    icon: "location.north.line.fill",
                    color: getCountryAccentColor(country)
                )
                
                CountryStatCard(
                    title: "总距离",
                    value: formatTotalDistance(),
                    icon: "map.fill",
                    color: .blue
                )
                
                CountryStatCard(
                    title: "总时长",
                    value: formatTotalDuration(),
                    icon: "clock.fill",
                    color: .green
                )
                
                CountryStatCard(
                    title: "访问城市",
                    value: "\(getVisitedCities().count)",
                    icon: "building.2.fill",
                    color: .orange
                )
            }
        }
        .padding(20)
        .background(Color(.systemBackground))
        .cornerRadius(20)
        .shadow(color: .black.opacity(0.05), radius: 10, x: 0, y: 5)
    }
    
    private var journeysSection: some View {
        VStack(spacing: 16) {
            HStack {
                Text("在\(country)的行程")
                    .font(.headline)
                    .fontWeight(.semibold)
                
                Spacer()
                
                Text("\(journeys.count) 个行程")
                    .font(.caption)
                    .foregroundColor(.secondary)
            }
            
            if journeys.isEmpty {
                EmptyStateView(
                    title: "暂无行程",
                    message: "还没有在\(country)的旅行记录",
                    icon: "airplane.departure"
                )
            } else {
                ForEach(journeys.sorted { $0.endDate > $1.endDate }, id: \.id) { journey in
                    Button(action: {
                        selectedJourney = journey
                        showingJourneyDetail = true
                    }) {
                        CountryJourneyCard(journey: journey, country: country)
                    }
                    .buttonStyle(PlainButtonStyle())
                }
            }
        }
        .padding(20)
        .background(Color(.systemBackground))
        .cornerRadius(20)
        .shadow(color: .black.opacity(0.05), radius: 10, x: 0, y: 5)
    }
    
    private var citiesSection: some View {
        let cities = getVisitedCities()
        
        return VStack(spacing: 16) {
            HStack {
                Text("访问过的城市")
                    .font(.headline)
                    .fontWeight(.semibold)
                
                Spacer()
                
                Text("\(cities.count) 个城市")
                    .font(.caption)
                    .foregroundColor(.secondary)
            }
            
            if cities.isEmpty {
                Text("暂无城市数据")
                    .font(.subheadline)
                    .foregroundColor(.secondary)
                    .frame(maxWidth: .infinity)
                    .padding()
                    .background(Color.gray.opacity(0.05))
                    .cornerRadius(12)
            } else {
                LazyVGrid(columns: Array(repeating: GridItem(.flexible()), count: 2), spacing: 12) {
                    ForEach(cities, id: \.self) { city in
                        CityCard(city: city, country: country)
                    }
                }
            }
        }
        .padding(20)
        .background(Color(.systemBackground))
        .cornerRadius(20)
        .shadow(color: .black.opacity(0.05), radius: 10, x: 0, y: 5)
    }
    
    // MARK: - Helper Methods
    
    private func getVisitedCities() -> [String] {
        let allCities = journeys.flatMap { $0.visitedCities }
        return Array(Set(allCities)).sorted()
    }
    
    private func formatTotalDistance() -> String {
        let totalDistance = journeys.reduce(0) { $0 + $1.totalDistance }
        if totalDistance < 1000 {
            return String(format: "%.0f m", totalDistance)
        } else {
            return String(format: "%.1f km", totalDistance / 1000)
        }
    }
    
    private func formatTotalDuration() -> String {
        let totalDuration = journeys.reduce(0) { $0 + $1.totalDuration }
        let hours = Int(totalDuration / 3600)
        let minutes = Int((totalDuration.truncatingRemainder(dividingBy: 3600)) / 60)
        
        if hours > 0 {
            return "\(hours)h \(minutes)m"
        } else {
            return "\(minutes)m"
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
    
    private func getCountryDescription(_ country: String) -> String {
        switch country.lowercased() {
        case "france": return "浪漫之都，艺术与文化的完美融合"
        case "japan": return "传统与现代交织的神奇国度"
        case "china": return "历史悠久的文明古国，风景秀美"
        case "usa", "united states": return "自由之地，梦想起航的地方"
        case "uk", "united kingdom": return "绅士之国，历史与现代并存"
        default: return "探索世界的美丽角落"
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

// MARK: - Supporting Views

struct CountryStatCard: View {
    let title: String
    let value: String
    let icon: String
    let color: Color
    
    var body: some View {
        VStack(spacing: 12) {
            Circle()
                .fill(color.opacity(0.1))
                .frame(width: 50, height: 50)
                .overlay(
                    Image(systemName: icon)
                        .font(.title3)
                        .foregroundColor(color)
                )
            
            VStack(spacing: 4) {
                Text(value)
                    .font(.headline)
                    .fontWeight(.bold)
                    .foregroundColor(.primary)
                
                Text(title)
                    .font(.caption)
                    .foregroundColor(.secondary)
            }
        }
        .frame(maxWidth: .infinity)
        .padding(.vertical, 20)
        .background(
            RoundedRectangle(cornerRadius: 16)
                .fill(color.opacity(0.03))
                .overlay(
                    RoundedRectangle(cornerRadius: 16)
                        .stroke(color.opacity(0.2), lineWidth: 1)
                )
        )
    }
}

struct CountryJourneyCard: View {
    let journey: Journey
    let country: String
    
    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack {
                VStack(alignment: .leading, spacing: 4) {
                    Text(journey.title)
                        .font(.headline)
                        .fontWeight(.semibold)
                        .foregroundColor(.primary)
                    
                    Text(journey.endDate.formatted(date: .abbreviated, time: .omitted))
                        .font(.caption)
                        .foregroundColor(.secondary)
                }
                
                Spacer()
                
                Image(systemName: "chevron.right")
                    .font(.caption)
                    .foregroundColor(.secondary)
            }
            
            HStack(spacing: 20) {
                HStack(spacing: 4) {
                    Image(systemName: "map")
                        .font(.caption2)
                        .foregroundColor(.blue)
                    
                    Text(journey.formattedDistance)
                        .font(.caption)
                        .foregroundColor(.secondary)
                }
                
                HStack(spacing: 4) {
                    Image(systemName: "clock")
                        .font(.caption2)
                        .foregroundColor(.green)
                    
                    Text(journey.formattedDuration)
                        .font(.caption)
                        .foregroundColor(.secondary)
                }
                
                HStack(spacing: 4) {
                    Image(systemName: "camera")
                        .font(.caption2)
                        .foregroundColor(.orange)
                    
                    Text("\(journey.photos.count)")
                        .font(.caption)
                        .foregroundColor(.secondary)
                }
                
                Spacer()
            }
            
            if !journey.notes.isEmpty {
                Text(journey.notes)
                    .font(.caption)
                    .foregroundColor(.secondary)
                    .lineLimit(2)
                    .padding(.top, 4)
            }
        }
        .padding(16)
        .background(Color.gray.opacity(0.03))
        .cornerRadius(12)
        .overlay(
            RoundedRectangle(cornerRadius: 12)
                .stroke(Color.gray.opacity(0.1), lineWidth: 1)
        )
    }
}

struct CityCard: View {
    let city: String
    let country: String
    
    var body: some View {
        VStack(spacing: 8) {
            Circle()
                .fill(LinearGradient(
                    gradient: Gradient(colors: [
                        getCountryAccentColor(country).opacity(0.6),
                        getCountryAccentColor(country).opacity(0.3)
                    ]),
                    startPoint: .topLeading,
                    endPoint: .bottomTrailing
                ))
                .frame(width: 50, height: 50)
                .overlay(
                    Image(systemName: "building.2.fill")
                        .font(.title3)
                        .foregroundColor(.white)
                )
            
            VStack(spacing: 4) {
                Text(city)
                    .font(.subheadline)
                    .fontWeight(.semibold)
                    .foregroundColor(.primary)
                    .multilineTextAlignment(.center)
                
                Text(getCityDescription(city))
                    .font(.caption2)
                    .foregroundColor(.secondary)
                    .multilineTextAlignment(.center)
            }
        }
        .frame(maxWidth: .infinity)
        .frame(height: 120)
        .padding()
        .background(Color.gray.opacity(0.03))
        .cornerRadius(16)
        .overlay(
            RoundedRectangle(cornerRadius: 16)
                .stroke(getCountryAccentColor(country).opacity(0.2), lineWidth: 1)
        )
    }
    
    private func getCityDescription(_ city: String) -> String {
        switch city.lowercased() {
        case "paris": return "光之城"
        case "tokyo": return "现代都市"
        case "beijing": return "古都新韵"
        case "new york": return "不夜城"
        case "london": return "雾都"
        default: return "美丽城市"
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

#Preview {
    NavigationView {
        CountryDetailView(
            country: "法国",
            journeys: [
                Journey(title: "巴黎之旅", startDate: Date(), endDate: Date()),
                Journey(title: "马赛探索", startDate: Date(), endDate: Date())
            ]
        )
    }
}
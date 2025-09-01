//
//  AllCountriesView.swift
//  RecordPath
//
//  所有国家列表页面
//

import SwiftUI

struct AllCountriesView: View {
    @EnvironmentObject var authManager: AuthenticationManager
    @State private var searchText = ""
    
    var body: some View {
        VStack {
            if let user = authManager.currentUser {
                let countries = filteredCountries(user.visitedCountries)
                
                if countries.isEmpty {
                    emptyStateView
                } else {
                    ScrollView {
                        LazyVGrid(columns: Array(repeating: GridItem(.flexible()), count: 2), spacing: 16) {
                            ForEach(countries, id: \.self) { country in
                                NavigationLink(destination: CountryDetailView(
                                    country: country,
                                    journeys: getJourneysForCountry(country)
                                )) {
                                    CountryGridCard(country: country)
                                }
                                .buttonStyle(PlainButtonStyle())
                            }
                        }
                        .padding()
                    }
                    .searchable(text: $searchText, prompt: "搜索国家")
                }
            } else {
                Text("请先登录")
                    .foregroundColor(.secondary)
            }
        }
        .navigationTitle("探索过的国家")
        .navigationBarTitleDisplayMode(.large)
        .background(
            LinearGradient(
                gradient: Gradient(colors: [
                    Color.blue.opacity(0.03),
                    Color.clear
                ]),
                startPoint: .top,
                endPoint: .bottom
            )
        )
    }
    
    private var emptyStateView: some View {
        VStack(spacing: 20) {
            Image(systemName: "globe.americas")
                .font(.system(size: 60))
                .foregroundColor(.gray.opacity(0.6))
            
            Text("还没有访问过任何国家")
                .font(.title2)
                .fontWeight(.semibold)
                .foregroundColor(.primary)
            
            Text("开始你的环球之旅，留下足迹吧！")
                .font(.body)
                .foregroundColor(.secondary)
                .multilineTextAlignment(.center)
                .padding(.horizontal)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .background(Color(.systemBackground))
    }
    
    private func filteredCountries(_ countries: [String]) -> [String] {
        if searchText.isEmpty {
            return countries.sorted()
        } else {
            return countries.filter { $0.localizedCaseInsensitiveContains(searchText) }.sorted()
        }
    }
    
    private func getJourneysForCountry(_ country: String) -> [Journey] {
        guard let user = authManager.currentUser else { return [] }
        return user.journeys.filter { journey in
            journey.visitedCountries.contains(country)
        }
    }
}

struct CountryGridCard: View {
    let country: String
    @EnvironmentObject var authManager: AuthenticationManager
    
    private var journeyCount: Int {
        guard let user = authManager.currentUser else { return 0 }
        return user.journeys.filter { $0.visitedCountries.contains(country) }.count
    }
    
    var body: some View {
        VStack(spacing: 16) {
            // Country Flag
            Text(getCountryFlag(country))
                .font(.system(size: 50))
                .shadow(color: .black.opacity(0.1), radius: 4, x: 0, y: 2)
            
            VStack(spacing: 8) {
                Text(country)
                    .font(.headline)
                    .fontWeight(.semibold)
                    .foregroundColor(.primary)
                    .multilineTextAlignment(.center)
                
                Text("\(journeyCount) 个行程")
                    .font(.caption)
                    .foregroundColor(.secondary)
                
                Text(getCountryLandmark(country))
                    .font(.caption2)
                    .foregroundColor(.secondary)
                    .multilineTextAlignment(.center)
            }
        }
        .frame(maxWidth: .infinity)
        .frame(height: 160)
        .padding()
        .background(
            RoundedRectangle(cornerRadius: 20)
                .fill(Color(.systemBackground))
                .shadow(color: .black.opacity(0.05), radius: 10, x: 0, y: 5)
        )
        .overlay(
            RoundedRectangle(cornerRadius: 20)
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
        case "france": return "埃菲尔铁塔"
        case "japan": return "富士山"
        case "china": return "长城"
        case "usa", "united states": return "自由女神像"
        case "uk", "united kingdom": return "大本钟"
        default: return "美丽的地方"
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
        AllCountriesView()
            .environmentObject(AuthenticationManager())
    }
}
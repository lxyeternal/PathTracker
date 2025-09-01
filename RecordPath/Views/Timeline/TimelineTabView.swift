import SwiftUI
import CoreLocation

struct TimelineTabView: View {
    @EnvironmentObject var authManager: AuthenticationManager
    @State private var selectedTimeFilter: TimeFilter = .thisMonth
    @State private var showingCustomDatePicker = false
    @State private var customStartDate = Date()
    @State private var customEndDate = Date()
    @State private var searchText = ""
    @State private var selectedJourney: Journey?
    @State private var showingJourneyDetail = false
    
    var body: some View {
        NavigationView {
            VStack(spacing: 0) {
                // Time Filter Picker
                timeFilterSection
                
                // Search Bar
                searchSection
                
                // Statistics Summary
                statisticsSection
                
                // Journey Timeline
                journeyTimelineSection
            }
            .navigationTitle("时间线")
            .navigationBarTitleDisplayMode(.inline)
            .navigationBarItems(
                trailing: Button(action: { showingCustomDatePicker = true }) {
                    Image(systemName: "calendar.badge.plus")
                }
            )
        }
        .sheet(isPresented: $showingCustomDatePicker) {
            CustomDateRangeSheet(
                startDate: $customStartDate,
                endDate: $customEndDate,
                onApply: {
                    selectedTimeFilter = .custom
                    showingCustomDatePicker = false
                }
            )
        }
        .sheet(isPresented: $showingJourneyDetail) {
            if let journey = selectedJourney {
                JourneyDetailSheet(journey: journey)
            }
        }
    }
    
    private var timeFilterSection: some View {
        ScrollView(.horizontal, showsIndicators: false) {
            HStack(spacing: 12) {
                ForEach(TimeFilter.allCases, id: \.self) { filter in
                    TimeFilterChip(
                        filter: filter,
                        isSelected: selectedTimeFilter == filter,
                        onTap: { selectedTimeFilter = filter }
                    )
                }
            }
            .padding(.horizontal)
        }
        .padding(.vertical, 8)
        .background(Color(.systemBackground))
    }
    
    private var searchSection: some View {
        HStack {
            Image(systemName: "magnifyingglass")
                .foregroundColor(.secondary)
            
            TextField("搜索行程...", text: $searchText)
                .textFieldStyle(PlainTextFieldStyle())
        }
        .padding()
        .background(Color(.systemGray6))
        .cornerRadius(12)
        .padding(.horizontal)
        .padding(.bottom, 8)
    }
    
    private var statisticsSection: some View {
        VStack(spacing: 16) {
            HStack {
                Text("摘要")
                    .font(.headline)
                    .fontWeight(.semibold)
                Spacer()
                Text(selectedTimeFilter.rawValue)
                    .font(.caption)
                    .foregroundColor(.secondary)
            }
            
            HStack(spacing: 16) {
                SummaryCard(
                    title: "行程",
                    value: "\(filteredJourneys.count)",
                    icon: "location.north.line.fill",
                    color: .blue
                )
                
                SummaryCard(
                    title: "距离",
                    value: totalDistance,
                    icon: "map.fill",
                    color: .green
                )
                
                SummaryCard(
                    title: "时长",
                    value: totalDuration,
                    icon: "clock.fill",
                    color: .orange
                )
                
                SummaryCard(
                    title: "国家",
                    value: "\(uniqueCountries.count)",
                    icon: "globe",
                    color: .purple
                )
            }
        }
        .padding()
        .background(Color(.systemBackground))
        .cornerRadius(16)
        .shadow(color: .black.opacity(0.05), radius: 8, x: 0, y: 2)
        .padding(.horizontal)
        .padding(.bottom, 8)
    }
    
    private var journeyTimelineSection: some View {
        ScrollView {
            LazyVStack(spacing: 16) {
                if filteredJourneys.isEmpty {
                    EmptyTimelineView(filter: selectedTimeFilter)
                } else {
                    ForEach(groupedJourneys.keys.sorted(by: >), id: \.self) { date in
                        VStack(alignment: .leading, spacing: 12) {
                            HStack {
                                Text(formatSectionDate(date))
                                    .font(.headline)
                                    .fontWeight(.semibold)
                                    .foregroundColor(.primary)
                                
                                Spacer()
                                
                                Text("\(groupedJourneys[date]?.count ?? 0) 个行程")
                                    .font(.caption)
                                    .foregroundColor(.secondary)
                            }
                            .padding(.horizontal)
                            
                            ForEach(groupedJourneys[date] ?? []) { journey in
                                Button(action: {
                                    selectedJourney = journey
                                    showingJourneyDetail = true
                                }) {
                                    HStack(spacing: 16) {
                                        VStack(alignment: .leading, spacing: 8) {
                                            Text(journey.title)
                                                .font(.headline)
                                                .fontWeight(.semibold)
                                                .foregroundColor(.primary)
                                            
                                            HStack(spacing: 16) {
                                                Label(journey.formattedDistance, systemImage: "map.fill")
                                                Label(journey.formattedDuration, systemImage: "clock.fill")
                                            }
                                            .font(.caption)
                                            .foregroundColor(.secondary)
                                        }
                                        
                                        Spacer()
                                        
                                        HStack(spacing: 2) {
                                            ForEach(journey.visitedCountries.prefix(3), id: \.self) { country in
                                                Text(getCountryFlag(country))
                                                    .font(.caption)
                                            }
                                        }
                                    }
                                    .padding()
                                    .background(Color(.systemBackground))
                                    .cornerRadius(16)
                                    .shadow(color: .black.opacity(0.05), radius: 8, x: 0, y: 2)
                                }
                                .buttonStyle(PlainButtonStyle())
                            }
                        }
                    }
                }
            }
            .padding(.horizontal)
            .padding(.bottom, 100) // Space for tab bar
        }
    }
    
    private var filteredJourneys: [Journey] {
        guard let user = authManager.currentUser else { return [] }
        
        let (startDate, endDate): (Date, Date)
        if selectedTimeFilter == .custom {
            startDate = customStartDate
            endDate = customEndDate
        } else {
            let range = selectedTimeFilter.dateRange()
            startDate = range.start
            endDate = range.end
        }
        
        var journeys = user.journeys.filter { journey in
            journey.endDate >= startDate && journey.startDate <= endDate
        }
        
        if !searchText.isEmpty {
            journeys = journeys.filter { journey in
                journey.title.localizedCaseInsensitiveContains(searchText) ||
                journey.notes.localizedCaseInsensitiveContains(searchText) ||
                journey.visitedCountries.contains { $0.localizedCaseInsensitiveContains(searchText) } ||
                journey.visitedCities.contains { $0.localizedCaseInsensitiveContains(searchText) }
            }
        }
        
        return journeys.sorted { $0.endDate > $1.endDate }
    }
    
    private var groupedJourneys: [Date: [Journey]] {
        let calendar = Calendar.current
        return Dictionary(grouping: filteredJourneys) { journey in
            calendar.startOfDay(for: journey.endDate)
        }
    }
    
    private var totalDistance: String {
        let distance = filteredJourneys.reduce(0) { $0 + $1.totalDistance }
        if distance < 1000 {
            return String(format: "%.0f m", distance)
        } else {
            return String(format: "%.1f km", distance / 1000)
        }
    }
    
    private var totalDuration: String {
        let duration = filteredJourneys.reduce(0) { $0 + $1.totalDuration }
        let hours = Int(duration / 3600)
        let minutes = Int((duration.truncatingRemainder(dividingBy: 3600)) / 60)
        
        if hours > 0 {
            return "\(hours)h \(minutes)m"
        } else {
            return "\(minutes)m"
        }
    }
    
    private var uniqueCountries: Set<String> {
        Set(filteredJourneys.flatMap { $0.visitedCountries })
    }
    
    private func formatSectionDate(_ date: Date) -> String {
        let calendar = Calendar.current
        if calendar.isDateInToday(date) {
            return "今天"
        } else if calendar.isDateInYesterday(date) {
            return "昨天"
        } else {
            let formatter = DateFormatter()
            formatter.dateFormat = "yyyy年MM月dd日"
            return formatter.string(from: date)
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

struct TimeFilterChip: View {
    let filter: TimeFilter
    let isSelected: Bool
    let onTap: () -> Void
    
    var body: some View {
        Button(action: onTap) {
            HStack(spacing: 6) {
                Image(systemName: filter.icon)
                    .font(.caption)
                
                Text(filter.rawValue)
                    .font(.subheadline)
                    .fontWeight(.medium)
            }
            .padding(.horizontal, 16)
            .padding(.vertical, 8)
            .background(
                isSelected ?
                LinearGradient(gradient: Gradient(colors: [.blue, .purple]), startPoint: .leading, endPoint: .trailing) :
                LinearGradient(gradient: Gradient(colors: [Color(.systemGray5), Color(.systemGray5)]), startPoint: .leading, endPoint: .trailing)
            )
            .foregroundColor(isSelected ? .white : .primary)
            .cornerRadius(20)
            .shadow(color: isSelected ? .blue.opacity(0.3) : .clear, radius: 4, x: 0, y: 2)
        }
    }
}

struct SummaryCard: View {
    let title: String
    let value: String
    let icon: String
    let color: Color
    
    var body: some View {
        VStack(spacing: 8) {
            Image(systemName: icon)
                .font(.title3)
                .foregroundColor(color)
            
            Text(value)
                .font(.headline)
                .fontWeight(.bold)
                .foregroundColor(.primary)
            
            Text(title)
                .font(.caption)
                .foregroundColor(.secondary)
        }
        .frame(maxWidth: .infinity)
        .padding()
        .background(Color(.systemGray6))
        .cornerRadius(12)
    }
}

struct EmptyTimelineView: View {
    let filter: TimeFilter
    
    var body: some View {
        VStack(spacing: 20) {
            Image(systemName: "clock.arrow.circlepath")
                .font(.system(size: 60))
                .foregroundColor(.gray.opacity(0.6))
            
            VStack(spacing: 8) {
                Text("没有 \(filter.rawValue.lowercased()) 的行程")
                    .font(.headline)
                    .fontWeight(.semibold)
                    .foregroundColor(.primary)
                
                Text("开始记录您的旅行以在此处查看")
                    .font(.subheadline)
                    .foregroundColor(.secondary)
                    .multilineTextAlignment(.center)
            }
            
            Button("开始记录") {
                // Switch to recording tab
            }
            .font(.headline)
            .foregroundColor(.white)
            .padding(.horizontal, 24)
            .padding(.vertical, 12)
            .background(
                LinearGradient(gradient: Gradient(colors: [.blue, .purple]), startPoint: .leading, endPoint: .trailing)
            )
            .cornerRadius(25)
            .shadow(color: .blue.opacity(0.3), radius: 8, x: 0, y: 4)
        }
        .frame(maxWidth: .infinity)
        .padding(.vertical, 80)
    }
}

struct CustomDateRangeSheet: View {
    @Binding var startDate: Date
    @Binding var endDate: Date
    let onApply: () -> Void
    @Environment(\.dismiss) private var dismiss
    
    var body: some View {
        NavigationView {
            VStack(spacing: 24) {
                VStack(spacing: 16) {
                    Text("自定义日期范围")
                        .font(.title2)
                        .fontWeight(.bold)
                    
                    Text("为您的时间线选择日期范围")
                        .font(.subheadline)
                        .foregroundColor(.secondary)
                        .multilineTextAlignment(.center)
                }
                
                VStack(spacing: 20) {
                    VStack(alignment: .leading, spacing: 8) {
                        Text("开始日期")
                            .font(.headline)
                            .fontWeight(.medium)
                        
                        DatePicker("开始日期", selection: $startDate, displayedComponents: .date)
                            .datePickerStyle(GraphicalDatePickerStyle())
                    }
                    
                    VStack(alignment: .leading, spacing: 8) {
                        Text("结束日期")
                            .font(.headline)
                            .fontWeight(.medium)
                        
                        DatePicker("结束日期", selection: $endDate, in: startDate..., displayedComponents: .date)
                            .datePickerStyle(GraphicalDatePickerStyle())
                    }
                }
                
                Button(action: onApply) {
                    Text("应用筛选")
                        .frame(maxWidth: .infinity)
                        .frame(height: 50)
                        .background(
                            LinearGradient(gradient: Gradient(colors: [.blue, .purple]), startPoint: .leading, endPoint: .trailing)
                        )
                        .foregroundColor(.white)
                        .cornerRadius(25)
                        .shadow(color: .blue.opacity(0.3), radius: 8, x: 0, y: 4)
                }
                .padding(.top, 20)
                
                Spacer()
            }
            .padding()
            .navigationTitle("日期范围")
            .navigationBarTitleDisplayMode(.inline)
            .navigationBarItems(
                trailing: Button("取消") { dismiss() }
            )
        }
        .onAppear {
            // Ensure end date is not before start date
            if endDate < startDate {
                endDate = startDate
            }
        }
    }
}

struct JourneyDetailSheet: View {
    let journey: Journey
    @Environment(\.dismiss) private var dismiss
    
    var body: some View {
        NavigationView {
            ScrollView {
                VStack(spacing: 24) {
                    // Header
                    VStack(spacing: 16) {
                        Text(journey.title)
                            .font(.title)
                            .fontWeight(.bold)
                            .multilineTextAlignment(.center)
                        
                        HStack {
                            Text(journey.startDate.formatted(date: .abbreviated, time: .shortened))
                            Text("→")
                                .foregroundColor(.secondary)
                            Text(journey.endDate.formatted(date: .abbreviated, time: .shortened))
                        }
                        .font(.subheadline)
                        .foregroundColor(.secondary)
                    }
                    
                    // Statistics
                    LazyVGrid(columns: Array(repeating: GridItem(.flexible()), count: 2), spacing: 16) {
                        DetailStatCard(title: "距离", value: journey.formattedDistance, icon: "map.fill", color: .blue)
                        DetailStatCard(title: "时长", value: journey.formattedDuration, icon: "clock.fill", color: .green)
                        DetailStatCard(title: "路段", value: "\(journey.segments.count)", icon: "point.3.connected.trianglepath.dotted", color: .orange)
                        DetailStatCard(title: "国家", value: "\(journey.visitedCountries.count)", icon: "globe", color: .purple)
                    }
                    
                    // Notes
                    if !journey.notes.isEmpty {
                        VStack(alignment: .leading, spacing: 12) {
                            Text("笔记")
                                .font(.headline)
                                .fontWeight(.semibold)
                            
                            Text(journey.notes)
                                .font(.body)
                                .foregroundColor(.secondary)
                        }
                        .frame(maxWidth: .infinity, alignment: .leading)
                        .padding()
                        .background(Color(.systemGray6))
                        .cornerRadius(12)
                    }
                    
                    // Countries and Cities
                    VStack(spacing: 16) {
                        if !journey.visitedCountries.isEmpty {
                            VStack(alignment: .leading, spacing: 12) {
                                Text("访问过的国家")
                                    .font(.headline)
                                    .fontWeight(.semibold)
                                
                                LazyVGrid(columns: Array(repeating: GridItem(.flexible()), count: 2), spacing: 8) {
                                    ForEach(journey.visitedCountries, id: \.self) { country in
                                        CountryBadge(country: country)
                                    }
                                }
                            }
                        }
                        
                        if !journey.visitedCities.isEmpty {
                            VStack(alignment: .leading, spacing: 12) {
                                Text("访问过的城市")
                                    .font(.headline)
                                    .fontWeight(.semibold)
                                
                                LazyVGrid(columns: Array(repeating: GridItem(.flexible()), count: 2), spacing: 8) {
                                    ForEach(journey.visitedCities, id: \.self) { city in
                                        CityBadge(city: city)
                                    }
                                }
                            }
                        }
                    }
                    
                    Spacer(minLength: 50)
                }
                .padding()
            }
            .navigationTitle("行程详情")
            .navigationBarTitleDisplayMode(.inline)
            .navigationBarItems(
                trailing: Button("完成") { dismiss() }
            )
        }
    }
}

struct DetailStatCard: View {
    let title: String
    let value: String
    let icon: String
    let color: Color
    
    var body: some View {
        VStack(spacing: 12) {
            Image(systemName: icon)
                .font(.title2)
                .foregroundColor(color)
            
            Text(value)
                .font(.title2)
                .fontWeight(.bold)
                .foregroundColor(.primary)
            
            Text(title)
                .font(.caption)
                .foregroundColor(.secondary)
        }
        .frame(maxWidth: .infinity)
        .padding()
        .background(Color(.systemBackground))
        .cornerRadius(16)
        .shadow(color: .black.opacity(0.05), radius: 8, x: 0, y: 2)
        .overlay(
            RoundedRectangle(cornerRadius: 16)
                .stroke(color.opacity(0.3), lineWidth: 1)
        )
    }
}

struct CityBadge: View {
    let city: String
    
    var body: some View {
        HStack(spacing: 8) {
            Image(systemName: "building.2.fill")
                .font(.caption)
                .foregroundColor(.blue)
            
            Text(city)
                .font(.subheadline)
                .fontWeight(.medium)
        }
        .padding(.horizontal, 12)
        .padding(.vertical, 6)
        .background(Color.blue.opacity(0.1))
        .cornerRadius(16)
    }
}

#Preview {
    TimelineTabView()
        .environmentObject(AuthenticationManager())
}
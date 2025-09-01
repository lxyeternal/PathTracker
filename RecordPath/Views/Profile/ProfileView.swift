import SwiftUI
import PhotosUI

struct ProfileTabView: View {
    @EnvironmentObject var authManager: AuthenticationManager
    @State private var showingImagePicker = false
    @State private var showingEditProfile = false
    @State private var selectedPhotoItem: PhotosPickerItem?
    @State private var profileImage: UIImage?
    
    // Settings sheets
    @State private var showingPrivacySettings = false
    @State private var showingNotificationSettings = false
    @State private var showingExportData = false
    @State private var showingHelpSupport = false
    
    var body: some View {
        NavigationView {
            ScrollView {
                VStack(spacing: 24) {
                    // Profile Header
                    profileHeaderSection
                    
                    // Stats Section
                    statsSection
                    
                    // Travel Summary
                    travelSummarySection
                    
                    // Settings
                    settingsSection
                    
                    // Logout Button
                    logoutSection
                }
                .padding()
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
            .navigationTitle("我的")
            .navigationBarTitleDisplayMode(.inline)
            .navigationBarItems(
                trailing: Button("编辑") {
                    showingEditProfile = true
                }
            )
        }
        .sheet(isPresented: $showingEditProfile) {
            EditProfileSheet()
                .environmentObject(authManager)
        }
        .onChange(of: selectedPhotoItem) { oldValue, newItem in
            Task {
                if let newItem = newItem {
                    if let data = try? await newItem.loadTransferable(type: Data.self) {
                        if let image = UIImage(data: data) {
                            profileImage = image
                            // Here you would save the image to the user profile
                        }
                    }
                }
            }
        }
        .sheet(isPresented: $showingPrivacySettings) {
            PrivacySettingsView()
        }
        .sheet(isPresented: $showingNotificationSettings) {
            NotificationSettingsView()
        }
        .sheet(isPresented: $showingExportData) {
            ExportDataView()
        }
        .sheet(isPresented: $showingHelpSupport) {
            HelpSupportView()
        }
    }
    
    private var profileHeaderSection: some View {
        VStack(spacing: 20) {
            // Profile Image
            Button(action: { showingImagePicker = true }) {
                Group {
                    if let profileImage = profileImage {
                        Image(uiImage: profileImage)
                            .resizable()
                            .aspectRatio(contentMode: .fill)
                    } else {
                        LinearGradient(
                            gradient: Gradient(colors: [.blue, .purple]),
                            startPoint: .topLeading,
                            endPoint: .bottomTrailing
                        )
                        .overlay(
                            Image(systemName: "person.fill")
                                .font(.system(size: 40))
                                .foregroundColor(.white)
                        )
                    }
                }
                .frame(width: 120, height: 120)
                .clipShape(Circle())
                .overlay(
                    Circle()
                        .stroke(Color.white, lineWidth: 4)
                        .shadow(color: .black.opacity(0.1), radius: 8, x: 0, y: 4)
                )
                .overlay(
                    // Edit button overlay
                    Circle()
                        .fill(Color.blue)
                        .frame(width: 36, height: 36)
                        .overlay(
                            Image(systemName: "camera.fill")
                                .font(.caption)
                                .foregroundColor(.white)
                        )
                        .offset(x: 40, y: 40)
                )
            }
            .photosPicker(isPresented: $showingImagePicker, selection: $selectedPhotoItem, matching: .images)
            
            // User Info
            VStack(spacing: 8) {
                Text(authManager.currentUser?.username ?? "旅行者")
                    .font(.title)
                    .fontWeight(.bold)
                
                Text(authManager.currentUser?.email ?? "user@example.com")
                    .font(.subheadline)
                    .foregroundColor(.secondary)
                
                // Member since
                Text("注册于 \(formatMemberSince())")
                    .font(.caption)
                    .foregroundColor(.secondary)
            }
        }
        .padding()
        .background(Color(.systemBackground))
        .cornerRadius(20)
        .shadow(color: .black.opacity(0.05), radius: 10, x: 0, y: 4)
    }
    
    private var statsSection: some View {
        VStack(spacing: 16) {
            HStack {
                Text("旅行统计")
                    .font(.headline)
                    .fontWeight(.semibold)
                Spacer()
            }
            
            LazyVGrid(columns: Array(repeating: GridItem(.flexible()), count: 3), spacing: 16) {
                ProfileStatCard(
                    title: "行程",
                    value: "\(authManager.currentUser?.totalJourneys ?? 0)",
                    icon: "location.fill",
                    color: .blue
                )
                
                ProfileStatCard(
                    title: "国家",
                    value: "\(authManager.currentUser?.visitedCountries.count ?? 0)",
                    icon: "globe",
                    color: .green
                )
                
                ProfileStatCard(
                    title: "城市",
                    value: "\(authManager.currentUser?.visitedCities.count ?? 0)",
                    icon: "building.2",
                    color: .orange
                )
                
                ProfileStatCard(
                    title: "照片",
                    value: "\(authManager.currentUser?.totalPhotos ?? 0)",
                    icon: "camera.fill",
                    color: .purple
                )
                
ProfileStatCard(
                    title: "距离",
                    value: authManager.currentUser?.formattedTotalDistance ?? "0 km",
                    icon: "map",
                    color: .cyan
                )
                
                ProfileStatCard(
                    title: "回忆",
                    value: "∞",
                    icon: "heart.fill",
                    color: .pink
                )
            }
        }
        .padding()
        .background(Color(.systemBackground))
        .cornerRadius(20)
        .shadow(color: .black.opacity(0.05), radius: 10, x: 0, y: 4)
    }
    
    private var travelSummarySection: some View {
        VStack(spacing: 16) {
            HStack {
                Text("旅行摘要")
                    .font(.headline)
                    .fontWeight(.semibold)
                Spacer()
            }
            
            if let user = authManager.currentUser, !user.visitedCountries.isEmpty {
LazyVGrid(columns: Array(repeating: GridItem(.flexible()), count: 2), spacing: 12) {
                    ForEach(user.visitedCountries.prefix(6), id: \.self) { country in
                        NavigationLink(destination: CountryDetailView(
                            country: country,
                            journeys: getJourneysForCountry(country)
                        )) {
                            CountryBadge(country: country)
                        }
                        .buttonStyle(PlainButtonStyle())
                    }
                    
                    if user.visitedCountries.count > 6 {
                        NavigationLink(destination: AllCountriesView()) {
                            MoreCountriesBadge(count: user.visitedCountries.count - 6)
                        }
                        .buttonStyle(PlainButtonStyle())
                    }
                }
            } else {
                EmptyTravelSummary()
            }
        }
        .padding()
        .background(Color(.systemBackground))
        .cornerRadius(20)
        .shadow(color: .black.opacity(0.05), radius: 10, x: 0, y: 4)
    }
    
    private var settingsSection: some View {
        VStack(spacing: 0) {
            SettingsRow(
                title: "隐私设置",
                icon: "lock.fill",
                color: .blue
            ) {
                showingPrivacySettings = true
            }
            
            Divider()
                .padding(.leading, 50)
            
            SettingsRow(
                title: "通知",
                icon: "bell.fill",
                color: .orange
            ) {
                showingNotificationSettings = true
            }
            
            Divider()
                .padding(.leading, 50)
            
            SettingsRow(
                title: "导出数据",
                icon: "square.and.arrow.up",
                color: .green
            ) {
                showingExportData = true
            }
            
            Divider()
                .padding(.leading, 50)
            
            SettingsRow(
                title: "帮助与支持",
                icon: "questionmark.circle.fill",
                color: .purple
            ) {
                showingHelpSupport = true
            }
        }
        .background(Color(.systemBackground))
        .cornerRadius(20)
        .shadow(color: .black.opacity(0.05), radius: 10, x: 0, y: 4)
    }
    
    private var logoutSection: some View {
        Button(action: {
            authManager.logout()
        }) {
            HStack {
                Image(systemName: "rectangle.portrait.and.arrow.right")
                    .font(.title3)
                
                Text("退出登录")
                    .font(.headline)
                    .fontWeight(.semibold)
            }
            .frame(maxWidth: .infinity)
            .frame(height: 50)
            .background(
                LinearGradient(
                    gradient: Gradient(colors: [Color.red.opacity(0.8), Color.red]),
                    startPoint: .leading,
                    endPoint: .trailing
                )
            )
            .foregroundColor(.white)
            .cornerRadius(25)
            .shadow(color: .red.opacity(0.3), radius: 10, x: 0, y: 5)
        }
        .padding(.top, 20)
    }
    
    private func formatMemberSince() -> String {
        let formatter = DateFormatter()
        formatter.dateFormat = "MMMM yyyy"
        return formatter.string(from: authManager.currentUser?.createdAt ?? Date())
    }
    
    private func getJourneysForCountry(_ country: String) -> [Journey] {
        guard let user = authManager.currentUser else { return [] }
        return user.journeys.filter { journey in
            journey.visitedCountries.contains(country)
        }
    }
}

struct ProfileStatCard: View {
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
                .multilineTextAlignment(.center)
        }
        .frame(maxWidth: .infinity)
        .frame(height: 100)
        .padding()
        .background(Color.gray.opacity(0.05))
        .cornerRadius(16)
        .overlay(
            RoundedRectangle(cornerRadius: 16)
                .stroke(color.opacity(0.3), lineWidth: 1)
        )
    }
}

struct CountryBadge: View {
    let country: String
    
    var body: some View {
        HStack(spacing: 8) {
            Text(getCountryFlag(country))
                .font(.title3)
            
            Text(country)
                .font(.subheadline)
                .fontWeight(.medium)
        }
        .padding(.horizontal, 12)
        .padding(.vertical, 6)
        .background(Color.gray.opacity(0.1))
        .cornerRadius(16)
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

struct MoreCountriesBadge: View {
    let count: Int
    
    var body: some View {
        HStack(spacing: 8) {
            Text("🌍")
                .font(.title3)
            
            Text("+\(count) 更多")
                .font(.subheadline)
                .fontWeight(.medium)
        }
        .padding(.horizontal, 12)
        .padding(.vertical, 6)
        .background(Color.blue.opacity(0.1))
        .cornerRadius(16)
    }
}

struct EmptyTravelSummary: View {
    var body: some View {
        VStack(spacing: 12) {
            Image(systemName: "airplane.departure")
                .font(.system(size: 40))
                .foregroundColor(.gray.opacity(0.6))
            
            Text("还没有旅行")
                .font(.headline)
                .foregroundColor(.primary)
            
            Text("开始你的旅程，探索世界！")
                .font(.subheadline)
                .foregroundColor(.secondary)
                .multilineTextAlignment(.center)
        }
        .frame(maxWidth: .infinity)
        .padding(.vertical, 30)
    }
}

struct SettingsRow: View {
    let title: String
    let icon: String
    let color: Color
    let action: () -> Void
    
    var body: some View {
        Button(action: action) {
            HStack(spacing: 16) {
                Circle()
                    .fill(color)
                    .frame(width: 32, height: 32)
                    .overlay(
                        Image(systemName: icon)
                            .font(.caption)
                            .foregroundColor(.white)
                    )
                
                Text(title)
                    .font(.subheadline)
                    .fontWeight(.medium)
                    .foregroundColor(.primary)
                
                Spacer()
                
                Image(systemName: "chevron.right")
                    .font(.caption)
                    .foregroundColor(.secondary)
            }
            .padding()
        }
    }
}

struct EditProfileSheet: View {
    @EnvironmentObject var authManager: AuthenticationManager
    @Environment(\.dismiss) private var dismiss
    @State private var username: String = ""
    @State private var email: String = ""
    
    var body: some View {
        NavigationView {
            Form {
                Section("个人信息") {
                    HStack {
                        Text("用户名")
                        Spacer()
                        TextField("用户名", text: $username)
                            .multilineTextAlignment(.trailing)
                    }
                    
                    HStack {
                        Text("邮箱")
                        Spacer()
                        TextField("邮箱", text: $email)
                            .multilineTextAlignment(.trailing)
                            .keyboardType(.emailAddress)
                    }
                }
                
                Section("账户") {
                    Button("修改密码") {
                        // Handle password change
                    }
                    
                    Button("删除账户") {
                        // Handle account deletion
                    }
                    .foregroundColor(.red)
                }
            }
            .navigationTitle("编辑个人资料")
            .navigationBarTitleDisplayMode(.inline)
            .navigationBarItems(
                leading: Button("取消") { dismiss() },
                trailing: Button("保存") {
                    // Save changes
                    dismiss()
                }
            )
        }
        .onAppear {
            username = authManager.currentUser?.username ?? ""
            email = authManager.currentUser?.email ?? ""
        }
    }
}

#Preview {
    ProfileTabView()
        .environmentObject(AuthenticationManager())
}
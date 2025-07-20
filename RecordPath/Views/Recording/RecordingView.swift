import SwiftUI
import PhotosUI
import CoreLocation

struct RecordingView: View {
    @EnvironmentObject var pathTrackingManager: PathTrackingManager
    @State private var journeyTitle = ""
    @State private var showingJourneyTitleInput = false
    @State private var showingPhotoCapture = false
    @State private var selectedPhotoItem: PhotosPickerItem?
    @State private var capturedPhotos: [JourneyPhoto] = []
    @State private var currentLocationName = "未知位置"
    @State private var isGettingLocation = false
    
    var body: some View {
        NavigationView {
            ScrollView {
                VStack(spacing: 24) {
                    // Main Tracking Status
                    trackingStatusCard
                    
                    // Current Journey Info
                    if let currentJourney = pathTrackingManager.currentJourney {
                        currentJourneyCard(currentJourney)
                    }
                    
                    // Control Buttons
                    controlButtonsSection
                    
                    // Photo Section
                    if pathTrackingManager.isTracking {
                        photoSection
                    }
                    
                    // Location Status
                    locationStatusCard
                }
                .padding()
            }
            .background(
                LinearGradient(
                    gradient: Gradient(colors: [
                        Color.blue.opacity(0.03),
                        Color.purple.opacity(0.03),
                        Color.clear
                    ]),
                    startPoint: .topLeading,
                    endPoint: .bottomTrailing
                )
            )
            .navigationTitle("Record Journey")
            .navigationBarTitleDisplayMode(.inline)
        }
        .sheet(isPresented: $showingJourneyTitleInput) {
            JourneyTitleInputView(
                journeyTitle: $journeyTitle,
                onStart: {
                    pathTrackingManager.startTracking(journeyTitle: journeyTitle)
                    showingJourneyTitleInput = false
                }
            )
        }
        .photosPicker(
            isPresented: $showingPhotoCapture,
            selection: $selectedPhotoItem,
            matching: .images
        )
        .onChange(of: selectedPhotoItem) { oldValue, newItem in
            Task {
                if let newItem = newItem {
                    if let data = try? await newItem.loadTransferable(type: Data.self),
                       let location = pathTrackingManager.currentLocation {
                        let photo = JourneyPhoto(
                            imageData: data,
                            location: location.coordinate,
                            timestamp: Date()
                        )
                        capturedPhotos.append(photo)
                        selectedPhotoItem = nil
                    }
                }
            }
        }
    }
    
    private var trackingStatusCard: some View {
        VStack(spacing: 20) {
            // Status Icon
            ZStack {
                Circle()
                    .fill(statusGradient)
                    .frame(width: 120, height: 120)
                    .shadow(color: statusColor.opacity(0.3), radius: 15, x: 0, y: 8)
                
                Image(systemName: statusIcon)
                    .font(.system(size: 45, weight: .medium))
                    .foregroundColor(.white)
                    .scaleEffect(pathTrackingManager.isTracking && !pathTrackingManager.isPaused ? 1.1 : 1.0)
                    .animation(.easeInOut(duration: 1.5).repeatForever(autoreverses: true), 
                              value: pathTrackingManager.isTracking && !pathTrackingManager.isPaused)
            }
            
            // Status Text
            VStack(spacing: 8) {
                Text(statusTitle)
                    .font(.title2)
                    .fontWeight(.bold)
                    .foregroundColor(.primary)
                
                Text(statusSubtitle)
                    .font(.subheadline)
                    .foregroundColor(.secondary)
                    .multilineTextAlignment(.center)
                    .padding(.horizontal)
            }
        }
        .padding(.vertical, 20)
        .frame(maxWidth: .infinity)
        .background(Color(.systemBackground))
        .cornerRadius(20)
        .shadow(color: .black.opacity(0.05), radius: 10, x: 0, y: 5)
    }
    
    private func currentJourneyCard(_ journey: Journey) -> some View {
        VStack(spacing: 16) {
            HStack {
                VStack(alignment: .leading, spacing: 4) {
                    Text("当前旅程")
                        .font(.caption)
                        .foregroundColor(.secondary)
                        .textCase(.uppercase)
                        .tracking(1.2)
                    
                    Text(journey.title)
                        .font(.title3)
                        .fontWeight(.semibold)
                        .foregroundColor(.primary)
                }
                Spacer()
            }
            
            // Stats Grid
            LazyVGrid(columns: Array(repeating: GridItem(.flexible()), count: 3), spacing: 16) {
                StatItem(
                    title: "距离",
                    value: journey.formattedDistance,
                    icon: "map",
                    color: .blue
                )
                
                StatItem(
                    title: "时长",
                    value: journey.formattedDuration,
                    icon: "clock",
                    color: .green
                )
                
                StatItem(
                    title: "照片",
                    value: "\(capturedPhotos.count)",
                    icon: "camera",
                    color: .orange
                )
            }
        }
        .padding(20)
        .background(Color(.systemBackground))
        .cornerRadius(20)
        .shadow(color: .black.opacity(0.05), radius: 10, x: 0, y: 5)
    }
    
    private var controlButtonsSection: some View {
        VStack(spacing: 16) {
            if !pathTrackingManager.isTracking {
                // Start Button
                ActionButton(
                    title: "开始新旅程",
                    icon: "play.fill",
                    color: .green,
                    action: {
                        // 检查权限并开始
                        if pathTrackingManager.authorizationStatus == .authorizedWhenInUse || 
                           pathTrackingManager.authorizationStatus == .authorizedAlways {
                            generateDefaultJourneyName()
                            showingJourneyTitleInput = true
                        } else {
                            // 请求权限
                            pathTrackingManager.requestLocationPermission()
                        }
                    }
                )
            } else {
                HStack(spacing: 12) {
                    if pathTrackingManager.isPaused {
                        // Resume Button
                        ActionButton(
                            title: "继续",
                            icon: "play.fill",
                            color: .blue,
                            isCompact: true,
                            action: {
                                pathTrackingManager.resumeTracking()
                            }
                        )
                    } else {
                        // Pause Button
                        ActionButton(
                            title: "暂停",
                            icon: "pause.fill",
                            color: .orange,
                            isCompact: true,
                            action: {
                                pathTrackingManager.pauseTracking()
                            }
                        )
                    }
                    
                    // Stop Button
                    ActionButton(
                        title: "结束",
                        icon: "stop.fill",
                        color: .red,
                        isCompact: true,
                        action: {
                            // Add captured photos to journey before stopping
                            pathTrackingManager.currentJourney?.photos.append(contentsOf: capturedPhotos)
                            pathTrackingManager.stopTracking()
                            capturedPhotos.removeAll()
                        }
                    )
                }
            }
        }
    }
    
    private var photoSection: some View {
        VStack(spacing: 16) {
            HStack {
                VStack(alignment: .leading, spacing: 4) {
                    Text("旅程照片")
                        .font(.headline)
                        .fontWeight(.semibold)
                    
                    Text("记录路线中的美好瞬间")
                        .font(.caption)
                        .foregroundColor(.secondary)
                }
                
                Spacer()
                
                Button(action: {
                    showingPhotoCapture = true
                }) {
                    Image(systemName: "camera.fill")
                        .font(.title3)
                        .foregroundColor(.white)
                        .frame(width: 44, height: 44)
                        .background(
                            LinearGradient(
                                gradient: Gradient(colors: [.purple, .pink]),
                                startPoint: .topLeading,
                                endPoint: .bottomTrailing
                            )
                        )
                        .cornerRadius(22)
                        .shadow(color: .purple.opacity(0.3), radius: 8, x: 0, y: 4)
                }
            }
            
            if capturedPhotos.isEmpty {
                VStack(spacing: 12) {
                    Image(systemName: "photo.on.rectangle")
                        .font(.system(size: 40))
                        .foregroundColor(.gray.opacity(0.6))
                    
                    Text("还没有照片")
                        .font(.headline)
                        .foregroundColor(.primary)
                    
                    Text("点击相机按钮添加照片")
                        .font(.caption)
                        .foregroundColor(.secondary)
                        .multilineTextAlignment(.center)
                }
                .frame(maxWidth: .infinity)
                .frame(height: 120)
                .background(Color.gray.opacity(0.05))
                .cornerRadius(16)
            } else {
                ScrollView(.horizontal, showsIndicators: false) {
                    HStack(spacing: 12) {
                        ForEach(capturedPhotos.indices, id: \.self) { index in
                            if let image = UIImage(data: capturedPhotos[index].imageData) {
                                Image(uiImage: image)
                                    .resizable()
                                    .aspectRatio(contentMode: .fill)
                                    .frame(width: 100, height: 100)
                                    .cornerRadius(16)
                                    .clipped()
                                    .overlay(
                                        RoundedRectangle(cornerRadius: 16)
                                            .stroke(Color.white, lineWidth: 2)
                                    )
                                    .shadow(color: .black.opacity(0.1), radius: 4, x: 0, y: 2)
                            }
                        }
                    }
                    .padding(.horizontal, 4)
                }
            }
        }
        .padding(20)
        .background(Color(.systemBackground))
        .cornerRadius(20)
        .shadow(color: .black.opacity(0.05), radius: 10, x: 0, y: 5)
    }
    
    private var locationStatusCard: some View {
        HStack(spacing: 16) {
            Circle()
                .fill(locationPermissionColor)
                .frame(width: 12, height: 12)
            
            VStack(alignment: .leading, spacing: 2) {
                Text("位置权限")
                    .font(.subheadline)
                    .fontWeight(.medium)
                
                Text(locationPermissionText)
                    .font(.caption)
                    .foregroundColor(.secondary)
            }
            
            Spacer()
            
            if pathTrackingManager.authorizationStatus == .denied || 
               pathTrackingManager.authorizationStatus == .restricted {
                Button("打开设置") {
                    if let settingsUrl = URL(string: UIApplication.openSettingsURLString) {
                        UIApplication.shared.open(settingsUrl)
                    }
                }
                .font(.caption)
                .foregroundColor(.blue)
                .padding(.horizontal, 16)
                .padding(.vertical, 8)
                .background(Color.blue.opacity(0.1))
                .cornerRadius(16)
            } else if pathTrackingManager.authorizationStatus == .notDetermined {
                Button("请求权限") {
                    pathTrackingManager.requestLocationPermission()
                }
                .font(.caption)
                .foregroundColor(.green)
                .padding(.horizontal, 16)
                .padding(.vertical, 8)
                .background(Color.green.opacity(0.1))
                .cornerRadius(16)
            }
        }
        .padding(16)
        .background(Color(.systemBackground))
        .cornerRadius(16)
        .shadow(color: .black.opacity(0.05), radius: 8, x: 0, y: 2)
    }
    
    // MARK: - Computed Properties
    
    private var statusGradient: LinearGradient {
        if pathTrackingManager.isTracking {
            if pathTrackingManager.isPaused {
                return LinearGradient(
                    gradient: Gradient(colors: [.orange, .yellow]),
                    startPoint: .topLeading,
                    endPoint: .bottomTrailing
                )
            } else {
                return LinearGradient(
                    gradient: Gradient(colors: [.green, .blue]),
                    startPoint: .topLeading,
                    endPoint: .bottomTrailing
                )
            }
        } else {
            return LinearGradient(
                gradient: Gradient(colors: [.gray.opacity(0.6), .gray]),
                startPoint: .topLeading,
                endPoint: .bottomTrailing
            )
        }
    }
    
    private var statusColor: Color {
        if pathTrackingManager.isTracking {
            return pathTrackingManager.isPaused ? .orange : .green
        } else {
            return .gray
        }
    }
    
    private var statusIcon: String {
        if pathTrackingManager.isTracking {
            return pathTrackingManager.isPaused ? "pause.fill" : "location.north.line.fill"
        } else {
            return "play.fill"
        }
    }
    
    private var statusTitle: String {
        if pathTrackingManager.isTracking {
            return pathTrackingManager.isPaused ? "旅程已暂停" : "正在记录旅程"
        } else {
            return "准备开始追踪"
        }
    }
    
    private var statusSubtitle: String {
        if pathTrackingManager.isTracking {
            return pathTrackingManager.isPaused ? 
                "点击继续以恢复记录" : 
                "正在记录您的GPS路线"
        } else {
            return "开始新旅程来追踪您的GPS路线"
        }
    }
    
    private var locationPermissionColor: Color {
        switch pathTrackingManager.authorizationStatus {
        case .authorizedWhenInUse, .authorizedAlways:
            return .green
        case .denied, .restricted:
            return .red
        case .notDetermined:
            return .orange
        @unknown default:
            return .gray
        }
    }
    
    private var locationPermissionText: String {
        switch pathTrackingManager.authorizationStatus {
        case .authorizedWhenInUse:
            return "使用应用时已授权"
        case .authorizedAlways:
            return "始终已授权"
        case .denied:
            return "位置访问被拒绝"
        case .restricted:
            return "位置访问受限"
        case .notDetermined:
            return "等待位置权限"
        @unknown default:
            return "未知权限状态"
        }
    }
    
    // MARK: - Helper Methods
    
    private func generateDefaultJourneyName() {
        isGettingLocation = true
        
        // 获取当前位置名称
        getCurrentLocationName { locationName in
            DispatchQueue.main.async {
                let formatter = DateFormatter()
                formatter.locale = Locale(identifier: "zh_CN")
                formatter.dateFormat = "MM月dd日 HH:mm"
                let timeString = formatter.string(from: Date())
                
                self.journeyTitle = "\(timeString) \(locationName)"
                self.currentLocationName = locationName
                self.isGettingLocation = false
            }
        }
    }
    
    private func getCurrentLocationName(completion: @escaping (String) -> Void) {
        guard let location = pathTrackingManager.currentLocation else {
            completion("未知位置")
            return
        }
        
        // 使用高德地图的地理编码服务
        let locationService = AMapLocationService()
        locationService.getLocationName(from: location) { locationName in
            DispatchQueue.main.async {
                completion(locationName)
            }
        }
    }
}

// MARK: - Supporting Views

struct ActionButton: View {
    let title: String
    let icon: String
    let color: Color
    var isCompact: Bool = false
    let action: () -> Void
    
    var body: some View {
        Button(action: action) {
            HStack(spacing: 8) {
                Image(systemName: icon)
                    .font(.title3)
                
                Text(title)
                    .font(isCompact ? .subheadline : .headline)
                    .fontWeight(.semibold)
            }
            .foregroundColor(.white)
            .frame(maxWidth: .infinity)
            .frame(height: isCompact ? 50 : 56)
            .background(
                LinearGradient(
                    gradient: Gradient(colors: [color, color.opacity(0.8)]),
                    startPoint: .topLeading,
                    endPoint: .bottomTrailing
                )
            )
            .cornerRadius(isCompact ? 25 : 28)
            .shadow(color: color.opacity(0.3), radius: 10, x: 0, y: 5)
        }
        .scaleEffect(1.0)
        .animation(.easeInOut(duration: 0.1), value: color)
    }
}

struct StatItem: View {
    let title: String
    let value: String
    let icon: String
    let color: Color
    
    var body: some View {
        VStack(spacing: 8) {
            Circle()
                .fill(color.opacity(0.1))
                .frame(width: 32, height: 32)
                .overlay(
                    Image(systemName: icon)
                        .font(.caption)
                        .foregroundColor(color)
                )
            
            Text(value)
                .font(.headline)
                .fontWeight(.bold)
                .foregroundColor(.primary)
            
            Text(title)
                .font(.caption)
                .foregroundColor(.secondary)
        }
        .frame(maxWidth: .infinity)
    }
}

struct JourneyTitleInputView: View {
    @Binding var journeyTitle: String
    let onStart: () -> Void
    @Environment(\.dismiss) private var dismiss
    @State private var editedTitle: String = ""
    
    var body: some View {
        NavigationView {
            VStack(spacing: 32) {
                // Header
                VStack(spacing: 16) {
                    Circle()
                        .fill(
                            LinearGradient(
                                gradient: Gradient(colors: [.blue, .purple]),
                                startPoint: .topLeading,
                                endPoint: .bottomTrailing
                            )
                        )
                        .frame(width: 100, height: 100)
                        .overlay(
                            Image(systemName: "location.north.line.fill")
                                .font(.system(size: 40))
                                .foregroundColor(.white)
                        )
                        .shadow(color: .blue.opacity(0.3), radius: 15, x: 0, y: 8)
                    
                    VStack(spacing: 8) {
                        Text("开始新旅程")
                            .font(.title)
                            .fontWeight(.bold)
                        
                        Text("为您的旅程起一个有意义的名字")
                            .font(.subheadline)
                            .foregroundColor(.secondary)
                            .multilineTextAlignment(.center)
                    }
                }
                
                // Input Section
                VStack(alignment: .leading, spacing: 12) {
                    Text("旅程名称")
                        .font(.headline)
                        .fontWeight(.medium)
                    
                    TextField("例如：晨跑中央公园", text: $editedTitle)
                        .textFieldStyle(RoundedBorderTextFieldStyle())
                        .font(.body)
                        .submitLabel(.done)
                        .onSubmit {
                            if !editedTitle.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
                                journeyTitle = editedTitle
                                onStart()
                            }
                        }
                    
                    // 显示默认建议
                    if !journeyTitle.isEmpty && editedTitle != journeyTitle {
                        HStack {
                            Text("建议：")
                                .font(.caption)
                                .foregroundColor(.secondary)
                            
                            Button(journeyTitle) {
                                editedTitle = journeyTitle
                            }
                            .font(.caption)
                            .foregroundColor(.blue)
                            .padding(.horizontal, 8)
                            .padding(.vertical, 4)
                            .background(Color.blue.opacity(0.1))
                            .cornerRadius(8)
                            
                            Spacer()
                        }
                    }
                }
                
                // Action Button
                ActionButton(
                    title: "开始记录",
                    icon: "play.fill",
                    color: .green,
                    action: {
                        journeyTitle = editedTitle.isEmpty ? journeyTitle : editedTitle
                        onStart()
                    }
                )
                .disabled(editedTitle.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty && journeyTitle.isEmpty)
                .opacity((editedTitle.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty && journeyTitle.isEmpty) ? 0.6 : 1.0)
                
                Spacer()
            }
            .padding(24)
            .navigationTitle("新旅程")
            .navigationBarTitleDisplayMode(.inline)
            .navigationBarItems(
                trailing: Button("取消") { dismiss() }
            )
        }
        .onAppear {
            // 使用传入的默认标题
            if editedTitle.isEmpty {
                editedTitle = journeyTitle
            }
        }
    }
}

#Preview {
    RecordingView()
        .environmentObject(PathTrackingManager())
}
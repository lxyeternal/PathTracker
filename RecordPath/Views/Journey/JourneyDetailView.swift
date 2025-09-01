//
//  JourneyDetailView.swift
//  RecordPath
//
//  行程详情页面
//

import SwiftUI
import MapKit

struct JourneyDetailView: View {
    let journey: Journey
    @Environment(\.dismiss) private var dismiss
    @State private var selectedPhoto: JourneyPhoto?
    @State private var showingPhotoDetail = false
    @State private var region: MKCoordinateRegion = MKCoordinateRegion(
        center: CLLocationCoordinate2D(latitude: 0, longitude: 0),
        span: MKCoordinateSpan(latitudeDelta: 0.01, longitudeDelta: 0.01)
    )
    
    var body: some View {
        ScrollView {
            VStack(spacing: 24) {
                // Header Section
                headerSection
                
                // Stats Section
                statsSection
                
                // Map Section
                mapSection
                
                // Path Segments Section
                pathSegmentsSection
                
                // Photos Section
                if !journey.photos.isEmpty {
                    photosSection
                }
                
                // Notes Section
                if !journey.notes.isEmpty {
                    notesSection
                }
                
                // Visited Places Section
                visitedPlacesSection
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
        .navigationTitle(journey.title)
        .navigationBarTitleDisplayMode(.large)
        .navigationBarBackButtonHidden(false)
        .onAppear {
            setupMapRegion()
        }
        .sheet(isPresented: $showingPhotoDetail) {
            if let photo = selectedPhoto {
                PhotoDetailView(photo: photo)
            }
        }
    }
    
    private var headerSection: some View {
        VStack(spacing: 16) {
            HStack {
                VStack(alignment: .leading, spacing: 8) {
                    Text(journey.title)
                        .font(.title2)
                        .fontWeight(.bold)
                        .foregroundColor(.primary)
                    
                    Label {
                        Text(journey.startDate.formatted(date: .abbreviated, time: .shortened))
                    } icon: {
                        Image(systemName: "calendar")
                    }
                    .font(.subheadline)
                    .foregroundColor(.secondary)
                }
                
                Spacer()
                
                // Countries visited
                VStack(alignment: .trailing, spacing: 4) {
                    Text("访问国家")
                        .font(.caption)
                        .foregroundColor(.secondary)
                    
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
            }
        }
        .padding(20)
        .background(Color(.systemBackground))
        .cornerRadius(20)
        .shadow(color: .black.opacity(0.05), radius: 10, x: 0, y: 5)
    }
    
    private var statsSection: some View {
        VStack(spacing: 16) {
            HStack {
                Text("旅程统计")
                    .font(.headline)
                    .fontWeight(.semibold)
                Spacer()
            }
            
            LazyVGrid(columns: Array(repeating: GridItem(.flexible()), count: 2), spacing: 16) {
                JourneyDetailStatCard(
                    title: "总距离",
                    value: journey.formattedDistance,
                    icon: "map.fill",
                    color: .blue
                )
                
                JourneyDetailStatCard(
                    title: "总时长",
                    value: journey.formattedDuration,
                    icon: "clock.fill",
                    color: .green
                )
                
                JourneyDetailStatCard(
                    title: "路径段",
                    value: "\(journey.segments.count)段",
                    icon: "point.3.connected.trianglepath.dotted",
                    color: .orange
                )
                
                JourneyDetailStatCard(
                    title: "照片",
                    value: "\(journey.photos.count)张",
                    icon: "camera.fill",
                    color: .purple
                )
            }
        }
        .padding(20)
        .background(Color(.systemBackground))
        .cornerRadius(20)
        .shadow(color: .black.opacity(0.05), radius: 10, x: 0, y: 5)
    }
    
    private var mapSection: some View {
        VStack(spacing: 16) {
            HStack {
                Text("路线图")
                    .font(.headline)
                    .fontWeight(.semibold)
                Spacer()
                
                Button("查看大图") {
                    // TODO: 打开全屏地图视图
                }
                .font(.subheadline)
                .foregroundColor(.blue)
            }
            
            Map(coordinateRegion: .constant(region), annotationItems: getMapAnnotations()) { annotation in
                MapPin(coordinate: annotation.coordinate, tint: .blue)
            }
            .frame(height: 200)
            .cornerRadius(16)
            .overlay(
                RoundedRectangle(cornerRadius: 16)
                    .stroke(Color.gray.opacity(0.2), lineWidth: 1)
            )
        }
        .padding(20)
        .background(Color(.systemBackground))
        .cornerRadius(20)
        .shadow(color: .black.opacity(0.05), radius: 10, x: 0, y: 5)
    }
    
    private var pathSegmentsSection: some View {
        VStack(spacing: 16) {
            HStack {
                Text("路径段详情")
                    .font(.headline)
                    .fontWeight(.semibold)
                Spacer()
            }
            
            ForEach(Array(journey.segments.enumerated()), id: \.element.id) { index, segment in
                PathSegmentCard(segment: segment, index: index + 1)
            }
        }
        .padding(20)
        .background(Color(.systemBackground))
        .cornerRadius(20)
        .shadow(color: .black.opacity(0.05), radius: 10, x: 0, y: 5)
    }
    
    private var photosSection: some View {
        VStack(spacing: 16) {
            HStack {
                Text("旅程照片")
                    .font(.headline)
                    .fontWeight(.semibold)
                Spacer()
                
                Text("\(journey.photos.count)张")
                    .font(.caption)
                    .foregroundColor(.secondary)
            }
            
            LazyVGrid(columns: Array(repeating: GridItem(.flexible(), spacing: 8), count: 3), spacing: 8) {
                ForEach(journey.photos, id: \.id) { photo in
                    if let image = UIImage(data: photo.imageData) {
                        Button(action: {
                            selectedPhoto = photo
                            showingPhotoDetail = true
                        }) {
                            Image(uiImage: image)
                                .resizable()
                                .aspectRatio(contentMode: .fill)
                                .frame(width: 100, height: 100)
                                .clipped()
                                .cornerRadius(12)
                                .overlay(
                                    RoundedRectangle(cornerRadius: 12)
                                        .stroke(Color.white, lineWidth: 2)
                                )
                        }
                        .shadow(color: .black.opacity(0.1), radius: 4, x: 0, y: 2)
                    }
                }
            }
        }
        .padding(20)
        .background(Color(.systemBackground))
        .cornerRadius(20)
        .shadow(color: .black.opacity(0.05), radius: 10, x: 0, y: 5)
    }
    
    private var notesSection: some View {
        VStack(spacing: 16) {
            HStack {
                Text("旅程笔记")
                    .font(.headline)
                    .fontWeight(.semibold)
                Spacer()
            }
            
            VStack(alignment: .leading, spacing: 8) {
                Text(journey.notes)
                    .font(.body)
                    .foregroundColor(.secondary)
                    .fixedSize(horizontal: false, vertical: true)
            }
            .frame(maxWidth: .infinity, alignment: .leading)
            .padding(16)
            .background(Color.gray.opacity(0.05))
            .cornerRadius(12)
        }
        .padding(20)
        .background(Color(.systemBackground))
        .cornerRadius(20)
        .shadow(color: .black.opacity(0.05), radius: 10, x: 0, y: 5)
    }
    
    private var visitedPlacesSection: some View {
        VStack(spacing: 16) {
            HStack {
                Text("访问地点")
                    .font(.headline)
                    .fontWeight(.semibold)
                Spacer()
            }
            
            VStack(spacing: 12) {
                ForEach(journey.visitedCountries, id: \.self) { country in
                    HStack {
                        Text(getCountryFlag(country))
                            .font(.title2)
                        
                        VStack(alignment: .leading, spacing: 2) {
                            Text(country)
                                .font(.subheadline)
                                .fontWeight(.medium)
                            
                            Text(getCountryLandmark(country))
                                .font(.caption)
                                .foregroundColor(.secondary)
                        }
                        
                        Spacer()
                    }
                    .padding(12)
                    .background(Color.gray.opacity(0.05))
                    .cornerRadius(12)
                }
            }
        }
        .padding(20)
        .background(Color(.systemBackground))
        .cornerRadius(20)
        .shadow(color: .black.opacity(0.05), radius: 10, x: 0, y: 5)
    }
    
    // MARK: - Helper Methods
    
    private func setupMapRegion() {
        let allPoints = journey.segments.flatMap { $0.trackPoints }
        guard !allPoints.isEmpty else { return }
        
        let latitudes = allPoints.map { $0.coordinate.latitude }
        let longitudes = allPoints.map { $0.coordinate.longitude }
        
        let minLat = latitudes.min() ?? 0
        let maxLat = latitudes.max() ?? 0
        let minLon = longitudes.min() ?? 0
        let maxLon = longitudes.max() ?? 0
        
        let center = CLLocationCoordinate2D(
            latitude: (minLat + maxLat) / 2,
            longitude: (minLon + maxLon) / 2
        )
        
        let span = MKCoordinateSpan(
            latitudeDelta: max(maxLat - minLat, 0.01) * 1.5,
            longitudeDelta: max(maxLon - minLon, 0.01) * 1.5
        )
        
        region = MKCoordinateRegion(center: center, span: span)
    }
    
    private func getMapAnnotations() -> [MapAnnotation] {
        var annotations: [MapAnnotation] = []
        
        for (index, segment) in journey.segments.enumerated() {
            if let firstPoint = segment.trackPoints.first {
                annotations.append(MapAnnotation(
                    id: "start_\(index)",
                    coordinate: firstPoint.coordinate,
                    title: "起点 \(index + 1)"
                ))
            }
            if let lastPoint = segment.trackPoints.last {
                annotations.append(MapAnnotation(
                    id: "end_\(index)",
                    coordinate: lastPoint.coordinate,
                    title: "终点 \(index + 1)"
                ))
            }
        }
        
        return annotations
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
}

// MARK: - Supporting Views

struct JourneyDetailStatCard: View {
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
        .padding(.vertical, 16)
        .background(Color.gray.opacity(0.02))
        .cornerRadius(16)
        .overlay(
            RoundedRectangle(cornerRadius: 16)
                .stroke(color.opacity(0.2), lineWidth: 1)
        )
    }
}

struct PathSegmentCard: View {
    let segment: PathSegment
    let index: Int
    
    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack {
                HStack(spacing: 8) {
                    Circle()
                        .fill(segment.isActive ? .green : .blue)
                        .frame(width: 12, height: 12)
                    
                    Text("路径段 \(index)")
                        .font(.headline)
                        .fontWeight(.semibold)
                }
                
                Spacer()
                
                Text("\(segment.trackPoints.count) 个点")
                    .font(.caption)
                    .foregroundColor(.secondary)
            }
            
            HStack(spacing: 20) {
                VStack(alignment: .leading, spacing: 4) {
                    Text("距离")
                        .font(.caption)
                        .foregroundColor(.secondary)
                    
                    Text(formatDistance(segment.distance))
                        .font(.subheadline)
                        .fontWeight(.medium)
                }
                
                VStack(alignment: .leading, spacing: 4) {
                    Text("时长")
                        .font(.caption)
                        .foregroundColor(.secondary)
                    
                    Text(formatDuration(segment.duration))
                        .font(.subheadline)
                        .fontWeight(.medium)
                }
                
                VStack(alignment: .leading, spacing: 4) {
                    Text("平均速度")
                        .font(.caption)
                        .foregroundColor(.secondary)
                    
                    Text(formatSpeed(segment.averageSpeed))
                        .font(.subheadline)
                        .fontWeight(.medium)
                }
                
                Spacer()
            }
        }
        .padding(16)
        .background(Color.gray.opacity(0.05))
        .cornerRadius(12)
    }
    
    private func formatDistance(_ distance: Double) -> String {
        if distance < 1000 {
            return String(format: "%.0f m", distance)
        } else {
            return String(format: "%.1f km", distance / 1000)
        }
    }
    
    private func formatDuration(_ duration: TimeInterval) -> String {
        let hours = Int(duration / 3600)
        let minutes = Int((duration.truncatingRemainder(dividingBy: 3600)) / 60)
        
        if hours > 0 {
            return "\(hours)h \(minutes)m"
        } else {
            return "\(minutes)m"
        }
    }
    
    private func formatSpeed(_ speed: Double) -> String {
        let kmh = speed * 3.6
        return String(format: "%.1f km/h", kmh)
    }
}

struct PhotoDetailView: View {
    let photo: JourneyPhoto
    @Environment(\.dismiss) private var dismiss
    
    var body: some View {
        NavigationView {
            ZStack {
                Color.black.ignoresSafeArea()
                
                VStack {
                    if let image = UIImage(data: photo.imageData) {
                        Image(uiImage: image)
                            .resizable()
                            .aspectRatio(contentMode: .fit)
                            .clipped()
                    }
                    
                    if !photo.caption.isEmpty {
                        VStack(alignment: .leading, spacing: 8) {
                            Text("说明")
                                .font(.headline)
                                .foregroundColor(.white)
                            
                            Text(photo.caption)
                                .font(.body)
                                .foregroundColor(.white.opacity(0.8))
                        }
                        .frame(maxWidth: .infinity, alignment: .leading)
                        .padding()
                        .background(Color.black.opacity(0.3))
                    }
                }
            }
            .navigationBarTitleDisplayMode(.inline)
            .navigationBarItems(
                leading: Button("完成") {
                    dismiss()
                }
                .foregroundColor(.white)
            )
        }
    }
}

struct MapAnnotation: Identifiable {
    let id: String
    let coordinate: CLLocationCoordinate2D
    let title: String
}

#Preview {
    NavigationView {
        JourneyDetailView(journey: Journey(
            title: "示例旅程",
            startDate: Date(),
            endDate: Date()
        ))
    }
}
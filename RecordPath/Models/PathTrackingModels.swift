import Foundation
import CoreLocation
import SwiftUI

// 路径点 - GPS轨迹的基本单位
struct TrackPoint: Identifiable {
    let id = UUID()
    let coordinate: CLLocationCoordinate2D
    let timestamp: Date
    let altitude: Double
    let speed: Double
    let accuracy: Double
}

// 路径段 - 连续的轨迹点组成一段路径
struct PathSegment: Identifiable {
    let id = UUID()
    var trackPoints: [TrackPoint] = []
    let startTime: Date
    var endTime: Date
    var isActive: Bool = false
    
    var duration: TimeInterval {
        return endTime.timeIntervalSince(startTime)
    }
    
    var distance: Double {
        guard trackPoints.count > 1 else { return 0 }
        var totalDistance: Double = 0
        
        for i in 1..<trackPoints.count {
            let location1 = CLLocation(
                latitude: trackPoints[i-1].coordinate.latitude,
                longitude: trackPoints[i-1].coordinate.longitude
            )
            let location2 = CLLocation(
                latitude: trackPoints[i].coordinate.latitude,
                longitude: trackPoints[i].coordinate.longitude
            )
            totalDistance += location1.distance(from: location2)
        }
        
        return totalDistance
    }
    
    var averageSpeed: Double {
        guard duration > 0 else { return 0 }
        return distance / duration
    }
    
    var boundingBox: (minLat: Double, maxLat: Double, minLon: Double, maxLon: Double) {
        guard !trackPoints.isEmpty else {
            return (0, 0, 0, 0)
        }
        
        let latitudes = trackPoints.map { $0.coordinate.latitude }
        let longitudes = trackPoints.map { $0.coordinate.longitude }
        
        return (
            minLat: latitudes.min() ?? 0,
            maxLat: latitudes.max() ?? 0,
            minLon: longitudes.min() ?? 0,
            maxLon: longitudes.max() ?? 0
        )
    }
}

// 旅行记录 - 一次完整的旅行，包含多个路径段
struct Journey: Identifiable {
    let id = UUID()
    var title: String
    var segments: [PathSegment] = []
    let startDate: Date
    var endDate: Date
    var notes: String = ""
    var photos: [JourneyPhoto] = []
    
    var totalDistance: Double {
        return segments.reduce(0) { $0 + $1.distance }
    }
    
    var totalDuration: TimeInterval {
        return endDate.timeIntervalSince(startDate)
    }
    
    var visitedCountries: [String] {
        // 这里需要根据GPS坐标反向地理编码来获取国家信息
        // 暂时返回示例数据
        return ["France", "Japan", "China"]
    }
    
    var visitedCities: [String] {
        // 同样需要反向地理编码
        return ["Paris", "Tokyo", "Beijing"]
    }
    
    var formattedDistance: String {
        if totalDistance < 1000 {
            return String(format: "%.0f m", totalDistance)
        } else {
            return String(format: "%.1f km", totalDistance / 1000)
        }
    }
    
    var formattedDuration: String {
        let hours = Int(totalDuration / 3600)
        let minutes = Int((totalDuration.truncatingRemainder(dividingBy: 3600)) / 60)
        
        if hours > 0 {
            return "\(hours)h \(minutes)m"
        } else {
            return "\(minutes)m"
        }
    }
}

// 旅行照片
struct JourneyPhoto: Identifiable {
    let id = UUID()
    let imageData: Data
    let location: CLLocationCoordinate2D?
    let timestamp: Date
    var caption: String = ""
}

// 地点信息 - 基于GPS坐标识别的地点
struct IdentifiedPlace: Identifiable {
    let id = UUID()
    let name: String
    let type: PlaceType
    let coordinate: CLLocationCoordinate2D
    let country: String
    let city: String?
    let visitTime: Date
    let stayDuration: TimeInterval // 在该地点停留的时间
}

enum PlaceType: String, CaseIterable {
    case country = "Country"
    case city = "City"
    case landmark = "Landmark"
    case restaurant = "Restaurant"
    case hotel = "Hotel"
    case transport = "Transport"
    case shopping = "Shopping"
    case nature = "Nature"
    case unknown = "Unknown"
    
    var icon: String {
        switch self {
        case .country: return "flag.fill"
        case .city: return "building.2.fill"
        case .landmark: return "star.fill"
        case .restaurant: return "fork.knife"
        case .hotel: return "bed.double.fill"
        case .transport: return "car.fill"
        case .shopping: return "bag.fill"
        case .nature: return "leaf.fill"
        case .unknown: return "location.fill"
        }
    }
    
    var color: Color {
        switch self {
        case .country: return .blue
        case .city: return .green
        case .landmark: return .purple
        case .restaurant: return .orange
        case .hotel: return .indigo
        case .transport: return .red
        case .shopping: return .pink
        case .nature: return .mint
        case .unknown: return .gray
        }
    }
}

// 时间过滤器
enum TimeFilter: String, CaseIterable {
    case today = "Today"
    case yesterday = "Yesterday"
    case thisWeek = "This Week"
    case thisMonth = "This Month"
    case thisYear = "This Year"
    case custom = "Custom Range"
    
    var icon: String {
        switch self {
        case .today: return "calendar.circle"
        case .yesterday: return "calendar.circle.fill"
        case .thisWeek: return "calendar.badge.clock"
        case .thisMonth: return "calendar"
        case .thisYear: return "calendar.badge.plus"
        case .custom: return "slider.horizontal.3"
        }
    }
    
    func dateRange() -> (start: Date, end: Date) {
        let calendar = Calendar.current
        let now = Date()
        
        switch self {
        case .today:
            let startOfDay = calendar.startOfDay(for: now)
            return (startOfDay, now)
            
        case .yesterday:
            let yesterday = calendar.date(byAdding: .day, value: -1, to: now)!
            let startOfYesterday = calendar.startOfDay(for: yesterday)
            let endOfYesterday = calendar.date(byAdding: .day, value: 1, to: startOfYesterday)!
            return (startOfYesterday, endOfYesterday)
            
        case .thisWeek:
            let startOfWeek = calendar.dateInterval(of: .weekOfYear, for: now)?.start ?? now
            return (startOfWeek, now)
            
        case .thisMonth:
            let startOfMonth = calendar.dateInterval(of: .month, for: now)?.start ?? now
            return (startOfMonth, now)
            
        case .thisYear:
            let startOfYear = calendar.dateInterval(of: .year, for: now)?.start ?? now
            return (startOfYear, now)
            
        case .custom:
            // 默认返回最近30天
            let thirtyDaysAgo = calendar.date(byAdding: .day, value: -30, to: now) ?? now
            return (thirtyDaysAgo, now)
        }
    }
}

// 用户更新后的模型
struct User: Identifiable {
    let id = UUID()
    var username: String
    var email: String
    var profileImageData: Data?
    var createdAt: Date
    var journeys: [Journey] = []
    var currentJourney: Journey?
    
    // 统计属性
    var totalJourneys: Int {
        return journeys.count
    }
    
    var totalDistance: Double {
        return journeys.reduce(0) { $0 + $1.totalDistance }
    }
    
    var totalDuration: TimeInterval {
        return journeys.reduce(0) { $0 + $1.totalDuration }
    }
    
    var visitedCountries: [String] {
        let allCountries = journeys.flatMap { $0.visitedCountries }
        return Array(Set(allCountries)).sorted()
    }
    
    var visitedCities: [String] {
        let allCities = journeys.flatMap { $0.visitedCities }
        return Array(Set(allCities)).sorted()
    }
    
    var totalPhotos: Int {
        return journeys.reduce(0) { $0 + $1.photos.count }
    }
    
    var recentJourneys: [Journey] {
        return journeys.sorted { $0.endDate > $1.endDate }
    }
    
    var formattedTotalDistance: String {
        if totalDistance < 1000 {
            return String(format: "%.0f m", totalDistance)
        } else {
            return String(format: "%.1f km", totalDistance / 1000)
        }
    }
}
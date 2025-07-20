import Foundation
import Combine
import CoreLocation

class AuthenticationManager: ObservableObject {
    @Published var isAuthenticated = false
    @Published var currentUser: User?
    
    private var cancellables = Set<AnyCancellable>()
    
    init() {
        setupAuthenticationListener()
        checkAuthenticationStatus()
    }
    
    private func setupAuthenticationListener() {
        NotificationCenter.default.publisher(for: .userDidAuthenticate)
            .sink { [weak self] notification in
                if let user = notification.object as? User {
                    self?.currentUser = user
                    self?.isAuthenticated = true
                    self?.saveAuthenticationState(user: user)
                }
            }
            .store(in: &cancellables)
    }
    
    private func checkAuthenticationStatus() {
        // Check if user is already logged in
        if let userID = UserDefaults.standard.string(forKey: "currentUserID"),
           let uuid = UUID(uuidString: userID) {
            // Create user with sample data
            let user = createUser(
                username: UserDefaults.standard.string(forKey: "currentUsername") ?? "Traveler",
                email: UserDefaults.standard.string(forKey: "currentEmail") ?? "user@example.com"
            )
            currentUser = user
            isAuthenticated = true
        }
    }
    
    private func saveAuthenticationState(user: User) {
        // Save user info to UserDefaults for persistence
        UserDefaults.standard.set(user.id.uuidString, forKey: "currentUserID")
        UserDefaults.standard.set(user.username, forKey: "currentUsername")
        UserDefaults.standard.set(user.email, forKey: "currentEmail")
    }
    
    func logout() {
        isAuthenticated = false
        currentUser = nil
        UserDefaults.standard.removeObject(forKey: "currentUserID")
        UserDefaults.standard.removeObject(forKey: "currentUsername")
        UserDefaults.standard.removeObject(forKey: "currentEmail")
    }
    
    func deleteAccount() {
        logout()
    }
    
    func createUser(username: String, email: String) -> User {
        var user = User(
            username: username,
            email: email,
            createdAt: Date()
        )
        
        // 创建示例旅程数据
        let sampleJourneys = createSampleJourneys()
        user.journeys = sampleJourneys
        
        return user
    }
    
    private func createSampleJourneys() -> [Journey] {
        let calendar = Calendar.current
        let now = Date()
        
        // 示例旅程 1: 巴黎之旅
        let parisJourney = Journey(
            title: "巴黎浪漫之旅",
            segments: createParisSegments(),
            startDate: calendar.date(byAdding: .day, value: -5, to: now) ?? now,
            endDate: calendar.date(byAdding: .day, value: -4, to: now) ?? now,
            notes: "在巴黎度过了美好的一天，从埃菲尔铁塔到塞纳河，每一个角落都充满了浪漫"
        )
        
        // 示例旅程 2: 东京探索
        let tokyoJourney = Journey(
            title: "东京都市探索",
            segments: createTokyoSegments(),
            startDate: calendar.date(byAdding: .day, value: -3, to: now) ?? now,
            endDate: calendar.date(byAdding: .day, value: -2, to: now) ?? now,
            notes: "体验了东京的现代化与传统文化的完美融合"
        )
        
        // 示例旅程 3: 北京历史之旅
        let beijingJourney = Journey(
            title: "北京历史文化之旅",
            segments: createBeijingSegments(),
            startDate: calendar.date(byAdding: .day, value: -1, to: now) ?? now,
            endDate: now,
            notes: "感受了中华文明的博大精深"
        )
        
        return [parisJourney, tokyoJourney, beijingJourney]
    }
    
    private func createParisSegments() -> [PathSegment] {
        let startTime = Date().addingTimeInterval(-432000) // 5 days ago
        
        // 巴黎路径段：从酒店到埃菲尔铁塔
        let parisPoints = [
            TrackPoint(coordinate: CLLocationCoordinate2D(latitude: 48.8566, longitude: 2.3522), timestamp: startTime, altitude: 35, speed: 0, accuracy: 5),
            TrackPoint(coordinate: CLLocationCoordinate2D(latitude: 48.8570, longitude: 2.3500), timestamp: startTime.addingTimeInterval(300), altitude: 35, speed: 1.2, accuracy: 5),
            TrackPoint(coordinate: CLLocationCoordinate2D(latitude: 48.8575, longitude: 2.3480), timestamp: startTime.addingTimeInterval(600), altitude: 35, speed: 1.3, accuracy: 5),
            TrackPoint(coordinate: CLLocationCoordinate2D(latitude: 48.8580, longitude: 2.3460), timestamp: startTime.addingTimeInterval(900), altitude: 35, speed: 1.1, accuracy: 5),
            TrackPoint(coordinate: CLLocationCoordinate2D(latitude: 48.8584, longitude: 2.2945), timestamp: startTime.addingTimeInterval(1200), altitude: 35, speed: 0, accuracy: 5) // 埃菲尔铁塔
        ]
        
        let segment = PathSegment(
            trackPoints: parisPoints,
            startTime: startTime,
            endTime: startTime.addingTimeInterval(1200),
            isActive: false
        )
        
        return [segment]
    }
    
    private func createTokyoSegments() -> [PathSegment] {
        let startTime = Date().addingTimeInterval(-259200) // 3 days ago
        
        // 东京路径段：从新宿到天空树
        let tokyoPoints = [
            TrackPoint(coordinate: CLLocationCoordinate2D(latitude: 35.6895, longitude: 139.6917), timestamp: startTime, altitude: 40, speed: 0, accuracy: 5), // 新宿
            TrackPoint(coordinate: CLLocationCoordinate2D(latitude: 35.6950, longitude: 139.7000), timestamp: startTime.addingTimeInterval(600), altitude: 40, speed: 2.5, accuracy: 5),
            TrackPoint(coordinate: CLLocationCoordinate2D(latitude: 35.7000, longitude: 139.7050), timestamp: startTime.addingTimeInterval(1200), altitude: 45, speed: 2.3, accuracy: 5),
            TrackPoint(coordinate: CLLocationCoordinate2D(latitude: 35.7101, longitude: 139.8107), timestamp: startTime.addingTimeInterval(1800), altitude: 45, speed: 0, accuracy: 5) // 天空树
        ]
        
        let segment = PathSegment(
            trackPoints: tokyoPoints,
            startTime: startTime,
            endTime: startTime.addingTimeInterval(1800),
            isActive: false
        )
        
        return [segment]
    }
    
    private func createBeijingSegments() -> [PathSegment] {
        let startTime = Date().addingTimeInterval(-86400) // 1 day ago
        
        // 北京路径段：从故宫到天安门
        let beijingPoints = [
            TrackPoint(coordinate: CLLocationCoordinate2D(latitude: 39.9163, longitude: 116.3972), timestamp: startTime, altitude: 50, speed: 0, accuracy: 5), // 故宫
            TrackPoint(coordinate: CLLocationCoordinate2D(latitude: 39.9130, longitude: 116.4000), timestamp: startTime.addingTimeInterval(300), altitude: 50, speed: 1.0, accuracy: 5),
            TrackPoint(coordinate: CLLocationCoordinate2D(latitude: 39.9100, longitude: 116.4030), timestamp: startTime.addingTimeInterval(600), altitude: 50, speed: 1.1, accuracy: 5),
            TrackPoint(coordinate: CLLocationCoordinate2D(latitude: 39.9042, longitude: 116.4074), timestamp: startTime.addingTimeInterval(900), altitude: 50, speed: 0, accuracy: 5) // 天安门
        ]
        
        let segment = PathSegment(
            trackPoints: beijingPoints,
            startTime: startTime,
            endTime: startTime.addingTimeInterval(900),
            isActive: false
        )
        
        return [segment]
    }
}

extension User {
    var visits: [Visit] {
        // Convert journeys to visits for legacy compatibility
        return journeys.flatMap { journey in
            // Create a visit for each journey
            return [Visit(
                visitDate: journey.startDate,
                comment: journey.notes,
                rating: min(5, max(1, Int(journey.totalDistance / 1000))), // Rating based on distance
                weather: nil,
                createdAt: journey.startDate,
                location: Location(
                    name: journey.title,
                    address: nil,
                    city: journey.visitedCities.first,
                    country: journey.visitedCountries.first,
                    latitude: journey.segments.first?.trackPoints.first?.coordinate.latitude ?? 0,
                    longitude: journey.segments.first?.trackPoints.first?.coordinate.longitude ?? 0,
                    category: "journey"
                )
            )]
        }
    }
    
    var visitCount: Int {
        return visits.count
    }
    
    var countriesVisited: [String] {
        return visitedCountries
    }
    
    var citiesVisited: [String] {
        return visitedCities
    }
    
    var recentVisits: [Visit] {
        return visits.sorted { $0.visitDate > $1.visitDate }
    }
}
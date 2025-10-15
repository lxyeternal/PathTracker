import Foundation
import Combine
import CoreLocation

class AuthenticationManager: ObservableObject {
    @Published var isAuthenticated = false
    @Published var currentUser: User?
    @Published var errorMessage: String?
    
    private var cancellables = Set<AnyCancellable>()
    private let firebaseService = FirebaseService.shared
    
    init() {
        setupFirebaseListener()
        setupAuthenticationListener()
        checkAuthenticationStatus()
    }
    
    private func setupFirebaseListener() {
        firebaseService.$isAuthenticated
            .receive(on: DispatchQueue.main)
            .sink { [weak self] isAuth in
                self?.isAuthenticated = isAuth
                if !isAuth {
                    self?.currentUser = nil
                }
            }
            .store(in: &cancellables)
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
        if let userID = UserDefaults.standard.string(forKey: "currentUserID"),
           UUID(uuidString: userID) != nil {
            let user = createUser(
                username: UserDefaults.standard.string(forKey: "currentUsername") ?? "Traveler",
                email: UserDefaults.standard.string(forKey: "currentEmail") ?? "user@example.com"
            )
            currentUser = user
            isAuthenticated = true
        }
    }
    
    private func saveAuthenticationState(user: User) {
        UserDefaults.standard.set(user.id.uuidString, forKey: "currentUserID")
        UserDefaults.standard.set(user.username, forKey: "currentUsername")
        UserDefaults.standard.set(user.email, forKey: "currentEmail")
    }
    
    // MARK: - Firebase Authentication Methods
    
    func signInAnonymously() async {
        do {
            try await firebaseService.signInAnonymously()
            await createUserFromFirebase()
        } catch {
            await MainActor.run {
                self.errorMessage = firebaseService.handleAuthError(error)
            }
        }
    }
    
    func signUp(email: String, password: String, username: String) async {
        do {
            try await firebaseService.signUp(email: email, password: password)
            await createUserFromFirebase(username: username)
        } catch {
            await MainActor.run {
                self.errorMessage = firebaseService.handleAuthError(error)
            }
        }
    }
    
    func signIn(email: String, password: String) async {
        do {
            try await firebaseService.signIn(email: email, password: password)
            await createUserFromFirebase()
        } catch {
            await MainActor.run {
                self.errorMessage = firebaseService.handleAuthError(error)
            }
        }
    }
    
    func logout() {
        do {
            try firebaseService.signOut()
            isAuthenticated = false
            currentUser = nil
            UserDefaults.standard.removeObject(forKey: "currentUserID")
            UserDefaults.standard.removeObject(forKey: "currentUsername")
            UserDefaults.standard.removeObject(forKey: "currentEmail")
        } catch {
            errorMessage = firebaseService.handleAuthError(error)
        }
    }
    
    func deleteAccount() async {
        do {
            try await firebaseService.deleteAccount()
            await MainActor.run {
                self.isAuthenticated = false
                self.currentUser = nil
            }
        } catch {
            await MainActor.run {
                self.errorMessage = firebaseService.handleAuthError(error)
            }
        }
    }
    
    private func createUserFromFirebase(username: String? = nil) async {
        guard let firebaseUser = firebaseService.currentUser else { return }
        
        let user = createUser(
            username: username ?? firebaseUser.displayName ?? "Traveler",
            email: firebaseUser.email ?? "anonymous@example.com"
        )
        
        await MainActor.run {
            self.currentUser = user
            self.saveAuthenticationState(user: user)
        }
    }
    
    func createUser(username: String, email: String) -> User {
        var user = User(
            username: username,
            email: email,
            createdAt: Date()
        )
        
        let sampleJourneys = createSampleJourneys()
        user.journeys = sampleJourneys
        
        return user
    }
    
    private func createSampleJourneys() -> [Journey] {
        let calendar = Calendar.current
        let now = Date()
        
        let parisJourney = Journey(
            title: "巴黎浪漫之旅",
            segments: createParisSegments(),
            startDate: calendar.date(byAdding: .day, value: -5, to: now) ?? now,
            endDate: calendar.date(byAdding: .day, value: -4, to: now) ?? now,
            notes: "在巴黎度过了美好的一天，从埃菲尔铁塔到塞纳河，每一个角落都充满了浪漫"
        )
        
        let tokyoJourney = Journey(
            title: "东京都市探索",
            segments: createTokyoSegments(),
            startDate: calendar.date(byAdding: .day, value: -3, to: now) ?? now,
            endDate: calendar.date(byAdding: .day, value: -2, to: now) ?? now,
            notes: "体验了东京的现代化与传统文化的完美融合"
        )
        
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
        let startTime = Date().addingTimeInterval(-432000)
        
        let parisPoints = [
            TrackPoint(coordinate: CLLocationCoordinate2D(latitude: 48.8566, longitude: 2.3522), timestamp: startTime, altitude: 35, speed: 0, accuracy: 5),
            TrackPoint(coordinate: CLLocationCoordinate2D(latitude: 48.8570, longitude: 2.3500), timestamp: startTime.addingTimeInterval(300), altitude: 35, speed: 1.2, accuracy: 5),
            TrackPoint(coordinate: CLLocationCoordinate2D(latitude: 48.8575, longitude: 2.3480), timestamp: startTime.addingTimeInterval(600), altitude: 35, speed: 1.3, accuracy: 5),
            TrackPoint(coordinate: CLLocationCoordinate2D(latitude: 48.8580, longitude: 2.3460), timestamp: startTime.addingTimeInterval(900), altitude: 35, speed: 1.1, accuracy: 5),
            TrackPoint(coordinate: CLLocationCoordinate2D(latitude: 48.8584, longitude: 2.2945), timestamp: startTime.addingTimeInterval(1200), altitude: 35, speed: 0, accuracy: 5)
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
        let startTime = Date().addingTimeInterval(-259200)
        
        let tokyoPoints = [
            TrackPoint(coordinate: CLLocationCoordinate2D(latitude: 35.6895, longitude: 139.6917), timestamp: startTime, altitude: 40, speed: 0, accuracy: 5),
            TrackPoint(coordinate: CLLocationCoordinate2D(latitude: 35.6950, longitude: 139.7000), timestamp: startTime.addingTimeInterval(600), altitude: 40, speed: 2.5, accuracy: 5),
            TrackPoint(coordinate: CLLocationCoordinate2D(latitude: 35.7000, longitude: 139.7050), timestamp: startTime.addingTimeInterval(1200), altitude: 45, speed: 2.3, accuracy: 5),
            TrackPoint(coordinate: CLLocationCoordinate2D(latitude: 35.7101, longitude: 139.8107), timestamp: startTime.addingTimeInterval(1800), altitude: 45, speed: 0, accuracy: 5)
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
        let startTime = Date().addingTimeInterval(-86400)
        
        let beijingPoints = [
            TrackPoint(coordinate: CLLocationCoordinate2D(latitude: 39.9163, longitude: 116.3972), timestamp: startTime, altitude: 50, speed: 0, accuracy: 5),
            TrackPoint(coordinate: CLLocationCoordinate2D(latitude: 39.9130, longitude: 116.4000), timestamp: startTime.addingTimeInterval(300), altitude: 50, speed: 1.0, accuracy: 5),
            TrackPoint(coordinate: CLLocationCoordinate2D(latitude: 39.9100, longitude: 116.4030), timestamp: startTime.addingTimeInterval(600), altitude: 50, speed: 1.1, accuracy: 5),
            TrackPoint(coordinate: CLLocationCoordinate2D(latitude: 39.9042, longitude: 116.4074), timestamp: startTime.addingTimeInterval(900), altitude: 50, speed: 0, accuracy: 5)
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
        return journeys.flatMap { journey in
            return [Visit(
                visitDate: journey.startDate,
                comment: journey.notes,
                rating: min(5, max(1, Int(journey.totalDistance / 1000))),
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
import CoreLocation
import Foundation
import Combine

class PathTrackingManager: NSObject, ObservableObject {
    private let locationService = CoreLocationService()
    
    @Published var isTracking = false
    @Published var isPaused = false
    @Published var currentLocation: CLLocation?
    @Published var currentJourney: Journey?
    @Published var authorizationStatus: CLAuthorizationStatus = .notDetermined
    
    // 当前路径段
    private var currentSegment: PathSegment?
    
    // 追踪参数
    private let minimumDistance: Double = 5.0 // 最小记录距离（米）
    private let minimumTimeInterval: TimeInterval = 10.0 // 最小记录时间间隔（秒）
    private var lastRecordedLocation: CLLocation?
    private var lastRecordedTime: Date?
    
    override init() {
        super.init()
        setupLocationService()
    }
    
    private func setupLocationService() {
        locationService.delegate = self
        authorizationStatus = locationService.authorizationStatus
        
        // 监听位置服务状态变化
        setupLocationServiceObservers()
        
        print("🗺️ PathTrackingManager初始化完成，使用Apple原生CoreLocation服务")
    }
    
    private func setupLocationServiceObservers() {
        // 监听当前位置变化
        locationService.$currentLocation
            .assign(to: \.currentLocation, on: self)
            .store(in: &cancellables)
        
        // 监听权限状态变化
        locationService.$authorizationStatus
            .assign(to: \.authorizationStatus, on: self)
            .store(in: &cancellables)
    }
    
    private var cancellables = Set<AnyCancellable>()
    
    // MARK: - 权限管理
    
    func requestLocationPermission() {
        print("📍 请求位置权限，当前状态: \(authorizationStatus.description)")
        locationService.requestLocationPermission()
    }
    
    // MARK: - 路径追踪控制
    
    func startTracking(journeyTitle: String = "") {
        guard authorizationStatus == .authorizedWhenInUse || authorizationStatus == .authorizedAlways else {
            requestLocationPermission()
            return
        }
        
        isTracking = true
        
        // 创建新的旅程
        let title = journeyTitle.isEmpty ? "Journey \(Date().formatted(date: .abbreviated, time: .shortened))" : journeyTitle
        currentJourney = Journey(
            title: title,
            startDate: Date(),
            endDate: Date()
        )
        
        // 创建新的路径段
        currentSegment = PathSegment(
            startTime: Date(),
            endTime: Date(),
            isActive: true
        )
        
        locationService.startLocationUpdates()
        
        print("✅ 开始追踪旅程: \(title)")
    }
    
    func stopTracking() {
        guard isTracking else { return }
        
        isTracking = false
        isPaused = false
        locationService.stopLocationUpdates()
        
        // 完成当前路径段
        if var segment = currentSegment {
            segment.endTime = Date()
            segment.isActive = false
            currentJourney?.segments.append(segment)
        }
        
        // 完成当前旅程
        currentJourney?.endDate = Date()
        
        // 保存旅程（这里需要集成到用户数据中）
        if let journey = currentJourney {
            saveJourney(journey)
        }
        
        currentSegment = nil
        
        print("🛑 Stopped tracking")
    }
    
    func pauseTracking() {
        guard isTracking && !isPaused else { return }
        
        isPaused = true
        locationService.stopLocationUpdates()
        
        // 完成当前路径段
        if var segment = currentSegment {
            segment.endTime = Date()
            segment.isActive = false
            currentJourney?.segments.append(segment)
            currentSegment = nil
        }
        
        print("⏸️ Paused tracking")
    }
    
    func resumeTracking() {
        guard isTracking && isPaused else { return }
        
        isPaused = false
        locationService.startLocationUpdates()
        
        // 创建新的路径段
        currentSegment = PathSegment(
            startTime: Date(),
            endTime: Date(),
            isActive: true
        )
        
        print("▶️ Resumed tracking")
    }
    
    // MARK: - 照片管理
    
    func addPhotoToCurrentJourney(_ photo: JourneyPhoto) {
        guard isTracking else { return }
        currentJourney?.photos.append(photo)
    }
    
    // MARK: - 数据处理
    
    private func addTrackPoint(from location: CLLocation) {
        // 检查是否满足记录条件
        if shouldRecordLocation(location) {
            let trackPoint = TrackPoint(
                coordinate: location.coordinate,
                timestamp: location.timestamp,
                altitude: location.altitude,
                speed: location.speed,
                accuracy: location.horizontalAccuracy
            )
            
            currentSegment?.trackPoints.append(trackPoint)
            lastRecordedLocation = location
            lastRecordedTime = location.timestamp
            
            // 实时更新当前路径段的结束时间
            currentSegment?.endTime = location.timestamp
            
            print("📍 Recorded track point: \(location.coordinate)")
        }
    }
    
    private func shouldRecordLocation(_ location: CLLocation) -> Bool {
        // 检查位置精度
        guard location.horizontalAccuracy < 50 else { return false }
        
        // 检查时间间隔
        if let lastTime = lastRecordedTime {
            guard location.timestamp.timeIntervalSince(lastTime) >= minimumTimeInterval else {
                return false
            }
        }
        
        // 检查距离
        if let lastLocation = lastRecordedLocation {
            guard location.distance(from: lastLocation) >= minimumDistance else {
                return false
            }
        }
        
        return true
    }
    
    private func saveJourney(_ journey: Journey) {
        // 这里需要集成到AuthenticationManager或数据持久化系统中
        NotificationCenter.default.post(
            name: NSNotification.Name("JourneyCompleted"),
            object: journey
        )
    }
    
    // MARK: - 地理编码
    
    private func reverseGeocodeLocation(_ location: CLLocation) {
        locationService.reverseGeocode(location: location) { address in
            guard let address = address else { return }
            
            // 获取国家和城市信息
            self.locationService.getCountryAndCity(from: location) { country, city in
                let place = IdentifiedPlace(
                    name: address,
                    type: .unknown,
                    coordinate: location.coordinate,
                    country: country ?? "未知国家",
                    city: city,
                    visitTime: Date(),
                    stayDuration: 0
                )
                
                // 可以添加到当前旅程的地点列表中
                print("🏷️ 识别地点: \(place.name), 国家: \(place.country), 城市: \(place.city ?? "未知")")
            }
        }
    }
    
    // MARK: - 数据查询
    
    func getJourneysForTimeFilter(_ filter: TimeFilter, customStart: Date? = nil, customEnd: Date? = nil) -> [Journey] {
        // For now, return empty array since there's no data source integration yet
        // In the future, this would filter journeys based on the date range
        return []
    }
    
    func getTotalStatsForPeriod(_ filter: TimeFilter) -> (distance: Double, duration: TimeInterval, countries: Int, cities: Int) {
        let journeys = getJourneysForTimeFilter(filter)
        
        let totalDistance = journeys.reduce(0) { $0 + $1.totalDistance }
        let totalDuration = journeys.reduce(0) { $0 + $1.totalDuration }
        let countries = Set(journeys.flatMap { $0.visitedCountries }).count
        let cities = Set(journeys.flatMap { $0.visitedCities }).count
        
        return (totalDistance, totalDuration, countries, cities)
    }
}

// MARK: - LocationServiceDelegate

extension PathTrackingManager: LocationServiceDelegate {
    func locationService(_ service: CoreLocationService, didUpdateLocation location: CLLocation) {
        // currentLocation已经通过Combine自动更新
        
        if isTracking && !isPaused {
            addTrackPoint(from: location)
            
            // 定期进行反向地理编码（降低频率以节省资源）
            if let lastTime = lastRecordedTime,
               location.timestamp.timeIntervalSince(lastTime) >= 60.0 { // 每分钟一次
                reverseGeocodeLocation(location)
            }
        }
    }
    
    func locationService(_ service: CoreLocationService, didChangeAuthorization status: CLAuthorizationStatus) {
        // authorizationStatus已经通过Combine自动更新
        
        switch status {
        case .authorizedWhenInUse, .authorizedAlways:
            if isTracking && !isPaused {
                locationService.startLocationUpdates()
            }
        case .denied, .restricted:
            if isTracking {
                stopTracking()
            }
        default:
            break
        }
    }
    
    func locationService(_ service: CoreLocationService, didFailWithError error: Error) {
        print("❌ 位置服务错误: \(error.localizedDescription)")
    }
}
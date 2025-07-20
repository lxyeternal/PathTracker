import CoreLocation
import Foundation
import Combine

class PathTrackingManager: NSObject, ObservableObject {
    private let locationManager = CLLocationManager()
    private let geocoder = CLGeocoder()
    
    @Published var isTracking = false
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
        setupLocationManager()
    }
    
    private func setupLocationManager() {
        locationManager.delegate = self
        locationManager.desiredAccuracy = kCLLocationAccuracyBest
        locationManager.distanceFilter = 5.0
        locationManager.allowsBackgroundLocationUpdates = false // 需要在Info.plist中配置后台权限才能设为true
        authorizationStatus = locationManager.authorizationStatus
    }
    
    // MARK: - 权限管理
    
    func requestLocationPermission() {
        switch authorizationStatus {
        case .notDetermined:
            locationManager.requestWhenInUseAuthorization()
        case .denied, .restricted:
            // 显示设置提示
            break
        case .authorizedWhenInUse:
            // 可以请求总是授权以支持后台追踪
            locationManager.requestAlwaysAuthorization()
        case .authorizedAlways:
            break
        @unknown default:
            break
        }
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
        
        locationManager.startUpdatingLocation()
        
        print("✅ Started tracking journey: \(title)")
    }
    
    func stopTracking() {
        guard isTracking else { return }
        
        isTracking = false
        locationManager.stopUpdatingLocation()
        
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
        guard isTracking else { return }
        
        locationManager.stopUpdatingLocation()
        
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
        guard isTracking else { return }
        
        locationManager.startUpdatingLocation()
        
        // 创建新的路径段
        currentSegment = PathSegment(
            startTime: Date(),
            endTime: Date(),
            isActive: true
        )
        
        print("▶️ Resumed tracking")
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
        geocoder.reverseGeocodeLocation(location) { [weak self] placemarks, error in
            guard let placemark = placemarks?.first, error == nil else { return }
            
            // 这里可以识别和记录经过的地点
            let place = IdentifiedPlace(
                name: placemark.name ?? "Unknown",
                type: .unknown,
                coordinate: location.coordinate,
                country: placemark.country ?? "Unknown",
                city: placemark.locality,
                visitTime: Date(),
                stayDuration: 0
            )
            
            // 可以添加到当前旅程的地点列表中
            print("🏷️ Identified place: \(place.name) in \(place.country)")
        }
    }
    
    // MARK: - 数据查询
    
    func getJourneysForTimeFilter(_ filter: TimeFilter, customStart: Date? = nil, customEnd: Date? = nil) -> [Journey] {
        let (startDate, endDate): (Date, Date)
        
        if filter == .custom, let customStart = customStart, let customEnd = customEnd {
            startDate = customStart
            endDate = customEnd
        } else {
            let range = filter.dateRange()
            startDate = range.start
            endDate = range.end
        }
        
        // 这里需要从数据源过滤旅程
        // 暂时返回空数组
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

// MARK: - CLLocationManagerDelegate

extension PathTrackingManager: CLLocationManagerDelegate {
    func locationManager(_ manager: CLLocationManager, didUpdateLocations locations: [CLLocation]) {
        guard let location = locations.last else { return }
        
        currentLocation = location
        
        if isTracking {
            addTrackPoint(from: location)
            
            // 定期进行反向地理编码（降低频率以节省资源）
            if let lastTime = lastRecordedTime,
               location.timestamp.timeIntervalSince(lastTime) >= 60.0 { // 每分钟一次
                reverseGeocodeLocation(location)
            }
        }
    }
    
    func locationManager(_ manager: CLLocationManager, didChangeAuthorization status: CLAuthorizationStatus) {
        DispatchQueue.main.async {
            self.authorizationStatus = status
        }
        
        switch status {
        case .authorizedWhenInUse, .authorizedAlways:
            if isTracking {
                locationManager.startUpdatingLocation()
            }
        case .denied, .restricted:
            stopTracking()
        default:
            break
        }
    }
    
    func locationManager(_ manager: CLLocationManager, didFailWithError error: Error) {
        print("❌ Location manager failed with error: \(error.localizedDescription)")
    }
}
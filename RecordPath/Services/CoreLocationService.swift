//
//  CoreLocationService.swift
//  RecordPath
//
//  Apple原生定位服务封装
//

import Foundation
import CoreLocation
import Combine

protocol LocationServiceDelegate: AnyObject {
    func locationService(_ service: CoreLocationService, didUpdateLocation location: CLLocation)
    func locationService(_ service: CoreLocationService, didFailWithError error: Error)
    func locationService(_ service: CoreLocationService, didChangeAuthorization status: CLAuthorizationStatus)
}

class CoreLocationService: NSObject, ObservableObject {
    
    // MARK: - Properties
    weak var delegate: LocationServiceDelegate?
    
    @Published var authorizationStatus: CLAuthorizationStatus = .notDetermined
    @Published var currentLocation: CLLocation?
    @Published var isLocationServicesEnabled = false
    
    // 系统定位管理器
    private var locationManager: CLLocationManager
    
    // 定位配置
    private let desiredAccuracy: CLLocationAccuracy = kCLLocationAccuracyBest
    private let distanceFilter: CLLocationDistance = 5.0
    
    // MARK: - Initialization
    
    override init() {
        locationManager = CLLocationManager()
        super.init()
        setupLocationService()
    }
    
    // MARK: - Setup
    
    private func setupLocationService() {
        print("📍 初始化Apple原生定位服务")
        
        locationManager.delegate = self
        locationManager.desiredAccuracy = desiredAccuracy
        locationManager.distanceFilter = distanceFilter
        locationManager.pausesLocationUpdatesAutomatically = false
        
        // 检查位置服务是否可用
        isLocationServicesEnabled = CLLocationManager.locationServicesEnabled()
        authorizationStatus = locationManager.authorizationStatus
        
        print("✅ CoreLocation服务配置完成")
        print("📊 位置服务可用: \(isLocationServicesEnabled)")
        print("🔐 当前权限状态: \(authorizationStatus.description)")
    }
    
    // MARK: - Public Methods
    
    func requestLocationPermission() {
        print("📍 请求位置权限")
        
        guard isLocationServicesEnabled else {
            print("❌ 设备位置服务未启用")
            let error = NSError(
                domain: "CoreLocationService", 
                code: 1001, 
                userInfo: [NSLocalizedDescriptionKey: "设备位置服务未启用，请在设置中开启位置服务"]
            )
            delegate?.locationService(self, didFailWithError: error)
            return
        }
        
        switch authorizationStatus {
        case .notDetermined:
            locationManager.requestWhenInUseAuthorization()
            print("🔄 请求使用期间位置权限")
        case .denied, .restricted:
            print("❌ 位置权限被拒绝或受限")
            let error = NSError(
                domain: "CoreLocationService", 
                code: 1002, 
                userInfo: [NSLocalizedDescriptionKey: "位置权限被拒绝，请在设置中允许位置访问"]
            )
            delegate?.locationService(self, didFailWithError: error)
        case .authorizedWhenInUse:
            print("✅ 已获得使用期间位置权限")
        case .authorizedAlways:
            print("✅ 已获得始终位置权限")
        @unknown default:
            print("❓ 未知权限状态")
        }
    }
    
    func startLocationUpdates() {
        print("▶️ 开始位置更新")
        
        guard isLocationServicesEnabled else {
            print("❌ 位置服务未启用，无法开始更新")
            return
        }
        
        guard authorizationStatus == .authorizedWhenInUse || authorizationStatus == .authorizedAlways else {
            print("❌ 位置权限不足")
            requestLocationPermission()
            return
        }
        
        locationManager.startUpdatingLocation()
        print("✅ 位置更新已启动")
    }
    
    func stopLocationUpdates() {
        print("⏹️ 停止位置更新")
        locationManager.stopUpdatingLocation()
    }
    
    func requestOneTimeLocation() {
        print("📍 请求单次位置")
        
        guard authorizationStatus == .authorizedWhenInUse || authorizationStatus == .authorizedAlways else {
            print("❌ 位置权限不足")
            requestLocationPermission()
            return
        }
        
        locationManager.requestLocation()
    }
    
    // MARK: - Location Utilities
    
    func reverseGeocode(location: CLLocation, completion: @escaping (String?) -> Void) {
        print("🔍 反向地理编码：\(location.coordinate)")
        
        let geocoder = CLGeocoder()
        geocoder.reverseGeocodeLocation(location) { placemarks, error in
            DispatchQueue.main.async {
                if let error = error {
                    print("❌ 反向地理编码失败：\(error.localizedDescription)")
                    completion(nil)
                    return
                }
                
                guard let placemark = placemarks?.first else {
                    print("⚠️ 未找到地址信息")
                    completion(nil)
                    return
                }
                
                var addressComponents: [String] = []
                
                // 构建地址（优先中文地址）
                if let name = placemark.name, !name.isEmpty {
                    addressComponents.append(name)
                }
                if let thoroughfare = placemark.thoroughfare, thoroughfare != placemark.name {
                    addressComponents.append(thoroughfare)
                }
                if let locality = placemark.locality {
                    addressComponents.append(locality)
                }
                if let administrativeArea = placemark.administrativeArea {
                    addressComponents.append(administrativeArea)
                }
                if let country = placemark.country {
                    addressComponents.append(country)
                }
                
                let address = addressComponents.joined(separator: ", ")
                print("✅ 地址解析完成：\(address)")
                completion(address.isEmpty ? nil : address)
            }
        }
    }
    
    func getLocationName(from location: CLLocation, completion: @escaping (String) -> Void) {
        reverseGeocode(location: location) { address in
            if let address = address {
                // 提取主要地名（通常是第一个组件）
                let components = address.components(separatedBy: ", ")
                let locationName = components.first ?? address
                completion(locationName)
            } else {
                completion("未知位置")
            }
        }
    }
    
    func getCountryAndCity(from location: CLLocation, completion: @escaping (String?, String?) -> Void) {
        let geocoder = CLGeocoder()
        geocoder.reverseGeocodeLocation(location) { placemarks, error in
            DispatchQueue.main.async {
                guard let placemark = placemarks?.first else {
                    completion(nil, nil)
                    return
                }
                
                let country = placemark.country
                let city = placemark.locality ?? placemark.administrativeArea
                completion(country, city)
            }
        }
    }
    
    // MARK: - Utility Methods
    
    func calculateDistance(from: CLLocation, to: CLLocation) -> Double {
        return from.distance(from: to)
    }
    
    func isValidLocation(_ location: CLLocation) -> Bool {
        // 检查位置的有效性
        return location.horizontalAccuracy > 0 && 
               location.horizontalAccuracy < 100 && // 精度小于100米
               abs(location.timestamp.timeIntervalSinceNow) < 30 // 时间戳不超过30秒
    }
}

// MARK: - CLLocationManagerDelegate

extension CoreLocationService: CLLocationManagerDelegate {
    
    func locationManager(_ manager: CLLocationManager, didUpdateLocations locations: [CLLocation]) {
        guard let location = locations.last else { return }
        
        // 验证位置有效性
        guard isValidLocation(location) else {
            print("⚠️ 位置数据无效，忽略：accuracy=\(location.horizontalAccuracy)m, age=\(abs(location.timestamp.timeIntervalSinceNow))s")
            return
        }
        
        print("📍 位置更新：lat:\(String(format: "%.6f", location.coordinate.latitude)), lon:\(String(format: "%.6f", location.coordinate.longitude)), accuracy:\(String(format: "%.1f", location.horizontalAccuracy))m")
        
        DispatchQueue.main.async {
            self.currentLocation = location
        }
        
        delegate?.locationService(self, didUpdateLocation: location)
    }
    
    func locationManager(_ manager: CLLocationManager, didFailWithError error: Error) {
        print("❌ 定位失败：\(error.localizedDescription)")
        
        if let clError = error as? CLError {
            switch clError.code {
            case .denied:
                print("❌ 位置权限被拒绝")
            case .locationUnknown:
                print("❌ 无法确定位置")
            case .network:
                print("❌ 网络错误")
            default:
                print("❌ 其他定位错误：\(clError.localizedDescription)")
            }
        }
        
        delegate?.locationService(self, didFailWithError: error)
    }
    
    func locationManager(_ manager: CLLocationManager, didChangeAuthorization status: CLAuthorizationStatus) {
        print("🔐 权限状态变更：\(status.description)")
        
        DispatchQueue.main.async {
            self.authorizationStatus = status
        }
        
        delegate?.locationService(self, didChangeAuthorization: status)
        
        switch status {
        case .authorizedWhenInUse, .authorizedAlways:
            print("✅ 位置权限已获得")
            if CLLocationManager.locationServicesEnabled() {
                print("📍 位置服务已启用")
            }
        case .denied, .restricted:
            print("❌ 位置权限被拒绝")
            stopLocationUpdates()
        case .notDetermined:
            print("⏳ 位置权限待确定")
        @unknown default:
            print("❓ 未知权限状态")
        }
    }
}

// MARK: - Authorization Status Extensions

extension CLAuthorizationStatus {
    var description: String {
        switch self {
        case .notDetermined: return "未确定"
        case .restricted: return "受限"
        case .denied: return "拒绝"
        case .authorizedAlways: return "始终授权"
        case .authorizedWhenInUse: return "使用时授权"
        @unknown default: return "未知"
        }
    }
    
    var isAuthorized: Bool {
        return self == .authorizedWhenInUse || self == .authorizedAlways
    }
}

// MARK: - Backward Compatibility

// 为了保持向后兼容性，创建一个类型别名
typealias AMapLocationService = CoreLocationService
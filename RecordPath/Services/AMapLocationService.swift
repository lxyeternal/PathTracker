//
//  AMapLocationService.swift
//  RecordPath
//
//  高德地图定位服务封装
//

import Foundation
import CoreLocation
import Combine
#if !targetEnvironment(simulator)
import AMapLocationKit
#endif

protocol LocationServiceDelegate: AnyObject {
    func locationService(_ service: AMapLocationService, didUpdateLocation location: CLLocation)
    func locationService(_ service: AMapLocationService, didFailWithError error: Error)
    func locationService(_ service: AMapLocationService, didChangeAuthorization status: CLAuthorizationStatus)
}

class AMapLocationService: NSObject, ObservableObject {
    
    // MARK: - Properties
    weak var delegate: LocationServiceDelegate?
    
    @Published var authorizationStatus: CLAuthorizationStatus = .notDetermined
    @Published var currentLocation: CLLocation?
    @Published var isLocationServicesEnabled = false
    
    // 高德地图定位管理器
    #if !targetEnvironment(simulator)
    private var amapLocationManager: AMapLocationManager?
    #endif
    
    // 备用系统定位管理器
    private var systemLocationManager: CLLocationManager?
    
    // 定位配置
    private let desiredAccuracy: CLLocationAccuracy = kCLLocationAccuracyBest
    private let distanceFilter: CLLocationDistance = 5.0
    
    // MARK: - Initialization
    
    override init() {
        super.init()
        setupLocationService()
    }
    
    // MARK: - Setup
    
    private func setupLocationService() {
        print("🗺️ 初始化高德地图定位服务")
        
        // 启用高德地图定位管理器
        setupAMapLocationManager()
        
        // 备用系统定位管理器
        setupSystemLocationManager()
    }
    
    // 高德地图定位管理器配置
    private func setupAMapLocationManager() {
        #if !targetEnvironment(simulator)
        amapLocationManager = AMapLocationManager()
        amapLocationManager?.delegate = self
        amapLocationManager?.pausesLocationUpdatesAutomatically = false
        amapLocationManager?.allowsBackgroundLocationUpdates = false // 根据需要配置
        
        // 设置定位精度
        amapLocationManager?.desiredAccuracy = kCLLocationAccuracyBest
        amapLocationManager?.locationTimeout = 10
        amapLocationManager?.reGeocodeTimeout = 5
        
        print("✅ 高德地图定位管理器配置完成")
        #else
        print("⚠️ 模拟器环境：跳过高德地图配置")
        #endif
    }
    
    // 临时系统定位管理器（开发阶段使用）
    private func setupSystemLocationManager() {
        systemLocationManager = CLLocationManager()
        systemLocationManager?.delegate = self
        systemLocationManager?.desiredAccuracy = desiredAccuracy
        systemLocationManager?.distanceFilter = distanceFilter
        systemLocationManager?.pausesLocationUpdatesAutomatically = false
        
        authorizationStatus = systemLocationManager?.authorizationStatus ?? .notDetermined
        print("⚠️ 使用系统定位管理器（临时）")
    }
    
    // MARK: - Public Methods
    
    func requestLocationPermission() {
        print("📍 请求位置权限")
        
        // 高德地图权限请求（通过系统CLLocationManager处理）
        // AMap的权限管理是通过系统CLLocationManager完成的
        
        // 临时使用系统权限请求
        guard let manager = systemLocationManager else { return }
        
        switch authorizationStatus {
        case .notDetermined:
            manager.requestWhenInUseAuthorization()
        case .denied, .restricted:
            print("❌ 位置权限被拒绝或受限")
        default:
            break
        }
    }
    
    func startLocationUpdates() {
        print("▶️ 开始位置更新")
        
        guard authorizationStatus == .authorizedWhenInUse || authorizationStatus == .authorizedAlways else {
            print("❌ 位置权限不足")
            requestLocationPermission()
            return
        }
        
        // 高德地图开始定位
        #if !targetEnvironment(simulator)
        amapLocationManager?.startUpdatingLocation()
        #endif
        
        // 备用系统定位（模拟器上启用）
        #if targetEnvironment(simulator)
        systemLocationManager?.startUpdatingLocation()
        #endif
    }
    
    func stopLocationUpdates() {
        print("⏹️ 停止位置更新")
        
        // 高德地图停止定位
        #if !targetEnvironment(simulator)
        amapLocationManager?.stopUpdatingLocation()
        #endif
        
        // 备用系统定位
        systemLocationManager?.stopUpdatingLocation()
    }
    
    // MARK: - Location Utilities
    
    func reverseGeocode(location: CLLocation, completion: @escaping (String?) -> Void) {
        print("🔍 反向地理编码：\(location.coordinate)")
        
        /*
        // TODO: 使用高德地图的反向地理编码
        // 这里可以使用AMapSearchKit进行反向地理编码
        // 获得更准确的中文地址信息
        */
        
        // 临时使用系统反向地理编码
        let geocoder = CLGeocoder()
        geocoder.reverseGeocodeLocation(location) { placemarks, error in
            if let error = error {
                print("❌ 反向地理编码失败：\(error.localizedDescription)")
                completion(nil)
                return
            }
            
            guard let placemark = placemarks?.first else {
                completion(nil)
                return
            }
            
            var addressComponents: [String] = []
            
            // 构建中文地址
            if let country = placemark.country {
                addressComponents.append(country)
            }
            if let administrativeArea = placemark.administrativeArea {
                addressComponents.append(administrativeArea)
            }
            if let locality = placemark.locality {
                addressComponents.append(locality)
            }
            if let thoroughfare = placemark.thoroughfare {
                addressComponents.append(thoroughfare)
            }
            if let name = placemark.name, name != placemark.thoroughfare {
                addressComponents.append(name)
            }
            
            let address = addressComponents.joined(separator: " ")
            print("✅ 地址解析完成：\(address)")
            completion(address.isEmpty ? nil : address)
        }
    }
    
    func getLocationName(from location: CLLocation, completion: @escaping (String) -> Void) {
        reverseGeocode(location: location) { address in
            if let address = address {
                // 提取主要地名
                let components = address.components(separatedBy: " ")
                let locationName = components.last ?? address
                completion(locationName)
            } else {
                completion("未知位置")
            }
        }
    }
}

// MARK: - CLLocationManagerDelegate (临时使用)

extension AMapLocationService: CLLocationManagerDelegate {
    
    func locationManager(_ manager: CLLocationManager, didUpdateLocations locations: [CLLocation]) {
        guard let location = locations.last else { return }
        
        // 过滤无效位置
        guard location.horizontalAccuracy < 100 && location.horizontalAccuracy > 0 else {
            print("⚠️ 位置精度不足，忽略：\(location.horizontalAccuracy)m")
            return
        }
        
        print("📍 位置更新：lat:\(location.coordinate.latitude), lon:\(location.coordinate.longitude), accuracy:\(location.horizontalAccuracy)m")
        
        DispatchQueue.main.async {
            self.currentLocation = location
        }
        
        delegate?.locationService(self, didUpdateLocation: location)
    }
    
    func locationManager(_ manager: CLLocationManager, didFailWithError error: Error) {
        print("❌ 定位失败：\(error.localizedDescription)")
        delegate?.locationService(self, didFailWithError: error)
    }
    
    func locationManager(_ manager: CLLocationManager, didChangeAuthorization status: CLAuthorizationStatus) {
        print("🔐 权限状态变更：\(status.rawValue)")
        
        DispatchQueue.main.async {
            self.authorizationStatus = status
        }
        
        delegate?.locationService(self, didChangeAuthorization: status)
        
        switch status {
        case .authorizedWhenInUse, .authorizedAlways:
            print("✅ 位置权限已获得")
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

// MARK: - AMapLocationManagerDelegate

#if !targetEnvironment(simulator)
extension AMapLocationService: AMapLocationManagerDelegate {
    
    func amapLocationManager(_ manager: AMapLocationManager!, didUpdate location: CLLocation!) {
        guard let location = location else { return }
        
        print("🗺️ 高德定位更新：lat:\(location.coordinate.latitude), lon:\(location.coordinate.longitude), accuracy:\(location.horizontalAccuracy)m")
        
        DispatchQueue.main.async {
            self.currentLocation = location
        }
        
        delegate?.locationService(self, didUpdateLocation: location)
    }
    
    func amapLocationManager(_ manager: AMapLocationManager!, didFailWithError error: Error!) {
        print("❌ 高德定位失败：\(error.localizedDescription)")
        delegate?.locationService(self, didFailWithError: error)
    }
    
    func amapLocationManager(_ manager: AMapLocationManager!, didChange status: CLAuthorizationStatus) {
        print("🔐 高德定位权限变更：\(status.rawValue)")
        
        DispatchQueue.main.async {
            self.authorizationStatus = status
        }
        
        delegate?.locationService(self, didChangeAuthorization: status)
    }
}
#endif

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
}
//
//  RecordPathApp.swift
//  RecordPath
//
//  Created by Blue on 14/7/25.
//

import SwiftUI
#if !targetEnvironment(simulator)
import AMapFoundationKit
#endif

@main
struct RecordPathApp: App {
    
    init() {
        // 配置高德地图API Key
        configureAMapServices()
    }
    
    var body: some Scene {
        WindowGroup {
            ContentView()
        }
    }
    
    private func configureAMapServices() {
        #if !targetEnvironment(simulator)
        AMapServices.shared().apiKey = "b8383a545b59835164229ea06feedf86"
        AMapServices.shared().enableHTTPS = true
        print("✅ 高德地图SDK配置完成，API Key: b8383a545b59835164229ea06feedf86")
        #else
        print("⚠️ 模拟器环境：使用CoreLocation备用方案")
        #endif
    }
}

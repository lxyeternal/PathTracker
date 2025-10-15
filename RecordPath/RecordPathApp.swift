//
//  RecordPathApp.swift
//  RecordPath
//
//  Created by Blue on 14/7/25.
//

import SwiftUI
import Firebase

@main
struct RecordPathApp: App {
    
    init() {
        configureFirebase()
        configureLocationServices()
    }
    
    var body: some Scene {
        WindowGroup {
            ContentView()
        }
    }
    
    private func configureFirebase() {
        FirebaseApp.configure()
        print("🔥 Firebase 已初始化")
    }
    
    private func configureLocationServices() {
        print("✅ 使用Apple原生CoreLocation服务")
        print("📍 应用启动完成，准备使用系统定位服务")
    }
}

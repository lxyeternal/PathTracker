//
//  ContentView.swift
//  RecordPath
//
//  Created by Blue on 14/7/25.
//

import SwiftUI

struct ContentView: View {
    @StateObject private var authManager = AuthenticationManager()
    @StateObject private var pathTrackingManager = PathTrackingManager()
    
    var body: some View {
        Group {
            if authManager.isAuthenticated {
                DashboardView()
                    .environmentObject(authManager)
                    .environmentObject(pathTrackingManager)
            } else {
                AuthenticationView()
                    .environmentObject(authManager)
            }
        }
        .animation(.easeInOut(duration: 0.3), value: authManager.isAuthenticated)
    }
}

#Preview {
    ContentView()
}

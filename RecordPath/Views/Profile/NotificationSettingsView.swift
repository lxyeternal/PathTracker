import SwiftUI

struct NotificationSettingsView: View {
    @Environment(\.dismiss) private var dismiss
    @State private var journeyReminders = true
    @State private var locationAlerts = false
    @State private var weeklyDigest = true
    @State private var socialUpdates = true
    @State private var promotionalContent = false
    
    var body: some View {
        NavigationView {
            Form {
                Section("Journey Notifications") {
                    Toggle("Journey Reminders", isOn: $journeyReminders)
                    Toggle("Location Alerts", isOn: $locationAlerts)
                    
                    Text("Get notified about interesting places near your current location or reminders to record your journeys.")
                        .font(.caption)
                        .foregroundColor(.secondary)
                }
                
                Section("Regular Updates") {
                    Toggle("Weekly Digest", isOn: $weeklyDigest)
                    Toggle("Social Updates", isOn: $socialUpdates)
                    
                    Text("Receive weekly summaries of your travels and updates from fellow travelers.")
                        .font(.caption)
                        .foregroundColor(.secondary)
                }
                
                Section("Marketing") {
                    Toggle("Promotional Content", isOn: $promotionalContent)
                    
                    Text("Receive information about new features, travel deals, and special offers.")
                        .font(.caption)
                        .foregroundColor(.secondary)
                }
                
                Section("Notification Schedule") {
                    HStack {
                        Text("Quiet Hours")
                        Spacer()
                        Text("10:00 PM - 8:00 AM")
                            .foregroundColor(.secondary)
                    }
                    
                    Button("Customize Schedule") {
                        // Handle schedule customization
                    }
                }
            }
            .navigationTitle("Notifications")
            .navigationBarTitleDisplayMode(.inline)
            .navigationBarItems(
                trailing: Button("Done") { dismiss() }
            )
        }
    }
}

#Preview {
    NotificationSettingsView()
}
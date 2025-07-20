import SwiftUI

struct PrivacySettingsView: View {
    @Environment(\.dismiss) private var dismiss
    @State private var locationSharing = true
    @State private var dataCollection = false
    @State private var analytics = true
    @State private var crashReporting = true
    
    var body: some View {
        NavigationView {
            Form {
                Section("Location Privacy") {
                    Toggle("Allow Location Sharing", isOn: $locationSharing)
                    
                    Text("When enabled, your location data may be used to enhance your travel experience and provide better recommendations.")
                        .font(.caption)
                        .foregroundColor(.secondary)
                }
                
                Section("Data Collection") {
                    Toggle("Usage Data Collection", isOn: $dataCollection)
                    Toggle("Analytics", isOn: $analytics)
                    Toggle("Crash Reporting", isOn: $crashReporting)
                    
                    Text("Help us improve the app by sharing anonymous usage data and crash reports.")
                        .font(.caption)
                        .foregroundColor(.secondary)
                }
                
                Section("Data Management") {
                    Button("Download My Data") {
                        // Handle data download
                    }
                    
                    Button("Delete My Data") {
                        // Handle data deletion
                    }
                    .foregroundColor(.red)
                }
                
                Section("Privacy Policy") {
                    Button("View Privacy Policy") {
                        // Open privacy policy
                    }
                    
                    Button("View Terms of Service") {
                        // Open terms of service
                    }
                }
            }
            .navigationTitle("Privacy Settings")
            .navigationBarTitleDisplayMode(.inline)
            .navigationBarItems(
                trailing: Button("Done") { dismiss() }
            )
        }
    }
}

#Preview {
    PrivacySettingsView()
}
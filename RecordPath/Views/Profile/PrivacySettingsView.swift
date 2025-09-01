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
                Section("位置隐私") {
                    Toggle("允许位置共享", isOn: $locationSharing)
                    
                    Text("启用后，您的位置数据可能会用于增强您的旅行体验并提供更好的建议。")
                        .font(.caption)
                        .foregroundColor(.secondary)
                }
                
                Section("数据收集") {
                    Toggle("使用数据收集", isOn: $dataCollection)
                    Toggle("分析", isOn: $analytics)
                    Toggle("崩溃报告", isOn: $crashReporting)
                    
                    Text("通过分享匿名使用数据和崩溃报告来帮助我们改进应用。")
                        .font(.caption)
                        .foregroundColor(.secondary)
                }
                
                Section("数据管理") {
                    Button("下载我的数据") {
                        // Handle data download
                    }
                    
                    Button("删除我的数据") {
                        // Handle data deletion
                    }
                    .foregroundColor(.red)
                }
                
                Section("隐私政策") {
                    Button("查看隐私政策") {
                        // Open privacy policy
                    }
                    
                    Button("查看服务条款") {
                        // Open terms of service
                    }
                }
            }
            .navigationTitle("隐私设置")
            .navigationBarTitleDisplayMode(.inline)
            .navigationBarItems(
                trailing: Button("完成") { dismiss() }
            )
        }
    }
}

#Preview {
    PrivacySettingsView()
}
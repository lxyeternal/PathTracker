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
                Section("行程通知") {
                    Toggle("行程提醒", isOn: $journeyReminders)
                    Toggle("位置提醒", isOn: $locationAlerts)
                    
                    Text("获取关于您当前位置附近有趣地方的通知，或提醒您记录行程。")
                        .font(.caption)
                        .foregroundColor(.secondary)
                }
                
                Section("定期更新") {
                    Toggle("每周摘要", isOn: $weeklyDigest)
                    Toggle("社交动态", isOn: $socialUpdates)
                    
                    Text("接收您的旅行每周摘要以及来自其他旅行者的更新。")
                        .font(.caption)
                        .foregroundColor(.secondary)
                }
                
                Section("市场营销") {
                    Toggle("推广内容", isOn: $promotionalContent)
                    
                    Text("接收有关新功能、旅行优惠和特别优惠的信息。")
                        .font(.caption)
                        .foregroundColor(.secondary)
                }
                
                Section("通知时间表") {
                    HStack {
                        Text("静默时段")
                        Spacer()
                        Text("晚上10:00 - 早上8:00")
                            .foregroundColor(.secondary)
                    }
                    
                    Button("自定义时间表") {
                        // Handle schedule customization
                    }
                }
            }
            .navigationTitle("通知")
            .navigationBarTitleDisplayMode(.inline)
            .navigationBarItems(
                trailing: Button("完成") { dismiss() }
            )
        }
    }
}

#Preview {
    NotificationSettingsView()
}
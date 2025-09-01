import SwiftUI

struct ExportDataView: View {
    @Environment(\.dismiss) private var dismiss
    @EnvironmentObject var authManager: AuthenticationManager
    @State private var selectedFormat: ExportFormat = .json
    @State private var includePhotos = true
    @State private var dateRange: ExportDateRange = .all
    @State private var isExporting = false
    @State private var showingSuccessAlert = false
    
    var body: some View {
        NavigationView {
            Form {
                Section("导出格式") {
                    Picker("格式", selection: $selectedFormat) {
                        ForEach(ExportFormat.allCases, id: \.self) { format in
                            HStack {
                                Image(systemName: format.icon)
                                Text(format.rawValue)
                            }
                            .tag(format)
                        }
                    }
                    .pickerStyle(SegmentedPickerStyle())
                    
                    Text(selectedFormat.description)
                        .font(.caption)
                        .foregroundColor(.secondary)
                }
                
                Section("数据选项") {
                    Toggle("包含照片", isOn: $includePhotos)
                    
                    Picker("日期范围", selection: $dateRange) {
                        ForEach(ExportDateRange.allCases, id: \.self) { range in
                            Text(range.rawValue).tag(range)
                        }
                    }
                    
                    if !includePhotos {
                        Text("照片将被排除以减小文件大小。")
                            .font(.caption)
                            .foregroundColor(.secondary)
                    }
                }
                
                Section("数据摘要") {
                    if let user = authManager.currentUser {
                        HStack {
                            Text("行程")
                            Spacer()
                            Text("\(user.totalJourneys)")
                                .foregroundColor(.secondary)
                        }
                        
                        HStack {
                            Text("照片")
                            Spacer()
                            Text("\(includePhotos ? user.totalPhotos : 0)")
                                .foregroundColor(.secondary)
                        }
                        
                        HStack {
                            Text("访问过的国家")
                            Spacer()
                            Text("\(user.visitedCountries.count)")
                                .foregroundColor(.secondary)
                        }
                        
                        HStack {
                            Text("预计大小")
                            Spacer()
                            Text(estimatedFileSize)
                                .foregroundColor(.secondary)
                        }
                    }
                }
                
                Section {
                    Button(action: exportData) {
                        HStack {
                            if isExporting {
                                ProgressView()
                                    .scaleEffect(0.8)
                            } else {
                                Image(systemName: "square.and.arrow.up")
                            }
                            
                            Text(isExporting ? "正在导出..." : "导出数据")
                        }
                        .frame(maxWidth: .infinity)
                    }
                    .disabled(isExporting)
                }
            }
            .navigationTitle("导出数据")
            .navigationBarTitleDisplayMode(.inline)
            .navigationBarItems(
                trailing: Button("完成") { dismiss() }
            )
        }
        .alert("导出完成", isPresented: $showingSuccessAlert) {
            Button("好的") { dismiss() }
        } message: {
            Text("您的数据已成功导出并保存到“文件”应用中。")
        }
    }
    
    private var estimatedFileSize: String {
        guard let user = authManager.currentUser else { return "0 MB" }
        
        let baseSize = user.totalJourneys * 50 // 50KB per journey
        let photoSize = includePhotos ? user.totalPhotos * 500 : 0 // 500KB per photo
        let totalKB = baseSize + photoSize
        
        if totalKB < 1024 {
            return "\(totalKB) KB"
        } else {
            let totalMB = Double(totalKB) / 1024.0
            return String(format: "%.1f MB", totalMB)
        }
    }
    
    private func exportData() {
        isExporting = true
        
        // Simulate export process
        DispatchQueue.main.asyncAfter(deadline: .now() + 2) {
            isExporting = false
            showingSuccessAlert = true
        }
    }
}

enum ExportFormat: String, CaseIterable {
    case json = "JSON"
    case gpx = "GPX"
    case kml = "KML"
    
    var icon: String {
        switch self {
        case .json: return "doc.text"
        case .gpx: return "map"
        case .kml: return "globe"
        }
    }
    
    var description: String {
        switch self {
        case .json: return "人类可读格式，包含所有数据"
        case .gpx: return "GPS交换格式，与大多数GPS设备兼容"
        case .kml: return "用于可视化的谷歌地球格式"
        }
    }
}

enum ExportDateRange: String, CaseIterable {
    case all = "全部时间"
    case thisYear = "今年"
    case lastSixMonths = "过去6个月"
    case lastMonth = "上个月"
}

#Preview {
    ExportDataView()
        .environmentObject(AuthenticationManager())
}
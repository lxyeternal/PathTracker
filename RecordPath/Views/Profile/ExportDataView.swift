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
                Section("Export Format") {
                    Picker("Format", selection: $selectedFormat) {
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
                
                Section("Data Options") {
                    Toggle("Include Photos", isOn: $includePhotos)
                    
                    Picker("Date Range", selection: $dateRange) {
                        ForEach(ExportDateRange.allCases, id: \.self) { range in
                            Text(range.rawValue).tag(range)
                        }
                    }
                    
                    if !includePhotos {
                        Text("Photos will be excluded to reduce file size.")
                            .font(.caption)
                            .foregroundColor(.secondary)
                    }
                }
                
                Section("Data Summary") {
                    if let user = authManager.currentUser {
                        HStack {
                            Text("Journeys")
                            Spacer()
                            Text("\(user.totalJourneys)")
                                .foregroundColor(.secondary)
                        }
                        
                        HStack {
                            Text("Photos")
                            Spacer()
                            Text("\(includePhotos ? user.totalPhotos : 0)")
                                .foregroundColor(.secondary)
                        }
                        
                        HStack {
                            Text("Countries Visited")
                            Spacer()
                            Text("\(user.visitedCountries.count)")
                                .foregroundColor(.secondary)
                        }
                        
                        HStack {
                            Text("Estimated Size")
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
                            
                            Text(isExporting ? "Exporting..." : "Export Data")
                        }
                        .frame(maxWidth: .infinity)
                    }
                    .disabled(isExporting)
                }
            }
            .navigationTitle("Export Data")
            .navigationBarTitleDisplayMode(.inline)
            .navigationBarItems(
                trailing: Button("Done") { dismiss() }
            )
        }
        .alert("Export Complete", isPresented: $showingSuccessAlert) {
            Button("OK") { dismiss() }
        } message: {
            Text("Your data has been exported successfully and saved to Files.")
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
        case .json: return "Human-readable format with all data included"
        case .gpx: return "GPS exchange format, compatible with most GPS devices"
        case .kml: return "Google Earth format for visualization"
        }
    }
}

enum ExportDateRange: String, CaseIterable {
    case all = "All Time"
    case thisYear = "This Year"
    case lastSixMonths = "Last 6 Months"
    case lastMonth = "Last Month"
}

#Preview {
    ExportDataView()
        .environmentObject(AuthenticationManager())
}
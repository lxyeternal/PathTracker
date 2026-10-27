import Foundation
import UIKit
import CoreLocation

/// A plain-text log of what recording did, kept on the device so a tester can export it from
/// Settings. Coordinates are rounded to about 100 m, so the log never holds an exact address.
enum Diagnostics {
    private static let queue = DispatchQueue(label: "Diagnostics")
    private static let maxBytes = 3_000_000

    static var fileURL: URL { URL.documentsDirectory.appending(path: "Waytrace-diagnostics.log") }

    /// Counters summarised once a minute instead of one line per GPS fix.
    private nonisolated(unsafe) static var counters: [String: Int] = [:]
    private nonisolated(unsafe) static var lastSummary = Date()

    static func record(_ event: String) {
        let stamp = Date().formatted(.iso8601.year().month().day().time(includingFractionalSeconds: false).timeSeparator(.colon))
        let line = "\(stamp) \(event)\n"
        queue.async {
            let url = fileURL
            if let size = try? FileManager.default.attributesOfItem(atPath: url.path)[.size] as? Int, size > maxBytes {
                // Keep the newer half.
                if let data = try? Data(contentsOf: url) {
                    try? data.suffix(maxBytes / 2).write(to: url)
                }
            }
            if let handle = try? FileHandle(forWritingTo: url) {
                handle.seekToEndOfFile()
                handle.write(Data(line.utf8))
                try? handle.close()
            } else {
                try? Data(line.utf8).write(to: url)
            }
        }
    }

    /// Counts a frequent event ("fix", "jump") and writes the totals every minute.
    static func count(_ name: String) {
        queue.async {
            counters[name, default: 0] += 1
            guard Date().timeIntervalSince(lastSummary) >= 60 else { return }
            let summary = counters.sorted { $0.key < $1.key }.map { "\($0.key)=\($0.value)" }.joined(separator: " ")
            counters = [:]
            lastSummary = Date()
            DispatchQueue.main.async { record("minute \(summary) \(battery)") }
        }
    }

    @MainActor
    static func launched() {
        UIDevice.current.isBatteryMonitoringEnabled = true
        let state = UIApplication.shared.applicationState
        let how = state == .background ? "background (relaunched by iOS)" : "foreground"
        let version = Bundle.main.infoDictionary?["CFBundleShortVersionString"] as? String ?? "?"
        let build = Bundle.main.infoDictionary?["CFBundleVersion"] as? String ?? "?"
        record("launch \(how) app=\(version)(\(build)) iOS=\(UIDevice.current.systemVersion) \(battery)")
    }

    static var battery: String {
        let level = UIDevice.current.batteryLevel
        return level < 0 ? "battery=?" : "battery=\(Int(level * 100))%"
    }

    /// "31.23,121.47 ±12m"
    static func describe(_ location: CLLocation) -> String {
        String(format: "%.3f,%.3f ±%.0fm speed=%.1f", location.coordinate.latitude, location.coordinate.longitude,
               location.horizontalAccuracy, max(location.speed, 0))
    }

    static func clear() {
        queue.async { try? FileManager.default.removeItem(at: fileURL) }
    }
}

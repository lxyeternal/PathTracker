import Foundation
import MetricKit

/// Writes what iOS says about the last crash or hang into the diagnostics log, so someone whose
/// app keeps closing can export the log from Settings and it says why. iOS hands these over the
/// next time the app runs; nothing leaves the phone unless the person shares the log.
final class CrashReports: NSObject, MXMetricManagerSubscriber {
    static let shared = CrashReports()

    func start() {
        MXMetricManager.shared.add(self)
    }

    func didReceive(_ payloads: [MXDiagnosticPayload]) {
        for payload in payloads {
            for crash in payload.crashDiagnostics ?? [] {
                Diagnostics.record(Self.line(
                    "crash", meta: crash.metaData,
                    details: ["type": crash.exceptionType?.stringValue, "code": crash.exceptionCode?.stringValue,
                              "signal": crash.signal?.stringValue, "reason": crash.terminationReason],
                    stack: crash.callStackTree.jsonRepresentation()))
            }
            for hang in payload.hangDiagnostics ?? [] {
                let seconds = hang.hangDuration.converted(to: .seconds).value
                Diagnostics.record(Self.line("hang", meta: hang.metaData, details: ["seconds": String(format: "%.1f", seconds)],
                                             stack: hang.callStackTree.jsonRepresentation()))
            }
        }
    }

    static func line(_ kind: String, meta: MXMetaData, details: [String: String?], stack: Data) -> String {
        let said = details.sorted { $0.key < $1.key }.compactMap { key, value in value.map { "\(key)=\($0)" } }.joined(separator: " ")
        return "\(kind) app=\(meta.applicationBuildVersion) os=\(meta.osVersion) device=\(meta.deviceType) \(said) frames=\(frames(in: stack).joined(separator: " < "))"
    }

    /// The top of the stack that crashed, as "binary+offset": enough to find the line with the
    /// build's symbols, and short enough for one line of the log.
    static func frames(in stack: Data, limit: Int = 14) -> [String] {
        guard let root = try? JSONSerialization.jsonObject(with: stack) as? [String: Any],
              let stacks = root["callStacks"] as? [[String: Any]] else { return [] }
        let blamed = stacks.first { $0["threadAttributed"] as? Bool == true } ?? stacks.first
        var frame = (blamed?["callStackRootFrames"] as? [[String: Any]])?.first
        var result: [String] = []
        while let current = frame, result.count < limit {
            let name = current["binaryName"] as? String ?? "?"
            let offset = (current["offsetIntoBinaryTextSegment"] as? NSNumber)?.intValue ?? 0
            result.append("\(name)+\(offset)")
            frame = (current["subFrames"] as? [[String: Any]])?.first
        }
        return result
    }
}

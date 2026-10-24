import Foundation
import CoreTransferable
import UniformTypeIdentifiers
import SwiftData

/// GPX 1.1 export, readable by AllTrails, Strava, Google Earth and most GPS tools.
struct GPXDocument: Transferable {
    let name: String
    /// Encoded chunk blobs; decoded only when the file is actually exported.
    let blobs: [Data]
    let waypoints: [(name: String, latitude: Double, longitude: Double, time: Date)]

    @MainActor
    init(name: String, chunks: [TrackChunk], stays: [Stay]) {
        self.name = name
        let zones = PrivacyZones.shared
        self.blobs = chunks.sorted { $0.startDate < $1.startDate }
            .flatMap { zones.visibleSegments(of: $0.points) }
            .map(TrackCodec.encode)
        self.waypoints = stays.filter { !zones.isHidden($0.coordinate) }
            .map { ($0.displayName, $0.latitude, $0.longitude, $0.arrival) }
    }

    static var transferRepresentation: some TransferRepresentation {
        FileRepresentation(exportedContentType: .gpx) { document in
            let safeName = document.name.replacingOccurrences(of: "/", with: "-")
            let url = URL.temporaryDirectory.appending(path: "\(safeName).gpx")
            try document.xml().write(to: url, atomically: true, encoding: .utf8)
            return SentTransferredFile(url)
        }
    }

    func xml() -> String {
        let iso = ISO8601DateFormatter()
        var out = """
        <?xml version="1.0" encoding="UTF-8"?>
        <gpx version="1.1" creator="PathTracker" xmlns="http://www.topografix.com/GPX/1/1">
          <metadata><name>\(escape(name))</name><time>\(iso.string(from: Date()))</time></metadata>

        """
        for point in waypoints {
            out += "  <wpt lat=\"\(point.latitude)\" lon=\"\(point.longitude)\"><time>\(iso.string(from: point.time))</time><name>\(escape(point.name))</name></wpt>\n"
        }
        out += "  <trk><name>\(escape(name))</name>\n"
        for segment in blobs.map(TrackCodec.decode) where !segment.isEmpty {
            out += "    <trkseg>\n"
            for p in segment {
                out += "      <trkpt lat=\"\(p.latitude)\" lon=\"\(p.longitude)\"><ele>\(String(format: "%.1f", p.altitude))</ele><time>\(iso.string(from: p.timestamp))</time></trkpt>\n"
            }
            out += "    </trkseg>\n"
        }
        out += "  </trk>\n</gpx>\n"
        return out
    }

    private func escape(_ text: String) -> String {
        text.replacingOccurrences(of: "&", with: "&amp;")
            .replacingOccurrences(of: "<", with: "&lt;")
            .replacingOccurrences(of: ">", with: "&gt;")
            .replacingOccurrences(of: "\"", with: "&quot;")
    }
}

extension UTType {
    static let gpx = UTType(importedAs: "com.topografix.gpx", conformingTo: .xml)
}

/// Everything recorded, as one GPX file. The file is only built once the user picks where to
/// send it, so the share button opens instantly even with years of history.
struct AllTracksExport: Transferable {
    let container: ModelContainer

    static var transferRepresentation: some TransferRepresentation {
        FileRepresentation(exportedContentType: .gpx) { export in
            let document = await MainActor.run {
                let context = ModelContext(export.container)
                let chunks = (try? context.fetch(FetchDescriptor<TrackChunk>(sortBy: [SortDescriptor(\.startDate)]))) ?? []
                let stays = (try? context.fetch(FetchDescriptor<Stay>(sortBy: [SortDescriptor(\.arrival)]))) ?? []
                return GPXDocument(name: "PathTracker", chunks: chunks, stays: stays)
            }
            let url = URL.temporaryDirectory.appending(path: "PathTracker.gpx")
            try document.xml().write(to: url, atomically: true, encoding: .utf8)
            return SentTransferredFile(url)
        }
    }
}

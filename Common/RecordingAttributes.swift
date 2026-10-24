#if os(iOS)
import ActivityKit
import Foundation

/// The Live Activity shown while a manual recording runs: on the Lock Screen, in the Dynamic
/// Island, and (by iOS itself) in the Apple Watch Smart Stack.
struct RecordingAttributes: ActivityAttributes {
    struct ContentState: Codable, Hashable {
        var distance: Double
        /// The Watch is recording along, so the card can say so.
        var watchRecording: Bool
    }

    var tripID: UUID
    var title: String
    var emoji: String
    var start: Date
}
#endif

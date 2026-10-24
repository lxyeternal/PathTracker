import Foundation

/// The Watch app and its watch-face complications share the latest snapshot through an App Group.
enum SharedSnapshot {
    static let groupID = "group.com.honywen.waytrace"
    private static let key = "watch.snapshot"

    private static var defaults: UserDefaults { UserDefaults(suiteName: groupID) ?? .standard }

    static func save(_ snapshot: WatchSnapshot) {
        defaults.set(snapshot.encoded(), forKey: key)
    }

    static func load() -> WatchSnapshot? {
        WatchSnapshot.decode(defaults.data(forKey: key))
    }
}

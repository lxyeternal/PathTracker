import Foundation

/// The country whose passport the person holds. It issues the passport in the app (and gets
/// no entry stamps of its own), and going anywhere else is going abroad. Unset, the country
/// where the most time was spent stands in for it. Kept in iCloud so every device agrees.
enum Nationality {
    private static let key = "profile.nationality"

    static var code: String? {
        get {
            // iCloud first, so a change made on another device wins.
            NSUbiquitousKeyValueStore.default.string(forKey: key) ?? UserDefaults.standard.string(forKey: key)
        }
        set {
            UserDefaults.standard.set(newValue, forKey: key)
            if let newValue {
                NSUbiquitousKeyValueStore.default.set(newValue, forKey: key)
            } else {
                NSUbiquitousKeyValueStore.default.removeObject(forKey: key)
            }
        }
    }

    /// Recomputes what depends on it when another device changes it.
    @MainActor
    static func observeOtherDevices() {
        NotificationCenter.default.addObserver(forName: NSUbiquitousKeyValueStore.didChangeExternallyNotification,
                                               object: NSUbiquitousKeyValueStore.default, queue: .main) { note in
            let keys = note.userInfo?[NSUbiquitousKeyValueStoreChangedKeysKey] as? [String] ?? []
            guard keys.contains(key) else { return }
            MainActor.assumeIsolated { PlaceSummaries.shared.refresh() }
        }
        NSUbiquitousKeyValueStore.default.synchronize()
    }

    /// Every country and region, by name in the app's language.
    static var all: [(code: String, name: String)] {
        Locale.Region.isoRegions
            .map(\.identifier)
            .filter { $0.count == 2 && $0.allSatisfy(\.isLetter) }
            .compactMap { code in appLocale.localizedString(forRegionCode: code).map { (code, $0) } }
            .sorted { $0.name.localizedStandardCompare($1.name) == .orderedAscending }
    }
}

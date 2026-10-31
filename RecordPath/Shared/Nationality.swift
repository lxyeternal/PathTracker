import Foundation

/// The country whose passport the person holds. It issues the passport in the app (and gets
/// no entry stamps of its own), and going anywhere else is going abroad. Unset, the country
/// where the most time was spent stands in for it. Kept in iCloud so every device agrees.
enum Nationality {
    private static let key = "profile.nationality"

    static var code: String? {
        get {
            UserDefaults.standard.string(forKey: key) ?? NSUbiquitousKeyValueStore.default.string(forKey: key)
        }
        set {
            UserDefaults.standard.set(newValue, forKey: key)
            NSUbiquitousKeyValueStore.default.set(newValue, forKey: key)
        }
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

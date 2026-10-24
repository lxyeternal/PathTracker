import Foundation
import SwiftUI

/// The language the app shows itself in, chosen in the app's Settings and independent of the
/// system language. Switching takes effect immediately for everything the app draws; system
/// permission prompts follow on the next launch, as iOS reads those at startup.
enum AppLanguage: String, CaseIterable, Identifiable {
    case system
    case chinese = "zh-Hans"
    case english = "en"

    var id: String { rawValue }

    /// Each language is named in itself, so it's recognizable whatever is showing now.
    var nativeName: String {
        switch self {
        case .system: String(localized: "跟随系统", bundle: .appLanguage)
        case .chinese: "简体中文"
        case .english: "English"
        }
    }

    /// The localization actually used: the chosen one, or the best match for the system.
    var resolved: String {
        guard self == .system else { return rawValue }
        let available = Bundle.main.localizations.filter { $0 != "Base" }
        // Choosing "system" removes our AppleLanguages override, so this is the device's own list.
        return Bundle.preferredLocalizations(from: available, forPreferences: Locale.preferredLanguages).first ?? "zh-Hans"
    }

    /// Keeps the user's region (units, first weekday) but uses the app's language.
    var locale: Locale {
        var components = Locale.Components(locale: .autoupdatingCurrent)
        components.languageComponents = Locale.Language.Components(identifier: resolved)
        return Locale(components: components)
    }
}

/// The locale for formatting dates, numbers and units in the app's language.
nonisolated(unsafe) var appLocale: Locale = .autoupdatingCurrent

extension Bundle {
    /// Strings in the app's chosen language. Chinese is the source language, so it is an empty
    /// bundle whose lookups fall back to the (Chinese) keys themselves.
    nonisolated(unsafe) static var appLanguage: Bundle = .main
}

@MainActor
@Observable
final class LanguageSettings {
    static let shared = LanguageSettings()
    private static let key = "app.language"

    private(set) var language: AppLanguage

    private init() {
        language = AppLanguage(rawValue: UserDefaults.standard.string(forKey: Self.key) ?? "") ?? .system
        Self.apply(language)
    }

    func set(_ newValue: AppLanguage) {
        guard newValue != language else { return }
        language = newValue
        UserDefaults.standard.set(newValue.rawValue, forKey: Self.key)
        // iOS reads this at launch for permission prompts and the app's name under its icon.
        if newValue == .system {
            UserDefaults.standard.removeObject(forKey: "AppleLanguages")
        } else {
            UserDefaults.standard.set([newValue.rawValue], forKey: "AppleLanguages")
        }
        Self.apply(newValue)
    }

    var locale: Locale { language.locale }

    private static func apply(_ language: AppLanguage) {
        let localization = language.resolved
        appLocale = language.locale
        if localization.hasPrefix("zh") {
            Bundle.appLanguage = sourceLanguageBundle
        } else {
            Bundle.appLanguage = Bundle.main.path(forResource: localization, ofType: "lproj")
                .flatMap(Bundle.init(path:)) ?? .main
        }
    }

    /// A bundle with no string tables, so every lookup returns its Chinese key.
    private static let sourceLanguageBundle: Bundle = {
        let url = URL.temporaryDirectory.appending(path: "SourceLanguage.bundle")
        try? FileManager.default.createDirectory(at: url, withIntermediateDirectories: true)
        return Bundle(url: url) ?? .main
    }()
}

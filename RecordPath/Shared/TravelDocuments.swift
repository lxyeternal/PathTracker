import Foundation
import Observation
import UserNotifications

/// A passport or a visa the person holds: when it runs out, and what it allows.
struct TravelDocument: Codable, Identifiable, Hashable {
    enum Kind: String, Codable, CaseIterable { case passport, visa, eVisa }
    enum Entries: String, Codable, CaseIterable { case single, double, multiple }

    var id = UUID()
    var kind: Kind = .visa
    /// The issuing country (ISO 3166 alpha-2), or `TravelDocument.schengen`.
    var country: String
    /// "B1/B2", "C", "旅游" — what the visa says it is.
    var category = ""
    var number = ""
    var holder = ""
    /// Where it was issued: "BEIJING", "SHANGHAI".
    var post: String?
    var issued: Date?
    var expires: Date
    var entries: Entries = .multiple
    /// The longest a single stay may last, when the visa says.
    var stayDays: Int?
    var notes = ""
    var added = Date()

    static let schengen = "SCHENGEN"

    var isSchengen: Bool { country == Self.schengen }

    /// The countries a visa lets the person into: the whole area for Schengen.
    var coveredCountries: Set<String> { isSchengen ? Schengen.members : [country] }

    func daysLeft(from now: Date = .now) -> Int {
        let calendar = Calendar.current
        return calendar.dateComponents([.day], from: calendar.startOfDay(for: now), to: calendar.startOfDay(for: expires)).day ?? 0
    }

    var isExpired: Bool { daysLeft() < 0 }

    /// Soon enough to start thinking about renewing.
    var isExpiringSoon: Bool { !isExpired && daysLeft() <= (kind == .passport ? 180 : 60) }

    var countryName: String {
        if isSchengen { return String(localized: "申根区", bundle: .appLanguage) }
        return appLocale.localizedString(forRegionCode: country) ?? country
    }

    var englishName: String {
        if isSchengen { return "SCHENGEN STATES" }
        return (Locale(identifier: "en").localizedString(forRegionCode: country) ?? country).uppercased()
    }

    var flag: String { isSchengen ? "🇪🇺" : String.flag(for: country) }
}

/// The Schengen area and its rule: no more than 90 days in any 180.
enum Schengen {
    static let members: Set<String> = ["AT", "BE", "BG", "HR", "CZ", "DK", "EE", "FI", "FR", "DE", "GR", "HU", "IS", "IT", "LV",
                                       "LI", "LT", "LU", "MT", "NL", "NO", "PL", "PT", "RO", "SK", "SI", "ES", "SE", "CH"]

    struct Allowance {
        /// Days in the area within the 180 days up to today, today included.
        let used: Int
        var remaining: Int { max(0, 90 - used) }
        /// The day the oldest of the counted days drops out of the window, freeing a day.
        let nextFreed: Date?
    }

    /// Counts every calendar day with a stay in the area: arriving and leaving days count in full.
    static func allowance(stays: [(country: String?, arrival: Date, departure: Date?)], on today: Date = .now) -> Allowance {
        let calendar = Calendar.current
        let end = calendar.startOfDay(for: today)
        guard let start = calendar.date(byAdding: .day, value: -179, to: end) else { return Allowance(used: 0, nextFreed: nil) }
        var days = Set<Date>()
        for stay in stays where stay.country.map(members.contains) ?? false {
            var day = max(calendar.startOfDay(for: stay.arrival), start)
            let last = min(calendar.startOfDay(for: stay.departure ?? today), end)
            while day <= last {
                days.insert(day)
                guard let next = calendar.date(byAdding: .day, value: 1, to: day) else { break }
                day = next
            }
        }
        let freed = days.min().flatMap { calendar.date(byAdding: .day, value: 180, to: $0) }
        return Allowance(used: days.count, nextFreed: freed)
    }
}

/// The documents, kept in iCloud's key-value store: a handful of small records that every
/// device should agree on, without a database schema of their own.
@MainActor
@Observable
final class TravelDocuments {
    static let shared = TravelDocuments()
    private static let key = "travel.documents"

    private(set) var all: [TravelDocument] = []

    /// The passport first, then visas by how soon they run out, expired ones last.
    var sorted: [TravelDocument] {
        all.sorted { a, b in
            if (a.kind == .passport) != (b.kind == .passport) { return a.kind == .passport }
            if a.isExpired != b.isExpired { return !a.isExpired }
            return a.isExpired ? a.expires > b.expires : a.expires < b.expires
        }
    }

    var passport: TravelDocument? { all.first { $0.kind == .passport } }

    private init() {
        load()
        NotificationCenter.default.addObserver(forName: NSUbiquitousKeyValueStore.didChangeExternallyNotification,
                                               object: NSUbiquitousKeyValueStore.default, queue: .main) { note in
            let keys = note.userInfo?[NSUbiquitousKeyValueStoreChangedKeysKey] as? [String] ?? []
            guard keys.contains(Self.key) else { return }
            MainActor.assumeIsolated {
                TravelDocuments.shared.load()
                TravelDocuments.shared.scheduleReminders()
            }
        }
    }

    private func load() {
        let data = NSUbiquitousKeyValueStore.default.data(forKey: Self.key) ?? UserDefaults.standard.data(forKey: Self.key)
        all = data.flatMap { try? JSONDecoder().decode([TravelDocument].self, from: $0) } ?? []
    }

    func save(_ document: TravelDocument) {
        if let index = all.firstIndex(where: { $0.id == document.id }) {
            all[index] = document
        } else {
            // One passport at a time: a new one replaces the old.
            if document.kind == .passport { all.removeAll { $0.kind == .passport } }
            all.append(document)
        }
        persist()
    }

    func delete(_ document: TravelDocument) {
        all.removeAll { $0.id == document.id }
        persist()
    }

    private func persist() {
        guard let data = try? JSONEncoder().encode(all) else { return }
        UserDefaults.standard.set(data, forKey: Self.key)
        NSUbiquitousKeyValueStore.default.set(data, forKey: Self.key)
        scheduleReminders(asking: true)
    }

    #if DEBUG
    func loadSamples() {
        let calendar = Calendar.current
        func date(_ years: Int, _ days: Int = 0) -> Date {
            calendar.date(byAdding: DateComponents(year: years, day: days), to: calendar.startOfDay(for: .now)) ?? .now
        }
        all = [
            TravelDocument(kind: .passport, country: Nationality.code ?? "CN", number: "EJ1234567", holder: "SPECIMEN TEST",
                           issued: date(-5, -130), expires: date(5, -131)),
            TravelDocument(kind: .visa, country: "US", category: "B1/B2", number: "A12345678", holder: "SPECIMEN TEST",
                           issued: date(-2, -230), expires: date(8, -231)),
            TravelDocument(kind: .visa, country: TravelDocument.schengen, category: "C", issued: date(0, -320), expires: date(0, 46), stayDays: 90),
            TravelDocument(kind: .visa, country: "JP", category: String(localized: "短期滞在", bundle: .appLanguage),
                           issued: date(-2, -40), expires: date(2, 90), stayDays: 30),
            TravelDocument(kind: .visa, country: "GB", category: "Visitor", issued: date(-1, -20), expires: date(1, 200), stayDays: 180),
            TravelDocument(kind: .eVisa, country: "AU", category: "600", issued: date(0, -170), expires: date(0, 560), stayDays: 90),
            TravelDocument(kind: .visa, country: "KR", category: "C-3", issued: date(-2), expires: date(-1, -40), entries: .single, stayDays: 30),
        ]
    }
    #endif

    // MARK: Reminders

    private static let reminderPrefix = "document."

    /// A nudge 90, 30 and 7 days before each document runs out, at nine in the morning. Asks
    /// for permission only right after the person saved one, never out of the blue.
    func scheduleReminders(asking: Bool = false) {
        let documents = all
        Task {
            let center = UNUserNotificationCenter.current()
            let pending = await center.pendingNotificationRequests().map(\.identifier).filter { $0.hasPrefix(Self.reminderPrefix) }
            center.removePendingNotificationRequests(withIdentifiers: pending)
            if asking, await center.notificationSettings().authorizationStatus == .notDetermined, !documents.isEmpty {
                _ = try? await center.requestAuthorization(options: [.alert, .sound, .badge])
            }
            let calendar = Calendar.current
            for document in documents {
                for days in [90, 30, 7] {
                    guard let day = calendar.date(byAdding: .day, value: -days, to: document.expires),
                          let fire = calendar.date(bySettingHour: 9, minute: 0, second: 0, of: day), fire > .now else { continue }
                    let content = UNMutableNotificationContent()
                    content.title = document.kind == .passport
                        ? String(localized: "护照还有 \(days) 天到期", bundle: .appLanguage)
                        : String(localized: "\(document.countryName)签证还有 \(days) 天到期", bundle: .appLanguage)
                    content.body = document.kind == .passport
                        ? String(localized: "很多国家要求护照有效期还剩 6 个月以上，记得提前换发。", bundle: .appLanguage)
                        : String(localized: "到期日是 \(document.expires.formatted(Date.FormatStyle(date: .long, time: .omitted, locale: appLocale)))。", bundle: .appLanguage)
                    content.sound = .default
                    let trigger = UNCalendarNotificationTrigger(dateMatching: calendar.dateComponents([.year, .month, .day, .hour, .minute], from: fire),
                                                                repeats: false)
                    try? await center.add(UNNotificationRequest(identifier: "\(Self.reminderPrefix)\(document.id).\(days)",
                                                                content: content, trigger: trigger))
                }
            }
        }
    }
}

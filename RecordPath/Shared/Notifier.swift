import Foundation
import SwiftData
import UserNotifications
import os

/// Local notifications for the moments worth a nudge: arriving somewhere for the first time, a
/// milestone, and Monday's look back at the week. Nothing leaves the device.
@MainActor
@Observable
final class Notifier {
    enum Setting: String, CaseIterable {
        case arrivals = "notify.arrivals"
        case milestones = "notify.milestones"
        case weekly = "notify.weekly"

        var isOn: Bool { UserDefaults.standard.object(forKey: rawValue) as? Bool ?? true }
    }

    private(set) var authorization: UNAuthorizationStatus = .notDetermined
    private let context: ModelContext
    private let activity: ActivityProvider
    private let center = UNUserNotificationCenter.current()
    private var lastCheck = Date.distantPast
    private let log = Logger(subsystem: "PathTracker", category: "Notifier")

    private enum Keys {
        static let knownMilestones = "notify.knownMilestones"
        static let lastWeekly = "notify.lastWeekly"
    }

    init(context: ModelContext, activity: ActivityProvider) {
        self.context = context
        self.activity = activity
    }

    func refreshAuthorization() async {
        authorization = await center.notificationSettings().authorizationStatus
    }

    func requestAuthorization() async {
        _ = try? await center.requestAuthorization(options: [.alert, .sound, .badge])
        await refreshAuthorization()
    }

    // MARK: Arrivals

    /// Called once a place has been named. Only live arrivals count: places named later
    /// (imports, iCloud sync, catching up after being offline) never notify or celebrate.
    func placeTagged(_ stay: Stay) {
        guard Date().timeIntervalSince(stay.arrival) < 6 * 3600, !stay.isFromPhotos else { return }
        let id = stay.id
        let others = ((try? context.fetch(FetchDescriptor<Stay>(predicate: #Predicate { $0.id != id }))) ?? [])
            .filter { $0.tagState == .tagged }
        if let arrival = Self.firstArrival(stay, after: others) {
            var item = Celebrations.Item(id: arrival.id, kind: arrival.kind, title: arrival.title, subtitle: arrival.body,
                                         countryCode: stay.countryCode, latitude: stay.latitude, longitude: stay.longitude, date: stay.arrival)
            switch arrival.kind {
            case .country:
                let before = others.filter { $0.arrival < stay.arrival }.max { $0.arrival < $1.arrival }
                item.byAir = stay.category == .airport || before.map { $0.location.distance(from: stay.location) > 400_000 } ?? false
                item.port = stay.category == .airport ? stay.displayName : (stay.city ?? stay.placeName)
            case .city:
                item.city = arrival.place
            default:
                break
            }
            Celebrations.shared.add(item)
            if Setting.arrivals.isOn { post(id: arrival.id, title: arrival.title, body: arrival.body) }
        } else if let reunion = Reunion.find(stay, after: others) {
            let id = "reunion.\(stay.id.uuidString)"
            let when = reunion.lastVisit.formatted(.dateTime.year().month().day().locale(appLocale))
            Celebrations.shared.add(Celebrations.Item(id: id, kind: .reunion, title: stay.displayName, subtitle: stay.city ?? "",
                                                      countryCode: stay.countryCode, latitude: stay.latitude, longitude: stay.longitude,
                                                      lastVisit: reunion.lastVisit, firstVisit: reunion.firstVisit, visits: reunion.visits))
            if Setting.arrivals.isOn {
                post(id: id, title: String(localized: "重逢 · \(stay.displayName)", bundle: .appLanguage),
                     body: String(localized: "你上次来这里是\(when)，已经过去\(Reunion.away(since: reunion.lastVisit))。", bundle: .appLanguage))
            }
        } else if let sight = Self.firstSight(stay, after: others) {
            Celebrations.shared.add(Celebrations.Item(id: sight.id, kind: .sight, title: sight.title, subtitle: sight.body,
                                                      countryCode: stay.countryCode, latitude: stay.latitude, longitude: stay.longitude))
        }
    }

    struct Arrival: Equatable {
        let id: String
        var kind: Celebrations.Item.Kind = .city
        let title: String
        let body: String
        /// A new city's name.
        var place: String?
    }

    /// A sight the user hasn't been to before, for a quiet banner.
    static func firstSight(_ stay: Stay, after others: [Stay]) -> Arrival? {
        guard stay.isLandmark, !others.isEmpty else { return nil }
        let seen = others.contains { $0.isLandmark && $0.location.distance(from: stay.location) < 300 }
        guard !seen else { return nil }
        let sights = Set(others.filter(\.isLandmark).map(\.displayName)).count + 1
        return Arrival(id: "sight.\(stay.id.uuidString)", kind: .sight, title: stay.displayName,
                       body: String(localized: "新景点 · 你去过的第 \(sights) 个景点", bundle: .appLanguage))
    }

    /// What's new about this place compared with everywhere before it: a country, else a
    /// province, else a city. Nothing for the very first place, which isn't news.
    static func firstArrival(_ stay: Stay, after others: [Stay]) -> Arrival? {
        guard !others.isEmpty, let code = stay.countryCode else { return nil }
        if !others.contains(where: { $0.countryCode == code }) {
            let name = WorldInsights.countryName(code: code, fallback: stay.country)
            let count = Set(others.compactMap(\.countryCode)).count + 1
            return Arrival(id: "arrival.\(code)", kind: .country, title: String(localized: "欢迎来到\(name) \(String.flag(for: code))", bundle: .appLanguage),
                           body: String(localized: "这是你去过的第 \(count) 个国家和地区。", bundle: .appLanguage))
        }
        func provinceOf(_ s: Stay) -> Province? { Province.containing(countryCode: s.countryCode, region: s.region, city: s.city) }
        if let province = provinceOf(stay), !others.contains(where: { provinceOf($0) == province }) {
            let lit = Set(others.compactMap { provinceOf($0)?.id }).count + 1
            return Arrival(id: "arrival.\(province.id)", kind: .province, title: String(localized: "第一次来\(province.name)", bundle: .appLanguage),
                           body: String(localized: "盖上了第 \(lit) 枚省份印。", bundle: .appLanguage))
        }
        let names = CityNames.canonical(for: others + [stay])
        func city(_ s: Stay) -> String? { CityNames.key(s).flatMap { names[$0] }.map { "\(s.countryCode ?? "")|\($0)" } }
        if let key = city(stay), !others.contains(where: { city($0) == key }), let name = CityNames.key(stay).flatMap({ names[$0] }) {
            let count = Set(others.compactMap(city)).count + 1
            return Arrival(id: "arrival.city.\(key)", title: String(localized: "第一次来\(name)", bundle: .appLanguage),
                           body: String(localized: "这是你去过的第 \(count) 座城市。", bundle: .appLanguage), place: name)
        }
        return nil
    }

    // MARK: Milestones and the weekly look back

    /// Checks at most every half hour, from wherever the app happens to be running.
    func checkPeriodically() {
        guard Date().timeIntervalSince(lastCheck) > 30 * 60 else { return }
        lastCheck = Date()
        checkMilestones()
        Task { await scheduleWeeklySummaryIfDue() }
    }

    func checkMilestones() {
        let progress = currentMilestones()
        let reached = Set(progress.reached.map(\.id))
        let defaults = UserDefaults.standard
        guard let known = defaults.stringArray(forKey: Keys.knownMilestones).map(Set.init) else {
            // First run: everything already reached is history, not news.
            defaults.set(Array(reached), forKey: Keys.knownMilestones)
            return
        }
        let new = progress.reached.filter { !known.contains($0.id) }
        defaults.set(Array(known.union(reached)), forKey: Keys.knownMilestones)
        for item in new {
            Celebrations.shared.add(Celebrations.Item(id: "milestone.\(item.id)", kind: .milestone, title: item.milestone.title,
                                                      subtitle: item.milestone.kind.title, date: item.date))
        }
        guard Setting.milestones.isOn, let latest = new.first else { return }
        post(id: "milestone.\(latest.id)", title: String(localized: "达成里程碑", bundle: .appLanguage), body: latest.milestone.title)
    }

    func currentMilestones() -> MilestoneProgress {
        let stays = (try? context.fetch(FetchDescriptor<Stay>())) ?? []
        let chunks = (try? context.fetch(FetchDescriptor<TrackChunk>())) ?? []
        return MilestoneProgress(stays: stays, movements: chunks.filter { $0.mode != .flying }.map { ($0.startDate, $0.distance) })
    }

    /// On Monday (or Tuesday, if the app didn't run on Monday), last week in one line.
    private func scheduleWeeklySummaryIfDue() async {
        guard Setting.weekly.isOn, authorization == .authorized || authorization == .provisional else { return }
        var calendar = Calendar.current
        calendar.firstWeekday = 2
        let now = Date()
        guard let thisWeek = calendar.dateInterval(of: .weekOfYear, for: now),
              let lastWeekStart = calendar.date(byAdding: .day, value: -7, to: thisWeek.start),
              now.timeIntervalSince(thisWeek.start) < 2 * 86_400 else { return }
        let defaults = UserDefaults.standard
        if let last = defaults.object(forKey: Keys.lastWeekly) as? Date, last >= lastWeekStart { return }

        let start = lastWeekStart, end = thisWeek.start
        let chunks = (try? context.fetch(FetchDescriptor<TrackChunk>(predicate: #Predicate { $0.startDate >= start && $0.startDate < end }))) ?? []
        let stays = (try? context.fetch(FetchDescriptor<Stay>(predicate: #Predicate { $0.arrival >= start && $0.arrival < end }))) ?? []
        guard !chunks.isEmpty || !stays.isEmpty else { return }
        let steps = await activity.activity(from: start, days: 7).reduce(0) { $0 + $1.steps }
        let distance = chunks.filter { $0.mode != .flying }.reduce(0) { $0 + $1.distance }

        var parts: [String] = []
        if steps > 0 { parts.append(String(localized: "走了 \(Format.steps(steps)) 步", bundle: .appLanguage)) }
        parts.append(String(localized: "移动 \(Format.distance(distance))", bundle: .appLanguage))
        parts.append(String(localized: "去了 \(stays.count) 个地方", bundle: .appLanguage))
        var body = parts.joined(separator: String(localized: "，", bundle: .appLanguage)) + String(localized: "。", bundle: .appLanguage)
        body = body.prefix(1).uppercased() + body.dropFirst()

        // Delivered at 9:00 on Monday, or right away if that has passed.
        let nine = calendar.date(bySettingHour: 9, minute: 0, second: 0, of: thisWeek.start) ?? now
        let delay = max(5, nine.timeIntervalSince(now))
        post(id: "weekly", title: String(localized: "上周回顾", bundle: .appLanguage), body: body, after: delay)
        defaults.set(lastWeekStart, forKey: Keys.lastWeekly)
    }

    private func post(id: String, title: String, body: String, after delay: TimeInterval = 1) {
        let content = UNMutableNotificationContent()
        content.title = title
        content.body = body
        content.sound = .default
        let request = UNNotificationRequest(identifier: id, content: content,
                                            trigger: UNTimeIntervalNotificationTrigger(timeInterval: delay, repeats: false))
        center.add(request) { [log] error in
            if let error { log.error("Notification failed: \(error.localizedDescription)") }
        }
    }
}

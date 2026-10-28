import SwiftUI
import SwiftData
import UserNotifications

@main
struct RecordPathApp: App {
    @Environment(\.scenePhase) private var scenePhase
    // Created at launch, including background relaunches triggered by location events,
    // so recording resumes before any UI exists.
    private let services = AppServices.shared

    var body: some Scene {
        WindowGroup {
            RootView()
                .environment(services.engine)
                .environment(services.activity)
                .environment(services.account)
                .environment(services.notifier)
                .environment(\.placeTagger, services.tagger)
        }
        .modelContainer(services.container)
        .onChange(of: scenePhase, initial: true) { _, phase in
            switch phase {
            case .background:
                Diagnostics.record("phase background")
                services.engine.persistNow()
            case .active:
                Diagnostics.record("phase active \(Diagnostics.battery)")
                services.engine.refreshState()
                services.tagger.enqueue()
                services.liveRecording.refreshNow()
                services.notifier.checkPeriodically()
                PlaceSummaries.shared.setNeedsRefresh()
                Task {
                    await services.activity.refreshToday()
                    await services.notifier.refreshAuthorization()
                    services.watch.scheduleUpdate(immediately: true)
                    await services.account.verifyCredential()
                }
            default:
                break
            }
        }
    }
}

@MainActor
final class AppServices {
    static let shared = AppServices()

    let container: ModelContainer
    let tagger: PlaceTagger
    let engine: LocationEngine
    let activity: ActivityProvider
    let account: AccountManager
    let watch: WatchBridge
    let liveRecording: LiveRecording
    let notifier: Notifier
    private let notificationPresenter = NotificationPresenter()

    private init() {
        // Before anything builds a string, so even background launches use the chosen language.
        _ = LanguageSettings.shared
        Diagnostics.launched()
        let inMemory = ProcessInfo.processInfo.arguments.contains("-uiTesting")
        container = PersistenceController.makeContainer(inMemory: inMemory)
        tagger = PlaceTagger(context: container.mainContext)
        engine = LocationEngine(context: container.mainContext, tagger: tagger)
        activity = ActivityProvider()
        account = AccountManager()
        watch = WatchBridge(context: container.mainContext, engine: engine, activity: activity)
        watch.activate()
        liveRecording = LiveRecording(context: container.mainContext, engine: engine)
        liveRecording.activate()
        notifier = Notifier(context: container.mainContext, activity: activity)
        PlaceSummaries.shared.attach(container.mainContext)
        _ = CloudSync.shared
        tagger.onTagged = { [notifier] stay in
            notifier.placeTagged(stay)
            notifier.checkPeriodically()
        }
        tagger.onPhotosTagged = { [notifier] in notifier.checkMilestones() }
        PlaceSummaries.shared.onStamps = { [notifier] book in notifier.checkStamps(book) }
        #if DEBUG
        // Launched with -ceremonySamples: one of each ceremony, for trying them out.
        // Launched with -stressData on an empty store: thousands of places, for checking long lists.
        // -demoData does the same with the sample days alone, for screenshots.
        let empty = (try? container.mainContext.fetchCount(FetchDescriptor<Stay>())) == 0
        if empty, ProcessInfo.processInfo.arguments.contains("-stressData") || ProcessInfo.processInfo.arguments.contains("-demoData") {
            DemoData.generate(in: container.mainContext)
            if ProcessInfo.processInfo.arguments.contains("-stressData") { DemoData.photoStress(in: container.mainContext) }
        }
        // Followed by a kind ("province", "city", ...) for just that one.
        let arguments = ProcessInfo.processInfo.arguments
        if let flag = arguments.firstIndex(of: "-ceremonySamples") {
            Celebrations.shared.pending.forEach(Celebrations.shared.finish)
            Celebrations.shared.addSamples()
            if flag + 1 < arguments.count, let kind = Celebrations.Item.Kind(rawValue: arguments[flag + 1]) {
                Celebrations.shared.pending.filter { $0.kind != kind }.forEach(Celebrations.shared.finish)
            }
        }
        #endif
        UNUserNotificationCenter.current().delegate = notificationPresenter
    }
}

private struct PlaceTaggerKey: EnvironmentKey {
    static let defaultValue: PlaceTagger? = nil
}

extension EnvironmentValues {
    var placeTagger: PlaceTagger? {
        get { self[PlaceTaggerKey.self] }
        set { self[PlaceTaggerKey.self] = newValue }
    }
}

/// Shows the app's notifications even while it's open, as a banner.
private final class NotificationPresenter: NSObject, UNUserNotificationCenterDelegate {
    func userNotificationCenter(_ center: UNUserNotificationCenter, willPresent notification: UNNotification) async
        -> UNNotificationPresentationOptions {
        [.banner, .sound]
    }
}

import SwiftUI
import SwiftData

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
                .environment(\.placeTagger, services.tagger)
        }
        .modelContainer(services.container)
        .onChange(of: scenePhase) { _, phase in
            switch phase {
            case .background:
                services.engine.persistNow()
            case .active:
                services.engine.refreshState()
                services.tagger.enqueue()
                Task {
                    await services.activity.refreshToday()
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

    private init() {
        // Before anything builds a string, so even background launches use the chosen language.
        _ = LanguageSettings.shared
        let inMemory = ProcessInfo.processInfo.arguments.contains("-uiTesting")
        container = PersistenceController.makeContainer(inMemory: inMemory)
        tagger = PlaceTagger(context: container.mainContext)
        engine = LocationEngine(context: container.mainContext, tagger: tagger)
        activity = ActivityProvider()
        account = AccountManager()
        watch = WatchBridge(context: container.mainContext, engine: engine, activity: activity)
        watch.activate()
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

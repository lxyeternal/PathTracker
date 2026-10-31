import SwiftUI
import WatchKit
import HealthKit

@main
struct WaytraceWatchApp: App {
    @WKApplicationDelegateAdaptor private var delegate: WatchAppDelegate
    @Environment(\.scenePhase) private var scenePhase
    @State private var link = PhoneLink.shared
    @State private var recorder = WorkoutRecorder.shared
    @State private var language = LanguageSettings.shared

    init() {
        PhoneLink.shared.activate()
        #if DEBUG
        // HealthKit can't open the Watch app from the iPhone between simulators; this runs the
        // same path for testing: `simctl launch … -simulateWorkoutLaunch hiking`.
        let arguments = ProcessInfo.processInfo.arguments
        if let index = arguments.firstIndex(of: "-simulateWorkoutLaunch"), index + 1 < arguments.count,
           let activity = ActivityType(rawValue: arguments[index + 1]) {
            let configuration = HKWorkoutConfiguration()
            configuration.activityType = activity.workoutType
            WatchAppDelegate().handle(configuration)
        }
        #endif
    }

    var body: some Scene {
        WindowGroup {
            HomeView()
                .id(language.language)
                .environment(link)
                .environment(recorder)
                .environment(\.locale, language.locale)
        }
        .onChange(of: scenePhase) { _, phase in
            if phase == .active { link.refresh() }
        }
    }
}

/// Starting a recording on the iPhone with "record on Apple Watch" on opens the app here.
final class WatchAppDelegate: NSObject, WKApplicationDelegate {
    func handle(_ workoutConfiguration: HKWorkoutConfiguration) {
        let activity = ActivityType(workoutType: workoutConfiguration.activityType)
        Task { @MainActor in
            PhoneLink.shared.refresh()
            await WorkoutRecorder.shared.start(activity, linkedToPhone: true)
        }
    }

    /// The app ended mid-recording (a crash, an update) and watchOS relaunched it.
    func handleActiveWorkoutRecovery() {
        Task { @MainActor in await WorkoutRecorder.shared.recover() }
    }

    func applicationDidFinishLaunching() {
        // Give a pending recovery a moment; a route still on disk after that has no workout left.
        Task { @MainActor in
            try? await Task.sleep(for: .seconds(8))
            WorkoutRecorder.shared.sendOrphanedRoute()
        }
    }
}

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
           let activity = WatchActivity(rawValue: arguments[index + 1]) {
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
        let activity = WatchActivity(workoutType: workoutConfiguration.activityType)
        Task { @MainActor in
            PhoneLink.shared.refresh()
            await WorkoutRecorder.shared.start(activity, linkedToPhone: true)
        }
    }
}

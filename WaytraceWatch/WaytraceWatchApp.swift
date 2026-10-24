import SwiftUI

@main
struct WaytraceWatchApp: App {
    @Environment(\.scenePhase) private var scenePhase
    @State private var link = PhoneLink.shared
    @State private var recorder = WorkoutRecorder()
    @State private var language = LanguageSettings.shared

    init() {
        PhoneLink.shared.activate()
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

import SwiftUI

struct RootView: View {
    @AppStorage("onboarding.completed") private var onboardingCompleted = false
    @State private var navigator = AppNavigator()
    @State private var showingSettings = false
    @State private var ceremony: [Celebrations.Item] = []
    @State private var showingCeremony = false
    @Environment(\.scenePhase) private var scenePhase
    private var language = LanguageSettings.shared
    private var celebrations = Celebrations.shared

    var body: some View {
        ZStack {
            if onboardingCompleted {
                MainTabView(showingSettings: $showingSettings)
                    .transition(.opacity.combined(with: .scale(scale: 1.04)))
            } else {
                OnboardingView { onboardingCompleted = true }
                    .transition(.opacity)
            }
        }
        .animation(.smooth(duration: 0.5), value: onboardingCompleted)
        // Rebuilding on a language change re-renders every string, including ones computed
        // in code; Settings stays open because it's presented from outside this subtree.
        .id(language.language)
        .sheet(isPresented: $showingSettings) {
            SettingsView()
                .id(language.language)
        }
        .fullScreenCover(isPresented: $showingCeremony) {
            CeremonyView(items: ceremony)
                .environment(\.locale, language.locale)
        }
        .overlay(alignment: .top) {
            if onboardingCompleted, !showingCeremony, !showingSettings, scenePhase == .active,
               celebrations.ceremonies.isEmpty, let sight = celebrations.nextSight {
                SightBanner(item: sight) { celebrations.finish(sight) }
                    .id(sight.id)
            }
        }
        .onChange(of: scenePhase, initial: true) { presentCeremonyIfDue() }
        .onChange(of: celebrations.ceremonies.count) { presentCeremonyIfDue() }
        .onChange(of: showingSettings) { presentCeremonyIfDue() }
        .environment(navigator)
        .environment(\.locale, language.locale)
    }

    /// Firsts play once, the next time the app is in front with nothing else on top.
    private func presentCeremonyIfDue() {
        Task { @MainActor in
            try? await Task.sleep(for: .seconds(0.8))
            let items = celebrations.ceremonies
            guard onboardingCompleted, scenePhase == .active, !showingSettings, !showingCeremony, !items.isEmpty else { return }
            ceremony = items
            showingCeremony = true
        }
    }
}

struct MainTabView: View {
    @Binding var showingSettings: Bool
    @Environment(AppNavigator.self) private var navigator

    var body: some View {
        @Bindable var navigator = navigator
        TabView(selection: $navigator.section) {
            Tab("今天", systemImage: "point.topright.filled.arrow.triangle.backward.to.point.bottomleft.scurvepath", value: .today) {
                TodayView(showingSettings: $showingSettings)
            }
            Tab("足迹", systemImage: "globe.asia.australia.fill", value: .world) {
                WorldView(showingSettings: $showingSettings)
            }
            Tab("旅程", systemImage: "suitcase.rolling.fill", value: .trips) {
                TripsView(showingSettings: $showingSettings)
            }
            Tab("统计", systemImage: "chart.bar.xaxis", value: .stats) {
                StatsView(showingSettings: $showingSettings)
            }
        }
        .sensoryFeedback(.selection, trigger: navigator.section)
    }
}

/// The avatar button in every tab's toolbar that opens settings, like Apple's own apps.
struct ProfileToolbarButton: View {
    @Binding var showingSettings: Bool

    var body: some View {
        Button {
            showingSettings = true
        } label: {
            Avatar(size: 32)
        }
        .accessibilityLabel("设置")
    }
}

/// The user's photo, or their initial, or a placeholder.
struct Avatar: View {
    let size: CGFloat
    @Environment(AccountManager.self) private var account

    var body: some View {
        Group {
            if let image = account.avatar {
                Image(uiImage: image)
                    .resizable()
                    .scaledToFill()
            } else if let initial = account.profile.displayName?.first {
                Text(String(initial))
                    .font(.system(size: size * 0.45, weight: .semibold, design: .rounded))
                    .foregroundStyle(.white)
                    .frame(width: size, height: size)
                    .background(Circle().fill(Color.accentColor.gradient))
            } else {
                Image(systemName: "person.crop.circle.fill")
                    .resizable()
                    .symbolRenderingMode(.hierarchical)
                    .foregroundStyle(.tint)
            }
        }
        .frame(width: size, height: size)
        .clipShape(Circle())
        .accessibilityHidden(true)
    }
}

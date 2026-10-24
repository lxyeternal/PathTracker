import SwiftUI

struct RootView: View {
    @AppStorage("onboarding.completed") private var onboardingCompleted = false

    var body: some View {
        ZStack {
            if onboardingCompleted {
                MainTabView()
                    .transition(.opacity.combined(with: .scale(scale: 1.04)))
            } else {
                OnboardingView { onboardingCompleted = true }
                    .transition(.opacity)
            }
        }
        .animation(.smooth(duration: 0.5), value: onboardingCompleted)
    }
}

struct MainTabView: View {
    @State private var navigator = AppNavigator()
    @State private var showingSettings = false

    var body: some View {
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
        .sheet(isPresented: $showingSettings) {
            SettingsView()
        }
        .environment(navigator)
    }
}

/// The avatar button in every tab's toolbar that opens settings, like Apple's own apps.
struct ProfileToolbarButton: View {
    @Environment(AccountManager.self) private var account
    @Binding var showingSettings: Bool

    var body: some View {
        Button {
            showingSettings = true
        } label: {
            Avatar(name: account.profile?.displayName, size: 32)
        }
        .accessibilityLabel("设置")
    }
}

struct Avatar: View {
    let name: String?
    let size: CGFloat

    var body: some View {
        Group {
            if let initial = name?.first {
                Text(String(initial))
                    .font(.system(size: size * 0.45, weight: .semibold, design: .rounded))
                    .foregroundStyle(.white)
                    .frame(width: size, height: size)
                    .background(Circle().fill(Color.accentColor.gradient))
            } else {
                Image(systemName: "person.crop.circle.fill")
                    .font(.system(size: size))
                    .symbolRenderingMode(.hierarchical)
                    .foregroundStyle(.tint)
            }
        }
        .frame(width: size, height: size)
    }
}

import SwiftUI

// 앱 루트 — 첫 실행 시 onboarding, 이후 TabView.
struct RootView: View {
    @AppStorage("hasCompletedOnboarding") private var hasCompletedOnboarding: Bool = false

    var body: some View {
        if !hasCompletedOnboarding {
            OnboardingScreen(onComplete: { hasCompletedOnboarding = true })
        } else {
            mainTabs
        }
    }

    private var mainTabs: some View {
        TabView {
            Tab("경기", systemImage: KLIcon.resolve("tab.matches")) {
                NavigationStack { MatchesScreen() }
            }
            Tab("시즌", systemImage: KLIcon.resolve("tab.season")) {
                NavigationStack { SeasonScreen() }
            }
            Tab("친구", systemImage: KLIcon.resolve("tab.friends")) {
                NavigationStack { FriendsScreen() }
            }
            Tab("설정", systemImage: KLIcon.resolve("tab.settings")) {
                NavigationStack { SettingsScreen() }
            }
        }
        .tint(KLTokens.pitch)
    }
}

#Preview {
    RootView()
}

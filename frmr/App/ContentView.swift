import SwiftData
import SwiftUI

// nonisolated: a plain value type, compared from tests and any actor
nonisolated enum AppTab: Hashable {
    case library
    case camera
    case settings
}

struct ContentView: View {
    @Environment(ErrorState.self) private var errorState
    @Environment(\.modelContext) private var modelContext
    @AppStorage(Constants.DefaultsKeys.appearanceMode) private var appearanceMode = AppearanceMode.system.rawValue
    @Environment(\.scenePhase) private var scenePhase
    @State private var onboarding = OnboardingViewModel()

    private var preferredScheme: ColorScheme? {
        AppearanceMode(rawValue: appearanceMode)?.colorScheme
    }

    var body: some View {
        TabView(selection: Bindable(onboarding).selectedTab.projectedValue) {
            LibraryView()
                .tabItem { Label("Library", systemImage: "square.grid.2x2") }
                .tag(AppTab.library)
            CameraView()
                .tabItem { Label("Camera", systemImage: "camera.viewfinder") }
                .tag(AppTab.camera)
            SettingsView()
                .tabItem { Label("Settings", systemImage: "gearshape") }
                .tag(AppTab.settings)
        }
        .tint(.appTealDark)
        .preferredColorScheme(preferredScheme)
        .overlay(alignment: .bottom) { tabItemAnchorProxies }
        .overlayPreferenceValue(TabItemAnchorKey.self) { anchors in
            CoachMarkOverlay(
                step: onboarding.visibleStep,
                anchors: anchors,
                onAdvance: onboarding.advance,
                onSkip: onboarding.skip
            )
        }
        .appErrorAlert(errorState)
        .environment(onboarding)
        // The lock follows the selected tab, not CameraView's appear/disappear,
        // whose ordering against a tab switch is not guaranteed.
        // CONTRACT REQUEST candidate: pure static AppTab -> Mode mapping on
        // OnboardingViewModel; for now the single comparison lives in applyOrientationLock.
        .onAppear { applyOrientationLock() }
        .onChange(of: onboarding.selectedTab) { applyOrientationLock() }
        .onChange(of: scenePhase) { if scenePhase == .active { applyOrientationLock() } }
        .task {
            onboarding.errorState = errorState
            onboarding.start(context: modelContext)
        }
    }

    private func applyOrientationLock() {
        switch OnboardingViewModel.lockMode(for: onboarding.selectedTab) {
        case .portraitLocked: InterfaceOrientationLock.lockToPortrait()
        case .unlocked: InterfaceOrientationLock.unlock()
        }
    }

    // The tab bar is UIKit-managed, so anchor preferences on the .tabItem
    // labels never reach SwiftUI; the coach-mark targets come from invisible
    // proxies laid over the bar's icon band instead. The bar floats inset
    // from the screen edges (iOS 26 style), so the proxies are inset by a
    // width fraction rather than spanning edge to edge — proportional to live
    // geometry, not fixed points, so it tracks device width.
    // OPEN: tabBarEdgeFraction is fitted to the iPhone 17 Pro simulator;
    // verify the arrows land on the icons across device widths and Dynamic
    // Type, and re-fit or replace with real introspection if they drift.
    private var tabItemAnchorProxies: some View {
        GeometryReader { proxy in
            HStack(spacing: 0) {
                ForEach(CoachStep.allCases, id: \.self) { step in
                    Color.clear
                        .frame(height: Constants.Onboarding.tabBarBaseHeight)
                        .anchorPreference(key: TabItemAnchorKey.self, value: .bounds) { [step: $0] }
                }
            }
            .padding(.horizontal, proxy.size.width * Constants.Onboarding.tabBarEdgeFraction)
            .frame(maxHeight: .infinity, alignment: .bottom)
        }
        .allowsHitTesting(false)
    }
}

#Preview {
    ContentView()
        .environment(ErrorState())
}

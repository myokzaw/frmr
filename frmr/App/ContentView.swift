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
    @Environment(\.colorScheme) private var colorScheme
    @State private var onboarding = OnboardingViewModel()

    init() {
        Self.configureTabBarAppearance()
    }

    // v5.1 F8: iOS 26 draws the bar in Liquid Glass itself; on 17–25 it gets
    // the same frosted blur the app's other glass uses, with quiet small titles
    private static func configureTabBarAppearance() {
        guard #unavailable(iOS 26) else { return }
        let appearance = UITabBarAppearance()
        appearance.configureWithTransparentBackground()
        appearance.backgroundEffect = UIBlurEffect(style: .systemUltraThinMaterial)
        let title: [NSAttributedString.Key: Any] = [.font: UIFont.systemFont(ofSize: Constants.TabBarUI.titleFontSize, weight: .medium)]
        for item in [appearance.stackedLayoutAppearance, appearance.inlineLayoutAppearance, appearance.compactInlineLayoutAppearance] {
            item.normal.titleTextAttributes = title
            item.selected.titleTextAttributes = title
        }
        UITabBar.appearance().standardAppearance = appearance
        UITabBar.appearance().scrollEdgeAppearance = appearance
    }

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
        // The camera is always dark, whatever the system scheme
        .tint(ThemePalette.accent(for: onboarding.selectedTab == .camera ? .dark : colorScheme))
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
        // The bubbles point at the tab bar over the camera. The bar isn't covered
        // by the overlay, so a tap on it mid-walkthrough would leave a bubble
        // over the wrong screen: hold the camera until the walkthrough ends.
        .onChange(of: onboarding.selectedTab) {
            if onboarding.visibleStep != nil && onboarding.selectedTab != .camera {
                onboarding.selectedTab = .camera
            }
        }
        .onChange(of: scenePhase) { if scenePhase == .active { applyOrientationLock() } }
        .task {
            onboarding.errorState = errorState
            onboarding.start(context: modelContext)
            #if DEBUG
            // UI tests only: a Roll with photos in it, without a camera
            if RollSeedFixture.isRequested {
                RollSeedFixture.seed(in: modelContext)
            }
            if LibrarySeedFixture.isRequested {
                LibrarySeedFixture.seed(in: modelContext)
            }
            #endif
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

#if DEBUG
// Compiled out of release. Launched with `-UITestSeedRoll`, the app adds
// three generated photos to the Roll (different looks, newest last in the
// list) so a UI test can drive the Roll grid, selection, re-edit, Make strip
// and Clear roll. Adds three Roll photos to the simulator on every launch.
private enum RollSeedFixture {
    static let launchArgument = "-UITestSeedRoll"
    static let size = CGSize(width: 900, height: 1200)
    static let looks: [(UIColor, UIColor, StripCustomization.FilmStock)] = [
        (.systemPink, .systemIndigo, .portrait400),
        (.systemYellow, .systemGreen, .mono400),
        (.systemOrange, .systemTeal, .cine500T),
    ]

    static var isRequested: Bool {
        ProcessInfo.processInfo.arguments.contains(launchArgument)
    }

    static func seed(in context: ModelContext) {
        for (index, entry) in looks.enumerated() {
            let date = Date.now.addingTimeInterval(TimeInterval(-index))
            _ = try? RollViewModel.insert(
                original: photo(from: entry.0, to: entry.1),
                look: .stockDefaults(for: entry.2),
                capturedAt: date,
                context: context
            )
        }
    }

    private static func photo(from start: UIColor, to end: UIColor) -> UIImage {
        UIGraphicsImageRenderer(size: size).image { context in
            let colors = [start.cgColor, end.cgColor] as CFArray
            guard let gradient = CGGradient(colorsSpace: CGColorSpaceCreateDeviceRGB(), colors: colors, locations: nil) else { return }
            context.cgContext.drawLinearGradient(gradient, start: .zero, end: CGPoint(x: size.width, y: size.height), options: [])
        }
    }
}
#endif

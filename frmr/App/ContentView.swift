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
    @Environment(\.colorSchemeContrast) private var contrast
    // The app opens on the camera (v5 F1)
    @State private var selectedTab: AppTab = .camera

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
        let title: [NSAttributedString.Key: Any] = [.font: UIFont.preferredFont(forTextStyle: .caption2)]
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

    // The camera tab is the darkroom whatever the system scheme; the other
    // tabs follow it (v5.2 §4.4)
    private var tabTint: Color {
        ThemePalette.resolve(for: colorScheme, surface: AppTab.surface(for: selectedTab), contrast: contrast).tint
    }

    var body: some View {
        TabView(selection: $selectedTab) {
            LibraryView()
                .tabItem { Label("Library", systemImage: "photo.stack") }
                .tag(AppTab.library)
            CameraView()
                .toolbarColorScheme(.dark, for: .tabBar)
                .tabItem { Label("Camera", systemImage: "camera.viewfinder") }
                .tag(AppTab.camera)
            SettingsView()
                .tabItem { Label("Settings", systemImage: "gearshape") }
                .tag(AppTab.settings)
        }
        .tint(tabTint)
        .preferredColorScheme(preferredScheme)
        .environment(\.selectAppTab, AppTabSelection { selectedTab = $0 })
        .appErrorAlert(errorState)
        // The lock follows the selected tab, not CameraView's appear/disappear,
        // whose ordering against a tab switch is not guaranteed
        .onAppear { applyOrientationLock() }
        .onChange(of: selectedTab) { applyOrientationLock() }
        .onChange(of: scenePhase) { if scenePhase == .active { applyOrientationLock() } }
        .task {
            FrmrTips.configure()
            FrmrTips.noteAppOpened()
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

    // CONTRACT: lockMode(for:) still lives on OnboardingViewModel (a pure
    // static); it moves with the walkthrough's removal
    private func applyOrientationLock() {
        switch OnboardingViewModel.lockMode(for: selectedTab) {
        case .portraitLocked: InterfaceOrientationLock.lockToPortrait()
        case .unlocked: InterfaceOrientationLock.unlock()
        }
    }
}

extension AppTab {
    /// The camera is the darkroom; Library and Settings are paper.
    nonisolated static func surface(for tab: AppTab) -> FrmrSurface {
        tab == .camera ? .darkroom : .paper
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

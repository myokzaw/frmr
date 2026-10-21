import SwiftUI
import SwiftData

// OPEN: app display name is "Filum" as a placeholder — final name TBD
@main
struct FrmrApp: App {
    @UIApplicationDelegateAdaptor(AppDelegate.self) private var appDelegate
    @State private var errorState = ErrorState()

    init() {
        // Before any view reads the strip defaults: Settings binds its film
        // stock picker to the raw stored value, which may still be a v2 name
        StripViewModel.migrateLegacyDefaults(.standard)
    }

    var body: some Scene {
        WindowGroup {
            ContentView()
                .environment(errorState)
                .modelContainer(for: [DiaryEntry.self, DailyStrip.self, OnboardingState.self])
        }
    }
}

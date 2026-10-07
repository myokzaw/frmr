import SwiftUI
import SwiftData

// OPEN: app display name is "Filum" as a placeholder — final name TBD
@main
struct FrmrApp: App {
    @UIApplicationDelegateAdaptor(AppDelegate.self) private var appDelegate
    @State private var errorState = ErrorState()

    var body: some Scene {
        WindowGroup {
            ContentView()
                .environment(errorState)
                .modelContainer(for: [DiaryEntry.self, DailyStrip.self, OnboardingState.self])
        }
    }
}

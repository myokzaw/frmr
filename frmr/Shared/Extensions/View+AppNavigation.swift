import SwiftUI

/// Switches the root tab from anywhere below ContentView (the Roll's
/// "Take a photo" button). Replaces the walkthrough view model's tab binding.
struct AppTabSelection {
    var select: (AppTab) -> Void = { _ in }

    func callAsFunction(_ tab: AppTab) {
        select(tab)
    }
}

extension EnvironmentValues {
    @Entry var selectAppTab = AppTabSelection()
}

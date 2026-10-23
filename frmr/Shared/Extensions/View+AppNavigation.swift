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

extension ToolbarContent {
    /// iOS 26 wraps each bar item in its own glass bubble; a control that
    /// draws its own glass (the Library's segmented switch) then shows two
    /// stacked outlines and a touch-reactive "sticky" shell. Hides the bar's
    /// bubble on iOS 26; a no-op before.
    @ToolbarContentBuilder
    func frmrWithoutSharedBackground() -> some ToolbarContent {
        if #available(iOS 26, *) {
            sharedBackgroundVisibility(.hidden)
        } else {
            self
        }
    }
}

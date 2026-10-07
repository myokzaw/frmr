import SwiftUI

// Collects the tab-bar item rects the coach marks point at (v3 F5).
// The rects come from proxy views in ContentView, not from the .tabItem
// labels — those are UIKit-managed and never report SwiftUI preferences.
nonisolated struct TabItemAnchorKey: PreferenceKey {
    static let defaultValue: [CoachStep: Anchor<CGRect>] = [:]

    static func reduce(
        value: inout [CoachStep: Anchor<CGRect>],
        nextValue: () -> [CoachStep: Anchor<CGRect>]
    ) {
        value.merge(nextValue()) { _, new in new }
    }
}

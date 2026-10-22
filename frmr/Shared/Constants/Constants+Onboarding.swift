import Foundation
import CoreGraphics

nonisolated extension Constants {
    // MARK: First-run walkthrough (v3 F5/F6)
    enum Onboarding {
        static let scrimOpacity: CGFloat = 0.55
        static let bubbleMaxWidth: CGFloat = 260
        static let bubbleCornerRadius: CGFloat = 22
        static let bubbleEdgeInset: CGFloat = 16       // keeps edge-anchored bubbles on screen
        static let bubbleTabGap: CGFloat = 12
        static let arrowLength: CGFloat = 44
        static let arrowStroke: CGFloat = 1.5
        static let stepTransitionDuration: TimeInterval = 0.25
        static let bubbleBodyOpacity: CGFloat = 0.75
        static let bubbleInnerSpacing: CGFloat = 10
        static let bubblePadding: CGFloat = 20
        // The ring that marks the tab a bubble is about
        static let targetRingPadding: CGFloat = 4
        static let targetRingWidth: CGFloat = 2
        // The tab bar is UIKit-managed, so SwiftUI anchor preferences on
        // .tabItem labels never reach the preference system. The coach-mark
        // anchors come from equal-width proxies laid over the bar's icon band
        // instead; this is that band's UIKit-standard height above the bottom
        // safe-area inset.
        static let tabBarBaseHeight: CGFloat = 49
        // The floating tab bar is inset from the screen edges; the anchor
        // proxies are inset by this fraction of the screen width per side so
        // their thirds line up with the real icon centres.
        // OPEN: fitted against the iPhone 17 Pro simulator — verify on other widths
        static let tabBarEdgeFraction: CGFloat = 0.18
    }
}

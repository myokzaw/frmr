import Foundation
import CoreGraphics

// v5.2 M0: the shared design tokens (research/v5.2-ui-makeover.md §4.3, §4.5, §4.7).
// Per-screen namespaces keep their specific values but derive from these.
// Tokens are frozen after M0; changes go through the lead.
nonisolated extension Constants {
    enum DesignUI {
        // MARK: Spacing, 4-pt grid
        enum Space {
            static let xxs: CGFloat = 2
            static let xs: CGFloat = 4
            static let s: CGFloat = 8
            static let m: CGFloat = 12
            static let l: CGFloat = 16
            static let xl: CGFloat = 24
            static let xxl: CGFloat = 32
        }

        /// Screen side margin.
        static let gutter: CGFloat = Space.l
        /// Gap between thumbnails in the Roll's contact-sheet grid.
        static let contactSheetGutter: CGFloat = Space.xxs

        // MARK: Radii (buttons are capsules or circles, never rounded squares)
        enum Radius {
            static let thumb: CGFloat = 6      // thumbnails, dial swatches
            static let media: CGFloat = 12     // photos on paper screens, cards
            static let sheet: CGFloat = 24     // custom panels; use system sheets where possible
        }

        // MARK: Sizes
        /// Hard floor for anything tappable (HIG). Replaces the old 38 pt small glass button.
        static let targetMin: CGFloat = 44
        static let buttonGlass: CGFloat = targetMin
        static let buttonPrimaryHeight: CGFloat = 50
        static let shutterOuter: CGFloat = 76
        static let shutterInner: CGFloat = 64

        // MARK: Typography
        /// Stock codes and edge print are tracked out a little.
        static let codeTracking: CGFloat = 0.5

        // MARK: Glass (§4.5)
        /// iOS 17–25 only: a thin material over a bright sky is not enough
        /// contrast for white glyphs, so they get a hairline shadow.
        static let glyphShadowOpacity: Double = 0.25
        static let glyphShadowOffset: CGFloat = 1
        /// Reduce Transparency in the darkroom: #001219 at this opacity.
        static let opaqueDarkroomOpacity: CGFloat = 0.92
        static let primaryPressedOpacity: Double = 0.85

        // MARK: Motion (§4.7); the Reduce Motion fallbacks live in FrmrMotion
        enum Motion {
            static let snapDuration: TimeInterval = 0.25
            static let snapBounce: Double = 0.15
            static let snapReducedDuration: TimeInterval = 0.15
            static let panelDuration: TimeInterval = 0.35
            static let panelBounce: Double = 0.1
            static let panelReducedDuration: TimeInterval = 0.2
            static let hudFadeIn: TimeInterval = 0.12
            static let hudHold: TimeInterval = 0.7
            static let hudFadeOut: TimeInterval = 0.3
            /// Opacity and saturation ramp while a RAW is still developing.
            static let developDuration: TimeInterval = 0.6
        }
    }
}

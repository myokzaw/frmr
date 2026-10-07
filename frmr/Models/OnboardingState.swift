import SwiftData

// Single-row store for the walkthrough completion flag (v3 F6).
// OPEN: v3-1 — onboarding completion: SwiftData single-row model vs
// @AppStorage. SwiftData is the conservative default because CLAUDE.md names
// it as the persistence layer with no exception for UI flags; the value is
// behind OnboardingViewModel either way, so switching later touches one file.
@Model
final class OnboardingState {
    var hasCompletedWalkthrough: Bool

    init(hasCompletedWalkthrough: Bool = false) {
        self.hasCompletedWalkthrough = hasCompletedWalkthrough
    }
}

import Foundation

// The three tab-bar coach marks, in presentation order (v3 F5)
nonisolated enum CoachStep: Int, CaseIterable, Hashable {
    case library
    case camera
    case settings

    // nil after the last step — the walkthrough is done
    var next: CoachStep? {
        CoachStep(rawValue: rawValue + 1)
    }
}

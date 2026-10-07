import Testing
@testable import frmr

struct OnboardingLockModeTests {
    @Test func cameraTabLocksPortrait() {
        #expect(OnboardingViewModel.lockMode(for: .camera) == .portraitLocked)
    }

    @Test func libraryTabUnlocks() {
        #expect(OnboardingViewModel.lockMode(for: .library) == .unlocked)
    }

    @Test func settingsTabUnlocks() {
        #expect(OnboardingViewModel.lockMode(for: .settings) == .unlocked)
    }
}

import Testing
import UIKit
@testable import frmr

struct InterfaceOrientationLockTests {
    @Test func portraitLockedMaskIsPortraitOnly() {
        #expect(InterfaceOrientationLock.mask(for: .portraitLocked) == .portrait)
    }

    @Test func unlockedMaskMatchesPlistOrientations() {
        let mask = InterfaceOrientationLock.mask(for: .unlocked)
        #expect(mask == .allButUpsideDown)
        #expect(mask.contains(.portrait))
        #expect(!mask.contains(.portraitUpsideDown))
    }

    @MainActor @Test func lockAndUnlockAreIdempotent() {
        InterfaceOrientationLock.lockToPortrait()
        InterfaceOrientationLock.lockToPortrait()
        #expect(InterfaceOrientationLock.mask == .portrait)
        InterfaceOrientationLock.unlock()
        InterfaceOrientationLock.unlock()
        #expect(InterfaceOrientationLock.mask == .allButUpsideDown)
    }

    @Test(arguments: [(AppTab.camera, InterfaceOrientationLock.Mode.portraitLocked), (.library, .unlocked), (.settings, .unlocked)])
    func onlyTheCameraTabLocksPortrait(tab: AppTab, expected: InterfaceOrientationLock.Mode) {
        #expect(InterfaceOrientationLock.mode(for: tab) == expected)
    }
}

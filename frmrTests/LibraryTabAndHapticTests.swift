import AVFoundation
import CoreImage
import ImageIO
import Metal
import SwiftData
import SwiftUI
import Testing
import UIKit
@testable import frmr

// Library tab selection and the strip completion haptic.

// MARK: - v5 follow-ups: library tab, strip haptic

@MainActor
struct LibraryTabAndHapticTests {
    @Test func rollIsTheFirstAndDefaultTab() {
        let library = LibraryViewModel()
        #expect(library.tab == .roll && library.isRollTabActive)
        library.selectStripsTab()
        #expect(library.isStripsTabActive && !library.isRollTabActive)
        library.selectEntriesTab()
        #expect(library.isEntriesTabActive)
        library.selectRollTab()
        #expect(library.isRollTabActive)
    }

    @Test("The completion haptic plays only for the first render", arguments: [
        (false, true, true), (true, true, false), (false, false, false),
    ])
    func theCompletionHapticPlaysOnlyForTheFirstRender(alreadyPlayed: Bool, hasImages: Bool, expected: Bool) {
        #expect(StripViewModel.shouldPlayCompletionHaptic(alreadyPlayed: alreadyPlayed, hasImages: hasImages) == expected)
    }

    @Test func aReRenderAfterACustomizationChangeDoesNotPlayItAgain() async {
        let strip = StripViewModel(items: [StripItem(image: nil, caption: "", entryID: nil)], isPhotobooth: true)
        await strip.renderStrips()
        #expect(strip.hasPlayedCompletionHaptic)
        strip.customization.strengths.grain = 0.3
        await strip.renderStrips()
        #expect(strip.hasPlayedCompletionHaptic)
    }
}

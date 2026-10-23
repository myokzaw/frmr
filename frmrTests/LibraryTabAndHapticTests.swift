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

    @Test func tabsListInOrderWithLabels() {
        #expect(LibraryViewModel.Tab.allCases.map(\.label) == ["Roll", "Entries", "Strips"])
    }

    @Test func hasEntriesTodayLooksAtTheCreationDay() {
        func entry(_ date: Date) -> DiaryEntry { DiaryEntry(createdAt: date, photoPath: "Photos/x.jpg", prompt: "p", response: "r") }
        let yesterday = Calendar.current.date(byAdding: .day, value: -1, to: .now) ?? .now
        #expect(!LibraryViewModel.hasEntriesToday(in: []))
        #expect(!LibraryViewModel.hasEntriesToday(in: [entry(yesterday)]))
        #expect(LibraryViewModel.hasEntriesToday(in: [entry(yesterday), entry(.now)]))
    }

    @Test func downloadingAStripConfirmsOnlyOnSuccess() async {
        struct Boom: Error {}
        let strip = StripViewModel(items: [], isPhotobooth: true)
        #expect(!strip.didSaveToCameraRoll)
        await strip.saveToCameraRoll { _ in }
        #expect(strip.didSaveToCameraRoll)
        await strip.saveToCameraRoll { _ in throw Boom() }
        #expect(!strip.didSaveToCameraRoll, "a failed download clears the confirmation")
    }

    @Test func theMiniStripBadgeReadsFilledOverSlots() {
        let booth = PhotoboothViewModel()
        #expect(booth.stripProgressBadge == "0/\(booth.slotCount)")
        booth.add(UIImage())
        #expect(booth.stripProgressBadge == "1/\(booth.slotCount)")
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


// MARK: - Haptics (v5.2 S7)

struct HapticMappingTests {
    @Test func everyEventMapsToItsFeedback() {
        typealias F = HapticFeedback
        func f(_ event: HapticEvent, advance: Bool = true, core: Bool = true) -> F {
            F.feedback(for: event, filmAdvanceEnabled: advance, coreHapticsAvailable: core)
        }
        #expect(f(.detent) == .impact(.light))
        #expect(f(.reference) == .impact(.rigid))
        #expect(f(.saved) == .notification(.success))
        #expect(f(.warning) == .notification(.warning))
        #expect(f(.shutterAdvance) == .filmAdvance)
        #expect(HapticEvent.allCases.count == 5)
    }

    @Test(arguments: [(false, true), (true, false), (false, false)])
    func theShutterFallsBackToAHeavyImpact(advance: Bool, core: Bool) {
        #expect(HapticFeedback.feedback(for: .shutterAdvance, filmAdvanceEnabled: advance, coreHapticsAvailable: core) == .impact(.heavy))
    }

    @Test func filmAdvanceSettingDefaultsOnAndFollowsTheKey() throws {
        let defaults = try makeScratchDefaults()
        #expect(Haptics.isFilmAdvanceEnabled(in: defaults))
        defaults.set(false, forKey: Constants.DefaultsKeys.filmAdvanceHaptics)
        #expect(!Haptics.isFilmAdvanceEnabled(in: defaults))
        defaults.set(true, forKey: Constants.DefaultsKeys.filmAdvanceHaptics)
        #expect(Haptics.isFilmAdvanceEnabled(in: defaults))
    }
}

// MARK: - Entry row text (v5.2 M6)

@MainActor
struct EntryRowTextTests {
    private func entry(prompt: String = "What did you notice?", response: String, stock: StripCustomization.FilmStock = .daylight200, capturedAt: Date? = nil) -> DiaryEntry {
        DiaryEntry(createdAt: Date(timeIntervalSince1970: 1_700_000_000), photoPath: "Photos/x.jpg", prompt: prompt, response: response, filmStock: stock, capturedAt: capturedAt)
    }

    @Test func theExcerptIsTheTrimmedResponseElseThePrompt() {
        #expect(LibraryViewModel.excerpt(for: entry(response: "  Rain on the glass \n")) == "Rain on the glass")
        #expect(LibraryViewModel.excerpt(for: entry(prompt: " Who was there? ", response: "  \n ")) == "Who was there?")
        #expect(LibraryViewModel.excerpt(for: entry(prompt: " ", response: "")) == "")
    }

    @Test func theMetadataLineIsDateTimeThenTheStockLabel() {
        let created = Date(timeIntervalSince1970: 1_700_000_000)
        let when = created.formatted(date: .abbreviated, time: .shortened)
        #expect(LibraryViewModel.metadataLine(for: entry(response: "x")) == when + " \u{00B7} Daylight 200")
        #expect(LibraryViewModel.metadataLine(for: entry(response: "x", stock: .none)) == when + " \u{00B7} Original")
        // The shutter time wins over the save time
        let shot = created.addingTimeInterval(-86_400 * 3)
        let line = LibraryViewModel.metadataLine(for: entry(response: "x", capturedAt: shot))
        #expect(line.hasPrefix(shot.formatted(date: .abbreviated, time: .shortened)))
    }
}

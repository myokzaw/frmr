import AVFoundation
import CoreImage
import ImageIO
import Metal
import SwiftData
import SwiftUI
import Testing
import UIKit
@testable import frmr

// First-run walkthrough and the typewriter text.

// MARK: - v3 F5/F6: first-run walkthrough

struct OnboardingSequencingTests {

    // A fresh view model with the walkthrough running from step one; never
    // started against a ModelContext, so persistence is inert in these tests
    private func runningViewModel() -> OnboardingViewModel {
        let viewModel = OnboardingViewModel()
        viewModel.reset()
        return viewModel
    }

    @Test func advancingThroughAllThreeStepsCompletesExactlyOnce() {
        let viewModel = runningViewModel()
        #expect(viewModel.step == .library)
        viewModel.advance()
        #expect(viewModel.step == .camera)
        viewModel.advance()
        #expect(viewModel.step == .settings)
        #expect(!viewModel.hasCompleted)
        viewModel.advance()
        #expect(viewModel.step == nil)
        #expect(viewModel.hasCompleted)
        // Advancing past the end must not re-complete or revive a step
        viewModel.advance()
        #expect(viewModel.step == nil)
        #expect(viewModel.hasCompleted)
    }

    @Test func skipCompletesImmediatelyFromEveryStep() {
        for step in CoachStep.allCases {
            let viewModel = runningViewModel()
            for _ in 0..<step.rawValue { viewModel.advance() }
            #expect(viewModel.step == step)
            viewModel.skip()
            #expect(viewModel.step == nil)
            #expect(viewModel.hasCompleted)
        }
    }

    @Test func resetReturnsToTheFirstStepAndClearsCompletion() {
        let viewModel = runningViewModel()
        viewModel.skip()
        viewModel.reset()
        #expect(viewModel.step == .library)
        #expect(!viewModel.hasCompleted)
    }

    @Test("The walkthrough presents only with all three gates open", arguments: [
        (false, true, true, true),    // all open
        (true, true, true, false),    // already completed
        (false, false, true, false),  // permission unresolved
        (false, true, false, false),  // not portrait
    ])
    func shouldPresentRequiresAllThreeGates(hasCompleted: Bool, permissionResolved: Bool, isPortrait: Bool, expected: Bool) {
        #expect(OnboardingViewModel.shouldPresent(
            hasCompleted: hasCompleted, permissionResolved: permissionResolved, isPortrait: isPortrait) == expected)
    }

    @Test func stepOrderIsLibraryCameraSettings() {
        #expect(CoachStep.library.next == .camera)
        #expect(CoachStep.camera.next == .settings)
        #expect(CoachStep.settings.next == nil)
    }

    // Completion must survive a relaunch: a second view model loading from
    // the same store starts completed, and replay clears it again (F6)
    @Test func completionPersistsAcrossViewModelLifetimes() throws {
        let container = try ModelContainer(
            for: OnboardingState.self,
            configurations: ModelConfiguration(isStoredInMemoryOnly: true)
        )
        let context = ModelContext(container)

        let first = OnboardingViewModel()
        first.start(context: context)
        first.reset()
        first.skip()
        #expect(first.hasCompleted)

        let relaunched = OnboardingViewModel()
        relaunched.start(context: context)
        #expect(relaunched.hasCompleted)
        #expect(!OnboardingViewModel.shouldPresent(
            hasCompleted: relaunched.hasCompleted, permissionResolved: true, isPortrait: true))

        relaunched.replayWalkthrough()
        #expect(relaunched.step == .library)
        #expect(relaunched.selectedTab == .camera)

        let afterReplay = OnboardingViewModel()
        afterReplay.start(context: context)
        #expect(!afterReplay.hasCompleted)
    }

    // Catches a step being added without copy
    @Test func everyStepHasCopy() {
        for step in CoachStep.allCases {
            let entry = CoachCopy.entries[step]
            #expect(entry != nil)
            #expect(entry?.title.isEmpty == false)
            #expect(entry?.body.isEmpty == false)
        }
    }
}

// MARK: - v2 F8b: typewriter

struct TypewriterTextTests {

    @Test func revealsEveryCharacterInOrder() async {
        var frames: [String] = []
        await TypewriterText<Color>.reveal("hello", interval: 0.001) { frames.append($0) }

        #expect(frames == ["h", "he", "hel", "hell", "hello"])
    }

    @Test func emptyTextProducesNoFrames() async {
        var frames: [String] = []
        await TypewriterText<Color>.reveal("", interval: 0.001) { frames.append($0) }

        #expect(frames.isEmpty)
    }
}

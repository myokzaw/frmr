# Test consolidation: mapping (2026-10-21)

Before: `before.txt` (310 tests, 56 suites). After: `after.txt` (see its header). Every test that is gone from `after.txt` is listed in section 1 with the surviving test, and the argument case where it applies, that now covers it. Tests that exist in both lists under the same name but changed are in section 2. Section 3 lists what was reviewed and deliberately kept. Section 4 maps each invariant in `docs/film-simulation.md` §8 to its guarding tests.

Nothing under `frmr/frmr/` was edited. Nothing was left unmapped; the one §8 invariant with no direct test (colour matrix rows sum to 1) got a new test (`colourMatrixRowsSumToOne`).

## 1. Removed or merged tests

Short names are `Suite.test`. "(case X)" is the argument case of a parameterised test.

| # | Removed test | Now covered by |
|---|---|---|
| 1 | `AsShotStripRegressionTests.overrideIgnoresEveryFrameStock` | `overrideIgnoresEveryFrameStock(override:)` (case cine500T, the old case; also none, mono400) |
| 2 | `BloomAndLightLeakTests.disabledEffectsArePixelIdenticalToTheOffPath` | Its body asserted only "same render twice is equal" and "leak on changes the strip" (the name promised more than it checked). Determinism: `StripLookDeterminismRegressionTests.sameSeedIsPixelIdentical(stock:)` (case daylight200, effects on, wider). Leak changes the strip: `StripLookNoDarkeningRegressionTests.bloomAndLeakNeverDarkenAStrip` (`lit != off`, every stock). The real "disabled equals off" identity is `effectAtZeroStrengthIsPixelIdentical`. |
| 3 | `BoothStripTests.paperTextureIsDeterministicPerDateAndFaint` | `BoothPaperRegressionTests.paperTextureIsDeterministicPerDateAndStrip` (same bytes, other date differs, plus the texture-exists and texture-is-faint variance bounds, now for both papers). Strip-level re-render equality: `emptyStripPaperIsDeterministicAndNotPure(background:)` (case white). |
| 4 | `CameraControlMappingTests.chromeCounterRotatesToTheFourCardinalOrientations` | Moved unchanged to `RotationAcceptanceTests.chromeCounterRotatesToTheFourCardinalOrientations` (exact signs; the matrix test only checks poses mod 360). |
| 5 | `CameraControlMappingTests.chromeRotationTakesTheShortArcBetweenLandscapes` | `RotationAcceptanceTests.chromeRotationTakesTheShortArcAndAccumulatesWithoutWrapping` (first block) and `faceUpBetweenTwoLandscapesDoesNotChangeTheShortArc`. |
| 6 | `CameraControlMappingTests.chromeRotationAccumulatesWithoutWrapping` | `RotationAcceptanceTests.chromeRotationTakesTheShortArcAndAccumulatesWithoutWrapping` (180, 90, 0 sequence kept verbatim). |
| 7 | `CameraControlMappingTests.chromeRotationEveryStepIsAtMost180` | `RotationAcceptanceTests.everyOrientationFromEveryStartingAngleLandsOnItsPoseOrHolds` (step at most 180 for 14 start angles × all 7 orientations, a superset of the 4 × 4 grid from angle 0) and `longPseudoRandomSequence…`. |
| 8 | `CameraControlMappingTests.chromeRotationDoesNotDriftOnRepeatedOrientation` | `RotationAcceptanceTests.longPseudoRandomSequenceNeverDriftsAndNeverSpinsTheLongWay` (5,000 steps, pose distance checked each step). The "already on the pose is held" line is in `chromeRotationTakesTheShortArcAndAccumulatesWithoutWrapping`. |
| 9 | `CameraControlMappingTests.chromeRotationHoldsLastKnownAngleOnFaceUpOrDown` | faceUp, faceDown and unknown hold: `everyOrientationFromEveryStartingAngleLandsOnItsPoseOrHolds` ("flat/unknown must hold", start -90 included). The 720 to 810 line: `chromeRotationTakesTheShortArcAndAccumulatesWithoutWrapping`. |
| 10 | `CameraFilmStockTests.aCaptureShotKeepsItsStockInThePhotobooth` | `PerPhotoStockModelTests.photoboothShotsCarryTheirStockIntoTheStrip` (second block adds shots through `PhotoboothShot`, the capture path). |
| 11 | `DiaryReviewStateTests.offShowsTheOriginalWithoutRendering` | `StockOffIdentityTests.stockOffReturnsTheOriginalInstanceWithoutRendering(surface:)` (case diaryReview: same three assertions). |
| 12 | `EffectStrengthPipelineTests.allEffectsAtZeroLeaveOnlyTheFilmCube` | Grain 0 leaves a flat photo flat and grain 1 adds visible grain: `grainStrengthMultipliesTheStocksGrain` (now asserts variance at 0 under 0.5, at 1 above 0 + 1, and 0 < 0.5 < 1 < 1.5, Mono 3200 via `renderFullLook`, as the old test did). The other effects at 0: `effectAtZeroStrengthIsPixelIdentical`. |
| 13 | `EffectStrengthPipelineTests.rendersAreDeterministicForASeed` | `FullLookRegressionTests.fullLookIsSeedDeterministic(stock:boosted:)` (case cine500T, boosted: the same strengths 0.8/0.6/0.7/1.2/0.5; adds another seed differs). |
| 14 | `EffectStrengthPipelineTests.zeroStrengthIsPixelIdenticalToTheInputForEveryEffect` | `StrengthZeroIdentityTests.effectAtZeroStrengthIsPixelIdentical(effect:input:)` (all 5 effects × flatMidGrey; adds brightDotOnBlack). |
| 15 | `FilmLookCacheTests.offReturnsTheOriginal` | `StockOffIdentityTests.stockOffReturnsTheOriginalInstanceWithoutRendering` (case filmLookCache). |
| 16 | `FilmStockMigrationTests.storedV2StocksMigrateToTheirV4Equivalents` | `storedValuesMigrateToTheirStock(stored:expected:)` (cases iso100, iso400, iso3200, none). |
| 17 | `FilmStockMigrationTests.unknownOrMissingStoredValuesMigrateToOff` | same test (cases iso800, empty string, nil). |
| 18 | `FilmStockMigrationTests.currentRawValuesRoundTrip` | same test (one case per `FilmStock.allCases` raw value). |
| 19 | `FullLookRegressionTests.fullLookIsSeedDeterministicAndOffIsTheOriginal` | Seeded part: `fullLookIsSeedDeterministic(stock:boosted:)` (every non-Off stock, default and boosted strengths; adds another seed differs). Off part: `StockOffIdentityTests…(surface:)` (case fullLook, tagged photo, `===`). |
| 20 | `FullLookRenderTests.fullLookKeepsTheSourceSizeAndOrientation(stock:)` | `FullLookRegressionTests.fullLookKeepsOrientation(stock:)` (all 6 non-Off stocks × 8 orientations: tag, sensor pixel size and point size; the old cases daylight200, cine500T, mono3200 with tag .right are inside). |
| 21 | `FullLookRenderTests.heicKeepsPixelsSizeAndOrientationTag` | `FullLookRegressionTests.heicKeepsTheOrientationTag` (orientations right, left, up; sensor pixel size and tag; the `public.heic` type assertion was added to it). |
| 22 | `FullLookRenderTests.offReturnsTheDevelopedPhotoItself` | `StockOffIdentityTests…(surface:)` (case fullLook). |
| 23 | `FullLookRenderTests.theSameSeedGivesAnIdenticalResult` | `fullLookIsSeedDeterministic(stock:boosted:)` (case portrait400, not boosted). |
| 24 | `GrainTests.stripLookIsSeededThroughApplyStripLook` | `StripLookDeterminismRegressionTests.sameSeedIsPixelIdentical(stock:)` (case portrait400; now asserts same seed equal and seed + 1 different for every non-Off stock). |
| 25 | `HalationTests.zeroStrengthIsPixelIdentical` | `effectAtZeroStrengthIsPixelIdentical` (case halation × brightDotOnBlack). |
| 26 | `ImageProcessorTests.exifOrientationMapsOntoTheMatchingUIImageOrientation` and 27 `…cgOrientationRoundTripsEveryCase` | `exifOrientationMapsToTheMatchingUIImageOrientationAndBack(exif:ui:)` (the same 8 pairs; each case asserts both directions). `theFourQuarterTurnsAreDistinct` stays. |
| 28 | `ImageProcessorTests.filmStockNoneLeavesTheImageUntouched` | `StripLookDeterminismRegressionTests.offFastPathReturnsTheOriginal` (`===` for Off with B&W off, 3 orientations × 8 effect combinations × 5 prints; the old case was one point inside it). |
| 29 | `ImageProcessorTests.stripLookIsDeterministic` | `sameSeedIsPixelIdentical(stock:)` (case mono3200, B&W off; the old test used the default seed, the survivor an explicit one: same code path). |
| 30 | `ImageProcessorTests.stripLookKeepsATaggedPhotoUpright` | The matrix: `rightTaggedMatchesUpright(stock:)` (case daylight200, B&W on and off: output orientation `.up` and at most 2/255 from UIKit's upright copy) and `redEdgeLandsOnTheCorrectSide(stock:)` (case daylight200: red on top for `.right`, absolute check). The old test's slot-size assertion was added to the matrix oracle (`assertMatchesUprightOracle`), so every stock, tag and effect combination now checks it. |
| 31 | `LibraryTabAndHapticTests.theCompletionHapticPlaysOnlyForTheFirstRender` | Same name, parameterised: `(alreadyPlayed, hasImages, expected)` rows (false,true,true), (true,true,false), (false,false,false). |
| 32 | `OnboardingSequencingTests.onboardingPortraitGateHoldsOnFlatOrientations` | `RotationAcceptanceTests.onboardingIsPortraitCoversEveryCaseForBothPriorStates` (all 7 orientations × both prior states, a superset of the five old assertions). |
| 33 | `OnboardingSequencingTests.shouldPresentRequiresAllThreeGates` | Same name, parameterised: all-open, completed, permission unresolved, not portrait (the old test asserted "not portrait" twice). |
| 34 | `PerPhotoStockModelTests.diaryEntryRoundTripsItsStock` | Same name, parameterised: every stock through a SwiftData save and fetch, `filmStock` and `filmStockRaw` (the old case cine500T is inside). |
| 35 | `PerPhotoStockRoundTripRegressionTests.diaryEntryRoundTripsEveryStockAndOldRowsReadOff` | Round trip of every stock: `diaryEntryRoundTripsItsStock(stock:)` (stronger: persisted). Nil reads as Off, and `iso3200` migrates to Cine 500T: `anEntryWithoutAStoredStockReadsAsOff` (iso3200 assertion added; nil and iso400 were already there). |
| 36 | `PerPhotoStockRoundTripRegressionTests.photoboothShotsCarryTheirStockIntoStripItems` | `PerPhotoStockModelTests.photoboothShotsCarryTheirStockIntoTheStrip` (now four mixed stocks in order, original photo kept, both `add` paths). |
| 37 | `PhotoEditStateTests.offShowsTheOriginalWithoutRendering` | `StockOffIdentityTests…(surface:)` (case photoEdit: the same four assertions). |
| 38 | `StripDefaultsTests.aFreshInstallStoresNothing` | `StripStockDefaultMigrationTests.aFreshInstallDefaultsToAsShot` (migration of an empty store leaves the stock key unset, and the load gives As shot). |
| 39 | `StripStockOverrideTests.asShotOverOneStockMatchesThatOverrideExactly` | `AsShotStripRegressionTests.asShotOverOneStockMatchesThatOverrideExactly(stock:)` (case portrait400, the old case, plus none and mono3200). |
| 40 | `VignetteTests.vignetteZeroLeavesEveryLookUnchanged` | `StrengthZeroIdentityTests.vignetteZeroLeavesTheStockLookUnchanged(stock:)` (one case per non-Off stock, same assertion). |
| 41 | `WhiteBalanceVisibilityTests.selectedModeIsPresentInBothStates` | Implied by `collapsedShowsExactlyTheSelectedMode` (collapsed list is exactly `[mode]`) plus `expandedShowsAllModesInDeclarationOrder` (expanded list is `WBMode.allCases`, which holds every mode). |
| 42 | Xcode template UI tests: `frmrUITests.testExample`, `testLaunchPerformance`, `frmrUITestsLaunchTests.testLaunch` (files deleted) | Launch is exercised by every real UI test (`app.launch()` in all 11). They asserted nothing. `frmr.xcodeproj` uses file-system-synchronized groups, so nothing in `project.pbxproj` referenced the files. |

## 2. Same name, stronger test

| Test | Change |
|---|---|
| `StripLookOrientationRegressionTests` oracle (`rightTaggedMatchesUpright`, `leftTaggedMatchesUpright`, `everyOrientationMatchesUpright`) | Also asserts the slot-size crop (width and rounded height) for every stock, tag, B&W and effect combination. |
| `StripLookDeterminismRegressionTests.sameSeedIsPixelIdentical` | Also asserts seed + 1 renders a different frame (every non-Off stock). |
| `EffectStrengthPipelineTests.grainStrengthMultipliesTheStocksGrain` | Adds grain 0 and grain 1 versus flat. |
| `BoothPaperRegressionTests.paperTextureIsDeterministicPerDateAndStrip` | Also asserts the texture exists and is faint (variance between 0 and 16) for both papers. |
| `FullLookRegressionTests.heicKeepsTheOrientationTag` | Also asserts the file is `public.heic`. |
| `PerPhotoStockModelTests.anEntryWithoutAStoredStockReadsAsOff` | Adds `iso3200` to Cine 500T. |
| `PerPhotoStockModelTests.photoboothShotsCarryTheirStockIntoTheStrip` | Four mixed stocks, both ways of adding a shot. |
| `AsShotStripRegressionTests.asShotFrameEqualsAnOverrideOfItsOwnStock` | Unchanged (re-added next to its new parameterised siblings). |

## 3. Reviewed and kept (distinct semantics)

| Group | Why kept |
|---|---|
| `GrainTests.sameSeedIsIdenticalAndDifferentSeedsDiffer`, `stripSeedsAreStablePerSlotAndDistinctAcrossSlots`, `framesAcrossStripsGetDistinctSeedsAndStripZeroIsUnchanged`, `seededRandomIsReproducible`, `leakPlacementIsSeededAndLiesOutsideTheFrame`, `lightLeakOnlyBrightensAndIsDeterministic` | Unit tests of the seed functions and the low-level effects, which the render-level matrices do not reproduce. |
| `GrainTests.secondStripDiffersFromFirstButEachIsDeterministic` and `AsShotStripRegressionTests.secondStripDoesNotRepeatTheFirstStripsFrames` | Different configurations (override stock, whole strip, default strip index versus As shot, frame 0). Both kept. |
| `FilmModelTests` pre-normalisation versus normalised versions (`theChainIsMonotonicInExposure`/`normalisedChainIsMonotonic`, `balancedPrintKeepsMidGreyNeutralForEveryStockAndPrint`/`normalisedMidGreyStaysNeutral`) | Different stages of the chain (print balancing, then normalisation, then cube). |
| `DiaryReviewStateTests` versus `PhotoEditStateTests`/`PhotoReEditTests` (RAW replaces preview, Download waits for RAW, failed Download, quick taps) | Same behaviour in two production types (`DiaryReviewViewModel`, `PhotoEditViewModel`). Merging needs a shared protocol in the tests. Left as a follow-up; each guards its own class. |
| `DownloadRegressionTests.downloadWaitsForTheRAWAndSavesItUpright` versus `DiaryReviewStateTests.downloadWaitsForTheRAWAndSavesFullResolution` | One checks orientation and which image (developed, not preview), the other full size and a second tap. |
| `FullLookRenderTests.aCoveringSizeShrinksInUprightTerms` versus `FullLookRegressionTests.displaySizedFullLookKeepsOrientation` | Exact shrink arithmetic versus upright content. |
| `StripStockOverrideTests` semantic tests (`asShotRendersEachFrameWithItsOwnStock`, `anOverrideReplacesEveryFramesStock`) | Colour and neutrality of the rendered frames; the byte-equality tests above do not say what the pixels are. |
| `StripDefaultsTests`, `StripStockDefaultMigrationTests`, `FilmLookModelTests.storedStripDefaultsMigrateFromBoolsAndTheBloomKey` | Different stored keys and generations. |
| `ExposureStepTests` versus `CameraControlMappingTests` exposure tests | Step snapping versus drag mapping. |
| `StripRenderTimingTests`, `FilmStockSampleSheetTests`, `StripSampleRenderTests` | Kept as is, as instructed. |

## 4. Invariants in `docs/film-simulation.md` §8

| § | Invariant | Guarding tests |
|---|---|---|
| 1 | Orientation (never `CIImage(image:)`; upright image or sensor space plus tag) | `StripLookOrientationRegressionTests` (`rightTaggedMatchesUpright`, `leftTaggedMatchesUpright`, `everyOrientationMatchesUpright`, `redEdgeLandsOnTheCorrectSide`, `fullStripMatchesUprightStrip`); `AsShotStripRegressionTests.asShotMixedStocksKeepOrientation`, `asShotStripWithAnOffFrameStaysUpright`; `FullLookRegressionTests.fullLookKeepsOrientation`, `displaySizedFullLookKeepsOrientation`, `heicKeepsTheOrientationTag`; `DownloadRegressionTests.downloadWaitsForTheRAWAndSavesItUpright`; `ImageProcessorTests.exifOrientationMapsToTheMatchingUIImageOrientationAndBack`, `theFourQuarterTurnsAreDistinct`; `FullLookRenderTests.aCoveringSizeShrinksInUprightTerms`; `FilmPreviewMappingTests.theFrameRendersUprightIntoAMetalTexture`. The "never call `CIImage(image:)`" rule itself is a code-review check, not a unit test. |
| 2 | Neutrality; colour matrix rows sum to 1 | `FilmModelTests.balancedPrintKeepsMidGreyNeutralForEveryStockAndPrint`, `normalisedMidGreyStaysNeutral`, `monochromeCubesAreNeutralAtEveryLatticePoint`, `colourMatrixRowsSumToOne` (new in this pass: there was no direct test), `spectralWeightSetsSumToOne`; `ImageProcessorTests.monochromeThroughTheCubeIsNeutral`; `GrainTests.monochromeGrainIsNeutral`. |
| 3 | Monotonicity; the cube does not fold | `FilmModelTests.everyCurveIsStrictlyIncreasing`, `theChainIsMonotonicInExposure`, `normalisedChainIsMonotonic`, `cubeIsMonotonicAlongANeutralRampAndBlackStaysBelowWhite`, `eachColourChannelIsMonotonicAlongItsOwnAxis`. |
| 4 | Black and white targets (0 to `blackTarget` within 1/255; 1 to `printWhiteTarget`) | `FilmModelTests.inputBlackPrintsAtEachPrintsBlackTarget`, `inputWhitePrintsAtTheWhiteTargetForEveryStockAndPrint`, `matteKeepsItsLiftedBlacks`. |
| 5 | Strength semantics: 0 equals off; 1 equals v4; max 1.5 | 0 equals off: `StrengthZeroIdentityTests.effectAtZeroStrengthIsPixelIdentical` (5 effects × 2 inputs), `vignetteZeroLeavesTheStockLookUnchanged` (6 stocks), `EffectStrengthPipelineTests.grainStrengthMultipliesTheStocksGrain` (grain 0); stock Off: `StockOffIdentityTests` (4 surfaces) and `StripLookDeterminismRegressionTests.offFastPathReturnsTheOriginal`. 1 equals v4: `strengthOneIsTheV4Effect`, `aWholeRenderAtV4TogglesEqualsTheStrengthOneRender`, `FilmLookModelTests.defaultsMatchTheV4Look`. Maximum 1.5: `FilmLookModelTests.numbersDecodeAndClampToTheSliderRange`, `clampedStrengthHandlesNaNAndRange`, `PhotoEditStateTests.toolRulesFollowTheStock`. Scaling: `hazeAndLightLeakScaleWithStrength`, `halationScalesWithStrength`, `aLeakKeepsItsPlaceWhateverTheStrength`. |
| 6 | Non-destructive (stored photos are originals; the look is data) | `RollStoreTests.reEditSavesTheLookAndNeverTouchesTheFile`, `aRollPhotoRoundTripsItsLook`, `aDamagedLookDataStillShowsThePhotoAsTheOriginal`; `PhotoReEditTests.discardLeavesThePhotoUnchanged`; `PhotoEditStateTests.downloadWaitsForTheRAWSavesFullResolutionAndCreatesNoRollRecord`, `saveToRollStoresTheDevelopedOriginalAndTheLook`; `DiaryReviewStateTests.okCarriesTheChosenStockToTheEditorAndRetakeDropsTheCapture` ("the original is what gets saved"); `PerPhotoStockModelTests.photoboothShotsCarryTheirStockIntoTheStrip` (original kept); `StockOffIdentityTests`. |
| 7 | Determinism (§7: same inputs give byte-identical output) | `StripLookDeterminismRegressionTests.sameSeedIsPixelIdentical`, `stripRenderIsByteIdentical`; `FullLookRegressionTests.fullLookIsSeedDeterministic`; `AsShotStripRegressionTests.asShotStripIsDeterministic`; `BoothPaperRegressionTests.paperTextureIsDeterministicPerDateAndStrip`, `emptyStripPaperIsDeterministicAndNotPure`; `GrainTests.sameSeedIsIdenticalAndDifferentSeedsDiffer`, `stripSeedsAreStablePerSlotAndDistinctAcrossSlots`, `framesAcrossStripsGetDistinctSeedsAndStripZeroIsUnchanged`, `seededRandomIsReproducible`; `BloomAndLightLeakTests.lightLeakOnlyBrightensAndIsDeterministic`, `leakPlacementIsSeededAndLiesOutsideTheFrame`; `FilmModelTests.cubesAreDeterministicAndTheCacheReturnsTheSameBytes`; `EntryLookSeedTests.anEntrySavedFromAReviewRendersTheReviewsGrain`. |
| 8 | Offline, Apple frameworks only | Not a unit test: `scripts/frmr-guard.sh --all` (bans `URLSession`, `URLRequest`, `import Network`, third-party imports). |
| 9 | Every number in `Constants`, with OPEN markers | Not a unit test: `scripts/frmr-guard.sh --all` (warns on an `// OPEN:` marker with no `Constants` value nearby) and the QA manual audit for magic numbers. |

Unmapped: none. Gaps flagged: §8.1's "never call `CIImage(image:)`" and §8.8/§8.9 are enforced by the guard script and review, not by unit tests (unchanged by this pass).

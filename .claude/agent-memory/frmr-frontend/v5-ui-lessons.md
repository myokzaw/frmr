---
name: v5-ui-lessons
description: v5 frontend build lessons (dial, panels, edit step, Roll) and UI-test fixtures
metadata:
  type: project
---

- DEBUG fixtures: `-UITestPhotoEdit` (CameraView, generated photo, stub Download, real Save to roll), `-UITestSeedRoll` (ContentView, adds 3 Roll photos per launch). Tests in frmrUITests/PhotoModeUITests.swift.
- Dial = ScrollView + `.scrollTargetBehavior(.viewAligned)` + `.scrollPosition(id:anchor:.center)` + contentMargins; `.sensoryFeedback(.selection)` gives the detent haptic (no Haptics contract needed).
- Dark screens: set `.environment(\.colorScheme, .dark)` or slider tracks vanish in light mode.
- XCUITest: confirmationDialog buttons match twice, use `.firstMatch`; `adjust(toNormalizedSliderPosition:)` silently no-ops on off-screen sliders (scroll first); hold-to-compare checked by reading element value from a background queue during `press(forDuration:)`.
- LibraryViewModel.Tab has no Roll case; LibraryView holds the section as @State (contract request).

## v5.1 restyle lessons (Library/Settings/walkthrough)
- Native iOS 26 TabView is already Liquid Glass; keep it (UI tests use app.tabBars.buttons). Tint per tab: camera is always dark, so use the dark accent there.
- Colour roles with light/dark values live in Shared/Extensions/ThemePalette+Accent.swift (accent, onAccent, destructive); contrast measured there.
- Settings List rows only exist on screen: taller rows push `settings.filmStock` off after one swipeUp; keep EffectSliderRow compact (editor stacks five).
- Screenshot tour: frmrUITests/LibraryScreenshotTour.swift, gated by TEST_RUNNER_SHOTS_DIR (+SHOTS_PREFIX); fixtures -UITestSeedRoll + -UITestSeedLibrary (App/LibrarySeedFixture.swift).
- The walkthrough overlay does not cover the UIKit tab bar; ContentView snaps selectedTab back to camera while a step is showing.

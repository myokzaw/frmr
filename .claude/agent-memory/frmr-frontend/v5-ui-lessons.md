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

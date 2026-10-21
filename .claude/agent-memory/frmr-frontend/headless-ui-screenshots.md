---
name: headless-ui-screenshots
description: How to reach non-camera screens for screenshots when the simulator is headless (no tapping)
metadata:
  type: project
---

App always launches on the Camera tab; simctl cannot tap, and the iOS Simulator MCP needs user-granted access (often declined). Workaround: a temporary XCUITest in frmrUITests that navigates (Skip onboarding, tap tab) and writes `XCUIScreen.main.screenshot().pngRepresentation` to a host path passed via `TEST_RUNNER_SHOTS_DIR` env (xcodebuild forwards TEST_RUNNER_* minus the prefix). Delete the temp test afterwards.

Pitfalls: macOS has no `timeout` command (pipeline silently produces nothing). The sim can end up Shutdown between runs (other agents' xcodebuilds); `simctl boot` + `bootstatus -b` first. "Busy / Application failed preflight checks" = springboard not settled; retry after boot.

Settings @AppStorage can be typed with RawRepresentable enums (FilmStock, PrintStock?) — avoids raw-string tags; nil optional removes the key.

Strip screen menu Picker (v4 Part 2, 8 rows): opened while the card sits at the screen bottom, the menu clips its last row and XCUITest can't find it — `app.swipeUp()` before opening. Tapping a swatch scrolls the strip screen so the controls card is in view; good spot for screenshots. A long UI test run can look hung (0 CPU) while another agent's xcodebuild holds the simulator; kill and rerun in background with a log file.

v4 F10 review screen is reachable in the simulator via the DEBUG-only `-UITestDiaryReview` launch arg (CameraView `DiaryReviewFixture`: generated gradient, stub Download saver, skips startCamera). Each run of `testSavedEntryShowsInItsStock` adds one diary entry to the sim. Horizontally scrolling chip rows: `isHittable` throws for off-screen elements — compare `frame.maxX` to `app.frame.maxX` and swipe the containing scroll view. `.task` on a view whose body is an `if` with no matching branch never runs — put a `Color.clear` in a ZStack under it.

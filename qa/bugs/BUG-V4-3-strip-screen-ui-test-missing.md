# BUG-V4-3 Spec'd F7 UI test is missing; the strip screen has never run
- Severity: major | Owner: frontend (UI test) — needs the lead to decide how to seed photos
- Files: frmrUITests/frmrUITests.swift (template `testExample`, `testLaunchPerformance` only); frmrUITests/frmrUITestsLaunchTests.swift.
- Expected (frmr-v4-spec.md §F7 Tests): "A UI test opens the strip screen and cycles every stock without a crash (frmrUITests, simulator, PhotosPicker path)". §Implementation status F7 also says the strip screen "has never been seen running".
- Actual: no such test exists. QA ran `-only-testing:frmrUITests` on simulator 1B3A9DB6: 6/6 template cases pass (the runner works for QA, no "Application failed preflight checks"), but none reaches StripView.
- Why it isn't trivial: StripView is only reachable after PhotosPicker (photobooth) or with diary entries (camera, device-only). A launch argument that seeds a few bundled test images into the photobooth/diary under `#if DEBUG` would make it drivable headlessly — needs a lead decision, since it touches AppEntry (backend) and Photobooth (frontend).
- Evidence: qa run log; `grep -n "func test" frmrUITests/*.swift`.

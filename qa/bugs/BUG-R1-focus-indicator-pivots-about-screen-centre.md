# BUG-R1 Focus indicator rotates about the viewfinder centre, not its own centre
- Severity: major (device-visible in landscape) | Owner: frontend | Status: open, needs device confirmation
- File: frmr/Features/Camera/CameraView.swift, viewfinder overlay (~lines 66-72)
- Cause: `.position(point)` returns a view that fills the overlay; `.id(...)` and `.rotatingWithDevice()` are applied after it, so rotationEffect pivots about the centre of the full-frame overlay. Tapping off-centre in landscape should make the square swing away from the tap point.
- Steps: device, hold landscape, tap near a corner of the viewfinder.
- Expected (task brief: each control rotates about its OWN centre): indicator stays under the finger, glyph turned.
- Actual (by code reading): indicator appears at the tap point rotated about the screen centre by 90 degrees (position is displaced).
- Fix hint: apply `.rotatingWithDevice()` to FocusIndicatorView BEFORE `.position(point)`.
- Evidence: code reading only; not reproducible in unit tests.

Related minor: ExposureIndicatorView has `.padding(.trailing, ...)` applied before `.rotatingWithDevice()`, so its pivot is offset by half the padding. Rotate first, pad after.

## Frontend fix note
FocusIndicatorView now rotates first, then .position(point); ExposureIndicatorView rotates before the trailing padding. All other rotatingWithDevice sites re-checked: glyphs rotate inside fixed frames, no position/offset/padding before rotation. Not verified on device.

## QA re-verification 2026-10-06
Status: fixed in code, needs device. Source read confirms the fix; build and unit tests clean. Visual/VoiceOver confirmation requires a physical device.

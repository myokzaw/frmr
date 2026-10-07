# OBS-R3 Wide views rotated as a whole (not a regression to fix, report only)
- PhotoboothView caption (`capturedCountText`, long "live viewfinder - N of 4 captured") and PermissionDeniedOverlay text (multi-line, wide) use `.rotatingWithDevice()` on a wide view. View+DeviceRotation.swift's own comment says wide views swing their ends into neighbours. Caption copy is a pending product decision. Verify on device that neither clips off-screen in landscape.
- Leftover docs: frmr-v3-spec.md Theme A (F1/F2/F4, lines 15-194, 237, 321) still describes ChromeLayout/isStacked/edgeAlignment/chromeEdge*/compact chip metrics. No code references remain.
- Note: git baseline is the Xcode template (project is untracked), so the "only three tests removed" check cannot be done by git diff; verified instead that the three named tests are absent and the chrome rotation / WB / onboarding suites are present (48 tests in frmrTests.swift + 5 new).
- Observation: SwiftUI.Angle stores radians, so rotationAngle results carry ~1e-13 degree error (e.g. 270.0000000000001). Harmless visually; exact == tests are brittle (my first draft failed on it).

## Frontend fix note
PermissionDeniedOverlay text now has a bounded width (Constants.CameraUI.permissionTextMaxWidth) and minimumScaleFactor so it stays on screen when turned. Photobooth caption left as is: its copy is fixed and ~240pt wide, so turned 90 degrees it will overlap the slot row and buttons above/below (rotation does not reflow); no copy-preserving fix inside the view. Needs a product/layout call (e.g. hide or reposition caption in landscape via a ViewModel property).

## QA re-verification 2026-10-06
Status: fixed in code (PermissionDeniedOverlay bounded), needs device. Photobooth caption landscape overlap remains open pending user layout decision.

## Frontend fix note (caption, user decision)
User decided the Photobooth caption stays upright and unrotated in landscape, copy unchanged. PhotoboothView: removed `.rotatingWithDevice()` from the caption; added lineLimit(1), minimumScaleFactor (Constants.CameraUI.captionMinScale) and a maxWidth frame (captionMaxWidth) so it cannot wrap into neighbouring rows. All other Photobooth controls still rotate per-control. Not verified: needs a device in landscape.

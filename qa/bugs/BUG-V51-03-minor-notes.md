# BUG-V51-03 Minor findings (no failing test possible)

All owner frontend unless noted.
1. Editor: "Hold photo to compare" is cream at low opacity directly on the photo; unreadable over light photos (edit-continue-to-diary-dark.png). Needs a glass backing or scrim.
2. Editor Film chips row clips with a hard edge at the right margin ("Cine 50" cut); a fade mask or full-bleed scroll would read better. A tall empty gap sits between the chips and the tool bar.
3. Reduce Motion: still-unguarded animations: SettingsView:143, PhotoEditView:376, PhotoActionControls:51,91, CameraView:256, View+DeviceRotation:25, StockDial/Focus indicator use withAnimation (dial is guarded). Mostly fades; spin of the rotation glyphs and the live grain overlay (GrainOverlayView TimelineView) are the ones worth guarding.
4. Logic in views: ContentView bounces the tab back to Camera during the walkthrough (`onChange`), and PhotoEditView/StripView compute the "modified tools" set inline. Move to view models (backend) and unit-test.
5. `ThemePalette+Accent.swift` holds three raw hex colours outside Color+Palette.swift/Constants (fine as a palette, but belongs with the palette).
6. `RollViewModel.linkedEntryCount` / `photoIDsWithDiaryEntry` use `try?` and read a failed fetch as 0: the delete prompt would then skip the "keep entry" question (the delete itself still defaults to keepEntry, so no data is lost). Owner backend; low.

# BUG-R2 Photobooth icon-only buttons lack accessibility labels
- Severity: minor | Owner: frontend
- File: frmr/Features/Photobooth/PhotoboothView.swift. The PhotosPicker label (SecondarySquareLabel "photo.on.rectangle") and the undo Button ("arrow.uturn.backward") have no `.accessibilityLabel`. Only "Generate strip" has one.
- Expected: every icon-only control has a label (QA brief). VoiceOver would read the SF Symbol name.
- Evidence: grep accessibility in PhotoboothView.swift returns only line 123.

## Frontend fix note
Added accessibilityLabel "Choose photos from library" (PhotosPicker) and "Undo last photo" (undo button) in PhotoboothView.swift, inline literals like the existing labels (no copy table exists). Not marked verified.

## QA re-verification 2026-10-06
Status: fixed in code, needs device. Source read confirms the fix; build and unit tests clean. Visual/VoiceOver confirmation requires a physical device.

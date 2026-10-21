# OBS-V4-7 Saved entries show a different grain pattern from the review and the Download
- Severity: minor (observation) | Owner: backend
- Files: frmr/Features/Diary/DiaryViewModel.swift:106 seeds the display look with `StripGenerator.seed(for: entry.createdAt, slot: 0)`; frmr/Features/Diary/DiaryReviewViewModel.swift:152 (review and Download) seeds it with `captureDate`. `DiaryEntry.createdAt` defaults to `.now` when the entry is saved (DiaryViewModel.saveEntry, DiaryEntry init), which is after the user has written the prompt.
- Observed: the same photo and stock get a different grain field (and a different light-leak position, if the defaults ever turn the leak on) in the diary thumbnail and the entry viewer than on the review screen and in the downloaded file.
- Spec: F11 doesn't fix the display seed; F13 says the Download seed is "derived from the capture time". So this isn't a spec violation, but the review's promise ("this is what your photo looks like") quietly changes after saving. It's subtle at thumbnail size with stock-default effects.
- Suggest: save the capture date with the entry (or set `createdAt` to the capture date) and seed display renders from that.
- Device check: compare an entry's detail view with its review screen and its download, at the same zoom.

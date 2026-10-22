# BUG-V51-02 PhotoModeUITests.testEditorToolbarScrubberCompareAndDownload is flaky under load

- Severity: minor (test reliability)
- Owner: frontend (test)
- Actual: failed once in `scripts/test.sh all qa` ("photo reports Original while held", PhotoModeUITests.swift:246, 10 s timeout) while `frmr-guard --all` ran at the same time. Passed on the isolated rerun and on both screenshot passes.
- Cause suspected: the background-queue poll of `photo.value` races the blocked press on the main test thread.
- Fix suggestion: read `edit.compareBadge` existence or poll after `press(forDuration:)` with a longer hold, instead of a single check at 0.6 s.

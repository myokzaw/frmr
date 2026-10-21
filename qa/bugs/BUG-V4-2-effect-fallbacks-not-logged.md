# BUG-V4-2 Effect-stage filter failures fall back silently, without a log
- Severity: minor | Owner: backend
- File: frmr/Features/Camera/ImageProcessor.swift. Silent `return input` / `?? input` / `continue` with no log at :307, :312, :320, :328 (halation), :344 (luminance), :392 (bloom), :407-415 and :425 (light leak), :449, :480-486, :492, :519 (grain), :533, :540 (grain mask). Only the top-level read failure (:132) and render failure (:177) and the cube (:366) log.
- Expected (frmr-v4-spec.md §Definition of done): "cosmetic filter failures fall back to the unfiltered photo and are logged". CLAUDE.md: "Never silently catch and discard ... Log to console for debugging."
- Actual: if any of these Core Image steps returns nil the effect silently disappears from the strip; nothing reaches the console, so a missing halation/grain on device would be undiagnosable.
- Evidence: source read. Not reproducible in tests: the built-in filters never return nil for valid input on the simulator.
- Suggested: one `print("[ImageProcessor] <effect> failed; skipping")` (or Logger) per effect function's fallback.

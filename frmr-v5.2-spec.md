# frmr — v5.2 UI makeover (draft)

**Date:** 2026-10-21
**Status:** Decisions in progress. Build after v5.1 is merged and verified.
**Source:** `research/v5.2-ui-makeover.md` (iOS design engineer, Opus) contains the full audit, competitive research with sources, design system, per-screen proposals, signature moments and roadmap.
**Agent rule:** build agents run on Sonnet.

## Decisions made by the user (2026-10-21)

| Question | Decision |
|---|---|
| Editor after every Photo shot | **Add a Settings toggle "Edit after each shot", default on.** Off means keep shooting and edit later from the Roll thumbnail. |
| Camera layout on tall phones | **Dial and shutter below a 3:4 viewfinder**, on black. Floating glass controls only on short phones. |
| Film strip buttons | **Mini-strip sheet:** the four slots become a small strip in the thumbnail position. Tapping it opens gallery / Roll / undo / Generate, keeping Photo and Strip chrome identical. |
| Walkthrough | **Replace the custom coach marks with TipKit tips** anchored to real controls. |

## Remaining open questions (proposed defaults)

| # | Question | Proposed default |
|---|---|---|
| v5.2-5 | Colour swatches on the stock dial, or plain codes | Swatches plus codes |
| v5.2-6 | Contact-sheet Roll: always dark, or paper in light mode | Paper in light mode, dark in dark mode |
| v5.2-7 | Strip screen "Archive": merge Save and Archive into one "Keep strip" | Yes |
| v5.2-8 | Adopt the system serif permanently instead of bundling Newsreader | Yes |
| v5.2-9 | Settings toggle for the richer film-advance haptic | Yes, default on |
| v5.2-10 | Tab bar | Keep for now; revisit after the camera layout lands |

## Already handed to the v5.1 agents (from the audit)

- **Contrast:** "Save to roll" on teal, tab tint on the dark camera, rust in dark mode, character count.
- **Touch targets:** 44pt minimum for the strip buttons.
- **Strip screen:** Close overlaps the strip; Save/Share/Archive are clipped.
- **Library:** the Roll's left-edge bleed, lists scrolling under the tab bar, Entries showing the response first, Strips in two columns.
- **Walkthrough:** the "Library" bubble appears on the Settings screen.
- **Accessibility:** Reduce Motion, Reduce Transparency, and Dynamic Type where text is touched.

## Roadmap

See `research/v5.2-ui-makeover.md` §7. The order:
1. A design-token PR by one agent first: Dynamic Type type roles, spacing, radii, colour roles with light and dark values, and the upgraded `frmrGlass`.
2. Then camera, restyle and backend agents in parallel (separate worktrees).
3. Then a QA accessibility pass.

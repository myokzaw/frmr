# frmr — v5.1 Feature Specification (brainstorm draft)

**Date:** 2026-10-21
**Status:** Requirements agreed; not started. Build after v5 is pushed.
**Baseline:** v5 on `v5-photo-camera`: Photo mode is the launch screen, the editor appears after every shot, and the Roll exists.
**Agent rule:** every sub-agent runs on **Sonnet**.

## Goal

**Diary stops being a separate camera mode** (F1–F7), and **the UI gets a modern refresh** (F8). and becomes a step after taking a photo. The user shoots in the normal camera, edits the look, then chooses **Continue to diary** (beside **Save to roll**) to write a reflection about that photo.

## Decisions made by the user (2026-10-21)

| Question | Decision |
|---|---|
| Does "Continue to diary" also save to the Roll? | **Yes: Roll + diary.** The photo goes into the Roll (re-editable) and the diary entry links to it. |
| Editor bottom row | **Discard moves to the top bar** next to Retake. The bottom row is **Continue to diary** and **Save to roll** side by side. |
| Diary mode | **Removed from the mode switch.** The switch becomes Photo / Film strip. |
| Timing | Push v5 first (after the QA test cleanup); this is **v5.1**. |

## Proposed flow

```
Camera (Photo) ──shutter──▶ Editor (Film / Print / Effects)
                                   │
          ┌────────────────────────┼─────────────────────────┐
     Save to roll            Continue to diary          Discard / Retake (top bar)
          │                        │
     Roll (Library)      saves to Roll, then ──▶ Prompt screen (EntryEditorView)
                                                     │  Save entry / Skip
                                                     ▼
                                          Diary entry linked to the Roll photo
                                          (Library → Entries)
```

## Feature sketch

| # | Feature | Notes |
|---|---|---|
| F1 | Mode switch: Photo / Film strip | Remove `.diary` from the switch. Photo stays the launch mode. Film strip is unchanged. |
| F2 | Editor top bar | Icons (v5.1-1): ✕ Discard and ↺ Retake on the left (Delete in re-edit), the hold-to-compare hint, and Download on the right, each with an accessibility label. |
| F3 | Editor bottom row | **Continue to diary** (secondary) and **Save to roll** (primary), side by side. Not offered when re-editing from the Roll (v5.1-2): only right after a capture. |
| F4 | Continue to diary | Saves the photo to the Roll first (same as Save to roll), then presents the existing prompt screen (`EntryEditorView`) with the edited look as its header. Save entry and Skip create a `DiaryEntry` that **links to the `RollPhoto`** (new optional `rollPhotoID`). It doesn't store a second copy of the image. |
| F5 | Data model | `DiaryEntry.rollPhotoID: UUID?` (additive). Older entries keep their own `photoPath` and look and display as they do now. The entry's look comes from the linked Roll photo, so re-editing the photo updates the entry (v5.1-3: live link). |
| F6 | Removed or retired | Diary camera mode; the diary review screen (`DiaryReviewView` / `DiaryReviewViewModel`, now unreachable); `presentsReviewStep`. Delete the code and its tests (v5.1-4). |
| F7 | Library | **Entries tab is kept** (v5.1-5). Roll thumbnails of photos with a diary entry show a small book badge (v5.1-6). |

## Decisions on the open questions (user, 2026-10-21)

| # | Question | Decision |
|---|---|---|
| v5.1-1 | Top bar layout | **Icons:** ✕ Discard and ↺ Retake (Delete in re-edit) on the left, Download on the right, each with an accessibility label |
| v5.1-2 | Offer Continue to diary when re-editing a Roll photo later | **No.** Only right after a capture. |
| v5.1-3 | Entry photo: live link or snapshot | **Live link** to the Roll photo (one photo, one look) |
| v5.1-4 | Delete the old diary review screen code | **Yes** (`DiaryReviewView`, `DiaryReviewViewModel`, `presentsReviewStep` and their tests) |
| v5.1-5 | Keep Library → Entries | **Yes** |
| v5.1-6 | Mark Roll photos that have a diary entry | **Yes:** a small book badge on the thumbnail |
| v5.1-7 | Deleting a Roll photo that has an entry | **Ask each time:** delete both, or keep the entry with its own copy of the photo and look |
| v5.1-8 | Walkthrough copy | **"Shoot on film. Write about a photo with Continue to diary."** |

## F8 — Modern UI refresh (added 2026-10-21)

**Why:** the user finds the v5 UI clunky. Compared with current camera apps:
- the bottom third stacks WB/EV chips, the dial, its caption, the shutter and the tab bar;
- every control has the same visual weight;
- heavy monospace labels and outlined capsules sit everywhere;
- the editor stacks five full-width sliders.

**References:**
- **iOS 26 Camera:** two default modes, everything else behind a swipe, round Liquid Glass buttons floating over a full-screen viewfinder ([MacRumors](https://macrumors.com/guide/ios-26-camera-app), [Lightstalking](https://www.lightstalking.com/camera-ios26/)).
- **Halide Mark III:** the most-used controls get the most prominence, with Liquid Glass styling ([Engadget](https://engadget.com/2182499/halide-mark-iii-adds-a-built-in-editor-to-the-popular-camera-app), [Digital Trends](https://www.digitaltrends.com/phones/halide-mark-iii-brings-artsy-film-magic-to-one-of-the-best-iphone-camera-apps/)).
- **Obscura:** built for one thumb, with the editor fitted into the space under the photo ([MacStories](https://www.macstories.net/?p=69035), [Sketch](https://go.sketch.com/blog/obscura-studio/)).

**User decisions:**

| Question | Decision |
|---|---|
| Tab bar on the camera | **Keep it.** Restyle it slimmer; it doesn't hide. |
| Stock selection | **Keep a slimmer dial** above the shutter: smaller, quieter type, no separate caption line. The full stock name shows in the selected cell or a small label. |
| Glass look | **Liquid Glass on iOS 26, frosted-blur fallback on iOS 17–25.** Same layout everywhere; iOS 17 stays the minimum. |
| Editor | **Icon toolbar plus one scrubber**, like the Photos app editor: Film, Print, Halation, Haze, Light leak, Grain, Vignette. One tick-mark scrubber adjusts the selected tool (0–150%), with a value readout. Film and Print show their chips in the scrubber's place. The photo stays large. |

**Proposed camera layout** (the frontend proposes final measurements with screenshots for lead and user review):
- **Top:** mode switch (Photo / Strip once Diary is removed in this release) as a small glass segmented control. White balance and exposure become **small glass icon buttons at the top right**, opening their panels as glass sheets. This clears the chips out of the bottom stack.
- **Bottom stack, top to bottom:** slim dial → shutter row (Roll thumbnail, shutter, flip) → slim tab bar.
- **Styling:** controls float over the full viewfinder on glass or blur backings, with no outlined capsules. Type is SF Pro and small; monospace only for short codes and values. One accent colour (amber) for the shutter and selection.
- **Unchanged:** the camera rotation rules (glyphs rotate in place; wide controls stay put).

**Proposed editor layout:**
- **Top:** icon buttons per v5.1-1 (✕ Discard, ↺ Retake or Delete, ↓ Download), on glass.
- **Photo:** as large as possible; hold to compare.
- **Below the photo:** the selected tool's name and value, then the scrubber (or chips for Film and Print), then the icon toolbar. A reset (double-tap the scrubber, or a small reset icon) restores the stock default.
- **Bottom:** Continue to diary and Save to roll, side by side.

**Implementation notes:**
- A shared `GlassBackground` modifier: `.glassEffect` when `#available(iOS 26, *)`, `.ultraThinMaterial` otherwise.
- Every number goes in the Constants UI namespaces.
- Accessibility: icon buttons get labels, the scrubber is an adjustable element (increment/decrement in 5% steps), and Dynamic Type is respected.
- **Tests:** update the UI tests for the new controls and add screenshots before and after for review.

| # | Open question (F8) | Proposed default |
|---|---|---|
| v5.1-9 | Where the mode switch sits once only Photo / Strip remain | Small glass segmented control at the top left |
| v5.1-10 | Scrubber haptics | A light tick every 10%, and a stronger one at 100% (the stock default) |
| v5.1-11 | Apply the restyle to Library, Settings and the strip screen too | Light pass: same type scale and glass sheets; no layout changes |

## Migration

- Existing diary entries keep working: own `photoPath` plus look, no Roll link.
- No data is lost. Stored settings referring to the Diary mode are ignored, since launch is already always Photo.

## Sequencing (when approved)

1. **Backend (Sonnet):**
   - `DiaryEntry.rollPhotoID`
   - "save to Roll, then start diary" in `PhotoEditViewModel`
   - remove the Diary mode and the review code
   - tests
2. **Frontend (Sonnet):**
   - mode switch without Diary
   - editor top and bottom bars
   - prompt screen presented from the editor
   - Roll badge
   - UI tests
3. **QA (Sonnet):** regressions, and old entries still displaying.
4. **Lead:** docs (README, CHANGELOG, project.md, CLAUDE.md, `docs/film-simulation.md` if touched, `docs/testing.md`), then commit and push to the v5 branch.

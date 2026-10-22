# frmr — v5.1 Feature Specification (brainstorm draft)

**Date:** 2026-10-21
**Status:** In progress (2026-10-21). v5 is pushed (`1d4a1dd`). F8 open questions v5.1-9…11 use the proposed defaults (the user didn't answer them; they can be changed later).
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
| v5.1-11 | Apply the restyle to Library, Settings and the strip screen too | **User decision (2026-10-21): yes, every screen gets the modern treatment** (see F9 and F10), not just a light pass |

## F9 — Film strip camera matches the Photo camera (user, 2026-10-21)

**Film strip mode uses the same camera UI as Photo mode.** It is the same screen with a strip-specific layer on top:
- the same glass top bar: mode switch (Photo / Strip), white balance and exposure glass icons with their sheets;
- the same slim stock dial (this overturns v5-2, which kept the old Film chip for Film strip);
- the same shutter row, slim tab bar and rotation rules.

**Strip-specific additions**, styled to match:
- a compact row of four slot thumbnails (filled or empty) just above the dial, showing "n of 4";
- gallery picker and undo as small glass icon buttons;
- **Generate**: appears as the primary action once at least one slot is filled. It replaces the Roll thumbnail position, or sits beside the shutter (frontend proposes; lead and user review the screenshot).
- **Pick from Roll** sits next to the gallery picker.

Each strip shot keeps the stock chosen on the dial when it was taken. Unchanged: the strip screen flow after Generate, and "As shot" behaviour.

## F10 — Modern UI on every screen (user, 2026-10-21)

The F8 visual language applies everywhere:
- glass sheets and backings (Liquid Glass on iOS 26, frosted blur on iOS 17–25);
- quiet SF Pro type, with monospace only for codes and values;
- no outlined capsules;
- one amber accent;
- generous spacing;
- icon buttons with accessibility labels.

| Screen | Modernisation |
|---|---|
| **Strip screen** | Strip preview as the hero on a quiet background. Controls (paper, stock, print, B&W, effects) move into a glass bottom sheet using the editor's icon toolbar and single scrubber pattern. Save, Share and Archive become icons, plus one primary action. |
| **Prompt screen (EntryEditorView)** | The photo header in its look, full-bleed with rounded corners. Typewriter prompt; a clean writing card; character count as quiet metadata. Save entry is primary, Skip secondary. |
| **Library** | Segmented Roll / Entries / Strips in glass. The Roll grid has tighter gutters, subtle rounded corners and the book badge (F7). The selection bar is a glass toolbar. Entries are a modern list with thumbnail and excerpt. Strip thumbnails are larger. Empty states use the new style. |
| **Entry and strip detail viewers** | Full-bleed media, glass top bar with icon actions, metadata in a quiet footer. |
| **Settings** | Inset grouped list with the new type scale and quieter section headers; sliders match the editor scrubber where it fits; destructive rows stay rust. |
| **Walkthrough (coach marks)** | Glass bubbles and the new type; same steps. |
| **Tab bar** | Slimmer and glass-backed (F8). |

**Process:** the frontend produces before/after screenshots of every screen, in light and dark where relevant. The lead reviews them and sends a selection to the user before the round is accepted.

## F11 — Faster parallel agent workflow (user, 2026-10-21)

**Measured:**
- The unit tests themselves run in about 37 s; most of each 3–5 min agent cycle was rebuilding, plus running the full suite every time.
- The UI tests took about 465 s, serially on one simulator, because simulator cloning fails on this machine.
- Agents shared one folder and two simulators, and all edited `Constants.swift`.

**Done (lead, 2026-10-21):**
- One simulator per role (`frmr-backend`, `frmr-frontend`, `frmr-qa`, `frmr-lead`) and three UI shard simulators (`frmr-ui-1…3`).
- `scripts/test.sh`, with tiers `suite`, `fast`, `unit`, `ui` and `all`:
  - one `build-for-testing`, then `test-without-building` (`--no-build` re-runs take about 6 s);
  - `fast` skips the slow matrix and timing suites;
  - `ui` shards XCTest classes across three simulators at once;
  - any Swift warning fails the run.
- `docs/testing.md` §0 documents the workflow, and the agent role files now point to the script.

**Queued (after the current backend round, so as not to disturb it):**
1. **Split `Constants.swift` into files per owner**: `Constants+Camera`, `+ImageProcessing`, `+Strip`, `+Diary` (backend) and `+CameraUI`, `+EditorUI`, … (frontend). Parallel agents then stop editing the same file.
2. **Worktree isolation for parallel rounds**: backend and frontend each get their own git worktree (Agent `isolation: "worktree"`) and the lead merges them. Neither builds against the other's half-finished edits.
3. **Faster UI tests**: a DEBUG launch argument that turns off animations (`UIView.setAnimationsEnabled(false)`) and shortens debounces during UI tests (frontend). Also reduce relaunches inside UI tests.
4. **Run the backend and frontend v5.1 rounds in parallel** where their files don't overlap: for example, frontend F10 restyling of Library and Settings while backend finishes F4/F5.

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

## Implementation status — v5.1

| Item | Status |
|---|---|
| v5 pushed | ✅ `v5-photo-camera` @ `1d4a1dd` |
| Backend (Sonnet): F1, F4, F5, F7 model; Roll delete with entry; badge API; walkthrough copy | ✅ 287 unit tests (lead, full tier, 48 s). Legacy camera shims remain until frontend A is done. New decision v5.1-12: Clear roll keeps linked entries as their own copies by default. |
| Workflow (F11) | ✅ `Constants.swift` split into `frmr/Shared/Constants/` (one file per namespace); `scripts/test.sh` boots its simulator; restyle role added (`frmr-restyle`, UI shards `frmr-ui-4…6`); shared `GlassBackground` modifier; local checkpoint `84358fb` (not pushed). |
| Frontend A (Sonnet, worktree `worktrees/camera`, branch `v5.1-camera`) | ✅ `62bb710`: shared Photo/Strip chrome (glass mode switch, WB/EV sheets, slim dial; strip slots plus amber Generate in the thumbnail slot), editor (glass ✕ ↺ ↓, 7-tool icon bar, tick scrubber with haptics, Continue to diary + amber Save), single-cover editor→prompt handoff, prompt and strip screens restyled, review screen deleted, `-UITestFast`. Audit fixes: 44pt targets, amber-on-dark primaries, strip screen Close/Save layout, Reduce Motion/Transparency. Open: large Dynamic Type, dark screenshot pass. |
| Frontend B (Sonnet, worktree `worktrees/restyle`, branch `v5.1-restyle`) | ✅ `bd11de4`: glass segmented Library, Roll grid (gutters, book badge, glass selection bar with Delete), delete-with-entry and Clear roll prompts, Entries with the response first, two-column Strips, dark full-bleed viewers, Settings restyle, walkthrough anchoring fix, light/dark accent and destructive roles (≥5:1). The tab bar stays native (Liquid Glass on iOS 26), not slimmed, so UI tests keep working. |
| Merge | ✅ `5049e61` + `7d6e009` into `v5-photo-camera`; `GlassIconButton` add/add conflict resolved (camera version plus `isEnabled`). Lead run: **290 unit + 15 UI pass** (`scripts/test.sh all lead`, 8 min; UI shards now balanced by test count). |
| Backend contracts (Sonnet) | In progress: Pick from Roll keeps the full look; `isWhiteBalanceAdjusted`/`isExposureAdjusted`; `stripProgressText`; editor tool in the VM; shorter debounce under `-UITestFast` |
| QA (Sonnet) | Queued after the backend contracts |
| QA (Sonnet) | Queued |

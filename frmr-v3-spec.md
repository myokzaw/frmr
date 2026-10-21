# frmr — v3 Feature Specification

**Date:** 2026-08-24
**Baseline:** v2 build, all eight features implemented, plus post-v2 rotation bugfix parts 1–6 (part 7 reverted). 28 unit tests passing, compiling without warnings.
**Context files:** Read alongside `CLAUDE.md` (engineering rules) and `project.md` (full product spec). All constraints from those documents apply here. `frmr-v2-spec.md` is required background for §Theme A — the landscape work is a direct continuation of the post-v2 bugfix series.

---

## Overview

v3 has two independent themes that share no code and can be built in parallel.

| Theme | Features | What it fixes |
|---|---|---|
| **A — Landscape chrome** | F1 `isStacked` delivery bug · F2 Bottom-edge chrome redistribution · F3 Collapsible white balance · F4 Compact landscape chip metrics | The camera chrome in landscape is one deep column against a single edge, reaching too far into the frame. |
| **B — First-run walkthrough** | F5 Coach marks for the three tab icons · F6 Replay from Settings + persistence | A first-time user gets a camera screen with no explanation of what Library / Camera / Settings do. |

No new user flows. One new screen-level overlay (the walkthrough), one new feature directory, one new model. The ethos from §1 — *intentional, user-initiated, offline, no AI* — governs every decision. The walkthrough is the only thing in the app that appears without a tap; §F5 documents that as a deliberate, bounded exception and everything after the first showing is user-initiated.

---

> **Superseded (post-v3 decision, user-approved).** F1, F2 and F4 are replaced by one rule: the camera screen has a single portrait layout. Controls never move, stack or reflow with device orientation; each control rotates individually about its own centre (easeInOut 0.3s, shortest arc, via an unwrapped accumulated angle). Wide backing shapes stay static and only the glyph rotates. All chips are 44pt circles, so the 32pt along-axis exception in F4 no longer exists. `ChromeLayout`, the edge strip and the v3-5 edge mapping are removed. The viewfinder, tab bar and onboarding overlay never rotate. The mode toggle (Diary / Film strip), white-balance chips and Photobooth Generate button are icon-only with accessibility labels. The Photobooth caption copy is unchanged by decision, and the caption is the one deliberate exception to rotation: it stays upright and unrotated (single line, bounded width, minimum scale) because a wide string cannot rotate in place without overlapping neighbours; its on-screen fit in landscape is unverified. F3 (collapsible white balance) stands.

# Theme A — Landscape chrome

## F1 — `isStacked` is not reaching `LensChipRow` and `WhiteBalanceControl`

### What it is

A bugfix, and a prerequisite for F2–F4. Post-v2 part 3 gave `ModeToggle`, `LensChipRow`, and `WhiteBalanceControl` an `isStacked: Bool` that switches `HStack` → `VStack` in landscape. Part 7 was a failed attempt to address a device screenshot where the mode toggle stacked correctly but the other two did not; it was reverted without root-causing.

A fresh device screenshot (2026-08-24, landscape hold) shows the same thing. It also narrows the cause considerably:

- The mode toggle renders **stacked** — `Film strip` above `Diary` in the portrait buffer, which reads as a horizontal pill in the hand. Correct.
- The lens chips (`Tele`, `1×`, `0.5×`) and the WB chips (`Shade`, `Cloudy`, `Daylight`, `Auto`) render **side by side** in the buffer, which reads as a long vertical column running down the screen. Wrong.
- **All three groups have rotated glyphs.** The text in every chip is sideways.

That last point is the diagnostic. `uiRotationAngle` and `chromeLayout` are computed in the same `applyOrientation(_:)` callback from the same notification. Rotation is arriving at all three views; the layout flag is arriving at only one. That exonerates the observer, the notification wiring, and `chromeLayout(for:current:)` — the failure is downstream, in delivery or in the branch itself.

### Why

Everything in F2–F4 assumes the two chip groups actually stack. Building compaction on top of a control that silently ignores its layout flag will produce another round of unexplained device screenshots.

### Root-cause first, then fix

Do not change layout code before confirming the cause. In order:

1. **Read the three call sites in `CameraView.swift`.** All three should pass `viewModel.chromeLayout == .sideBySide ? false : true` (or equivalent). If `isStacked` was declared with a default value — `let isStacked: Bool = false` — then a call site that omits the argument compiles cleanly and silently pins the control to the portrait layout forever. This is the leading hypothesis and it is consistent with every observed symptom.
2. **Read the branch in each of the two views.** Confirm `isStacked` selects `VStack` and not `HStack`. An inversion in these two but not in `ModeToggle` produces exactly this screenshot.
3. **If neither, instrument.** Temporarily render the raw values as text inside each of the three control bodies (`Text("\(isStacked)")`), build to the device, and photograph the result. This is the step part 7 skipped.

### Files changed

| File | Change |
|---|---|
| `Features/Camera/CameraView.swift` | Fix the `LensChipRow` and `WhiteBalanceControl` call sites, and/or `LensChipRow`'s branch, per the finding above |
| `Features/Camera/WhiteBalanceControl.swift` | Fix the branch if inverted |

### Notes

- Whatever the finding, **remove any default value from `isStacked`** on all three controls. A required parameter makes an omitted call site a compile error instead of a silent visual bug. This is the durable fix regardless of which hypothesis is correct.
- Record the actual root cause in this document when found. Part 7 was reverted precisely because it changed behaviour without one.

### Finding (2026-08-24) — both hypotheses disproven; cause not established

Steps 1 and 2 were carried out by reading the code. **Both documented hypotheses are wrong:**

1. **No default value existed.** All three controls declared `let isStacked: Bool` with no default, and all three call sites (`CameraView.swift` lines 16, 41, 49 pre-change) passed `viewModel.chromeLayout == .stacked` identically. An omitted argument was already a compile error, so the "silently pinned to portrait" mechanism was not possible.
2. **No branch was inverted.** `ModeToggle`, `LensChipRow`, and `WhiteBalanceControl` each branched `if isStacked { VStack } else { HStack }`. All three agreed.

The three views received the same flag from the same property and branched on it the same way, so **nothing in the source explains the screenshot.** Step 3 (on-device instrumentation) is the only remaining way to establish the cause, and it needs a physical device — unavailable in this session. **The root cause is therefore still unknown, and this document should not be read as claiming otherwise.**

**What was done instead: the failure mode was removed structurally rather than patched.** F2 moves all three controls into a *single* `chromeEdgeStrip` container that is built only when `chromeLayout.isStacked`, and each control is passed a literal `isStacked: true` inside it (and a literal `false` in the portrait branch). The three controls can no longer disagree about the layout, because there is no longer a per-control flag evaluated in three different container contexts — there is one branch, in one place, and the arrangement follows from which branch built the view at all. F3 shrinks the surface further: white balance collapses to a single chip, which has no arrangement to get wrong.

A device screenshot is still required to confirm the symptom is gone, per the checklist below. If it recurs, `Constants.CameraUI.chromeDebugOverlayEnabled` renders the live `chromeLayout` and rotation angle over the viewfinder in DEBUG builds — that is step 3, pre-wired, so the next person with a device can photograph the real values without writing throwaway code.

### Tests

The existing `chipGroupsStackOnlyInLandscape` covers the mapping, and it passes — the mapping was never the problem. No new pure logic here. Verification is a device photograph showing all three groups stacked in landscape.

---

## F2 — Chrome moves to the user's bottom edge

### What it is

In landscape, the mode toggle, lens chips, and white balance move out of the bottom `VStack` and into a thin strip along the edge the user perceives as the **bottom** of the screen. The shutter button and flip button stay exactly where they are. Portrait is untouched.

### Why

Post-v2 parts 5 and 6 attacked landscape depth by tightening the gaps inside the cluster. That has a floor: the cluster is a single column, so its depth is the sum of everything in it, and tightening spacing can only ever remove the gaps. Splitting the chrome across two edges caps depth at the *tallest single item* rather than the total, which is a different order of saving. It is also how every real camera app lays out in landscape — settings along one long edge, shutter on a short edge, viewfinder uninterrupted between them.

### The edge is orientation-dependent

The interface is locked to portrait on the camera screen (post-v2 part 1), so the layout buffer is always portrait-shaped and the edge the user calls "bottom" is a *different buffer edge* in each landscape orientation:

| Device orientation | User's bottom edge | Buffer edge to use |
|---|---|---|
| `.portrait` | buffer bottom | n/a — existing portrait layout |
| `.landscapeLeft` | — | **leading** |
| `.landscapeRight` | — | **trailing** |
| `.faceUp` / `.faceDown` / `.unknown` | — | hold last known value |

This cannot be a fixed `.leading` alignment. It needs the same treatment `rotationAngle(for:current:)` and `chromeLayout(for:current:)` already get: a pure static mapping with a hold-last-value branch, unit-tested.

**Fold it into the existing enum** rather than adding a fourth parallel property. `ChromeLayout` becomes three cases:

```swift
enum ChromeLayout {
    case sideBySide          // portrait — bottom VStack, HStack chip rows
    case stackedLeading      // landscapeLeft  — edge strip on buffer leading
    case stackedTrailing     // landscapeRight — edge strip on buffer trailing

    var isStacked: Bool { self != .sideBySide }
    var edgeAlignment: Alignment? { ... }   // nil for .sideBySide
}
```

Every existing `chromeLayout == .stacked` call site becomes `chromeLayout.isStacked`, so F1's fix and F2 land on the same property.

### Files changed

| File | Change |
|---|---|
| `Features/Camera/CameraViewModel.swift` | `ChromeLayout` gains `.stackedLeading` / `.stackedTrailing` in place of `.stacked`, plus `isStacked` and `edgeAlignment`. `chromeLayout(for:current:)` maps `.landscapeLeft` → `.stackedLeading`, `.landscapeRight` → `.stackedTrailing`, portrait cases → `.sideBySide`, face-up/down/unknown → hold last. |
| `Features/Camera/CameraView.swift` | The mode toggle, `LensChipRow`, and `WhiteBalanceControl` move out of the bottom `VStack` when `chromeLayout.isStacked`, into an `.overlay(alignment:)` on the full-screen `ZStack` driven by `chromeLayout.edgeAlignment`. The shutter `ZStack` and its trailing flip-button overlay are **not** moved. |
| `Shared/Constants.swift` | Add `CameraUI.chromeEdgeInset`, `CameraUI.chromeEdgeStripSpacing`, `CameraUI.chromeEdgeShutterClearance` |
| `frmrTests/frmrTests.swift` | Extend `CameraControlMappingTests` for the three-case mapping |

### Layout notes

- Use `.overlay(alignment:)` on the screen's outermost `ZStack`, the same pattern post-v2 part 4 used to anchor the flip button. Do **not** try to express this with `Spacer`s inside the existing `VStack` — a wide-and-short container is the exact shape that caused parts 2, 4, and 5.
- Counter-rotation is unchanged: `.rotatingWithDevice(viewModel.uiRotationAngle)` still applies to each control **individually**, never to the strip container. Moving a control to a different edge does not change how it rotates.
- The edge strip and the shutter cluster meet in a buffer corner. Inset the strip from the buffer bottom by `CameraUI.chromeEdgeShutterClearance` so the WB chips can never collide with the shutter ring or the tab bar.
- The tab bar is unchanged and still visible in landscape. See v3-4.

### Tests

`ChromeEdgeMappingTests` (or extend `CameraControlMappingTests`): each of the four cardinal orientations maps to the expected `ChromeLayout` case; face-up, face-down and unknown hold the previous value; `isStacked` is false only for the portrait cases.

**On device:** the `.landscapeLeft` → leading / `.landscapeRight` → trailing assignment follows the same sign convention as the existing rotation mapping, which is still flagged unverified. If the strip appears along the *top* edge on a real device, it is a one-line swap of the two cases — same fix shape as v2's rotation-direction note.

---

## F3 — Collapsible white balance

### What it is

The white balance control shows only the **active** mode as a single chip (`Auto ⌄`). Tapping it expands the full list inline; tapping any mode selects it and collapses again. Tapping elsewhere on the viewfinder also collapses it. This behaviour is the same in both orientations.

### Why

Six always-visible modes are the largest single consumer of chrome depth in the app. Collapsing to one chip is roughly a six-to-one reduction and removes the need for `chipStackMaxHeight` and its scroll view entirely — post-v2 part 2 added a capped vertical `ScrollView` specifically because six stacked chips would push the shutter button off screen. With F3 there is nothing to cap.

It is also the better portrait design. The expanded list competes with the shutter for attention on a screen whose whole point is composing a photograph, and white balance is a set-once-and-forget control for most sessions.

### Files changed

| File | Change |
|---|---|
| `Features/Camera/WhiteBalanceControl.swift` | Takes `isExpanded: Bool` and an `onToggle` closure. Renders one chip when collapsed, the full `HStack`/`VStack` when expanded. The scroll view and `chipStackMaxHeight` cap are removed. |
| `Features/Camera/CameraViewModel.swift` | Add `var isWhiteBalanceExpanded: Bool`, `func toggleWhiteBalanceExpansion()`, and collapse-on-select inside the existing white balance setter. Add the pure `static func visibleModes(expanded:selected:) -> [WhiteBalanceMode]`. |
| `Features/Camera/CameraView.swift` | Pass the flag; collapse on viewfinder tap (fold into the existing F1 tap-to-focus handler — one extra line, focus still fires) |
| `Shared/Constants.swift` | Add `CameraUI.wbExpandAnimationDuration`; **remove** `CameraUI.chipStackMaxHeight` |
| `frmrTests/frmrTests.swift` | `WhiteBalanceVisibilityTests` |

### Notes

- The chevron affordance is required. A lone `Auto` chip with no disclosure indicator reads as a status label, not a control.
- Selecting a mode collapses; selecting the *already active* mode also collapses. Never leave the list open after a selection.
- Expansion state is view state, not user data. It resets on every camera appear — no persistence, no `// OPEN:`.
- Keep the `visibleModes` decision in the ViewModel as a pure static function. It is the only genuinely testable part of this feature, and `CLAUDE.md`'s "views are dumb" rule means the branch cannot live in the view body anyway.

### Tests

`WhiteBalanceVisibilityTests`: collapsed returns exactly the selected mode; expanded returns all modes in declaration order; the selected mode is present in both cases.

---

## F4 — Compact chip metrics in landscape

### What it is

A second, smaller set of chip padding and font size values, used only when `chromeLayout.isStacked`. Portrait chip metrics are unchanged.

### Why

Post-v2 part 6 already established that stacked chips want tighter values than side-by-side ones — it added `stackedChipSpacing` for the gaps *between* chips. This extends the same reasoning to the padding and type *inside* each chip. It is the cheapest remaining depth saving and carries no behavioural risk.

### Files changed

| File | Change |
|---|---|
| `Shared/Components/CameraChip.swift` | Takes `isCompact: Bool`; selects between the standard and compact padding/font constants |
| `Features/Camera/CameraView.swift`, `WhiteBalanceControl.swift` | Pass `viewModel.chromeLayout.isStacked` through to each `CameraChip` |
| `Shared/Constants.swift` | Add `CameraUI.compactChipPaddingH`, `compactChipPaddingV`, `compactChipFontSize` |

### Notes

- Do not go below 11pt on the chip label. These are tap targets read at arm's length in whatever light the user happens to be shooting in.
- The chip's tap target must stay at least 44×44pt regardless of the visual padding. Shrink the drawn pill, not the hit region — use `.contentShape(Rectangle())` on a frame that keeps the minimum.

**Amended after the device photo (2026-08-24).** A 44pt minimum on *both* axes does not survive contact with a stacked column: the drawn pill is ~21pt, so a 44pt slot leaves ~11pt of dead layout space above and below every chip, and with `stackedChipSpacing` on top the lens chips sat ~27pt apart — reading as a sprawling list rather than one cluster, and reaching further into the frame than F2 and F4 exist to allow. The minimum is now split by axis: `minimumChipHitTarget` (44) across the stacking axis, `compactChipHitTarget` (32) along it, and `stackedChipSpacing` dropped 4 → 2, closing the gap to ~13pt. This is a deliberate, recorded deviation from the 44pt guideline on one axis only. Neighbouring targets abut, so no dead zone opens up between chips, and the value is a constant if 32 proves too small in the hand.

### Tests

Pure sizing constants, no branching logic beyond a ternary. No unit tests. Verify by screenshot in both orientations.

---

# Theme B — First-run walkthrough

## F5 — Coach marks for the three tab icons

### What it is

On first launch, after camera permission has been resolved, a dimmed overlay appears with a bubble and an arrow pointing at each of the three tab bar icons in turn — Library, Camera, Settings. Tapping anywhere advances. A `Skip` control is present on every step; the last step's primary control reads `Got it`.

**Portrait only.** The walkthrough never appears in landscape.

### Why

The tab bar is the app's only navigation and it is never explained. More importantly, the walkthrough is where a first-time user learns that Library exists at all — which is the argument against hiding the tab bar in landscape (v3-4).

Restricting it to portrait is not a limitation, it is the design. Every rotation bug in the post-v2 series came from chrome that had to survive counter-rotation inside a portrait-locked buffer. A portrait-only overlay never enters that system: no `.rotatingWithDevice`, no `ChromeLayout` branch, no wide-and-short container swinging its contents. The overlay is also the wrong shape for landscape regardless — a bubble sized to sit above a tab icon in a 390pt-wide buffer has nowhere to go once that buffer is read sideways.

### Sequencing — this is the part that breaks if rushed

First launch, in order:

1. App launches to the Camera tab.
2. System camera permission dialog appears (existing behaviour). The walkthrough **must not** be on screen at this point — a coach mark behind a system alert is unreachable and the scrim makes the alert look broken.
3. Permission resolved, either way. If denied, `PermissionDeniedOverlay` is showing; the walkthrough still runs, because Library and Settings are exactly what a user with denied permission needs to find.
4. Device is in portrait. If not, hold — see below.
5. Walkthrough runs: Library → Camera → Settings.
6. Completion is persisted. The first shutter tap, the Diary prompt, and the F8b typewriter all happen after this and are untouched.

**The gate is: permission resolved AND `chromeLayout == .sideBySide` AND not yet completed.**

Rotation mid-walkthrough: hide the overlay, keep the step index, resume at the same step when the device returns to portrait. Do not advance, do not complete, do not restart. A user who rotates away and back should not lose their place or have to sit through it twice.

If the device is in landscape at first launch, nothing shows and nothing is marked complete. The walkthrough appears the first time they hold the phone upright.

### Files changed

| File | Change |
|---|---|
| `Features/Onboarding/OnboardingViewModel.swift` | **New file.** `@Observable`. Holds `step: CoachStep?`, `hasCompleted: Bool`. Pure methods: `advance()`, `skip()`, `reset()`, and `static func shouldPresent(hasCompleted:permissionResolved:layout:) -> Bool`. No view types, no SwiftUI imports beyond what `@Observable` needs. |
| `Features/Onboarding/CoachStep.swift` | **New file.** `enum CoachStep: Int, CaseIterable { case library, camera, settings }` with an `next` computed property. |
| `Features/Onboarding/CoachCopy.swift` | **New file.** A static `[CoachStep: (title: String, body: String)]` or a parallel static array. **Zero logic** — the same discipline as `PromptBank`. |
| `Shared/Components/CoachMarkOverlay.swift` | **New file.** The scrim, the bubble, the arrow, and the tap-to-advance region. Reads tab item frames from the preference key below. |
| `Shared/Components/CoachBubble.swift` | **New file.** Rounded card, title + body + skip/got-it control. Pure SwiftUI. |
| `Shared/Components/CoachArrow.swift` | **New file.** A `Shape` drawing a short curved arrow from the bubble to a target point. Pure `Path` — no images, no SF Symbol. |
| `Shared/Components/TabItemAnchorKey.swift` | **New file.** A `PreferenceKey` collecting `[CoachStep: Anchor<CGRect>]` from the tab bar items. |
| `App/ContentView.swift` | Reports each tab item's anchor via the preference key, and attaches `.overlayPreferenceValue(TabItemAnchorKey.self) { ... CoachMarkOverlay ... }`. See the deviation note below. |
| `Shared/Constants.swift` | Add the `Onboarding` namespace (see §Constants) |
| `frmrTests/frmrTests.swift` | `OnboardingSequencingTests` |

### Deviation from `CLAUDE.md` project layout

Two, both deliberate:

**A new `Features/Onboarding/` directory.** The layout in `CLAUDE.md` does not have one. The alternative is scattering onboarding state into `ContentView` or an existing ViewModel, which is worse. Flagged here rather than done silently.

**`ContentView.swift` gains more than the `TabView`.** `CLAUDE.md` says "TabView root, nothing else". The coach marks must render above the tab bar and anchor to its item frames, so the root is the only place they can attach. The addition is bounded: an anchor preference on each tab item and one `.overlayPreferenceValue` modifier. All state and all decisions stay in `OnboardingViewModel`; `ContentView` gains no conditionals and no data transformation, so the spirit of the rule — views are dumb — holds. If this is unacceptable, the alternative is a `RootView` that wraps `ContentView`, at the cost of one more indirection.

### Anchoring

Use `.anchorPreference(key:value:transform:)` on each tab item and read the resolved `CGRect` in `.overlayPreferenceValue`. Do **not** hardcode tab item positions into `Constants.swift`. Tab item frames shift with Dynamic Type, with the device's safe area, and across device widths; a hardcoded arrow lands on the wrong icon on at least one supported configuration, and it will not be the one being tested on.

The bubble is placed above the anchor rect, horizontally clamped to stay within the screen with `Onboarding.bubbleEdgeInset` of margin — the Library and Settings icons are near the screen edges and a centred bubble would overflow. The arrow runs from the bubble's bottom edge to the top of the anchor rect, with `Onboarding.bubbleTabGap` between them.

### Notes

- The scrim must not swallow the tap that advances — put the tap gesture on the scrim itself. Do not make the highlighted tab icon tappable through the scrim; a user who taps the icon during its own coach mark and lands on a different tab has broken the sequence.
- The overlay is presentation, not action. It reads no data, writes nothing but its own completion flag, saves nothing, and touches no camera state. Framing it against `CLAUDE.md`'s "no automatic actions" rule: that rule protects the user from the app *doing* things on their behalf — saving to the camera roll, generating a strip, sharing. Showing an explanation is none of those. It is stated as an exception here so it is a decision on the record rather than an oversight, and F6 makes every subsequent showing user-initiated.
- Copy stays short. One line of body text per step. If a step needs a paragraph, the underlying UI is the thing to fix.
- No animation beyond a cross-fade between steps at `Onboarding.stepTransitionDuration`. A bouncing arrow is the wrong register for this app.

### Tests

`OnboardingSequencingTests` — all pure, no view host required:

- `advance()` three times from `.library` reaches completion; `hasCompleted` becomes true exactly once
- `skip()` from each of the three steps completes immediately
- `reset()` returns to `.library` and clears `hasCompleted`
- `shouldPresent` is false when already completed, false when permission is unresolved, false when the layout is not `.sideBySide`, true when all three hold
- `CoachCopy` has an entry for every `CoachStep.allCases` — this is the test that catches a step being added without copy

---

## F6 — Persistence and replay from Settings

### What it is

Completion is stored so the walkthrough does not reappear on every launch, and Settings gains a **Show intro again** row that resets it and returns the user to the Camera tab with the walkthrough running.

### Why

Without persistence the feature is a recurring interruption. Without replay it is unrecoverable — a user who skips on day one can never get the explanation back, and the one automatic thing in the app becomes a one-shot they might have dismissed by accident.

### Files changed

| File | Change |
|---|---|
| `Models/OnboardingState.swift` | **New file.** A single-row SwiftData model with `hasCompletedWalkthrough: Bool`. See the note below. |
| `Features/Settings/SettingsView.swift` | Add a **Show intro again** row that calls `OnboardingViewModel.reset()` and switches to the Camera tab |
| `App/ContentView.swift` | Tab selection becomes bindable so the replay can switch tabs |
| `Features/Onboarding/OnboardingViewModel.swift` | Load on init, persist on completion |

### Notes

- `// OPEN: onboarding completion — SwiftData single-row model vs @AppStorage`. `CLAUDE.md` names SwiftData as the persistence layer with no exception for UI flags, so the conservative default that does not break a stated rule is a one-row SwiftData model. `@AppStorage` is one line instead of a model plus a fetch, and this is a UI preference rather than user data — a reasonable argument for an exception, but it is an exception and should be decided rather than assumed. The value is behind `OnboardingViewModel` either way, so switching later touches one file.
- Replay is a full reset, not a resume — it always starts at `.library`.
- If the user is in landscape when they tap **Show intro again**, the same portrait gate applies: the flag is reset, the Camera tab is selected, and the walkthrough appears when they rotate upright. Consider whether the Settings row should say so; leaving it silent means a tap that appears to do nothing. `// OPEN: whether to surface the portrait requirement in the Settings row copy` — default: no extra copy, revisit if it confuses a tester.

---

## Constants additions (summary)

```swift
// CameraUI — F2
CameraUI.chromeEdgeInset             = 12.0   // strip inset from the buffer edge
CameraUI.chromeEdgeStripSpacing      = 8.0    // gap between the three groups in the strip
CameraUI.chromeEdgeShutterClearance  = 24.0   // strip inset from buffer bottom, clears shutter + tab bar

// CameraUI — F3
CameraUI.wbExpandAnimationDuration   = 0.2
// REMOVED: CameraUI.chipStackMaxHeight — no longer needed, WB collapses to one chip

// CameraUI — F4
CameraUI.compactChipPaddingH         = 8.0
CameraUI.compactChipPaddingV         = 4.0
CameraUI.compactChipFontSize         = 11.0   // floor — do not go lower
CameraUI.minimumChipHitTarget        = 44.0

// Onboarding — F5/F6
Onboarding.scrimOpacity              = 0.55
Onboarding.bubbleMaxWidth            = 260.0
Onboarding.bubbleCornerRadius        = 12.0
Onboarding.bubbleEdgeInset           = 16.0   // keeps edge-anchored bubbles on screen
Onboarding.bubbleTabGap              = 12.0
Onboarding.arrowLength               = 44.0
Onboarding.arrowStroke               = 1.5
Onboarding.stepTransitionDuration    = 0.25
```

---

## New files summary

| File | Feature | Type |
|---|---|---|
| `Features/Onboarding/OnboardingViewModel.swift` | F5 | `@Observable` |
| `Features/Onboarding/CoachStep.swift` | F5 | Enum |
| `Features/Onboarding/CoachCopy.swift` | F5 | Static copy, zero logic |
| `Shared/Components/CoachMarkOverlay.swift` | F5 | SwiftUI view |
| `Shared/Components/CoachBubble.swift` | F5 | SwiftUI view |
| `Shared/Components/CoachArrow.swift` | F5 | SwiftUI `Shape` |
| `Shared/Components/TabItemAnchorKey.swift` | F5 | `PreferenceKey` |
| `Models/OnboardingState.swift` | F6 | SwiftData model |

No new screens. No new tabs.

---

## Open decisions introduced by v3

| # | Decision | Default |
|---|---|---|
| v3-1 | Onboarding completion: SwiftData single-row model or `@AppStorage`? | SwiftData — does not break `CLAUDE.md`'s stated persistence rule |
| v3-2 | Does the walkthrough get a fourth step for the Diary / Film strip mode toggle? | No — scoped to the three tab icons as requested. Worth revisiting: the mode toggle is the genuinely novel control and it decides what the shutter does, so it is arguably more confusing to a newcomer than a conventional tab bar. |
| v3-3 | Should the Settings replay row mention the portrait requirement? | No extra copy |
| v3-4 | Hide the tab bar on the camera screen in landscape? | **No.** It is a real depth saving and a real camera app would do it, but it hides the exact three controls F5 exists to teach, and it would hide them specifically from a user who has rotated the phone before ever seeing the walkthrough. Revisit only after F2–F4 land and the remaining depth is measured. |
| v3-5 | `.landscapeLeft` → leading edge sign convention | Follows the existing rotation mapping's convention; unverified on device, one-line swap if backwards |

All v1 open items from project.md §14 and all v2 open items (v2-1 through v2-5) remain open and untouched. The A15 animated-grain benchmark (v2-3) is still outstanding.

---

## Sequencing recommendation

Themes A and B share no files except `Constants.swift` and can run in parallel as two agents. Within each:

**Theme A — must be sequential.**

1. **F1** — root-cause and fix the `isStacked` delivery bug. Nothing else in Theme A is verifiable until the two chip groups actually stack on a device. Do not skip the root-cause step.
2. **F3** — collapsible white balance. Biggest depth saving, works in both orientations, and it deletes `chipStackMaxHeight` before F2 has to find a home for a scroll view.
3. **F2** — bottom-edge redistribution. Do after F3 so the strip is being positioned around its final content.
4. **F4** — compact metrics. Last, because it is tuning, and tuning against a layout that is still moving is wasted work.

**Theme B — mostly parallel.**

5. **F5** — the walkthrough. `CoachStep`, `CoachCopy`, and `OnboardingViewModel` are pure and can be written and tested with no UI at all. Build and test those first, then the overlay.
6. **F6** — persistence and replay. Small, and depends on F5's ViewModel existing.

---

## Definition of done (v3)

- [ ] All v1 and v2 definition-of-done criteria still pass (no regressions)
- [ ] F1's root cause is identified and **written into this document**, and `isStacked` has no default value on any of the three controls
- [ ] All three chip groups verified stacked on a physical device in both landscape orientations
- [ ] The chrome strip appears along the user's bottom edge in both landscape orientations (device photograph, both ways)
- [ ] White balance collapses to a single chip and expands on tap, in both orientations
- [ ] The walkthrough appears exactly once on a fresh install, in portrait, after permission resolves
- [ ] The walkthrough does not appear in landscape, and resumes at the correct step on rotation back to portrait
- [ ] **Show intro again** in Settings replays it from step one
- [ ] Every `// OPEN:` in v3 files is marked in code with its value in `Constants.swift`
- [ ] No force-unwraps in new production paths
- [ ] All new errors surface via the existing `AppError` / `AppErrorAlert` system
- [ ] New pure logic has tests: `ChromeEdgeMappingTests`, `WhiteBalanceVisibilityTests`, `OnboardingSequencingTests`
- [ ] `Constants.swift` contains all new values; `chipStackMaxHeight` is removed
- [ ] Code compiles without warnings

---

## Handoff

Per `CLAUDE.md` §Working with other agents. Two independent context boundaries — hand these to separate agents, each with `CLAUDE.md`, `project.md`, `frmr-v2-spec.md`, and this file.

**Agent A — landscape chrome**

```
You are working on Theme A (landscape chrome) in a minimalist iOS journaling app.

Context files (required reading, in order):
1. CLAUDE.md        — engineering rules and constraints
2. project.md       — full product specification
3. frmr-v2-spec.md  — v2 features and the post-v2 rotation bugfix series (parts 1-7)
4. frmr-v3-spec.md  — this document; Theme A is F1-F4

Situation:
  DONE:    v2 F1-F8; post-v2 rotation bugfixes parts 1-6 (part 7 reverted, see v2 spec)
  DOING:   nothing
  BLOCKED: none
  NEXT:    F1 first — root-cause why isStacked reaches ModeToggle but not
           LensChipRow / WhiteBalanceControl. Do not change layout code before
           confirming the cause; part 7 failed by skipping that step. Then F3, F2, F4
           in that order.

Deliverable: a diff per feature, plus the root cause of F1 written into
frmr-v3-spec.md §F1. Device photographs in both landscape orientations for F1 and F2.

Do not add dependencies. Do not make network calls. Do not resolve OPEN: items by
guessing — flag them and use the placeholder pattern.
```

**Agent B — walkthrough**

```
You are working on Theme B (first-run walkthrough) in a minimalist iOS journaling app.

Context files (required reading, in order):
1. CLAUDE.md        — engineering rules and constraints
2. project.md       — full product specification
3. frmr-v3-spec.md  — this document; Theme B is F5-F6

Situation:
  DONE:    v1 and v2 complete; the tab bar (Library / Camera / Settings) is stable
  DOING:   nothing
  BLOCKED: v3-1 (SwiftData vs @AppStorage for the completion flag) — use the
           documented default and mark it OPEN, do not block
  NEXT:    F5. Build and unit-test CoachStep, CoachCopy and OnboardingViewModel
           with no UI first, then the overlay. Then F6.

Deliverable: the eight new files listed in §New files summary, a diff for
ContentView / SettingsView / Constants, and passing OnboardingSequencingTests.

The walkthrough is portrait-only. It must not use .rotatingWithDevice or read
ChromeLayout for anything other than the portrait gate.

Do not add dependencies. Do not make network calls. Do not resolve OPEN: items by
guessing — flag them and use the placeholder pattern.
```

---

## Implementation status — v3 build (2026-08-24)

All of F1–F6 implemented. Clean build, zero warnings, app and test targets both
compile. **Unit tests were written but not run in this session at the user's
request** — `OnboardingSequencingTests`, `WhiteBalanceVisibilityTests`, the
extended `CameraControlMappingTests`, and the new orientation tests are ready to
run.

| Feature | Status |
|---|---|
| F1 `isStacked` delivery | Both hypotheses disproven by reading; root cause **not established** (needs device). Failure mode removed structurally — see §F1 Finding. `isStacked` has no default on any control (it never did). |
| F2 Bottom-edge chrome | `ChromeLayout` is now three cases with `isStacked` / `edgeAlignment`. The three groups move into `chromeEdgeStrip`, an `.overlay(alignment:)` on the outer `ZStack`. Shutter and flip button untouched. **Edge assignment unverified on device (v3-5).** |
| F3 Collapsible WB | Collapses to one chip with a chevron; expands inline; collapses on select and on viewfinder tap. `chipStackMaxHeight` and its `ScrollView` removed. |
| F4 Compact chip metrics | `CameraChip` takes `isCompact`; drawn pill shrinks, hit region held at 44pt via `.contentShape` on a min-sized frame. |
| F5 Coach marks | Portrait-only, gated on permission-resolved + `.sideBySide` + not completed. Hides on rotation without losing the step. |
| F6 Persistence + replay | One-row SwiftData `OnboardingState`; **Show intro again** in Settings resets and returns to Camera. |

### Deviation from the spec: tab item anchoring

The spec calls for `.anchorPreference` on each `.tabItem`. **That does not work** —
`TabView`'s bar is UIKit-managed, so preferences set on `.tabItem` labels never
reach the SwiftUI preference system, and the overlay renders with no anchors at
all (verified in the simulator: the first build showed no coach mark).

Anchors now come from three equal-width invisible proxies laid over the tab bar's
icon band, inset from the screen edges by `Onboarding.tabBarEdgeFraction` because
the iOS 26 tab bar floats rather than spanning edge to edge. This still derives
from live geometry (screen width, safe area) rather than hardcoded positions, so
it tracks device width — but the inset fraction is **fitted against the iPhone 17
Pro simulator** and is marked `// OPEN:`. Verify the arrows land on their icons
across device widths and Dynamic Type sizes.

### Verified in the simulator

- Walkthrough appears on a fresh install, in portrait, after permission resolves
- Step one's bubble and arrow land on the Library icon
- White balance renders as a single `Auto ⌄` chip in portrait

### Still needs a physical device

- All three chip groups stacked, both landscape orientations (F1's checklist item)
- The chrome strip on the user's bottom edge, both ways (F2; v3-5 sign convention)
- Capture orientation for landscape and diagonal holds (see below)

---

## Post-v3 fix — captures were saved sideways when the phone was not upright

**Problem:** the camera screen locks the interface to portrait so the preview
never rotates (post-v2 part 1). Nothing ever set the photo connection's rotation
angle, so `AVCapturePhotoOutput` tagged **every** capture as portrait. Holding the
phone in landscape — or at a diagonal — produced a photo with the world lying on
its side inside an upright frame. The preview looked right the whole time, because
a preview fixed to the device cancels the device's own rotation; only the saved
file was wrong.

A second, independent defect sat behind it: `ImageProcessor.render(_:)` ended in
`UIImage(cgImage:)`, whose single-argument form hardcodes `.up`. The RAW-developed
image **replaces** the JPEG preview in `captureForDiary` / `captureForPhotobooth`,
so even once the EXIF tag was correct, the diary entry would swap a correctly
oriented preview for a flattened, sideways final image.

**Fix:**

| File | Change |
|---|---|
| `Features/Camera/CaptureSession.swift` | Added an `AVCaptureDevice.RotationCoordinator`, rebuilt whenever the active camera changes (it holds its device weakly). `applyCaptureRotation()` sets the photo connection's `videoRotationAngle` from `videoRotationAngleForHorizonLevelCapture` immediately before each capture, guarded by `isVideoRotationAngleSupported` — an unsupported value raises `NSInvalidArgumentException`, which Swift cannot catch. |
| `Features/Camera/ImageProcessor.swift` | `process(rawData:)` reads the capture's EXIF orientation, develops with `rawFilter.orientation = .up` (sensor space), and tags the result. `render(_:orientation:)` takes the orientation, defaulting to `.up` for the strip-look path, whose `CIImage(image:)` has already resolved orientation into pixels. **Correction (v4 F0):** that claim was wrong — `CIImage(image:)` ignores the tag, which rotated strip photos whenever a filter was on. See frmr-v4-spec.md §F0. |

**Why the coordinator rather than `UIDevice.orientation`:** it resolves against
gravity, so a phone held at an angle snaps to the nearest upright quarter-turn
instead of whatever cardinal orientation the device last reported, and it keeps
working when the device reports `.faceUp` — the case `rotationAngle(for:current:)`
can only paper over by holding its last value.

**Why develop in sensor space and tag, rather than let `CIRAWFilter` rotate:** it
makes the two capture paths symmetric — both end as unrotated pixels plus an
orientation tag — and it cannot double-rotate, since no transform of our own is
ever applied on top of the filter's. The preview connection is deliberately left
alone; the whole point of the portrait lock is that composition does not shift.

Downstream paths were checked and need no change: `StripGenerator.drawAspectFilled`
uses `image.draw(in:)` and sizes from `image.size` (both orientation-aware, and its
`max`-scale aspect-fill centre-crops a landscape photo into the square cell
correctly), `DiaryViewModel` re-encodes via `image.jpegData(...)`, and saving uses
`PHAssetChangeRequest.creationRequestForAsset(from:)` — all respect the tag.

### Tests

`ImageProcessorTests.exifOrientationMapsOntoTheMatchingUIImageOrientation` and
`.theFourQuarterTurnsAreDistinct` — the two enums share case names but not raw
values, so bridging through `rawValue` would silently turn `.right` into
`.downMirrored`. **Not exercisable without a device beyond the mapping:** the RAW
and connection behaviour needs a real capture. Verify by taking a photo in each
landscape orientation and at a diagonal, then checking the entry and the exported
strip both read upright.

---

## Post-v3 rework — rotate-in-place camera chrome (2026-10-06)

This section records the rework done after the v3 build, so v4 can start from what was actually decided and shipped. It supersedes v3 F1, F2 and F4 (see the note above Theme A). Where this section and the F-sections disagree, this section wins.

### Why

The v3 landscape design (an edge strip on the user's bottom edge, `ChromeLayout` with three cases, stacked chip groups, compact chip metrics) never looked polished on device, and F1's root cause was never found. The user asked for the iPhone Camera behaviour instead: **every control keeps its portrait position and rotates in place about its own centre.** That removes the whole class of bug (three controls disagreeing about a layout flag) by removing the layout switch.

### Final design

- The camera screen has one portrait layout. Controls never move, stack or reflow.
- Each control rotates individually, easeInOut 0.3s, along the shortest arc. Wide backing shapes stay static; only the glyph rotates inside a fixed 44pt frame.
- The viewfinder, tab bar and onboarding overlay never rotate.
- **Icon-only controls (user-approved):** the Diary / Film strip toggle (book / film glyphs), white-balance chips (`WBMode.symbolName`) and the Photobooth Generate button (amber checkmark disc). All have accessibility labels.
- **One documented exception:** the Photobooth caption ("live viewfinder — N of 4 captured", copy unchanged by decision) stays upright and unrotated, single line, bounded width, minimum scale. A wide string cannot rotate in place without overlapping neighbours.
- **Portrait lock (decision A, user-approved):** the interface stays portrait on the Camera tab. A landscape layout with controls docked on the far right was considered and rejected in favour of the lock.

### What changed, by owner

**Frontend**
- Removed the edge strip, every `isStacked` branch, container-level rotation (including `PhotoboothView`) and the dead constants (`chromeEdge*`, `compactChip*`, `stackedChipSpacing`, `chipChevronScale`, `minimumChipHitTarget`).
- `EnvironmentValues.deviceRotation`, set once on `CameraView`'s root; `.rotatingWithDevice()` takes no argument.
- `CameraChip` is a fixed 44pt circle (text and symbol initialisers); `WhiteBalanceControl` is one `HStack` of circle chips with no `isStacked`; `ModeToggle` is a static capsule with two 44pt icon segments; `FlipCameraButton` keeps its disc static and rotates only the glyph.
- Added `Constants.CameraUI`: `chipDiameter` (44), `chipIconSize` (16), `permissionTextMaxWidth` (280), `permissionTextMinScale` (0.8), `captionMaxWidth` (300), `captionMinScale` (0.7), `dockSpacing` (10), `dockTrailingPadding` (12).
- `ContentView` now drives the portrait lock from the selected tab (lock on Camera, unlock otherwise) on appear, on tab change and when the scene becomes active; `CameraView`'s own lock calls were removed so there is a single source of truth.
- `CameraView` has a temporary `dockedChrome` branch (compact vertical size class, controls docked trailing, `deviceRotation` forced to zero to avoid double rotation). It only appears if the lock fails. **Remove it once the lock is verified on device.**

**Backend**
- `CameraViewModel.rotationAngle(for:current:)` now returns an unwrapped, accumulated angle with every step in (−180, 180], so landscape-left to landscape-right no longer spins the long way. Exact 180° turns take the positive arc deterministically. Face-up / face-down / unknown hold the last value.
- Removed `ChromeLayout`, `chromeLayout(for:current:)` and the `// OPEN: v3-5` edge-mapping item. Onboarding now uses `isPortrait` and `static isPortrait(for:current:)`; `shouldPresent(...)` takes `isPortrait:`.
- `WBMode.symbolName` (auto `a.circle`, sunlight `sun.max`, cloudy `cloud`, shade `cloud.sun`, tungsten `lightbulb`, fluorescent `light.panel`).
- `InterfaceOrientationLock` hardened: idempotent `lockToPortrait()` / `unlock()`, `Mode { portraitLocked, unlocked }`, pure `mask(for:)`; each call updates the mask, calls `setNeedsUpdateOfSupportedInterfaceOrientations()` on every window's root controller (recursing through children and presented controllers), then `requestGeometryUpdate` on the foreground-active scene. Failures are logged (`Logger`, subsystem `frmr`, category `orientation`) with one retry after `Constants.Camera.orientationLockRetryDelay` (0.3s). The error is deliberately **not** surfaced via `AppError`: a failed lock is not user-actionable and the camera still works — a documented silent path.
- `OnboardingViewModel.lockMode(for: AppTab) -> InterfaceOrientationLock.Mode` (exhaustive switch, no `default`, so a new tab forces a decision).
- `CaptureSession.capturePhoto`: outer `sessionQueue.async` closure now `[weak self]` with `guard let self, self.camera != nil` (fixes the `#ImplicitStrongCapture` warning). **This is on the capture path and unverified on device.**
- Info.plist iPhone orientations unchanged: portrait + landscape left/right, no upside-down.

### Bugs found and fixed

| ID | Owner | Finding | Fix | Status |
|---|---|---|---|---|
| BUG-R1 (major) | frontend | `.position(point)` was applied before `.rotatingWithDevice()` on the focus indicator, so in landscape it pivoted about the full-frame overlay centre and swung away from the tap point. `ExposureIndicatorView` had a smaller version (padding applied before rotation). | Rotate first, then position / pad; every other `.rotatingWithDevice()` call site re-checked. | Fixed in code; needs device |
| BUG-R2 (minor) | frontend | Photobooth `PhotosPicker` label and undo button had no accessibility labels. | Added "Choose photos from library" and "Undo last photo". | Fixed in code; VoiceOver needs device |
| OBS-R3 | frontend | Wide views rotated as a whole (permission text, Photobooth caption) cannot reflow. | Permission text bounded (`permissionTextMaxWidth`, `permissionTextMinScale`); caption left unrotated by decision. | Fixed in code; fit in landscape needs device |
| Lock failure (sim) | backend + frontend | On an iPhone 18 Pro / iOS 27.0 simulator the whole interface rotated to landscape despite `lockToPortrait()`. Suspected causes, **unproven**: the old `requestGeometryUpdate` handler swallowed errors; the mask change was never re-read (no `setNeedsUpdateOfSupportedInterfaceOrientations()`); the lock ran only from a one-shot `.task` and used `connectedScenes.first`. | Hardened lock and tab-driven locking (above). | User reports landscape now works |
| Warning | backend | `CaptureSession.swift:150` weak-capture warning. | `[weak self]`. | Zero warnings; capture path device-only |

Tests removed on purpose (they only covered the deleted edge mapping): `chipGroupsStackOnlyInLandscape`, `chipGroupLayoutHoldsLastKnownStateOnFaceUpOrDown`, `edgeStripFollowsTheUsersBottomEdge`. Nothing else lost coverage as far as QA could tell, but the git baseline is the Xcode template, so there was no history to diff against.

Tests added: `RotationAcceptanceTests` (5 — every `UIDeviceOrientation` from 14 start angles, a 5000-step random sequence with no drift and no long-way spin, face-up between landscapes, exact quarter turns, `isPortrait` over all cases), plus backend tests for the accumulated angle (`chromeRotationTakesTheShortArcBetweenLandscapes`, `chromeRotationAccumulatesWithoutWrapping`, `chromeRotationEveryStepIsAtMost180`, `chromeRotationDoesNotDriftOnRepeatedOrientation`, `onboardingPortraitGateHoldsOnFlatOrientations`, `everyWhiteBalanceModeHasASymbolName`), `InterfaceOrientationLockTests` (3) and `OnboardingLockModeTests` (3). The last full QA count was 59 test cases passing (including 3 UI tests) before the lock and `lockMode` tests were added; the suite was not re-counted afterwards. `SwiftUI.Angle` stores radians, so long sequences produce values like 270.0000000000001 — acceptance tests compare with a 1e-6° tolerance; the production code is fine.

### Process notes

- This rework was the first run of the three-agent team (`.claude/agents/`, ownership map in `CLAUDE.md`). The ownership map worked: contract requests flowed frontend → lead → backend with no file collisions. Files the original map did not name (`WhiteBalanceControl.swift`, which holds both the `WBMode` enum and the view) needed a split rule: backend owns the enum, frontend the view struct.
- The shared guard script stayed clean (23 pre-existing `// OPEN:` warnings with no nearby `Constants.` value).
- `xcodebuild -destination 'platform=iOS Simulator,name=iPhone 17 Pro,OS=26.4'` is ambiguous (several 26.4 runtimes). Use the simulator `id=`. The full-scheme `test` run sometimes fails to launch the UI-test runner ("Busy") on a headless simulator; unit-only runs (`-only-testing:frmrTests`) are reliable. `simctl io screenshot` needs `--display=<framebuffer id>` when the default display is blank.

### Verified vs. unverified

- **User-verified in the simulator (iPhone 18 Pro, iOS 27.0):** landscape left and right behave as designed with the lock.
- **Not working / not understood — upside-down:** the user reports everything works **except upside-down**. The symptom was not characterised before this write-up. Hypothesis, unconfirmed: the plist omits `PortraitUpsideDown`, so the simulator may never deliver an upside-down interface orientation, and the chrome may not receive the 180° rotation. A real iPhone reports `UIDeviceOrientation.portraitUpsideDown` regardless, so the behaviour must be checked on a physical device. Use `chromeDebugOverlayEnabled` (it prints the accumulated angle, e.g. 810; the pose is the value mod 360) to see whether the angle or the application of it is wrong.
- **Device-only, still unverified:** landscape rotation sign per side; shortest-arc animation feel; expanded WB row in landscape; mode-toggle legibility without text; capture saved upright in every orientation (entry, exported strip, camera-roll copy); the `CaptureSession` `[weak self]` change on a healthy session; tap-to-focus staying under the finger in landscape (BUG-R1); VoiceOver reading the new labels; permission text and Photobooth caption fit in landscape; that sheets presented from the Camera tab (entry editor, strip) stay portrait; lock re-assertion after backgrounding; haptics.

### Carry-forward for v4

1. **Upside-down.** Characterise the symptom, test on a physical device, then decide: keep the lock and rotate the chrome 180° (needs the angle applied correctly), or add `UIInterfaceOrientationPortraitUpsideDown` to the plist and the unlocked mask. Adding it to the plist makes the *interface* rotate when held upside-down, which conflicts with the lock — decide deliberately.
2. **Remove the `dockedChrome` safety net** (and its comment) in `CameraView` once the lock is device-verified. Also delete the stale "CONTRACT REQUEST candidate" comment above `.onAppear` in `ContentView` (lines ~49–50).
3. **Root-cause the simulator lock failure properly** if it recurs: read the `orientation` console logs and record the actual `requestGeometryUpdate` error. The explanation above is inference only.
4. **Run the device checklist** above and record results here; mark BUG-R1 / BUG-R2 / OBS-R3 verified or reopen them.
5. **Photobooth caption:** decide whether the unrotated exception stays, or whether the copy gets shortened (e.g. "N/4") so it can rotate like everything else.
6. **Icon-only discoverability:** watch whether users find the mode toggle without text; revisit if not.
7. **Project docs:** `project.md` still describes the portrait-lock rationale and chrome counter-rotation in its old form, and `project.md` §14 / `CLAUDE.md` "Current build status" do not mention this rework — update them when v4 is specced. The orientation skill (`.claude/skills/ios-camera-orientation/SKILL.md`) was updated and is current.
8. **Open decisions still deferred from v1/v2** are unchanged (app name, Newsreader bundling, WB persistence, archive soft-hide, filter tuning, prompt repeat strategy, app icon) — see `project.md` §13/§14.
9. **Housekeeping:** the working tree is uncommitted; commit before starting v4.

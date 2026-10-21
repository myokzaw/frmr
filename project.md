# project.md — frmr: Photo Journal

Full product specification. Read alongside `CLAUDE.md` (engineering rules). Together these two files are the complete operating context for any agent working on this codebase.

---

## §1 What this app is

A minimalist iOS photography journal with a physically based film look. Core loop:

1. Take a photo (single diary shot or 4-shot film strip sequence) on a chosen film stock
2. *(v4 Part 2)* Review it and change the stock if wanted, then confirm
3. Receive a reflective prompt
4. Write a short entry
5. Entries compile into strips in a library, each frame in its own stock or one stock for the whole strip

The film look (v4) simulates film rather than filtering it:
- per-layer characteristic curves
- a negative → print chain
- halation
- exposure-dependent grain
- bloom and light leaks

It all runs on the device with Core Image. Six stocks: Daylight 200, Portrait 400, Cine 500T, Slide 100, Mono 400, Mono 3200. Prints: Lab, Cinema, Matte, Projection. See `frmr-v4-spec.md`.

No network dependency. No AI. No automation. Every action is explicit and user-initiated.

---

## §2 Screens

### Screen 1 — Camera: Diary mode

Default capture screen for a single daily photo + prompt.

**Layout**
- Full-bleed viewfinder background (warm brown radial gradient placeholder for live camera feed)
- Status bar area ~54px
- Segmented pill control top-center ("Diary" / "Film strip", pill radius 100px, active segment white bg)
- Horizontal scroll of white-balance chips near bottom ("Auto" active in teal `#005F73`, others translucent white 14% on dark)
- Shutter button: 76px circle, white 4px ring, 64px amber (`#EE9B00`) fill, centered, ~28px above home indicator

**Typography**
- Segmented control label: 13px/600 system UI
- Chips: 12px/500–600 system UI
- "live viewfinder" caption: 11px monospace, 45% white, letter-spacing 0.06em

---

### Screen 2 — Prompt screen

After capture, user answers a reflective prompt and writes a short entry.

**Layout**
- Top 38% is the just-captured photo (radial gradient placeholder)
- Below: prompt question, text-entry card, character count, primary CTA, two text links

**Typography**
- Prompt question: 25px/1.4 Newsreader italic 500
- Entry text: 16px/1.6 Newsreader regular
- Char count: 12px monospace/600, color `#CA6702`

**Components**
- Entry card: border-radius 12px, background = theme card color, 1px border
- Primary button "Save entry": full width, border-radius 10px, 16px padding, background = theme primary, white text 16px/600 system UI
- "Retake" / "Skip": 14px/500 system UI, muted color, centered, 28px gap

---

### Screen 3 — Camera: Film strip mode

Capture up to 4 shots that compile into one strip.

**Layout**
- Same segmented control (now "Film strip" active)
- Row of 4 slots below control: captured shots as 64×64 rounded (8px) gradient thumbnails; empty slots are 1.5px dashed white-30% squares
- Viewfinder fills remaining space (near-black radial gradient)
- Caption "live viewfinder — N of 4 captured" 11px monospace, 40% white
- Bottom row: secondary square button (44×44, 9px radius, 1.5px border) + shutter (same as mode 1) + spacer for symmetry

---

### Screen 4 — Strip preview & customization

Review the compiled strip and adjust its look before saving/sharing. *(Updated for v4.)*

**Layout**
- Centered booth strip, 150pt wide, on warm off-white (≈`#F4F0E7`) or near-black (≈`#171614`) photo paper with a faint texture.
- Thin even border (6pt) and thin gaps (4pt).
- Four 4:5 portrait frames with slightly rounded corners.
- A one-line italic caption under each frame.
- Date stamp at the bottom, monospace, letter-spacing 0.12em.

**Controls**
- "Background" swatch row: two swatches (White paper, Black paper), each with a rim and a 44pt target.
- Film stock picker: "As shot" (default; each frame keeps the stock it was taken on) plus Off and the six stocks.
- Print picker, shown only for an override stock with a print choice.
- Effects: Halation, Bloom and Light leak toggles.
- Black & white toggle, locked on for mono stocks.
- Three equal-width action buttons (Save / Share / Archive): 10px radius, theme card background, 13px/600 system UI.

### Screen 4b — Diary review (v4)

Shown after a diary capture, before the prompt screen.
- **Photo:** the photo in its chosen stock.
- **Stock row:** a scrolling row of the seven stock chips under the photo.
- **Buttons:**
  - **OK** at the bottom left (primary) leads to the prompt screen.
  - **Retake** at the bottom right discards the capture.
  - A **Download** icon at the photo's top right saves the full-resolution film photo to the camera roll and shows "Saved". It creates no entry, and the user stays on this screen.

---

### Screen 5 — Library

Browse past entries and strips.

**Layout**
- Large title "Library": 30px/600 Newsreader
- Tab row (Entries / Strips) with 2px bottom-border indicator on active tab (teal), 14px/600 vs 500 system UI
- Grouped list by date section ("Today", "Yesterday" — 12px/600 system UI uppercase, letter-spacing 0.08em, muted)
- Each row: 56×56 rounded-8px photo thumbnail + italic entry excerpt (15px/1.5 Newsreader italic), 14px gap

**Tab bar**
- Fixed bottom, 3 items (Library / Camera / Settings)
- Camera tab is emphasized: 34px teal circle raised -14px with white viewfinder icon
- Inactive icons/labels at 55% opacity, light-teal (`#94D2BD`) stroke/fill

---

### Screen 6 — Settings

Appearance, camera defaults, strip defaults, data management.

**Layout**
- Large title "Settings": 30px/600 Newsreader
- Grouped sections, each with an uppercase 12px/600 system UI label (letter-spacing 0.06–0.08em, muted) followed by a card (10px radius, theme card bg, 1px border)

**Sections**
- **Appearance:** 3-segment control (Light / Dark / System), 4px padding, 7px inner radius, active segment filled with theme primary + white text
- **Camera defaults:** single toggle row ("Remember white balance")
- **Strip defaults:** 3-row list (Background value "Cream", Film grain toggle, Black & white toggle), rows separated by 1px border, 14×16px padding
- **Data:** single destructive row "Clear diary" in rust (`#BB3E03`)

---

## §3 Interactions & behavior

- Segmented pill (Diary/Film strip) switches camera capture mode; persists as a default in Settings.
- Shutter tap → capture → navigate to Prompt screen (single mode) or fill next film-strip slot until 4/4, then navigate to Strip preview.
- Prompt screen "Skip" saves photo without text; "Retake" discards and returns to camera.
- Strip customization toggles (film grain, B&W, background color) apply a live preview to the strip card.
- Toggle switches: standard iOS-style pill, knob slides right when on (translate distance ≈ track width − knob width − 4px padding).
- Dark/Light mode: full theme swap driven by Settings → Appearance, defaulting to System.

---

## §4 State

| Key | Type | Notes |
|---|---|---|
| `captureMode` | `'diary' \| 'filmstrip'` | Persisted via Settings |
| `currentShots` | `[Photo]` (max 4) | Filmstrip mode only |
| `draftEntry` | `{ photo, promptText, charCount }` | In-flight entry |
| `appearanceMode` | `'light' \| 'dark' \| 'system'` | Persisted |
| `stripSettings` | `{ background, filmGrain: Bool, blackAndWhite: Bool }` | Persisted |
| `entries` | `[DiaryEntry]` grouped by date | SwiftData |

---

## §5 Design tokens

### Colors

| Name | Hex | Usage |
|---|---|---|
| Near black | `#001219` | Dark mode background; primary text (light mode) |
| Dark teal | `#005F73` | Primary actions & active states (light mode) |
| Mid teal | `#0A9396` | Primary actions & active states (dark mode) |
| Light teal | `#94D2BD` | Inactive icons/borders |
| Cream | `#E9D8A6` | Light mode background, strip paper |
| Amber | `#EE9B00` | Shutter button, primary CTA accent |
| Burnt orange | `#CA6702` | Hover/active on amber elements, char-count |
| Rust | `#BB3E03` | Destructive actions |
| Dark red | `#AE2012` | Deeper warning state |
| Deep crimson | `#9B2226` | Sparingly, deepest destructive state |

**Light theme:** bg `#E9D8A6`, text `#001219`, primary `#005F73`, card `#F5E9C6`, card border `rgba(0,18,25,.12)`, muted `rgba(0,18,25,.6)`

**Dark theme:** bg `#001219`, text `#E9D8A6`, primary `#0A9396`, card `#062830`, card border `rgba(148,210,189,.25)`, muted `rgba(233,216,166,.6)`

---

### §6 Typography

| Role | Font | Sizes / Weights |
|---|---|---|
| Headings & reflective copy | Newsreader (serif) | 9px · 15px · 25px · 30px; weights 400i / 500i / 600 |
| UI chrome | System UI (SF Pro) | 12–16px; weights 500–600 |
| Numeric/technical accents | Monospace (SF Mono) | 8px · 11–12px |

**Implementation note:** Newsreader is a Google Font. Bundle it as a custom font resource in the Xcode target (`Info.plist` → `UIAppFonts`). Do not load it from the network.

---

### §7 Spacing, radius, shadow

- Card radius: 10–12px
- Pills/segmented controls: 100px full radius, 7px inner segment radius
- Icon tile radius: 27% of icon size (app icon)
- Toggle track: 46×26px, radius 100px; knob 22px circle, 2px inset
- Card shadow (light): `0 4px 14px rgba(0,18,25,0.06–0.08)`
- Elevated shadow (strip, icon): `0 8–12px 24–32px rgba(0,0,0,0.25–0.28)`

---

## §8 Image processing pipeline

CoreImage pipeline — no third-party libraries. **Superseded in v4:** the strip look is now a film pipeline, specified in `frmr-v4-spec.md`. In order: upright (resolve orientation tag) → resize to slot → B&W luminance → halation → film colour cube (negative curve → print → output normalisation, built in `FilmModel.swift`) → bloom → light leak → grain. Effects are seeded per frame, so re-rendering a strip is pixel-identical.

The original v1 spec read: film grain plus `CIPhotoEffectMono` B&W, chained B&W → grain. That still describes Off + B&W, which uses `CIPhotoEffectMono`.

The same film chain also drives:
- `ImageProcessor.renderFullLook`: the review screen, entry display and full-resolution Download. Grain is scaled to the frame, so Download matches the review.
- `FilmPreviewRenderer`: the live viewfinder, which applies the colour cube only (no grain or effects).

All filter parameters live in `Constants.swift` (`Constants.ImageProcessing.Film` for v4).

---
## §9 Camera — AVFoundation requirements

- Session preset: `.photo`
- RAW capture via `AVCapturePhotoOutput` with `AVCapturePhotoSettings` enabling RAW format where device supports it; fall back to HEIF silently.
- White balance: manual `AVCaptureDevice.WhiteBalanceMode` with preset gains per chip label. Chip options: Auto, Daylight, Cloudy, Shade, Tungsten, Fluorescent.
- Session teardown must happen off the main thread.
- Camera permission: request at first launch; show a human-readable error alert (not silent failure) if denied.

---

## §10 Strip generation

`StripGenerator` produces a `UIImage` from strips of 4 cells (photo, caption, film stock) plus `StripCustomization`. *(Updated for v4 booth strip, F15.)*

Layout (at 2× resolution, logical units; all values in `Constants.Strip`, OPEN v4-16):
- Strip width: 150pt → 300px
- Border: 6pt, even on all sides
- 4 portrait photo slots at 4:5 (`cellAspectRatio` 0.8) with a 2.5pt corner radius
- Below each photo: a one-line italic caption band (2pt below the frame)
- Gap: 4pt between a caption band and the next frame, and before the date
- Date stamp at bottom: 8pt monospace, letter-spacing 0.12em
- Paper: `StripCustomization.background.color` (warm off-white or near-black) plus a faint texture seeded by the strip date and index
- No sprocket holes, frame numbers or edge date (removed in v4 F8)

Each photo is filmed with its effective stock (the strip override, or the frame's own stock when "As shot") through `ImageProcessor.applyStripLook` before compositing.

`StripGenerator` is pure logic (inputs in → image out) and must be fully unit-testable without a device.

---

## §11 Prompt bank

`PromptBank.swift` is a static `[String]` array. No networking, no database, no randomization logic beyond a simple `randomElement()` call at capture time. The array ships in the binary.

Minimum 50 prompts. Prompts are reflective, open-ended, and photo-agnostic (they should work regardless of what was photographed).

Example prompts (not final — expand to 50+):
- "What were you trying to hold onto in this moment?"
- "What does this place feel like at a different time of day?"
- "Who would you want to show this to, and why?"
- "What's just outside the frame?"
- "What were you thinking right before you took this?"

---

## §12 App icon

**Concept C — "Twin frames"** (selected).

- Teal (`#005F73`) squircle background (corner radius ≈ 22.5% of edge, matching iOS system mask)
- Two centered rounded-rect swatches stacked vertically (34×34pt at 120pt icon scale, 6pt radius): cream (`#E9D8A6`) on top, amber (`#EE9B00`) below, 6pt gap between them, roughly vertically centered as a group
- Export at 1024×1024 master (no transparency, no baked-in shadow — iOS applies its own mask)
- Standard iOS icon size set in `Assets.xcassets`

---

## §13 Open decisions (TBD)

These items are not yet decided. Use the `// OPEN:` pattern in code and put any magic values in `Constants.swift`.

| # | Decision | Default to use until resolved |
|---|---|---|
| 1 | Maximum entry character count | 280 |
| 2 | Whether film strip auto-advances to next slot or requires a deliberate tap | Auto-advance |
| 3 | Whether "Skip" on prompt screen shows a confirmation dialog | No confirmation |
| 4 | How many prompts to show before repeating | Full shuffle before repeat |
| 5 | Whether strip captions are editable after saving | Not editable |
| 6 | Archive behavior (what does "Archive" do on strip screen?) | Soft-hide from library, recoverable |
| 7 | Whether the app supports iPad | iPhone only for v1 |

---

## §14 Implementation status — v1 build (2026-07-31)

All six build phases are implemented, compiling without warnings, with unit tests passing. Source lives under `frmr/` in the layout defined by CLAUDE.md (`App/`, `Features/`, `Models/`, `Shared/`).

### Built and verified

| Area | Status | Key files |
|---|---|---|
| Foundation | ✅ Done | `Shared/Constants.swift` (all magic values incl. UI metrics), `Shared/AppError.swift` (`AppError` + `@Observable ErrorState`, alert at root), `Shared/Extensions/Color+Palette.swift` (hex init + palette + `ThemePalette` light/dark resolver) |
| App shell | ✅ Done | `App/AppEntry.swift` (SwiftData `ModelContainer`, `ErrorState` in environment), `App/ContentView.swift` (Library / Camera / Settings tabs, appearance override, root error alert) |
| Models | ✅ Done | `Models/DiaryEntry.swift`, `Models/DailyStrip.swift` (SwiftData), `Models/StripCustomization.swift` (value type + settings round-trip) |
| Camera | ✅ Done | `Features/Camera/CaptureSession.swift` (queue-confined AVCaptureSession wrapper, RAW+JPEG paired capture, HEIF/JPEG fallback, WB gains, off-main teardown, front/back + lens switching via `CameraPosition`/`CameraLens`), `ImageProcessor.swift` (CIRAWFilter + full look pipeline from Constants; strip B&W→grain chain), `WhiteBalanceControl.swift` (`WBMode` + shared `CameraChip` pill), `CameraViewModel.swift`, `CameraView.swift` (viewfinder, mode pill, lens chips 0.5×/1×/Tele, flip-camera button, shutter) |
| Diary flow | ✅ Done | `Features/Diary/PromptBank.swift` (69 prompts, zero logic), `DiaryViewModel.swift` (prompt selection no-immediate-repeat, 280-char hard limit, JPEG file storage + relative paths), `EntryEditorView.swift` (photo header with live RAW replacement, prompt, editor, char count, Save/Retake/Skip), `DiaryView.swift` (grouped list, Today/Yesterday sections; tap a row for the full-screen viewer), `EntryDetailView.swift` (full-screen photo + prompt + response + timestamp) |
| Strip | ✅ Done | `Features/Strip/StripGenerator.swift` (pure chunk + render to UIImage at 2×, §10 layout, date stamp), `StripViewModel.swift` (off-main render, PHPhotoLibrary save, persistence of strip PNGs + `DailyStrip` records), `StripView.swift` (preview, 5 swatches, grain/B&W live re-render, Save/Share/Archive) |
| Photobooth | ✅ Done | `Features/Photobooth/PhotoboothViewModel.swift` (4-slot state, PhotosPicker loading, gallery photos used as-is), `PhotoboothView.swift` (slot row, count caption, gallery/undo buttons, Generate CTA — strip only compiles on explicit tap) |
| Library | ✅ Done | `Features/Library/LibraryView.swift` + `LibraryViewModel.swift` (Entries/Strips tabs, "Make today's strip" toolbar action, strip thumbnails from disk; tap a strip for the full-screen viewer), `StripDetailView.swift` (full-screen strip + date + "Save to camera roll" for archived strips) |
| Settings | ✅ Done | `Features/Settings/SettingsView.swift` (no ViewModel; Appearance Light/Dark/System, Remember-WB stub, strip defaults, Clear diary with confirmation + file cleanup), `AppearanceMode` enum |
| Tests | ✅ 11 passing | `frmrTests/frmrTests.swift`: chunking 4→1 strip, 5→2 strips (second padded with 3 empty cells), 0→none; rendered strip width/scale; prompt no-immediate-repeat; prompt bank ≥ 50; SwiftData persistence via in-memory store (DiaryEntry round-trip, DailyStrip ordered entryIDs, delete-all used by "Clear diary", newest-first sort) |

Project settings: iOS 17.0 deployment target, iPhone-only (`TARGETED_DEVICE_FAMILY = 1`), camera + photo-library-add usage descriptions in the generated Info.plist. Zero third-party dependencies, zero network calls.

Verified in simulator (iPhone 17 Pro): all three tabs render in the cream/dark themes; film strip mode fills 4 slots from the gallery picker; Generate → strip preview with date stamp; B&W toggle live re-renders; Archive persists the strip into Library → Strips; capture without a camera surfaces the `AppError` alert. Diary capture needs a physical device (simulator has no camera).

### Changes since the initial build (2026-07-31, same day)

- **Capture crash fix:** `CaptureSession.makePhotoSettings()` now nests `AVVideoQualityKey` inside `AVVideoCompressionPropertiesKey` — the RAW+processed `AVCapturePhotoSettings` initializer throws `NSInvalidArgumentException` if the quality key is top-level.
- **Full-screen viewers:** diary entry rows and library strips are now tappable. `EntryDetailView` shows the photo at full size with prompt, response, and timestamp; `StripDetailView` shows the saved strip PNG at full size. Both handle missing files with a message instead of a blank screen. Viewer metrics live in `Constants.DetailUI`.
- **Persistence tests:** `PersistenceTests` exercises the SwiftData schema against an in-memory `ModelContainer` (round-trips, ordered `entryIDs`, `delete(model:)` as used by Settings' "Clear diary", newest-first sorting).
- **Export older strips:** the full-screen strip viewer now has a "Save to camera roll" button, so strips that were archived without exporting can be saved later. Camera-roll saving is deduplicated into `Shared/Extensions/PHPhotoLibrary+Save.swift` (permission check + `AppError` on failure), used by both `StripViewModel` and `LibraryViewModel.saveStripToCameraRoll`.
- **Camera switching:** flip button (front/back) beside the shutter and a lens chip row (0.5× / 1× / Tele) shown only when the back camera has multiple lenses. `CaptureSession.switchCamera(to:lens:)` swaps the session input on the session queue and restores the previous camera if the swap fails; the white-balance lock is re-applied to the new device. Discovery helpers: `CaptureSession.availableBackLenses()` / `hasFrontCamera()`. Front camera falls back to processed-only capture automatically where RAW is unsupported.
- **Error alerts inside covers:** the root alert couldn't present while a `fullScreenCover` was up, so the alert is now a reusable `AppErrorAlert` modifier (`.appErrorAlert(errorState)`) attached to the root, the entry editor, the strip screen, and the strip viewer — errors raised inside those flows surface immediately.

### Deferred / still open in code (all marked `// OPEN:` with values in Constants.swift)

1. App name — "frmr" placeholder (only in Info.plist strings; bundle display name unchanged)
2. Newsreader font — system serif design used everywhere serif is specced; font file not yet bundled (`PromptCard`, `FilmStripCell`, `DiaryView`, `StripGenerator`)
3. WB persistence — Settings toggle exists and is stored, but capture always resets to Auto on launch
4. Archive behavior — persists to in-app library only; soft-hide/recover not modeled (`DailyStrip` has no archived flag)
5. Vignette/unsharp/warm-push tuning — placeholder values in `Constants.ImageProcessing`, untested against real RAW captures
6. Prompt repeat strategy — random with no immediate repeat; full-shuffle-before-repeat not implemented
7. Strip crop — square (`cellAspectRatio = 1.0`)
8. App icon — §12 "Twin frames" concept not yet generated into `Assets.xcassets`

---

## §14a Implementation status — v2 build (2026-07-31)

All eight v2 features from `frmr-v2-spec.md` are implemented. Clean build, zero warnings, 28 unit tests passing.

| Theme | Features | Status |
|---|---|---|
| Camera feel | F1 tap-to-focus/expose · F2 swipe EV · F3 pinch zoom | Built; **need a physical device to verify** |
| Film grain | F4 luminosity-weighted grain · F5 film stock profiles · F6 animated preview grain | Built and visually verified |
| Strip & flow | F7 sprocket holes / frame numbers / edge date stamp · F8 haptics + prompt typewriter | Built; strip output verified, haptics need a device |

Key changes future agents should know about:

- **`StripCustomization.filmGrain: Bool` is gone**, replaced by `filmStock: FilmStock` (`.none` / `.iso100` / `.iso400` / `.iso3200`). Old UserDefaults values migrate on read via `FilmStock.migrating(fromLegacyGrainEnabled:)`. §4's `stripSettings` table entry is superseded. **Superseded again in v4:** the ISO cases are replaced by six named stocks plus `printStock` and `effects`. v2 values migrate at launch (`iso100` → Daylight 200, `iso400` → Portrait 400, `iso3200` → Cine 500T). See `frmr-v4-spec.md` §F7.
- **`ImageProcessor.applyStripLook` takes an `outputWidth:`.** Grain is per-pixel, so it must be pre-scaled to the size the photo will actually be drawn at — otherwise downscaling into a strip slot averages it away completely. Always pass it when compositing into a smaller rect.
- **`Shared/Haptics.swift`** owns the three feedback generators. Use it rather than instantiating `UIFeedbackGenerator` at a call site; the generators are pre-warmed.
- **`CameraViewModel` holds the preview layer** (via `registerPreviewLayer`) purely to convert taps into device points. Gestures live on the preview view so tap coordinates need no conversion of our own.
- Pure, unit-tested helpers now exist for the gesture maths: `CameraViewModel.exposureBias(fromDragHeight:base:)` and `CaptureSession.clampedZoom(_:min:max:)`.

Full detail, spec deviations, and the remaining v2 open decisions (v2-1 … v2-5) are in `frmr-v2-spec.md` § "Implementation status — v2 build".

---

## §14b Implementation status — v4 build (2026-10-20)

The v4 film pipeline is built:
- **Part 1:** F0 orientation fix, F1 resize-first float pipeline, F2/F3 curves and print stage, F4 halation, F5 grain v2, F6 bloom and light leak, F7 controls and migration.
- **Part 2:**
  - F8 plain strip, F9 camera film stock with live preview, F10 diary review, F11 per-photo stock, F12 As shot / override, F13 Download.
  - F14 stock calibration against real film, after a shadow / black-point fix found on real DNGs.
  - F15 booth strip.

Verification: QA verified everything on the simulator; device checks are outstanding. Full per-feature status, timings, deviations, QA findings and the device checklist are in `frmr-v4-spec.md` §Implementation status.

---

## §15 Design reference

The file `design/Photo Journal.dc.html` is a high-fidelity HTML prototype showing all 6 screens in light and dark mode, plus component breakdowns and app icon concepts. Open it in a browser to inspect exact measurements and states.

**Photo content in the mockup is placeholder** (CSS gradient blocks). Replace with real camera captures at runtime.

**SF Symbols** are the recommended source for all tab bar and UI icons (not the inline SVG paths used in the HTML mock).

# v4 film look: reference research and calibration plan

**Date:** 2026-10-20
**Method:**
1. Rendered the user's 5 iPhone 15 Pro Max DNGs through every stock with `frmrTests/FilmStockSampleSheetTests`. The sheets are kept outside the repo, because the photos are personal.
2. Compared those renders against galleries of real scanned film, browsing Flickr searches sorted by interestingness, and against practitioner write-ups.
3. Separately researched what makes a photobooth strip look real.

frmr's stocks are **inspired by** the real films below. The app uses its own names and its own numbers, and no reference images or data were copied.

**Caveat:** the references are scans, so lab, scanner and exposure all shape them. Treat everything here as direction, not measurement.

## 1. Stock by stock

| frmr stock | Real reference family | What real scans consistently show | What our render shows (user DNGs) | Change |
|---|---|---|---|---|
| **All stocks** | — | Shadows are dense and dark. Blacks are deep on lab scans, with only matte papers or faded prints looking milky. | Black lifted to ~20/255. Shadows below ~20% compressed; low-key photos turn grey. | **In progress:** deeper per-print blacks and a softer toe (backend). |
| **Daylight 200** | Consumer 200-speed colour negative (Gold-type) | Strong yellow-orange warmth in mids and highlights. Fairly punchy contrast and saturation. Skies lean teal. Shadows dense and can block up. | Warm on sunsets, but close to neutral on overcast scenes. Hard to tell apart from Portrait 400. | More warmth (R/G crossover toward yellow-orange in mids and highlights), a little more contrast and saturation, teal-leaning blues. |
| **Portrait 400** | Professional portrait 400 negative (Portra-type) | Soft contrast, restrained saturation, peachy natural skin, pastel greens, long creamy highlight roll-off, shadows open but still dark. | Nearly identical to Daylight 200. | Lower gamma, less saturation, gentler shoulder; warm skin bias without the yellow push; clearly softer than Daylight. |
| **Cine 500T** | Tungsten motion-picture negative (Vision3 500T / CineStill-type) | Deep blacks with a **teal/cyan** shadow cast. Practical lights stay warm. Saturated reds. Red halation ring around bright point lights. Daylight scenes read cool. | Cool, but the shadows lean blue-purple and grey. | Shift the shadow crossover toward teal/cyan (not purple), keep warm highlights warm, keep halation limited to bright points. |
| **Slide 100** | Daylight reversal / slide (Velvia / Ektachrome-type) | Highest contrast, deepest blacks, very saturated reds, oranges and greens, slight warm-magenta bias, little latitude. | Strong blues, but greens and reds not boosted enough; grey blacks. | Raise saturation in reds, oranges and greens; slight warm-magenta bias; deepest black of all prints. |
| **Mono 400** | Classic 400-speed B&W (Tri-X / HP5-type) | True blacks, bright whites, gritty midtone contrast, moderate visible grain. | Good highlights and midtones; grey blacks. | Mostly the black fix; small midtone contrast increase. |
| **Mono 3200** | Push / high-speed B&W (Delta 3200-type) | Grain clearly visible across midtones but **fine-structured**. Less visible in the brightest highlights. Lower midtone contrast; blacks still deep. | Grain clumps into blotchy mottling in bright skies; looks like noise, not grain. | Reduce the coarse octave's weight and size, cut grain amplitude in low-density (bright) areas, keep it strong in the mids. |

## 2. What makes a photobooth strip look real

From real analog strips (Flickr "analog photobooth strip"; Photoautomat / Fotoautomat booths) and booth-history sources:

1. **Tight layout.** Four frames almost touching, separated by thin paper gaps, inside a narrow, even border. No large margins and no text between frames.
2. **Frame shape.** Frames are slightly taller than wide (portrait), not square, with slightly soft or rounded corners.
3. **Paper, not a fill colour.** Warm off-white photographic paper with a faint surface texture and sheen, not pure #FFFFFF. Dark versions read as near-black, not pure black.
4. **Booth lighting and chemistry.** One fixed flash: faces bright, backgrounds falling off. Contrasty, often black and white or slightly toned (silvery, sepia). Small frame-to-frame exposure differences. Soft edge falloff in each frame. Occasional faint development unevenness or specks.
5. **Imperfection is the charm.** Slight blur, uneven density and small marks are what separates a chemical strip from a template. Sources: the Fotoautomat article and Autofoto/Photographers' Gallery; vendors also note that digital filters rarely handle highlights the way silver halide does.

**How this compares with frmr's plain strip (F8):**
- Our frames are square.
- Our gaps are large and hold captions.
- The background is a flat fill.
- There is no per-frame variation.

So frmr reads as a layout, not a booth print.

## 3. Proposed changes

**A. Stock calibration (backend, after the shadow fix lands):** apply the table in §1.
- Re-render the 5-photo sheets before and after each change.
- Add model tests per stock for the measurable parts:
  - warmth ratio at mid and highlight,
  - Portrait 400 gamma below Daylight 200,
  - Cine 500T shadow hue in the teal range,
  - Slide 100 saturation at or above every other stock,
  - Mono 3200 grain variance in highlights below its variance in midtones.

**B. Strip realism (needs user decisions, since it changes the agreed plain strip):**
1. Booth layout: thin even border, thin gaps, frames nearly touching.
2. Portrait frames (about 4:5) with slightly rounded corners.
3. Warm off-white paper and near-black paper with a faint texture.
4. Per-frame booth character, seeded so re-renders stay identical:
   - small exposure variation;
   - soft edge falloff;
   - optional faint development marks.
5. Captions: real strips have none. Options:
   - keep them under each frame (current);
   - move them to the back or detail view;
   - one caption line at the bottom with the date.

## Sources

- Practitioner comparisons of portrait vs consumer 200 colour negative: [Unique Photo](https://www.uniquephoto.com/photoinsider/best-35mm-film-stocks-for-portraits-color-rendition-skin-tones-grain-and-budget-compared), [Gridfiti](https://gridfiti.com/kodak-gold-vs-portra), [Moment](https://www.shopmoment.com/sg/articles/why-kodak-gold-200-is-still-my-favorite-film-stock-in-2024)
- Tungsten cinema negative and halation: [Wikipedia: Cinestill](https://en.wikipedia.org/wiki/Cinestill), [PhotographyTalk](https://www.photographytalk.com/cinestill-800t-kodak-vision3-explained/), [Brooklyn Film Camera](https://brooklynfilmcamera.com/blogs/guides/cinestill-800t-review-the-night-photography-film)
- Slide film: [Popular Photography](https://www.popphoto.com/gear/2008/12/velvia-100f-best-slide-film-ever), [EMULSIVE](https://emulsive.org/articles/my-2020-lockdown-journey-a-comparative-test-of-kodak-ektachrome-e100-and-fujifilm-velvia-50-bonus-portra-lomography-included)
- B&W 400 and 3200: [Rangefinder Forum](https://rangefinderforum.com/threads/tri-x-vs-hp5.159043/), [Photrio](https://www.photrio.com/forum/threads/hp5-vs-tri-x-at-800.98758)
- Photobooth strips: [Wikipedia: Fotoautomat](https://en.wikipedia.org/wiki/Fotoautomat), [The Photographers' Gallery: Autofoto](https://thephotographersgallery.org.uk/node/2792), [LA Photo Party](https://laphotoparty.com/vintage-photo-booth-overview/)
- Visual references: Flickr searches for each film family and for "analog photobooth strip", sorted by interestingness, viewed on 2026-10-20.

## Decisions (user, 2026-10-20)

- **Stock calibration:** apply all of §1, after the shadow fix. Spec: F14.
- **Strip realism:** booth layout, portrait frames and real paper tone. Booth character (per-frame variation and marks) is **not** wanted. Spec: F15.
- **Captions:** keep under each frame.

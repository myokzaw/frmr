import Foundation
import CoreGraphics

nonisolated extension Constants {
    // MARK: Strip layout (project.md §10, logical points; rendered at renderScale)
    enum Strip {
        // v4 F15 booth strip. OPEN: v4-16 — proportions are tuned by eye
        // against real booth strips: thin even border, frames nearly
        // touching, a slim caption band under each frame.
        // Width ÷ height of a frame: 4:5 portrait, like a booth print
        static let cellAspectRatio: CGFloat = 0.8
        static let width: CGFloat = 150
        // Paper around the frames on all four sides
        static let border: CGFloat = 6
        // Paper between one frame's caption band and the next frame (and
        // between the last caption band and the date stamp)
        static let frameGap: CGFloat = 4
        // Lines in each frame's caption band on the rendered strip: one keeps
        // the band slim so frames stay nearly touching; longer captions
        // truncate with an ellipsis (the full text stays in the diary)
        static let boothCaptionLines = 1
        // Booth prints have slightly soft frame corners
        static let frameCornerRadius: CGFloat = 2.5
        // OPEN: v4-9 — separate white paper border on a black strip. Default
        // none: true would paint the border white around the background.
        static let drawsPaperBorder = false
        static let captionSpacing: CGFloat = 2   // gap between a photo and its caption
        static let captionFontSize: CGFloat = 9
        static let captionMaxLines = 2
        static let dateFontSize: CGFloat = 8
        static let dateLetterSpacing: CGFloat = 0.12
        static let renderScale: CGFloat = 2
        static let emptySlotAlpha: CGFloat = 0.08
        // Odd 64-bit multiplier spreading slot indices across the seed space
        // before mixing (v4 F4–F6 per-slot seeds)
        static let slotSeedStride: UInt64 = 0x9E37_79B9_7F4A_7C15

        // v4 F15 paper: warm off-white and near-black photographic paper
        // (sRGB 0–1), never pure #FFFFFF or #000000
        static let paperWhite: (r: Double, g: Double, b: Double) = (0.957, 0.941, 0.906)
        static let paperBlack: (r: Double, g: Double, b: Double) = (0.090, 0.086, 0.082)
        // Faint paper texture: ± this much sRGB per texture cell, cells of
        // this many output pixels, smoothed by drawing the grid scaled up
        static let paperTextureAmplitude: Double = 0.012
        static let paperTextureCellPixels: CGFloat = 2
        // Separates the paper texture's random stream from the frames' seeds
        static let paperSeedSalt: UInt64 = 0x7061_7065_7200_0001

        // v4 F12: the stored Settings value for "As shot" (no strip-wide
        // stock override). Not a FilmStock raw value, so a v4 build reading it
        // falls back to Off rather than misreading it as a stock.
        static let asShotStoredValue = "asShot"
    }
}

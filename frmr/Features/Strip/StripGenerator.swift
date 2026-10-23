import SwiftUI
import UIKit

// Pure layout + rendering: cells in, UIImage out. No persistence, no UI.
// Fully unit-testable off-device (project.md §10).
nonisolated enum StripGenerator {

    struct Cell {
        let image: UIImage?
        let caption: String
        /// The stock the photo was taken on (v4 F11). Used when the strip has
        /// no stock override ("As shot", v4 F12).
        let filmStock: StripCustomization.FilmStock
        /// A Roll photo's own look (v5 F6); As shot renders it as is.
        let look: FilmLook?

        init(
            image: UIImage?,
            caption: String,
            filmStock: StripCustomization.FilmStock = .none,
            look: FilmLook? = nil
        ) {
            self.image = image
            self.caption = caption
            self.filmStock = look?.stock ?? filmStock
            self.look = look
        }

        static let empty = Cell(image: nil, caption: "")
    }

    // Splits items into strips of `perStrip`, padding the final strip so every
    // rendered strip has a full set of slots. Empty input produces no strips.
    static func chunked<T>(
        _ items: [T],
        into perStrip: Int = Constants.entriesPerStrip,
        paddingWith empty: T
    ) -> [[T]] {
        guard !items.isEmpty, perStrip > 0 else { return [] }
        return stride(from: 0, to: items.count, by: perStrip).map { start in
            var strip = Array(items[start..<min(start + perStrip, items.count)])
            while strip.count < perStrip {
                strip.append(empty)
            }
            return strip
        }
    }

    /// - Parameter stripIndex: this strip's position in a multi-strip render.
    ///   Folded into each frame's seed so strip 2's frames never repeat strip
    ///   1's grain or light leak; strip 0 keeps the single-strip seeds.
    static func render(
        strip: [Cell],
        customization: StripCustomization,
        date: Date,
        stripIndex: Int = 0
    ) -> UIImage {
        let layout = Layout()
        let format = UIGraphicsImageRendererFormat()
        format.scale = Constants.Strip.renderScale
        format.opaque = true
        let renderer = UIGraphicsImageRenderer(size: layout.totalSize, format: format)

        return renderer.image { rendererContext in
            let context = rendererContext.cgContext

            // v4 F8/F15: the paper fills the whole strip unless the white
            // paper border comes back (OPEN: v4-9)
            let full = CGRect(origin: .zero, size: layout.totalSize)
            if Constants.Strip.drawsPaperBorder {
                UIColor.white.setFill()
                context.fill(full)
            }
            let paperRect = Constants.Strip.drawsPaperBorder ? layout.backgroundRect : full
            UIColor(customization.background.color).setFill()
            context.fill(paperRect)
            if let texture = paperTexture(
                for: customization.background, size: paperRect.size, date: date, stripIndex: stripIndex
            ) {
                context.saveGState()
                context.interpolationQuality = .low
                UIImage(cgImage: texture).draw(in: paperRect)
                context.restoreGState()
            }

            for (index, cell) in strip.enumerated() {
                draw(
                    cell, at: index, layout: layout, customization: customization, date: date,
                    frame: frameIndex(strip: stripIndex, slot: index), in: context
                )
            }

            drawDateStamp(date, layout: layout, customization: customization)
        }
    }

    /// Seed for one frame's random effects (v4 F4–F6). `slot` is the frame's
    /// index across every strip rendered together (`frameIndex(strip:slot:)`),
    /// so the date and that index fully determine it: re-rendering is
    /// pixel-identical, and no two frames of one session share grain or a leak.
    static func seed(for date: Date, slot: Int) -> UInt64 {
        let seconds = UInt64(bitPattern: Int64(date.timeIntervalSince1970.rounded(.down)))
        return SeededRandom.derive(seconds, salt: UInt64(slot) &* Constants.Strip.slotSeedStride)
    }

    /// Seed for one photo's own look outside a strip — the review screen,
    /// Download and the diary display (OBS-V4-7): all three seed from the
    /// capture date through here, so they show the same grain.
    static func photoLookSeed(for captureDate: Date) -> UInt64 {
        seed(for: captureDate, slot: 0)
    }

    /// A frame's index across every strip rendered together.
    static func frameIndex(strip: Int, slot: Int) -> Int {
        strip * Constants.entriesPerStrip + slot
    }

    // MARK: Layout

    /// The booth layout (v4 F15, proportions OPEN: v4-16): a thin even
    /// border, 4:5 frames each with a slim caption band directly under it,
    /// a thin gap to the next frame, and the date stamp at the bottom.
    /// Internal so tests can check the geometry rather than re-derive it.
    struct Layout {
        let totalSize: CGSize
        let backgroundRect: CGRect
        let frameWidth: CGFloat
        let frameHeight: CGFloat
        let captionHeight: CGFloat
        let dateY: CGFloat
        let dateHeight: CGFloat

        /// Frame plus caption band: the vertical step from frame to frame
        /// is this plus `frameGap`.
        var cellHeight: CGFloat { frameHeight + Constants.Strip.captionSpacing + captionHeight }

        func photoRect(at index: Int) -> CGRect {
            typealias S = Constants.Strip
            return CGRect(
                x: S.border,
                y: S.border + CGFloat(index) * (cellHeight + S.frameGap),
                width: frameWidth,
                height: frameHeight
            )
        }

        func captionRect(at index: Int) -> CGRect {
            let photo = photoRect(at: index)
            return CGRect(
                x: photo.minX, y: photo.maxY + Constants.Strip.captionSpacing,
                width: frameWidth, height: captionHeight
            )
        }

        var dateRect: CGRect {
            CGRect(x: 0, y: dateY, width: totalSize.width, height: dateHeight)
        }

        init() {
            typealias S = Constants.Strip
            frameWidth = S.width - S.border * 2
            frameHeight = frameWidth / S.cellAspectRatio
            captionHeight = ceil(S.captionFontSize * 1.35) * CGFloat(S.boothCaptionLines)
            dateHeight = ceil(S.dateFontSize * 1.4)

            let cellCount = CGFloat(Constants.entriesPerStrip)
            let cellHeight = frameHeight + S.captionSpacing + captionHeight
            let cellsHeight = cellHeight * cellCount + S.frameGap * (cellCount - 1)
            dateY = S.border + cellsHeight + S.frameGap
            totalSize = CGSize(width: S.width, height: dateY + dateHeight + S.border)
            backgroundRect = CGRect(
                x: S.border,
                y: S.border,
                width: S.width - S.border * 2,
                height: totalSize.height - S.border * 2
            )
        }
    }

    // MARK: Paper (v4 F15)

    /// A faint, deterministic paper texture: the paper tone ± a small seeded
    /// value per cell, at cell resolution so drawing it scaled up softens it
    /// into a surface rather than pixel noise. Seeded by the strip date and
    /// strip index, so a re-render is identical and two strips differ.
    static func paperTexture(
        for background: StripCustomization.StripBackground,
        size: CGSize,
        date: Date,
        stripIndex: Int
    ) -> CGImage? {
        typealias S = Constants.Strip
        let cell = max(S.paperTextureCellPixels, 1)
        let width = Int((size.width * S.renderScale / cell).rounded(.up))
        let height = Int((size.height * S.renderScale / cell).rounded(.up))
        guard width > 0, height > 0 else { return nil }

        var random = SeededRandom(seed: SeededRandom.derive(
            seed(for: date, slot: 0), salt: S.paperSeedSalt &+ UInt64(max(stripIndex, 0))
        ))
        let paper = background.paperRGB
        var bytes = [UInt8](repeating: 255, count: width * height * 4)
        func byte(_ value: Double) -> UInt8 { UInt8(min(max(value * 255, 0), 255).rounded()) }
        for index in 0..<(width * height) {
            // Same offset on all channels: texture, not colour noise
            let offset = (random.nextUnit() * 2 - 1) * S.paperTextureAmplitude
            bytes[index * 4] = byte(paper.r + offset)
            bytes[index * 4 + 1] = byte(paper.g + offset)
            bytes[index * 4 + 2] = byte(paper.b + offset)
        }
        guard
            let space = CGColorSpace(name: CGColorSpace.sRGB),
            let provider = CGDataProvider(data: Data(bytes) as CFData)
        else {
            return nil
        }
        return CGImage(
            width: width, height: height, bitsPerComponent: 8, bitsPerPixel: 32, bytesPerRow: width * 4,
            space: space, bitmapInfo: CGBitmapInfo(rawValue: CGImageAlphaInfo.noneSkipLast.rawValue),
            provider: provider, decode: nil, shouldInterpolate: true, intent: .defaultIntent
        )
    }

    // MARK: Drawing

    private static func draw(
        _ cell: Cell,
        at index: Int,
        layout: Layout,
        customization: StripCustomization,
        date: Date,
        frame: Int,
        in context: CGContext
    ) {
        let photoRect = layout.photoRect(at: index)
        // Booth prints have softly rounded frame corners (v4 F15)
        let frameShape = UIBezierPath(roundedRect: photoRect, cornerRadius: Constants.Strip.frameCornerRadius)

        if let image = cell.image {
            // A superseded render (the customization changed again) is thrown
            // away by StripViewModel, so skip its filtering rather than finish
            // work nobody will see. Outside a task this is always false.
            guard !Task.isCancelled else { return }
            // The processor resizes and crops to the slot itself, so it needs
            // the slot's pixel width (v4 F1)
            // Each frame renders on its effective stock: the strip's override,
            // or the stock it was shot on (v4 F12)
            let filtered = ImageProcessor.applyStripLook(
                to: image,
                customization: customization.effective(forFrameStock: cell.filmStock, look: cell.look),
                outputWidth: photoRect.width * Constants.Strip.renderScale,
                seed: seed(for: date, slot: frame)
            )
            // Already slot-sized when filtered; the aspect fill still crops
            // unfiltered photos, which keep the untouched fast path
            drawAspectFilled(filtered, in: photoRect, clip: frameShape, context: context)
        } else {
            UIColor.black.withAlphaComponent(Constants.Strip.emptySlotAlpha).setFill()
            frameShape.fill()
        }

        drawCaption(cell.caption, in: layout.captionRect(at: index), customization: customization)
    }

    private static func drawAspectFilled(_ image: UIImage, in rect: CGRect, clip: UIBezierPath, context: CGContext) {
        guard image.size.width > 0, image.size.height > 0 else { return }
        let scale = max(rect.width / image.size.width, rect.height / image.size.height)
        let drawSize = CGSize(width: image.size.width * scale, height: image.size.height * scale)
        let drawOrigin = CGPoint(
            x: rect.midX - drawSize.width / 2,
            y: rect.midY - drawSize.height / 2
        )

        context.saveGState()
        clip.addClip()
        image.draw(in: CGRect(origin: drawOrigin, size: drawSize))
        context.restoreGState()
    }

    private static func drawCaption(_ caption: String, in rect: CGRect, customization: StripCustomization) {
        guard !caption.isEmpty else { return }

        let paragraph = NSMutableParagraphStyle()
        paragraph.lineBreakMode = .byTruncatingTail

        let attributed = NSAttributedString(string: caption, attributes: [
            .font: serifItalicFont(size: Constants.Strip.captionFontSize),
            .foregroundColor: UIColor(customization.background.contrastingTextColor),
            .paragraphStyle: paragraph,
        ])
        attributed.draw(with: rect, options: [.usesLineFragmentOrigin, .truncatesLastVisibleLine], context: nil)
    }

    private static func drawDateStamp(_ date: Date, layout: Layout, customization: StripCustomization) {
        typealias S = Constants.Strip
        let paragraph = NSMutableParagraphStyle()
        paragraph.alignment = .center

        let attributed = NSAttributedString(string: date.stripDateStamp, attributes: [
            .font: UIFont.monospacedSystemFont(ofSize: S.dateFontSize, weight: .regular),
            .foregroundColor: UIColor(customization.background.contrastingTextColor),
            .kern: S.dateFontSize * S.dateLetterSpacing,
            .paragraphStyle: paragraph,
        ])
        attributed.draw(in: layout.dateRect)
    }

    // System serif italic permanently (v5.2-8, Newsreader dropped)
    private static func serifItalicFont(size: CGFloat) -> UIFont {
        let base = UIFont.systemFont(ofSize: size)
        guard let descriptor = base.fontDescriptor
            .withDesign(.serif)?
            .withSymbolicTraits(.traitItalic)
        else {
            return base
        }
        return UIFont(descriptor: descriptor, size: size)
    }
}

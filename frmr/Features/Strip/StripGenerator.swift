import SwiftUI
import UIKit

// Pure layout + rendering: cells in, UIImage out. No persistence, no UI.
// Fully unit-testable off-device (project.md §10).
nonisolated enum StripGenerator {

    struct Cell {
        let image: UIImage?
        let caption: String

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

    static func render(strip: [Cell], customization: StripCustomization, date: Date) -> UIImage {
        let layout = Layout()
        let format = UIGraphicsImageRendererFormat()
        format.scale = Constants.Strip.renderScale
        format.opaque = true
        let renderer = UIGraphicsImageRenderer(size: layout.totalSize, format: format)

        return renderer.image { rendererContext in
            let context = rendererContext.cgContext

            // Photobooth paper: white sheet with the chosen background inset
            UIColor.white.setFill()
            context.fill(CGRect(origin: .zero, size: layout.totalSize))
            UIColor(customization.background.color).setFill()
            context.fill(layout.backgroundRect)

            for (index, cell) in strip.enumerated() {
                draw(cell, at: index, layout: layout, customization: customization, in: context)
            }

            drawDateStamp(date, layout: layout, customization: customization)

            // v2 F7 — film-edge detailing. Drawn last so the holes punch through
            // anything above them, including photo pixels that overflow a slot.
            drawFrameNumbers(strip.count, layout: layout)
            drawRotatedDateStamp(date, layout: layout, in: context)
            drawSprocketHoles(layout: layout, in: context)
        }
    }

    // MARK: Layout

    // All measurements from project.md §10, resolved once per render
    private struct Layout {
        let totalSize: CGSize
        let backgroundRect: CGRect
        let cellOriginX: CGFloat
        let cellWidth: CGFloat
        let photoHeight: CGFloat
        let captionHeight: CGFloat
        let cellHeight: CGFloat
        let firstCellY: CGFloat
        let dateY: CGFloat
        let dateHeight: CGFloat
        // Reserved right-hand gutter in the caption band so a frame number can
        // never collide with a long caption (v2 F7)
        let frameNumberColumnWidth: CGFloat

        func cellY(at index: Int) -> CGFloat {
            firstCellY + CGFloat(index) * (cellHeight + Constants.Strip.cellSpacing)
        }

        init() {
            typealias S = Constants.Strip
            let inset = S.paperBorder + S.contentPadding
            cellOriginX = inset
            cellWidth = S.width - inset * 2
            photoHeight = cellWidth / S.cellAspectRatio
            captionHeight = ceil(S.captionFontSize * 1.35) * CGFloat(S.captionMaxLines)
            cellHeight = photoHeight + S.captionSpacing + captionHeight
            firstCellY = inset
            dateHeight = ceil(S.dateFontSize * 1.4)
            frameNumberColumnWidth = ceil(S.frameNumberFontSize * 2.4)

            let cellCount = CGFloat(Constants.entriesPerStrip)
            let cellsHeight = cellHeight * cellCount + S.cellSpacing * (cellCount - 1)
            dateY = firstCellY + cellsHeight + S.cellSpacing
            totalSize = CGSize(width: S.width, height: dateY + dateHeight + inset)
            backgroundRect = CGRect(
                x: S.paperBorder,
                y: S.paperBorder,
                width: S.width - S.paperBorder * 2,
                height: totalSize.height - S.paperBorder * 2
            )
        }
    }

    // MARK: Drawing

    private static func draw(
        _ cell: Cell,
        at index: Int,
        layout: Layout,
        customization: StripCustomization,
        in context: CGContext
    ) {
        let cellY = layout.cellY(at: index)
        let photoRect = CGRect(x: layout.cellOriginX, y: cellY, width: layout.cellWidth, height: layout.photoHeight)

        if let image = cell.image {
            // Grain is per-pixel, so the processor needs to know how small the
            // photo is about to be drawn (v2 F4)
            let filtered = ImageProcessor.applyStripLook(
                to: image,
                customization: customization,
                outputWidth: photoRect.width * Constants.Strip.renderScale
            )
            drawAspectFilled(filtered, in: photoRect, context: context)
        } else {
            UIColor.black.withAlphaComponent(Constants.Strip.emptySlotAlpha).setFill()
            context.fill(photoRect)
        }

        let captionRect = CGRect(
            x: layout.cellOriginX,
            y: photoRect.maxY + Constants.Strip.captionSpacing,
            width: layout.cellWidth - layout.frameNumberColumnWidth,
            height: layout.captionHeight
        )
        drawCaption(cell.caption, in: captionRect, customization: customization)
    }

    private static func drawAspectFilled(_ image: UIImage, in rect: CGRect, context: CGContext) {
        guard image.size.width > 0, image.size.height > 0 else { return }
        let scale = max(rect.width / image.size.width, rect.height / image.size.height)
        let drawSize = CGSize(width: image.size.width * scale, height: image.size.height * scale)
        let drawOrigin = CGPoint(
            x: rect.midX - drawSize.width / 2,
            y: rect.midY - drawSize.height / 2
        )

        context.saveGState()
        context.clip(to: rect)
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
        let rect = CGRect(x: 0, y: layout.dateY, width: layout.totalSize.width, height: layout.dateHeight)
        attributed.draw(in: rect)
    }

    // MARK: Film-edge detailing (v2 F7)

    // Two columns of punched circles in the white paper border. Drawn last, so
    // they read as holes through the paper rather than dots printed on it.
    private static func drawSprocketHoles(layout: Layout, in context: CGContext) {
        typealias S = Constants.Strip
        guard S.sprocketHoleCount > 0 else { return }

        context.setFillColor(UIColor(Color(hex: S.sprocketHoleColorHex)).cgColor)
        let columnsX = [S.sprocketHoleInset, S.width - S.sprocketHoleInset]

        for index in 0..<Constants.entriesPerStrip {
            let cellTop = layout.cellY(at: index)
            // Holes are spaced evenly down the photo's height, one per band centre
            let band = layout.photoHeight / CGFloat(S.sprocketHoleCount)
            for hole in 0..<S.sprocketHoleCount {
                let centreY = cellTop + band * (CGFloat(hole) + 0.5)
                for centreX in columnsX {
                    let rect = CGRect(
                        x: centreX - S.sprocketHoleRadius,
                        y: centreY - S.sprocketHoleRadius,
                        width: S.sprocketHoleRadius * 2,
                        height: S.sprocketHoleRadius * 2
                    )
                    context.addEllipse(in: rect)
                }
            }
        }
        context.fillPath()
    }

    // Amber monospace frame counters, right-aligned in the caption band's
    // reserved gutter — the numbering printed alongside every 35mm frame.
    private static func drawFrameNumbers(_ count: Int, layout: Layout) {
        typealias S = Constants.Strip
        let paragraph = NSMutableParagraphStyle()
        paragraph.alignment = .right

        let attributes: [NSAttributedString.Key: Any] = [
            .font: UIFont.monospacedSystemFont(ofSize: S.frameNumberFontSize, weight: .medium),
            .foregroundColor: UIColor(Color(hex: S.frameNumberColorHex)),
            .paragraphStyle: paragraph,
        ]

        for index in 0..<min(count, Constants.entriesPerStrip) {
            let rect = CGRect(
                x: layout.cellOriginX + layout.cellWidth - layout.frameNumberColumnWidth,
                y: layout.cellY(at: index) + layout.photoHeight + S.captionSpacing + S.frameNumberInset,
                width: layout.frameNumberColumnWidth,
                height: ceil(S.frameNumberFontSize * 1.4)
            )
            NSAttributedString(string: String(format: "%02d", index + 1), attributes: attributes).draw(in: rect)
        }
    }

    // A DX-code-style stamp running bottom-to-top up the right paper border.
    // The bottom stamp stays for readability; this one is texture.
    private static func drawRotatedDateStamp(_ date: Date, layout: Layout, in context: CGContext) {
        typealias S = Constants.Strip
        let height = ceil(S.edgeDateFontSize * 1.4)
        let runLength = layout.totalSize.height - S.paperBorder * 2

        let paragraph = NSMutableParagraphStyle()
        paragraph.alignment = .center

        let attributed = NSAttributedString(string: date.stripDateStamp, attributes: [
            .font: UIFont.monospacedSystemFont(ofSize: S.edgeDateFontSize, weight: .regular),
            .foregroundColor: UIColor(Color(hex: S.frameNumberColorHex)),
            .kern: S.edgeDateFontSize * S.dateLetterSpacing,
            .paragraphStyle: paragraph,
        ])

        context.saveGState()
        defer { context.restoreGState() }
        // Anchor at the bottom of the right border, then rotate so the local
        // +x axis runs up the strip.
        context.translateBy(x: S.width - S.paperBorder / 2, y: layout.totalSize.height - S.paperBorder)
        context.rotate(by: S.datestampRotationDegrees * .pi / 180)
        attributed.draw(in: CGRect(x: 0, y: -height / 2, width: runLength, height: height))
    }

    // OPEN: spec calls for Newsreader italic; system serif until the font is bundled
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

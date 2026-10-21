import CoreImage
import CoreImage.CIFilterBuiltins
import ImageIO
import UIKit

// All CoreImage filter logic lives here. Two pipelines:
//  - process(rawData:) — the full RAW development look (Constants.ImageProcessing)
//  - applyStripLook(to:customization:) — B&W / grain applied at strip render time
nonisolated enum ImageProcessor {
    private static let context = CIContext()

    static func process(rawData: Data) throws -> UIImage {
        guard let rawFilter = CIRAWFilter(imageData: rawData, identifierHint: nil) else {
            throw AppError.rawProcessingFailed
        }
        rawFilter.luminanceNoiseReductionAmount = Constants.ImageProcessing.rawNoiseReduction
        rawFilter.sharpnessAmount = Constants.ImageProcessing.rawNoiseReductionSharpness

        // CaptureSession stamps how the phone was held into the capture's EXIF.
        // CIRAWFilter would otherwise apply that itself and hand back rotated
        // pixels, which this pipeline then flattened to `.up` — losing the
        // rotation and developing a landscape-held shot sideways. Developing in
        // sensor space and carrying the orientation as a tag instead keeps the
        // two capture paths symmetric: the JPEG preview is also unrotated pixels
        // plus an orientation tag, so both survive drawing and re-encoding.
        let orientation = Self.orientation(ofImageData: rawData)
        rawFilter.orientation = .up

        guard let developed = rawFilter.outputImage else {
            throw AppError.rawProcessingFailed
        }
        return try render(applyLook(to: developed), orientation: Self.uiOrientation(from: orientation))
    }

    /// EXIF orientation of a capture, defaulting to upright when the file
    /// carries no tag. Checked at the top level and in the TIFF dictionary,
    /// since RAW containers report it in either place.
    private static func orientation(ofImageData data: Data) -> CGImagePropertyOrientation {
        guard
            let source = CGImageSourceCreateWithData(data as CFData, nil),
            let properties = CGImageSourceCopyPropertiesAtIndex(source, 0, nil) as? [CFString: Any]
        else {
            return .up
        }
        let tiff = properties[kCGImagePropertyTIFFDictionary] as? [CFString: Any]
        guard
            let raw = (properties[kCGImagePropertyOrientation] as? UInt32)
                ?? (tiff?[kCGImagePropertyTIFFOrientation] as? UInt32),
            let orientation = CGImagePropertyOrientation(rawValue: raw)
        else {
            return .up
        }
        return orientation
    }

    // The two enums share case names but not raw values, so the mapping has to
    // be spelled out rather than bridged through rawValue. Internal so the
    // mapping is unit-testable without a capture.
    static func uiOrientation(from orientation: CGImagePropertyOrientation) -> UIImage.Orientation {
        switch orientation {
        case .up: return .up
        case .upMirrored: return .upMirrored
        case .down: return .down
        case .downMirrored: return .downMirrored
        case .leftMirrored: return .leftMirrored
        case .right: return .right
        case .rightMirrored: return .rightMirrored
        case .left: return .left
        @unknown default: return .up
        }
    }

    /// Inverse of `uiOrientation(from:)`, spelled out for the same reason.
    static func cgOrientation(from orientation: UIImage.Orientation) -> CGImagePropertyOrientation {
        switch orientation {
        case .up: return .up
        case .upMirrored: return .upMirrored
        case .down: return .down
        case .downMirrored: return .downMirrored
        case .leftMirrored: return .leftMirrored
        case .right: return .right
        case .rightMirrored: return .rightMirrored
        case .left: return .left
        @unknown default: return .up
        }
    }

    // Captures are unrotated pixels plus an orientation tag (post-v3 fix).
    // `CIImage(image:)` ignores that tag, so filtering through it and
    // rendering as `.up` laid every landscape-held photo on its side as soon
    // as grain or B&W was on. Resolve the tag into the pixels up front.
    private static func uprightCIImage(from image: UIImage) -> CIImage? {
        guard let cgImage = image.cgImage else {
            // CIImage-backed UIImages carry no separate tag to resolve
            return CIImage(image: image)
        }
        return CIImage(cgImage: cgImage).oriented(cgOrientation(from: image.imageOrientation))
    }

    /// - Parameter outputWidth: the width in pixels the result will be drawn at.
    ///   Grain is a per-pixel effect, so a full-resolution capture composited
    ///   into a 260px strip slot averages its grain away to nothing. Passing the
    ///   destination width scales the noise tile up to compensate.
    static func applyStripLook(
        to image: UIImage,
        customization: StripCustomization,
        outputWidth: CGFloat? = nil
    ) -> UIImage {
        let profile = customization.filmStock.profile
        guard customization.blackAndWhite || profile != nil else {
            return image
        }
        guard let input = uprightCIImage(from: image) else {
            // Cosmetic filters only — falling back to the unfiltered photo loses no
            // data and keeps the strip render from failing outright.
            print("[ImageProcessor] Could not read image for strip filters; using original")
            return image
        }

        var output = input
        // Filter order is fixed: B&W first, then the film stock's colour cast,
        // then grain (project.md §8, extended by v2 F5). The cast lands before
        // the grain so the grain itself stays neutral-coloured.
        if customization.blackAndWhite {
            let mono = CIFilter.photoEffectMono()
            mono.inputImage = output
            output = mono.outputImage ?? output
        }
        if let profile {
            // A B&W strip should stay neutral, so the cast is skipped there
            if !customization.blackAndWhite, !profile.isNeutral {
                output = applyColourCast(profile.colourMatrix, to: output)
            }
            let shrinkFactor = outputWidth.map { max(1, input.extent.width / $0) } ?? 1
            output = addGrain(to: output, profile: profile, sizeCompensation: shrinkFactor)
        }

        do {
            return try render(output)
        } catch {
            print("[ImageProcessor] Strip filter render failed; using original: \(error)")
            return image
        }
    }

    private static func applyLook(to input: CIImage) -> CIImage {
        typealias P = Constants.ImageProcessing
        var image = input

        let noiseReduction = CIFilter.noiseReduction()
        noiseReduction.inputImage = image
        noiseReduction.noiseLevel = P.noiseLevel
        noiseReduction.sharpness = P.noiseSharpness
        image = noiseReduction.outputImage ?? image

        // Anchors from the Lightroom preset: shadow + midtone, endpoints pinned.
        // The unspecified center point is interpolated between the two anchors.
        let toneCurve = CIFilter.toneCurve()
        toneCurve.inputImage = image
        toneCurve.point0 = CGPoint(x: 0, y: 0)
        toneCurve.point1 = CGPoint(x: CGFloat(P.toneCurveShadowInput), y: CGFloat(P.toneCurveShadowOutput))
        toneCurve.point2 = CGPoint(
            x: CGFloat((P.toneCurveShadowInput + P.toneCurveMidSimpleInput) / 2),
            y: CGFloat((P.toneCurveShadowOutput + P.toneCurveMidSimpleOutput) / 2)
        )
        toneCurve.point3 = CGPoint(x: CGFloat(P.toneCurveMidSimpleInput), y: CGFloat(P.toneCurveMidSimpleOutput))
        toneCurve.point4 = CGPoint(x: 1, y: 1)
        image = toneCurve.outputImage ?? image

        let colorControls = CIFilter.colorControls()
        colorControls.inputImage = image
        colorControls.contrast = P.colorContrast
        colorControls.saturation = P.colorSaturation
        image = colorControls.outputImage ?? image

        let vibrance = CIFilter.vibrance()
        vibrance.inputImage = image
        vibrance.amount = P.vibrance
        image = vibrance.outputImage ?? image

        let unsharp = CIFilter.unsharpMask()
        unsharp.inputImage = image
        unsharp.radius = P.unsharpRadius
        unsharp.intensity = P.unsharpIntensity
        image = unsharp.outputImage ?? image

        let warmth = CIFilter.temperatureAndTint()
        warmth.inputImage = image
        warmth.neutral = CIVector(x: 6500, y: 0)
        warmth.targetNeutral = CIVector(x: CGFloat(P.warmPushKelvin), y: CGFloat(P.warmPushTint))
        image = warmth.outputImage ?? image

        let vignette = CIFilter.vignette()
        vignette.inputImage = image
        vignette.intensity = P.vignetteIntensity
        vignette.radius = P.vignetteRadius
        image = vignette.outputImage ?? image

        return image
    }

    // MARK: Grain (v2 F4 / F5)

    private static func applyColourCast(_ matrix: [CGFloat], to input: CIImage) -> CIImage {
        guard matrix.count == 16 else { return input }
        let filter = CIFilter.colorMatrix()
        filter.inputImage = input
        filter.rVector = CIVector(x: matrix[0], y: matrix[1], z: matrix[2], w: matrix[3])
        filter.gVector = CIVector(x: matrix[4], y: matrix[5], z: matrix[6], w: matrix[7])
        filter.bVector = CIVector(x: matrix[8], y: matrix[9], z: matrix[10], w: matrix[11])
        filter.aVector = CIVector(x: matrix[12], y: matrix[13], z: matrix[14], w: matrix[15])
        return filter.outputImage ?? input
    }

    // Luminosity-weighted grain: a flat noise overlay reads as a Photoshop
    // texture, so the grain layer's opacity is shaped by a U-curve over the
    // image's own luminance — heavy in shadows, lightest in midtones, heavy
    // again in highlights. That U-curve is what makes it read as film.
    private static func addGrain(
        to input: CIImage,
        profile: Constants.ImageProcessing.FilmStockProfile,
        sizeCompensation: CGFloat
    ) -> CIImage {
        guard
            let grain = grainLayer(for: input, profile: profile, sizeCompensation: sizeCompensation),
            let mask = luminanceMask(for: input)
        else {
            return input
        }

        let shaped = CIFilter.blendWithMask()
        shaped.inputImage = grain
        shaped.backgroundImage = CIImage(color: .clear).cropped(to: input.extent)
        shaped.maskImage = mask
        guard let shapedGrain = shaped.outputImage else { return input }

        let composite = CIFilter.sourceOverCompositing()
        composite.inputImage = shapedGrain.cropped(to: input.extent)
        composite.backgroundImage = input
        return composite.outputImage ?? input
    }

    private static func grainLayer(
        for input: CIImage,
        profile: Constants.ImageProcessing.FilmStockProfile,
        sizeCompensation: CGFloat
    ) -> CIImage? {
        guard let noise = CIFilter.randomGenerator().outputImage else { return nil }

        // Scaling the tile up enlarges the individual grains — the difference
        // between fine ISO 100 and chunky pushed ISO 3200. The size compensation
        // keeps grains the same apparent size once the photo is downscaled into
        // its strip slot.
        let tileScale = profile.grainScale * sizeCompensation
        let scaled = tileScale == 1
            ? noise
            : noise.transformed(by: CGAffineTransform(scaleX: tileScale, y: tileScale))

        let desaturate = CIFilter.colorControls()
        desaturate.inputImage = scaled
        desaturate.saturation = 0
        guard let grayNoise = desaturate.outputImage else { return nil }

        // Alpha carries the grain strength; the mask scales it further per-pixel
        let faded = CIFilter.colorMatrix()
        faded.inputImage = grayNoise
        faded.aVector = CIVector(x: 0, y: 0, z: 0, w: CGFloat(profile.grainIntensity))
        return faded.outputImage?.cropped(to: input.extent)
    }

    private static func luminanceMask(for input: CIImage) -> CIImage? {
        let desaturate = CIFilter.colorControls()
        desaturate.inputImage = input
        desaturate.saturation = 0
        guard let gray = desaturate.outputImage else { return nil }

        // A soft mask keeps grain from clustering along hard edges
        let blur = CIFilter.gaussianBlur()
        blur.inputImage = gray
        blur.radius = Constants.ImageProcessing.grainMaskBlurRadius
        let softened = (blur.outputImage ?? gray).cropped(to: input.extent)

        let curves = CIFilter.colorCurves()
        curves.inputImage = softened
        curves.curvesDomain = CIVector(x: 0, y: 1)
        curves.curvesData = grainCurveData
        curves.colorSpace = CGColorSpace(name: CGColorSpace.sRGB) ?? CGColorSpaceCreateDeviceRGB()
        return curves.outputImage?.cropped(to: input.extent)
    }

    // CIColorCurves takes an evenly-spaced RGB lookup table as raw Float32 data.
    // The same value goes in all three channels: the mask is greyscale.
    private static let grainCurveData: Data = {
        let values = Constants.ImageProcessing.grainLuminanceCurve
        var floats: [Float] = []
        floats.reserveCapacity(values.count * 3)
        for value in values {
            floats.append(contentsOf: [value, value, value])
        }
        return floats.withUnsafeBufferPointer { Data(buffer: $0) }
    }()

    // MARK: Live preview grain (v2 F6)

    /// One frame of animated viewfinder grain. `phase` shifts the noise tile so
    /// successive frames differ — real film grain moves between frames, and a
    /// static tile immediately reads as a digital filter.
    static func makeLiveGrainTile(size: CGSize, phase: CGFloat) -> CGImage? {
        guard size.width >= 1, size.height >= 1,
              let noise = CIFilter.randomGenerator().outputImage
        else {
            return nil
        }

        let extent = CGRect(origin: .zero, size: size)
        let shifted = noise.transformed(
            by: CGAffineTransform(translationX: phase, y: phase * 1.7)
        )

        let desaturate = CIFilter.colorControls()
        desaturate.inputImage = shifted
        desaturate.saturation = 0
        guard let gray = desaturate.outputImage?.cropped(to: extent) else { return nil }

        return context.createCGImage(gray, from: extent)
    }

    /// - Parameter orientation: how the result should be read. Defaults to
    ///   upright: the strip-look path resolves its source's orientation into
    ///   the pixels first (`uprightCIImage(from:)`).
    private static func render(
        _ image: CIImage,
        orientation: UIImage.Orientation = .up
    ) throws -> UIImage {
        guard let cgImage = context.createCGImage(image, from: image.extent) else {
            throw AppError.rawProcessingFailed
        }
        return UIImage(cgImage: cgImage, scale: 1, orientation: orientation)
    }
}

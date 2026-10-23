import CoreImage
import CoreImage.CIFilterBuiltins
import ImageIO
import UniformTypeIdentifiers
import UIKit

// All CoreImage filter logic lives here. Two pipelines:
//  - process(rawData:) — the full RAW development look (Constants.ImageProcessing)
//  - applyStripLook(to:customization:outputWidth:) — the strip-time film look,
//    applied after resizing to the strip slot
nonisolated enum ImageProcessor {
    private static let context = CIContext()

    // The strip look gets its own half-float context: curves and glows banded
    // visibly in 8-bit. One static instance, because building a CIContext per
    // render costs more than the render itself at slot size (v4 F1).
    private static let stripContext = CIContext(options: [.workingFormat: CIFormat.RGBAh])
    private static let stripOutputColorSpace = CGColorSpace(name: CGColorSpace.sRGB) ?? CGColorSpaceCreateDeviceRGB()

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

    /// - Parameter outputWidth: the slot width in pixels the result will be
    ///   drawn at. Required: the photo is resized and centre-cropped to the
    ///   slot (`outputWidth × outputWidth / Strip.cellAspectRatio`) before any
    ///   effect runs, so every effect works in output pixels (v4 F1).
    /// - Returns: the original image untouched when no filter is active
    ///   (the caller aspect-fills it), otherwise an upright, slot-sized image.
    /// - Parameter seed: drives every random element (grain, light leak).
    ///   StripGenerator derives it from the strip date and slot index, so the
    ///   same strip re-renders pixel-identically.
    static func applyStripLook(
        to image: UIImage,
        customization: StripCustomization,
        outputWidth: CGFloat,
        seed: UInt64 = 0
    ) -> UIImage {
        // One photo has one stock: StripGenerator resolves As shot per frame
        // (`effective(forFrameStock:)`) before calling, so a nil here has no
        // frame stock to fall back on and renders as Off
        let stock = customization.filmStock ?? .none
        guard customization.blackAndWhite || stock != .none || customization.exposure != 0 else {
            return image
        }
        guard
            let upright = uprightCIImage(from: image),
            let input = resizedToSlot(upright, outputWidth: outputWidth)
        else {
            // Cosmetic filters only — falling back to the unfiltered photo loses no
            // data and keeps the strip render from failing outright.
            print("[ImageProcessor] Could not read image for strip filters; using original")
            return image
        }

        do {
            return try renderStrip(filmLook(input, customization: customization, outputWidth: outputWidth, seed: seed))
        } catch {
            print("[ImageProcessor] Strip filter render failed; using original: \(error)")
            return image
        }
    }

    /// One photo through its stock's full look (v4 F10, F11, F13): the
    /// stock's default print and effects, grain included — the same chain
    /// as the strip, but on the whole frame instead of a square slot.
    ///
    /// Works in sensor space and returns the source's orientation tag, so a
    /// saved file is tagged exactly like the capture. Effects are sized
    /// from the upright width, as the strip sizes them from the slot width.
    ///
    /// - Parameter coveringPixelSize: an upright display size in pixels. The
    ///   photo is first scaled down (never up) to the smallest size that
    ///   still covers it, for the review screen and thumbnails. nil keeps
    ///   full resolution (Download).
    /// - Returns: `image` itself for stock Off.
    static func renderFullLook(
        of image: UIImage,
        stock: StripCustomization.FilmStock,
        seed: UInt64,
        coveringPixelSize: CGSize? = nil
    ) throws -> UIImage {
        try renderFullLook(of: image, look: .stockDefaults(for: stock), seed: seed, coveringPixelSize: coveringPixelSize)
    }

    /// The same full-frame render for any `FilmLook` (v5 F4/F6): the
    /// look's print, B&W and effect strengths instead of the stock's
    /// defaults. A default look renders exactly like the stock overload.
    /// - Returns: `image` itself when the look changes nothing (stock Off
    ///   without B&W).
    static func renderFullLook(
        of image: UIImage,
        look: FilmLook,
        seed: UInt64,
        coveringPixelSize: CGSize? = nil
    ) throws -> UIImage {
        guard look.altersPhoto else { return image }
        guard let cgImage = image.cgImage else { throw AppError.filmLookRenderFailed }
        let orientation = image.imageOrientation
        var input = CIImage(cgImage: cgImage)
        var scale = image.scale

        if let target = coveringPixelSize,
           let resized = resized(input, toCover: sensorSpaceSize(of: target, for: orientation)) {
            input = resized
            scale = 1
        }
        // The swap is its own inverse, so it also maps sensor size to upright
        let uprightWidth = sensorSpaceSize(of: input.extent.size, for: orientation).width
        // Blurs and the leak are already fractions of the width; grain is
        // in pixels, so it scales with the frame (OPEN: v4-5,
        // Constants.ImageProcessing.Film.grainReferenceWidth)
        let output = filmLook(
            input, customization: look.customization, outputWidth: uprightWidth, seed: seed,
            grainScale: Double(uprightWidth) / Constants.ImageProcessing.Film.grainReferenceWidth
        )
        guard let rendered = stripContext.createCGImage(
            output, from: input.extent, format: .RGBA8, colorSpace: stripOutputColorSpace
        ) else {
            throw AppError.filmLookRenderFailed
        }
        return UIImage(cgImage: rendered, scale: scale, orientation: orientation)
    }

    /// An upright size expressed in the sensor-space pixels of a photo
    /// tagged `orientation`: quarter-turned tags swap width and height.
    static func sensorSpaceSize(of upright: CGSize, for orientation: UIImage.Orientation) -> CGSize {
        switch orientation {
        case .left, .right, .leftMirrored, .rightMirrored:
            return CGSize(width: upright.height, height: upright.width)
        default:
            return upright
        }
    }

    /// Lanczos downscale to the smallest size covering `target`, keeping
    /// the aspect ratio and the origin at zero. nil when no shrink is
    /// needed, so a full-size render never resamples.
    private static func resized(_ image: CIImage, toCover target: CGSize) -> CIImage? {
        let source = image.extent
        guard source.width > 0, source.height > 0, target.width >= 1, target.height >= 1 else { return nil }
        let scale = max(target.width / source.width, target.height / source.height)
        guard scale < 1 else { return nil }
        let lanczos = CIFilter.lanczosScaleTransform()
        lanczos.inputImage = image.clampedToExtent()
        lanczos.scale = Float(scale)
        lanczos.aspectRatio = 1
        guard let scaled = lanczos.outputImage else { return nil }
        let size = CGRect(
            x: 0, y: 0,
            width: (source.width * scale).rounded(),
            height: (source.height * scale).rounded()
        )
        return scaled.cropped(to: size)
    }

    /// HEIC data for the camera roll (v4 F13), carrying the image's
    /// orientation as its EXIF tag rather than rotating pixels.
    static func heicData(from image: UIImage, quality: Double = Constants.Diary.downloadHEICQuality) throws -> Data {
        guard let cgImage = image.cgImage else { throw AppError.filmLookRenderFailed }
        let data = NSMutableData()
        guard let destination = CGImageDestinationCreateWithData(
            data as CFMutableData, UTType.heic.identifier as CFString, 1, nil
        ) else {
            throw AppError.filmLookRenderFailed
        }
        let properties: [CFString: Any] = [
            kCGImagePropertyOrientation: cgOrientation(from: image.imageOrientation).rawValue,
            kCGImageDestinationLossyCompressionQuality: quality,
        ]
        CGImageDestinationAddImage(destination, cgImage, properties as CFDictionary)
        guard CGImageDestinationFinalize(destination) else { throw AppError.filmLookRenderFailed }
        return data as Data
    }

    /// The film chain on an already-sized image: everything after the
    /// resize, shared by the strip slot and the full-frame look.
    private static func filmLook(
        _ input: CIImage,
        customization: StripCustomization,
        outputWidth: CGFloat,
        seed: UInt64,
        grainScale: Double = 1
    ) -> CIImage {
        let stock = customization.filmStock ?? .none
        // Order is part of the spec (v4 §Theme C): monochrome luminance,
        // halation, the film cube, vignette, haze, light leak, then grain
        // last so it sits on top of the print. Every effect is scaled by its
        // strength (v5 F5); a strength of 0 skips the stage entirely, so it
        // is pixel-identical to the effect being off.
        let strengths = customization.strengths.clamped
        var output = input
        // v5.2 F-EXP: exposure is linear light scaled by 2^EV ahead of
        // everything else. With a stock the gain rides inside the cube (and
        // halation reads the exposed light), so the film's shoulder rolls
        // highlights off; with stock Off it is a plain linear gain.
        let exposureGain = customization.exposureGain
        if stock == .none, exposureGain != 1 {
            output = applyLinearGain(to: output, gain: exposureGain)
        }
        if let negative = stock.negative, let printProfile = customization.resolvedPrint?.profile {
            let monochrome = customization.rendersInBlackAndWhite
            if monochrome {
                output = luminance(of: output, weights: negative.monoWeights)
            }
            if strengths.halation > 0 {
                output = applyHalation(
                    to: output, strength: stock.halationStrength * strengths.halation, outputWidth: outputWidth,
                    exposureGain: exposureGain
                )
            }
            output = applyFilmCube(
                negative: negative, print: printProfile, monochrome: monochrome, exposureGain: exposureGain, to: output
            )
        } else if customization.blackAndWhite {
            // No stock: the plain B&W look from v1, unchanged
            let mono = CIFilter.photoEffectMono()
            mono.inputImage = output
            output = mono.outputImage ?? skipping("B&W (no stock)", output)
        }
        if stock != .none {
            // v5 F5 overturns OPEN: v4-4: the vignette sits after the cube,
            // on the printed picture, and defaults to 0
            if strengths.vignette > 0 {
                output = applyVignette(to: output, strength: strengths.vignette)
            }
            if strengths.haze > 0 {
                output = applyBloom(to: output, outputWidth: outputWidth, strength: strengths.haze)
            }
            if strengths.lightLeak > 0 {
                output = applyLightLeak(
                    to: output,
                    seed: SeededRandom.derive(seed, salt: Constants.ImageProcessing.Film.lightLeakSeedSalt),
                    strength: strengths.lightLeak
                )
            }
            output = addGrain(
                to: output,
                // The strength scales the stock's own intensity; 0 returns
                // the input untouched (addGrain skips a zero intensity)
                intensity: stock.grainIntensity * strengths.grain,
                // The strip passes 1: its grain is tuned at slot size
                sizePixels: stock.grainSizePixels * grainScale,
                monochrome: customization.rendersInBlackAndWhite,
                seed: SeededRandom.derive(seed, salt: Constants.ImageProcessing.Film.grainSeedSalt),
                profile: stock.grainProfile
            )
        }
        return output.cropped(to: input.extent)
    }

    // Filtering a 12 MP capture for a 260 px slot spent nearly all its time on
    // pixels that were thrown away when the strip drew it smaller. Resizing
    // first makes every later effect cost output pixels only, and lets grain
    // and blur sizes be stated directly in output pixels (v4 F1).
    /// Aspect-fills `image` into the strip slot for `outputWidth` and
    /// centre-crops it, returning an image whose extent starts at the origin.
    static func resizedToSlot(_ image: CIImage, outputWidth: CGFloat) -> CIImage? {
        let source = image.extent
        let width = outputWidth.rounded()
        let height = (outputWidth / Constants.Strip.cellAspectRatio).rounded()
        guard
            source.width > 0, source.height > 0, !source.isInfinite,
            width >= 1, height >= 1
        else {
            return nil
        }

        let scale = max(width / source.width, height / source.height)
        let lanczos = CIFilter.lanczosScaleTransform()
        // Clamping first stops the resampler pulling transparent black in
        // from outside the photo, which would darken the slot's edges.
        lanczos.inputImage = image
            .transformed(by: CGAffineTransform(translationX: -source.minX, y: -source.minY))
            .clampedToExtent()
        lanczos.scale = Float(scale)
        lanczos.aspectRatio = 1
        guard let scaled = lanczos.outputImage else { return nil }

        let crop = CGRect(
            x: ((source.width * scale - width) / 2).rounded(.down),
            y: ((source.height * scale - height) / 2).rounded(.down),
            width: width,
            height: height
        )
        return scaled
            .cropped(to: crop)
            .transformed(by: CGAffineTransform(translationX: -crop.minX, y: -crop.minY))
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

    // MARK: Halation (v4 F4)

    /// Adds the red-orange glow that light bouncing off the film base leaves
    /// around highlights. Works in linear light on the scene side of the
    /// cube, so the glow goes through the film's shoulder like real light.
    /// A strength of 0, or an image with nothing above the threshold, adds
    /// exactly nothing.
    ///
    /// - Parameter exposureGain: the 2^EV exposure (v5.2) the cube will
    ///   apply to this image. The key reads the exposed light (`input ×
    ///   gain`) and the glow is divided by the gain, so after the cube's own
    ///   gain it adds exactly what it would add to exposed light. 1 is the
    ///   unexposed behaviour, bit for bit.
    static func applyHalation(
        to input: CIImage, strength strengthIn: Double, outputWidth: CGFloat, exposureGain: Double = 1
    ) -> CIImage {
        typealias F = Constants.ImageProcessing.Film
        guard strengthIn > 0 else { return input }
        let strength = exposureGain == 1 ? strengthIn : strengthIn / exposureGain
        let extent = input.extent
        let t = F.halationThreshold
        let weights = F.Spectral.panchromatic

        // Highlight key: max(0, L − t) / (1 − t), as a grey image
        let gain = 1 / (1 - t)
        let keyScale = gain * exposureGain
        let row = CIVector(
            x: CGFloat(weights.r * keyScale), y: CGFloat(weights.g * keyScale), z: CGFloat(weights.b * keyScale), w: 0
        )
        let keyMatrix = CIFilter.colorMatrix()
        keyMatrix.inputImage = input
        keyMatrix.rVector = row
        keyMatrix.gVector = row
        keyMatrix.bVector = row
        keyMatrix.aVector = CIVector(x: 0, y: 0, z: 0, w: 1)
        keyMatrix.biasVector = CIVector(x: CGFloat(-t * gain), y: CGFloat(-t * gain), z: CGFloat(-t * gain), w: 0)
        let clamp = CIFilter.colorClamp()
        clamp.inputImage = keyMatrix.outputImage
        clamp.minComponents = CIVector(x: 0, y: 0, z: 0, w: 0)
        clamp.maxComponents = CIVector(x: 1, y: 1, z: 1, w: 1)
        guard let key = clamp.outputImage else { return skipping("Halation key", input) }

        let blur = CIFilter.gaussianBlur()
        blur.inputImage = key.clampedToExtent()
        blur.radius = Float(F.halationRadiusFraction * Double(outputWidth))
        guard let spread = blur.outputImage?.cropped(to: extent) else { return skipping("Halation blur", input) }

        let tint = CIFilter.colorMatrix()
        tint.inputImage = spread
        tint.rVector = CIVector(x: CGFloat(F.halationTint.r * strength), y: 0, z: 0, w: 0)
        tint.gVector = CIVector(x: 0, y: CGFloat(F.halationTint.g * strength), z: 0, w: 0)
        tint.bVector = CIVector(x: 0, y: 0, z: CGFloat(F.halationTint.b * strength), w: 0)
        tint.aVector = CIVector(x: 0, y: 0, z: 0, w: 1)
        guard let glow = tint.outputImage else { return skipping("Halation tint", input) }

        // Linear dodge is plain S + D on opaque images. CIAdditionCompositing
        // would also add the alphas, and a zero-alpha glow is wiped out by
        // CIColorMatrix's premultiply, so neither works for an additive light.
        let add = CIFilter.linearDodgeBlendMode()
        add.inputImage = glow
        add.backgroundImage = input
        return add.outputImage?.cropped(to: extent) ?? skipping("Halation blend", input)
    }

    // MARK: Exposure (v5.2 F-EXP)

    /// A plain gain on linear light (stock Off). Alpha is untouched.
    static func applyLinearGain(to input: CIImage, gain: Double) -> CIImage {
        guard gain != 1 else { return input }
        let g = CGFloat(gain)
        let matrix = CIFilter.colorMatrix()
        matrix.inputImage = input
        matrix.rVector = CIVector(x: g, y: 0, z: 0, w: 0)
        matrix.gVector = CIVector(x: 0, y: g, z: 0, w: 0)
        matrix.bVector = CIVector(x: 0, y: 0, z: g, w: 0)
        matrix.aVector = CIVector(x: 0, y: 0, z: 0, w: 1)
        return matrix.outputImage ?? skipping("Exposure gain", input)
    }

    // MARK: Film model (v4 F2/F3)

    // Linear-light luminance with the emulsion's own spectral weights. The
    // cube would compute the same thing, but doing it first means later
    // effects that run before the cube (halation, F4) already see monochrome.
    private static func luminance(of input: CIImage, weights: SpectralWeights) -> CIImage {
        let row = CIVector(x: CGFloat(weights.r), y: CGFloat(weights.g), z: CGFloat(weights.b), w: 0)
        let matrix = CIFilter.colorMatrix()
        matrix.inputImage = input
        matrix.rVector = row
        matrix.gVector = row
        matrix.bVector = row
        matrix.aVector = CIVector(x: 0, y: 0, z: 0, w: 1)
        return matrix.outputImage ?? skipping("Luminance", input)
    }

    // The negative→print chain is baked into a colour cube by the pure
    // FilmLUT, so the pixels come from exactly the maths the tests check.
    // OPEN: v4-8 — cube, not a Metal CIColorKernel
    // (Constants.ImageProcessing.Film.usesColourCube); switch only if
    // profiling shows the cube build or lookup is the bottleneck.
    // sRGB colour space: the cube is indexed by gamma-encoded values, which
    // spend its 64 steps evenly across what the eye sees.
    private static func applyFilmCube(
        negative: NegativeProfile,
        print printProfile: PrintProfile,
        monochrome: Bool,
        exposureGain: Double = 1,
        to input: CIImage
    ) -> CIImage {
        let dimension = Constants.ImageProcessing.Film.lutDimension
        let cube = CIFilter.colorCubeWithColorSpace()
        cube.inputImage = input
        cube.cubeDimension = Float(dimension)
        cube.cubeData = FilmLUT.cachedCube(
            negative: negative, print: printProfile, monochrome: monochrome, exposureGain: exposureGain, dimension: dimension
        )
        cube.colorSpace = stripOutputColorSpace
        return cube.outputImage ?? skipping("Film cube", input)
    }

    // MARK: Vignette (v5 F5)

    /// Darkens the corners of the printed picture: a multiply by a radial
    /// gradient that is white inside `vignetteInnerRadiusFraction` of the
    /// half-diagonal and falls to `1 − vignetteDarkening × strength` at the
    /// outer radius. Strength 0 returns the input untouched; the falloff
    /// never brightens, and neither the centre nor the seed matter, so a
    /// re-render is identical.
    static func applyVignette(to input: CIImage, strength: Double) -> CIImage {
        typealias S = Constants.ImageProcessing.Film.Strength
        guard strength > 0 else { return input }
        let extent = input.extent
        let halfDiagonal = 0.5 * (extent.width * extent.width + extent.height * extent.height).squareRoot()
        let corner = min(max(1 - S.vignetteDarkening * strength, 0), 1)
        let gradient = CIFilter.radialGradient()
        gradient.center = CGPoint(x: extent.midX, y: extent.midY)
        gradient.radius0 = Float(S.vignetteInnerRadiusFraction * halfDiagonal)
        gradient.radius1 = Float(S.vignetteOuterRadiusFraction * halfDiagonal)
        gradient.color0 = CIColor(red: 1, green: 1, blue: 1, alpha: 1)
        gradient.color1 = CIColor(red: corner, green: corner, blue: corner, alpha: 1)
        let multiply = CIFilter.multiplyCompositing()
        multiply.inputImage = gradient.outputImage?.cropped(to: extent)
        multiply.backgroundImage = input
        return multiply.outputImage?.cropped(to: extent) ?? skipping("Vignette", input)
    }

    // MARK: Bloom and light leak (v4 F6)

    /// Mist-filter bloom: a blurred copy screened back at `bloomStrength`.
    /// Highlights spread and contrast drops a little while detail stays
    /// sharp, because the original is never blurred. Screen only brightens.
    /// - Parameter strength: scales the screen amount (v5 F5); 1 is the v4
    ///   bloom, 0 returns the input untouched.
    static func applyBloom(to input: CIImage, outputWidth: CGFloat, strength scale: Double = 1) -> CIImage {
        typealias F = Constants.ImageProcessing.Film
        guard scale > 0 else { return input }
        let extent = input.extent
        let blur = CIFilter.gaussianBlur()
        blur.inputImage = input.clampedToExtent()
        blur.radius = Float(F.bloomRadiusFraction * Double(outputWidth))
        let strength = CGFloat(F.bloomStrength * scale)
        let fade = CIFilter.colorMatrix()
        fade.inputImage = blur.outputImage?.cropped(to: extent)
        fade.rVector = CIVector(x: strength, y: 0, z: 0, w: 0)
        fade.gVector = CIVector(x: 0, y: strength, z: 0, w: 0)
        fade.bVector = CIVector(x: 0, y: 0, z: strength, w: 0)
        let screen = CIFilter.screenBlendMode()
        screen.inputImage = fade.outputImage
        screen.backgroundImage = input
        return screen.outputImage?.cropped(to: extent) ?? skipping("Bloom", input)
    }

    /// Procedural light leak: warm radial glows centred just outside a
    /// seeded frame edge, screened over the photo. No image assets. Each
    /// glow fades to black, and screening black changes nothing, so a leak
    /// can only brighten.
    /// - Parameter strength: scales every glow's brightness (v5 F5); 1 is
    ///   the v4 leak, 0 returns the input untouched. The glows' positions
    ///   come from the seed alone, so strength never moves them.
    static func applyLightLeak(to input: CIImage, seed: UInt64, strength: Double = 1) -> CIImage {
        typealias F = Constants.ImageProcessing.Film
        guard strength > 0 else { return input }
        let extent = input.extent
        let linear = CGColorSpace(name: CGColorSpace.linearSRGB) ?? CGColorSpaceCreateDeviceRGB()
        let spots = LightLeak.spots(seed: seed, width: Double(extent.width), height: Double(extent.height))
        var output = input
        for spot in spots {
            let s = F.lightLeakStrength * strength
            guard
                let inner = CIColor(
                    red: CGFloat(spot.red * s), green: CGFloat(spot.green * s), blue: CGFloat(spot.blue * s),
                    alpha: 1, colorSpace: linear
                ),
                let outer = CIColor(red: 0, green: 0, blue: 0, alpha: 1, colorSpace: linear)
            else {
                _ = skipping("Light leak colour", output)
                continue
            }
            let gradient = CIFilter.radialGradient()
            gradient.center = CGPoint(x: extent.minX + spot.centreX, y: extent.minY + spot.centreY)
            gradient.radius0 = 0
            gradient.radius1 = Float(spot.radius)
            gradient.color0 = inner
            gradient.color1 = outer
            let screen = CIFilter.screenBlendMode()
            screen.inputImage = gradient.outputImage?.cropped(to: extent)
            screen.backgroundImage = output
            output = screen.outputImage?.cropped(to: extent) ?? skipping("Light leak blend", output)
        }
        return output
    }

    // MARK: Grain v2 (v4 F5)

    /// Density-shaped, mean-preserving film grain.
    ///
    /// Grain is a fluctuation in how much light the print passes, so it
    /// multiplies linear light: out = in · (1 + a · g), with g zero-mean noise
    /// in −1…1 and a the amplitude. The mean of a flat patch is unchanged and
    /// the result never goes negative, unlike adding noise, which clips at
    /// black and brightens the shadows on average. a follows the print's
    /// density through `grainDensityCurve`, applied after the curves so it
    /// sees the density the viewer sees.
    static func addGrain(
        to input: CIImage,
        intensity: Double,
        sizePixels: Double,
        monochrome: Bool,
        seed: UInt64,
        profile: GrainProfile = Constants.ImageProcessing.Film.Grain.standard
    ) -> CIImage {
        typealias F = Constants.ImageProcessing.Film
        guard intensity > 0 else { return input }
        let sizePixels = sizePixels * profile.sizeScale
        guard let noise = CIFilter.randomGenerator().outputImage else { return skipping("Grain noise", input) }
        let extent = input.extent
        var random = SeededRandom(seed: seed)

        // One octave: the noise tile shifted by a seeded whole-pixel offset,
        // scaled to grain size, mixed toward monochrome and weighted. Every
        // intermediate stays non-negative: Core Image's blend filters clamp
        // negative values, which would bias the grain bright.
        func octave(size: Double, weight: Double) -> CIImage? {
            let dx = CGFloat(random.next() % F.grainSeedOffsetRange)
            let dy = CGFloat(random.next() % F.grainSeedOffsetRange)
            let scale = CGFloat(max(size, 1))
            // CIRandomGenerator randomises alpha too; colour filters would
            // unpremultiply by it and skew the noise, so make it opaque first
            let tile = noise
                .transformed(by: CGAffineTransform(translationX: -dx, y: -dy))
                .transformed(by: CGAffineTransform(scaleX: scale, y: scale))
                .settingAlphaOne(in: extent)
            // Mono grain takes every channel from red; colour grain keeps a
            // `grainChroma` share of each dye layer's own noise
            let chroma = monochrome ? 0 : F.grainChroma
            let shared = (1 - chroma) * weight
            let own = chroma * weight
            let mix = CIFilter.colorMatrix()
            mix.inputImage = tile
            mix.rVector = CIVector(x: CGFloat(weight), y: 0, z: 0, w: 0)
            mix.gVector = CIVector(x: CGFloat(shared), y: CGFloat(own), z: 0, w: 0)
            mix.bVector = CIVector(x: CGFloat(shared), y: 0, z: CGFloat(own), w: 0)
            mix.aVector = CIVector(x: 0, y: 0, z: 0, w: 1)
            return mix.outputImage?.cropped(to: extent)
        }
        guard
            let fine = octave(size: sizePixels, weight: profile.fineWeight),
            let coarse = octave(size: sizePixels * profile.coarseSizeMultiplier, weight: profile.coarseWeight),
            let amplitude = grainAmplitudeMask(for: input, intensity: intensity, curve: profile.densityCurve)
        else {
            return skipping("Grain octaves or amplitude mask", input)
        }

        // n: the two octaves summed, uniform-ish in 0…1 with mean 0.5
        let sum = CIFilter.linearDodgeBlendMode()
        sum.inputImage = fine
        sum.backgroundImage = coarse
        guard let n = sum.outputImage else { return skipping("Grain octave sum", input) }

        // in·(1 + a·(2n − 1)) = in·(1 − a) + in·(2a·n), both terms positive
        let keep = CIFilter.colorMatrix()
        keep.inputImage = amplitude
        keep.rVector = CIVector(x: -1, y: 0, z: 0, w: 0)
        keep.gVector = CIVector(x: 0, y: -1, z: 0, w: 0)
        keep.bVector = CIVector(x: 0, y: 0, z: -1, w: 0)
        keep.biasVector = CIVector(x: 1, y: 1, z: 1, w: 0)
        let doubled = CIFilter.colorMatrix()
        doubled.inputImage = amplitude
        doubled.rVector = CIVector(x: 2, y: 0, z: 0, w: 0)
        doubled.gVector = CIVector(x: 0, y: 2, z: 0, w: 0)
        doubled.bVector = CIVector(x: 0, y: 0, z: 2, w: 0)

        let grain = CIFilter.multiplyCompositing()
        grain.inputImage = n
        grain.backgroundImage = doubled.outputImage
        let term1 = CIFilter.multiplyCompositing()
        term1.inputImage = keep.outputImage
        term1.backgroundImage = input
        let term2 = CIFilter.multiplyCompositing()
        term2.inputImage = grain.outputImage
        term2.backgroundImage = input
        let total = CIFilter.linearDodgeBlendMode()
        total.inputImage = term2.outputImage
        total.backgroundImage = term1.outputImage
        return total.outputImage?.cropped(to: extent) ?? skipping("Grain blend", input)
    }

    /// Every cosmetic stage falls back to its input when Core Image cannot
    /// build it. Logging the stage keeps a missing effect diagnosable on a
    /// device instead of silently vanishing from the strip.
    private static func skipping(_ stage: String, _ input: CIImage) -> CIImage {
        print("[ImageProcessor] \(stage) failed; skipping")
        return input
    }

    /// Grey image holding the grain amplitude per pixel: the density curve
    /// read at the pixel's luminance, times the stock's intensity.
    private static func grainAmplitudeMask(for input: CIImage, intensity: Double, curve: [Double]) -> CIImage? {
        let weights = Constants.ImageProcessing.Film.Spectral.panchromatic
        let luminance = self.luminance(of: input, weights: weights)

        let curves = CIFilter.colorCurves()
        curves.inputImage = luminance
        curves.curvesDomain = CIVector(x: 0, y: 1)
        curves.curvesData = grainCurveData(curve)
        curves.colorSpace = stripOutputColorSpace
        guard let weight = curves.outputImage else { return nil }

        let scale = CIFilter.colorMatrix()
        scale.inputImage = weight
        scale.rVector = CIVector(x: CGFloat(intensity), y: 0, z: 0, w: 0)
        scale.gVector = CIVector(x: 0, y: CGFloat(intensity), z: 0, w: 0)
        scale.bVector = CIVector(x: 0, y: 0, z: CGFloat(intensity), w: 0)
        return scale.outputImage?.cropped(to: input.extent)
    }

    // CIColorCurves takes an evenly spaced RGB lookup table as raw Float32
    // data; the same weight goes in all three channels.
    // 64 entries: cheap enough to build per render rather than cache per stock
    private static func grainCurveData(_ curve: [Double]) -> Data {
        let values = FilmGrain.amplitudeTable(curve: curve)
        var floats: [Float] = []
        floats.reserveCapacity(values.count * 3)
        for value in values {
            floats.append(contentsOf: [value, value, value])
        }
        return floats.withUnsafeBufferPointer { Data(buffer: $0) }
    }

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

    // Float working space in, 8-bit sRGB out: the strip is drawn into an
    // ordinary UIGraphicsImageRenderer, so there is no point keeping half floats.
    private static func renderStrip(_ image: CIImage) throws -> UIImage {
        guard let cgImage = stripContext.createCGImage(
            image,
            from: image.extent,
            format: .RGBA8,
            colorSpace: stripOutputColorSpace
        ) else {
            throw AppError.stripRenderFailed
        }
        return UIImage(cgImage: cgImage, scale: 1, orientation: .up)
    }
}

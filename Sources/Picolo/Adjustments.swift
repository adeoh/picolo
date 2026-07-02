import CoreImage
import CoreImage.CIFilterBuiltins

/// The full set of non-destructive edits Picolo applies to an image.
///
/// Values use neutral defaults so that an untouched `Adjustments` is the
/// identity transform — `apply(to:)` on a freshly created value returns the
/// input image unchanged.
struct Adjustments: Equatable {
    // Geometry — orientation is one of the 8 EXIF/dihedral states, crop is a
    // normalized (0…1, bottom-left origin like Core Image) rect within the
    // oriented image. Both neutral by default.
    var orientation: CGImagePropertyOrientation = .up
    var cropRect: CGRect = Adjustments.fullCrop

    static let fullCrop = CGRect(x: 0, y: 0, width: 1, height: 1)

    var brightness: Double = 0      // CIColorControls: -1 ... 1, neutral 0
    var contrast: Double = 1        // CIColorControls: 0.25 ... 4, neutral 1
    var saturation: Double = 1      // CIColorControls: 0 ... 2, neutral 1
    var exposure: Double = 0        // CIExposureAdjust EV: -3 ... 3, neutral 0
    var highlights: Double = 1      // CIHighlightShadowAdjust: 0 ... 1, neutral 1
    var shadows: Double = 0         // CIHighlightShadowAdjust: -1 ... 1, neutral 0
    var temperature: Double = 0     // offset around 6500K neutral: -2000 ... 2000

    // Motion blur — directional blur with a strength (radius) and direction (angle).
    var motionBlurRadius: Double = 0    // CIMotionBlur radius in px: 0 ... 100, neutral 0
    var motionBlurAngle: Double = 0     // direction in degrees: -180 ... 180, neutral 0

    // Levels — input/output remap with a midtone gamma, all neutral by default.
    var inputBlack: Double = 0      // 0 ... 1, neutral 0
    var inputWhite: Double = 1      // 0 ... 1, neutral 1
    var midtones: Double = 1        // 0.1 ... 3, neutral 1 (>1 brightens midtones)
    var outputBlack: Double = 0     // 0 ... 1, neutral 0
    var outputWhite: Double = 1     // 0 ... 1, neutral 1

    static let neutral = Adjustments()

    var isNeutral: Bool { self == .neutral }

    /// Applies the pipeline to `input` and returns the edited image.
    /// Order is geometry → exposure → tone/color → highlight-shadow → white
    /// balance → gamma.
    func apply(to input: CIImage) -> CIImage {
        var image = applyGeometry(to: input)
        let extent = image.extent

        if exposure != 0 {
            let f = CIFilter.exposureAdjust()
            f.inputImage = image
            f.ev = Float(exposure)
            image = f.outputImage ?? image
        }

        if brightness != 0 || contrast != 1 || saturation != 1 {
            let f = CIFilter.colorControls()
            f.inputImage = image
            f.brightness = Float(brightness)
            f.contrast = Float(contrast)
            f.saturation = Float(saturation)
            image = f.outputImage ?? image
        }

        if highlights != 1 || shadows != 0 {
            let f = CIFilter.highlightShadowAdjust()
            f.inputImage = image
            f.highlightAmount = Float(highlights)
            f.shadowAmount = Float(shadows)
            image = f.outputImage ?? image
        }

        if temperature != 0 {
            let f = CIFilter.temperatureAndTint()
            f.inputImage = image
            f.neutral = CIVector(x: 6500, y: 0)
            f.targetNeutral = CIVector(x: 6500 + temperature, y: 0)
            image = f.outputImage ?? image
        }

        image = applyLevels(to: image)

        if motionBlurRadius > 0 {
            // Clamp first so the blur samples real edge pixels instead of fading
            // into transparency at the borders.
            let f = CIFilter.motionBlur()
            f.inputImage = image.clampedToExtent()
            f.radius = Float(motionBlurRadius)
            f.angle = Float(motionBlurAngle * .pi / 180)
            image = f.outputImage ?? image
        }

        // Clamp back to the post-geometry extent; some filters expand it.
        return image.cropped(to: extent)
    }

    // MARK: - Geometry

    /// Orients (rotate/flip) then crops. Runs before any color work so all
    /// tonal filters only ever see the pixels that survive.
    private func applyGeometry(to input: CIImage) -> CIImage {
        var image = input
        if orientation != .up {
            image = image.oriented(orientation)
        }
        if cropRect != Adjustments.fullCrop {
            let e = image.extent
            let r = CGRect(x: e.minX + cropRect.minX * e.width,
                           y: e.minY + cropRect.minY * e.height,
                           width: cropRect.width * e.width,
                           height: cropRect.height * e.height)
                .integral.intersection(e)
            if !r.isEmpty { image = image.cropped(to: r) }
        }
        return image
    }

    /// Orientation composition in display space: `next` applied on top of what
    /// the user already sees. The 8 EXIF orientations form the dihedral group,
    /// so every rotate/flip sequence stays representable.
    mutating func rotate(clockwise: Bool) {
        let cw: [CGImagePropertyOrientation: CGImagePropertyOrientation] = [
            .up: .right, .right: .down, .down: .left, .left: .up,
            .upMirrored: .rightMirrored, .rightMirrored: .downMirrored,
            .downMirrored: .leftMirrored, .leftMirrored: .upMirrored,
        ]
        let table = clockwise ? cw : Dictionary(uniqueKeysWithValues: cw.map { ($1, $0) })
        orientation = table[orientation] ?? orientation
        cropRect = Adjustments.rotateCrop(cropRect, clockwise: clockwise)
    }

    mutating func flip(horizontal: Bool) {
        let flipH: [CGImagePropertyOrientation: CGImagePropertyOrientation] = [
            .up: .upMirrored, .upMirrored: .up, .down: .downMirrored, .downMirrored: .down,
            .right: .leftMirrored, .leftMirrored: .right, .left: .rightMirrored, .rightMirrored: .left,
        ]
        let flipV: [CGImagePropertyOrientation: CGImagePropertyOrientation] = [
            .up: .downMirrored, .downMirrored: .up, .down: .upMirrored, .upMirrored: .down,
            .right: .rightMirrored, .rightMirrored: .right, .left: .leftMirrored, .leftMirrored: .left,
        ]
        let table = horizontal ? flipH : flipV
        orientation = table[orientation] ?? orientation
        cropRect = Adjustments.flipCrop(cropRect, horizontal: horizontal)
    }

    /// The crop is defined within the oriented image, so re-orienting must
    /// carry the crop window along or the visible framing would jump.
    private static func rotateCrop(_ c: CGRect, clockwise: Bool) -> CGRect {
        guard c != fullCrop else { return c }
        // CI space is y-up. Rotating the image 90° CW maps a point (x, y) of
        // the old unit square to (y, 1 - x) in the new one; CCW is the inverse.
        return clockwise
            ? CGRect(x: c.minY, y: 1 - c.maxX, width: c.height, height: c.width)
            : CGRect(x: 1 - c.maxY, y: c.minX, width: c.height, height: c.width)
    }

    private static func flipCrop(_ c: CGRect, horizontal: Bool) -> CGRect {
        guard c != fullCrop else { return c }
        return horizontal
            ? CGRect(x: 1 - c.maxX, y: c.minY, width: c.width, height: c.height)
            : CGRect(x: c.minX, y: 1 - c.maxY, width: c.width, height: c.height)
    }

    private var levelsAreNeutral: Bool {
        inputBlack == 0 && inputWhite == 1 && midtones == 1
            && outputBlack == 0 && outputWhite == 1
    }

    /// Photoshop-style levels: remap [inputBlack, inputWhite] → [0, 1], apply a
    /// midtone gamma, then remap [0, 1] → [outputBlack, outputWhite].
    ///
    /// Levels values are display-referred (0…1 == the gamma-encoded pixel the
    /// user sees), but Core Image's working space is linear light. So the whole
    /// stage runs in sRGB-encoded space — encode in, do the math, decode out —
    /// otherwise an Input Black of 0.25 would clip mid-gray to black.
    private func applyLevels(to input: CIImage) -> CIImage {
        guard !levelsAreNeutral else { return input }
        var image = encodeToSRGB(input)

        // Input remap: scale·x + bias, with white kept above black to avoid /0.
        if inputBlack != 0 || inputWhite != 1 {
            let white = max(inputWhite, inputBlack + 0.0001)
            let scale = 1.0 / (white - inputBlack)
            let bias = -inputBlack * scale
            image = colorScale(image, scale: scale, bias: bias)
            // Levels can push values out of range; clamp so gamma stays defined.
            let clamp = CIFilter.colorClamp()
            clamp.inputImage = image
            clamp.minComponents = CIVector(x: 0, y: 0, z: 0, w: 0)
            clamp.maxComponents = CIVector(x: 1, y: 1, z: 1, w: 1)
            image = clamp.outputImage ?? image
        }

        // Midtone gamma. CIGammaAdjust raises to `power`, so invert so that
        // midtones > 1 brightens, matching the slider's direction.
        if midtones != 1 {
            let g = CIFilter.gammaAdjust()
            g.inputImage = image
            g.power = Float(1.0 / midtones)
            image = g.outputImage ?? image
        }

        // Output remap into [outputBlack, outputWhite].
        if outputBlack != 0 || outputWhite != 1 {
            image = colorScale(image, scale: outputWhite - outputBlack, bias: outputBlack)
        }

        return decodeFromSRGB(image)
    }

    private func encodeToSRGB(_ image: CIImage) -> CIImage {
        let f = CIFilter.linearToSRGBToneCurve()
        f.inputImage = image
        return f.outputImage ?? image
    }

    private func decodeFromSRGB(_ image: CIImage) -> CIImage {
        let f = CIFilter.sRGBToneCurveToLinear()
        f.inputImage = image
        return f.outputImage ?? image
    }

    /// Per-channel affine remap (RGB only; alpha untouched) via CIColorMatrix.
    private func colorScale(_ image: CIImage, scale: Double, bias: Double) -> CIImage {
        let s = CGFloat(scale)
        let b = CGFloat(bias)
        let f = CIFilter.colorMatrix()
        f.inputImage = image
        f.rVector = CIVector(x: s, y: 0, z: 0, w: 0)
        f.gVector = CIVector(x: 0, y: s, z: 0, w: 0)
        f.bVector = CIVector(x: 0, y: 0, z: s, w: 0)
        f.aVector = CIVector(x: 0, y: 0, z: 0, w: 1)
        f.biasVector = CIVector(x: b, y: b, z: b, w: 0)
        return f.outputImage ?? image
    }
}

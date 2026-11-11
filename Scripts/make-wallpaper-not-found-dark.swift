// make-wallpaper-not-found-dark.swift: draws the Dark Mode "Wallpaper Not Found" video,
// OpenWallpaperEngine/Resources/WallpaperNotFoundDark.mp4, frame by frame. Nothing else is needed:
// CoreGraphics and CoreImage draw, CoreText sets the text, AVFoundation encodes.
//
//   swiftc -O Scripts/make-wallpaper-not-found-dark.swift -o <scratch>/make-dark
//   <scratch>/make-dark [output.mp4] [--previews <folder>] [--no-video]
//
// The look: true black, soft diagonal light streaks at the light video's slant in greys and white,
// faint pink and teal tints in a few of them, drifting slowly. Every motion completes a whole
// number of cycles in `PlaceholderFrame.duration`, so the video loops without a seam. The text is
// the light video's: six strings, 5 s each, revealed left to right out of a blur, held, then blurred
// away left to right.
//
// `PlaceholderFrame.draw(at:size:in:)` is a pure function of the time and the size, so the app
// could draw the placeholder live with the same code.

import AVFoundation
import CoreGraphics
import CoreImage
import CoreText
import Foundation

enum PlaceholderFrame {
    static let duration = 30.0
    static let strings = [
        "Wallpaper Not Found",
        "未找到壁纸",
        "壁紙が見つかりません",
        "배경화면을 찾을 수 없습니다",
        "Fondo de pantalla no encontrado",
        "वॉलपेपर नहीं मिला",
    ]
    /// Each string's share of the loop.
    static let slot = duration / Double(strings.count)

    // MARK: Streaks

    /// One soft streak: an ellipse, long along the slant, lit by a radial falloff.
    struct Streak {
        var x: Double, y: Double          // centre, in units of the height (x from the left)
        var length: Double, width: Double // in units of the height
        var angle: Double                 // radians, counter-clockwise from the x axis
        var color: (Double, Double, Double)
        var alpha: Double
        var drift: Double                 // amplitude along the slant, in units of the height
        var sway: Double                  // amplitude across it
        var cycles: Int                   // whole cycles per loop
        var phase: Double
        var pulse: Double                 // brightness swing, 0…1
    }

    /// The light video's slant: streaks rise to the right at about 24°.
    static let slant = 24.0 * .pi / 180

    static let streaks: [Streak] = {
        var generator = SplitMix(seed: 0x0E_57A9)
        let white = (1.0, 1.0, 1.0)
        let grey = (0.78, 0.78, 0.8)
        let pink = (1.0, 0.6, 0.82)    // the light video's magenta, as a faint tint
        let teal = (0.55, 0.9, 0.88)   // and its cyan
        var result: [Streak] = []
        // Three layers, as in the light video: broad soft glows, medium bands, fine lines. Most of
        // the light sits low and to the right; the upper left stays dark.
        let layers: [(count: Int, width: ClosedRange<Double>, length: ClosedRange<Double>, alpha: ClosedRange<Double>)] = [
            (7, 0.28...0.6, 1.6...2.4, 0.14...0.26),
            (14, 0.04...0.13, 0.9...1.8, 0.1...0.28),
            (22, 0.005...0.02, 0.5...1.5, 0.08...0.3),
        ]
        var index = 0
        for layer in layers {
            for _ in 0..<layer.count {
                func pick(_ range: ClosedRange<Double>, _ curve: Double = 1) -> Double {
                    range.lowerBound + (range.upperBound - range.lowerBound) * pow(generator.next, curve)
                }
                let x = layer.count == 7 ? 0.7 + 1.2 * generator.next : -0.2 + 2.0 * generator.next
                let y = 0.3 + 0.8 * pow(generator.next, 0.6) + (x / 1.78) * 0.2
                let color = index % 8 == 2 ? pink : index % 9 == 6 ? teal : (generator.next < 0.55 ? white : grey)
                result.append(Streak(
                    x: x, y: y,
                    length: pick(layer.length), width: pick(layer.width, 1.6),
                    angle: slant + (generator.next - 0.5) * 0.08,
                    color: color, alpha: pick(layer.alpha, 1.4),
                    drift: 0.04 + 0.14 * generator.next,
                    sway: 0.005 + 0.025 * generator.next,
                    cycles: 1 + Int(generator.next * 2.99),
                    phase: generator.next * 2 * .pi,
                    pulse: 0.2 + 0.5 * generator.next))
                index += 1
            }
        }
        return result
    }()

    // MARK: Drawing

    /// Draws the frame at `time` (seconds, any value: the loop repeats) filling `size` in `context`,
    /// whose origin is the bottom left.
    static func draw(at time: Double, size: CGSize, in context: CGContext) {
        let t = time.truncatingRemainder(dividingBy: duration) + (time < 0 ? duration : 0)
        context.saveGState()
        context.setFillColor(CGColor(gray: 0, alpha: 1))
        context.fill(CGRect(origin: .zero, size: size))
        drawStreaks(at: t, size: size, in: context)
        drawText(at: t, size: size, in: context)
        context.restoreGState()
    }

    /// A soft falloff in `color`: bright core, long tail.
    private static func streakGradient(_ color: (Double, Double, Double)) -> CGGradient {
        let stops: [CGFloat] = [0, 0.25, 0.55, 1]
        let alphas: [CGFloat] = [1, 0.55, 0.16, 0]
        var components: [CGFloat] = []
        for a in alphas { components += [CGFloat(color.0), CGFloat(color.1), CGFloat(color.2), a] }
        return CGGradient(colorSpace: CGColorSpace(name: CGColorSpace.sRGB)!, colorComponents: components,
                          locations: stops, count: stops.count)!
    }

    private static let gradients: [CGGradient] = streaks.map { streakGradient($0.color) }

    private static func drawStreaks(at t: Double, size: CGSize, in context: CGContext) {
        let h = Double(size.height)
        context.saveGState()
        context.setBlendMode(.plusLighter)
        for (s, gradient) in zip(streaks, gradients) {
            let angle = 2 * Double.pi * Double(s.cycles) * t / duration + s.phase
            let along = s.drift * sin(angle)
            let across = s.sway * cos(angle)
            // Placed from the top left; CoreGraphics counts up from the bottom, where a positive
            // angle rises to the right.
            let cx = (s.x + along * cos(s.angle) - across * sin(s.angle)) * h
            let cy = (1 - s.y + along * sin(s.angle) + across * cos(s.angle)) * h
            let glow = s.alpha * (1 - s.pulse * 0.5 + s.pulse * 0.5 * sin(angle + 1.3))
            context.saveGState()
            context.translateBy(x: cx, y: cy)
            context.rotate(by: s.angle)
            context.scaleBy(x: s.length * h / 2, y: s.width * h / 2)
            context.setAlpha(glow)
            context.drawRadialGradient(gradient, startCenter: .zero, startRadius: 0,
                                       endCenter: .zero, endRadius: 1, options: [])
            context.restoreGState()
        }
        context.restoreGState()
    }

    // MARK: Text

    /// The light video's text: about 0.349 of the width for "Wallpaper Not Found", its middle at
    /// 0.479 of the height from the top.
    static let referenceWidth = 0.349
    static let centreFromTop = 0.479

    /// The string shown at `t`, how far its reveal (0…1) and its blur (in units of the text height) are.
    struct TextState { var index: Int; var reveal: Double; var blur: Double; var fade: Double; var glow: Double }

    static func textState(at t: Double) -> TextState? {
        let index = min(Int(t / slot), strings.count - 1)
        let local = t - Double(index) * slot
        // In: 0…0.6 s, sweeping left to right out of a blur. Hold to 3.0 s. Out: 3.0…3.9 s.
        let inEnd = 0.6, outStart = 3.0, outEnd = 3.9
        if local < inEnd {
            let p = smooth(local / inEnd)
            return TextState(index: index, reveal: p, blur: 0.12 * (1 - p), fade: 1, glow: 0)
        } else if local < outStart {
            return TextState(index: index, reveal: 1, blur: 0, fade: 1, glow: 0)
        } else if local < outEnd {
            let p = smooth((local - outStart) / (outEnd - outStart))
            return TextState(index: index, reveal: 1, blur: 0.02 + 0.16 * p, fade: 1 - p, glow: 1 - p)
        }
        return nil
    }

    private static func smooth(_ x: Double) -> Double {
        let c = min(max(x, 0), 1)
        return c * c * (3 - 2 * c)
    }

    private static func font(size: CGFloat) -> CTFont {
        CTFontCreateWithName("Helvetica Neue" as CFString, size, nil)
    }

    /// The font size that sets "Wallpaper Not Found" at the light video's width, for `width`.
    private static func fontSize(forWidth width: CGFloat) -> CGFloat {
        let probe: CGFloat = 100
        let line = makeLine(strings[0], size: probe)
        let measured = CTLineGetTypographicBounds(line, nil, nil, nil)
        return probe * width * CGFloat(referenceWidth) / CGFloat(measured)
    }

    private static func makeLine(_ string: String, size: CGFloat) -> CTLine {
        let attributes: [NSAttributedString.Key: Any] = [
            NSAttributedString.Key(kCTFontAttributeName as String): font(size: size),
            NSAttributedString.Key(kCTForegroundColorAttributeName as String): CGColor(gray: 1, alpha: 1),
        ]
        return CTLineCreateWithAttributedString(NSAttributedString(string: string, attributes: attributes))
    }

    private static let ciContext = CIContext(options: [.cacheIntermediates: false])

    private static func drawText(at t: Double, size: CGSize, in context: CGContext) {
        guard let state = textState(at: t) else { return }
        let fontSize = fontSize(forWidth: size.width)
        let line = makeLine(strings[state.index], size: fontSize)
        var ascent: CGFloat = 0, descent: CGFloat = 0
        let width = CGFloat(CTLineGetTypographicBounds(line, &ascent, &descent, nil))
        let lineHeight = ascent + descent
        // The text alone, with room for its blur, drawn into its own image.
        let pad = ceil(fontSize * 0.6)
        let box = CGSize(width: ceil(width + 2 * pad), height: ceil(lineHeight + 2 * pad))
        guard let layer = CGContext(data: nil, width: Int(box.width), height: Int(box.height), bitsPerComponent: 8,
                                    bytesPerRow: 0, space: CGColorSpace(name: CGColorSpace.sRGB)!,
                                    bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue) else { return }
        layer.textPosition = CGPoint(x: pad, y: pad + descent)
        // A faint dark edge keeps the text legible on the brightest streaks, as in the light video.
        layer.setShadow(offset: .zero, blur: fontSize * 0.08, color: CGColor(gray: 0, alpha: 0.6))
        CTLineDraw(line, layer)
        guard var image = layer.makeImage() else { return }
        let radius = state.blur * Double(lineHeight)
        if radius > 0.5 || state.glow > 0 {
            var ci = CIImage(cgImage: image)
            if radius > 0.5 {
                ci = ci.clampedToExtent().applyingGaussianBlur(sigma: radius).cropped(to: ci.extent)
            }
            if state.glow > 0, radius > 0.5 {
                // Blurring out, it first brightens, as the light video's text does.
                let halo = CIImage(cgImage: image).clampedToExtent().applyingGaussianBlur(sigma: radius * 0.5)
                    .cropped(to: ci.extent)
                    .applyingFilter("CIColorMatrix", parameters: [
                        "inputAVector": CIVector(x: 0, y: 0, z: 0, w: CGFloat(0.45 * state.glow)),
                        "inputRVector": CIVector(x: CGFloat(0.45 * state.glow), y: 0, z: 0, w: 0),
                        "inputGVector": CIVector(x: 0, y: CGFloat(0.45 * state.glow), z: 0, w: 0),
                        "inputBVector": CIVector(x: 0, y: 0, z: CGFloat(0.45 * state.glow), w: 0),
                    ])
                ci = halo.applyingFilter("CIAdditionCompositing", parameters: [kCIInputBackgroundImageKey: ci])
            }
            if let blurred = ciContext.createCGImage(ci, from: CGRect(origin: .zero, size: box)) { image = blurred }
        }
        let origin = CGPoint(x: (size.width - box.width) / 2,
                             y: size.height * (1 - CGFloat(centreFromTop)) - box.height / 2)
        let rect = CGRect(origin: origin, size: box)
        context.saveGState()
        context.setAlpha(CGFloat(state.fade))
        if state.reveal < 1 || state.fade < 1, let mask = sweepMask(reveal: state.reveal, fade: state.fade,
                                                                    width: Int(box.width)) {
            context.clip(to: rect, mask: mask)
        }
        context.draw(image, in: rect)
        context.restoreGState()
    }

    /// A horizontal mask: shown to the left of the sweep, a soft edge, hidden to its right. Fading
    /// out, the left goes first.
    private static func sweepMask(reveal: Double, fade: Double, width: Int) -> CGImage? {
        let soft = 0.35
        var bytes = [UInt8](repeating: 0, count: width)
        for x in 0..<width {
            let u = Double(x) / Double(max(width - 1, 1))
            // In: visible where u < reveal (with a soft edge). Out: hidden where u < 1 - fade.
            let inside = min(max((reveal * (1 + soft) - u) / soft, 0), 1)
            let gone = min(max(((1 - fade) * (1 + soft) - u) / soft, 0), 1)
            bytes[x] = UInt8(max(0, min(255, (inside * (1 - gone)) * 255)))
        }
        guard let provider = CGDataProvider(data: Data(bytes) as CFData) else { return nil }
        return CGImage(width: width, height: 1, bitsPerComponent: 8, bitsPerPixel: 8, bytesPerRow: width,
                       space: CGColorSpaceCreateDeviceGray(), bitmapInfo: CGBitmapInfo(rawValue: 0),
                       provider: provider, decode: nil, shouldInterpolate: true, intent: .defaultIntent)
    }
}

/// A small fixed-seed generator, so every run draws the same streaks.
struct SplitMix {
    private var state: UInt64
    init(seed: UInt64) { state = seed }
    var next: Double {
        mutating get {
            state &+= 0x9E37_79B9_7F4A_7C15
            var z = state
            z = (z ^ (z >> 30)) &* 0xBF58_476D_1CE4_E5B9
            z = (z ^ (z >> 27)) &* 0x94D0_49BB_1331_11EB
            z ^= z >> 31
            return Double(z >> 11) / Double(1 << 53)
        }
    }
}

// MARK: Rendering

let width = 3640, height = 2048, fps = 60
var output = URL(fileURLWithPath: "OpenWallpaperEngine/Resources/WallpaperNotFoundDark.mp4")
var previews: URL?
var writesVideo = true
var arguments = Array(CommandLine.arguments.dropFirst())
while let argument = arguments.first {
    arguments.removeFirst()
    if argument == "--no-video" {
        writesVideo = false
    } else if argument == "--previews", let folder = arguments.first {
        arguments.removeFirst()
        previews = URL(fileURLWithPath: folder, isDirectory: true)
    } else {
        output = URL(fileURLWithPath: argument)
    }
}

func makeContext(width: Int, height: Int, data: UnsafeMutableRawPointer? = nil, bytesPerRow: Int = 0) -> CGContext {
    CGContext(data: data, width: width, height: height, bitsPerComponent: 8, bytesPerRow: bytesPerRow,
              space: CGColorSpace(name: CGColorSpace.sRGB)!,
              bitmapInfo: CGImageAlphaInfo.premultipliedFirst.rawValue | CGBitmapInfo.byteOrder32Little.rawValue)!
}

if let previews {
    try FileManager.default.createDirectory(at: previews, withIntermediateDirectories: true)
    for seconds in [3.0, 8.0, 16.0, 25.0] {
        let previewWidth = 1280, previewHeight = 1280 * height / width
        let context = makeContext(width: previewWidth, height: previewHeight)
        PlaceholderFrame.draw(at: seconds, size: CGSize(width: previewWidth, height: previewHeight), in: context)
        let url = previews.appending(path: String(format: "dark-%02.0fs.png", seconds))
        let destination = CGImageDestinationCreateWithURL(url as CFURL, "public.png" as CFString, 1, nil)!
        CGImageDestinationAddImage(destination, context.makeImage()!, nil)
        CGImageDestinationFinalize(destination)
        print("preview \(url.path)")
    }
}

if !writesVideo { exit(0) }
try? FileManager.default.removeItem(at: output)
let writer = try AVAssetWriter(outputURL: output, fileType: .mp4)
let settings: [String: Any] = [
    AVVideoCodecKey: AVVideoCodecType.h264,
    AVVideoWidthKey: width,
    AVVideoHeightKey: height,
    AVVideoColorPropertiesKey: [
        AVVideoColorPrimariesKey: AVVideoColorPrimaries_ITU_R_709_2,
        AVVideoTransferFunctionKey: AVVideoTransferFunction_ITU_R_709_2,
        AVVideoYCbCrMatrixKey: AVVideoYCbCrMatrix_ITU_R_709_2,
    ],
    AVVideoCompressionPropertiesKey: [
        AVVideoAverageBitRateKey: 6_000_000,
        AVVideoProfileLevelKey: AVVideoProfileLevelH264HighAutoLevel,
        AVVideoExpectedSourceFrameRateKey: fps,
        AVVideoMaxKeyFrameIntervalKey: fps * 2,
        AVVideoAllowFrameReorderingKey: true,
    ],
]
let input = AVAssetWriterInput(mediaType: .video, outputSettings: settings)
input.expectsMediaDataInRealTime = false
let adaptor = AVAssetWriterInputPixelBufferAdaptor(assetWriterInput: input, sourcePixelBufferAttributes: [
    kCVPixelBufferPixelFormatTypeKey as String: kCVPixelFormatType_32BGRA,
    kCVPixelBufferWidthKey as String: width,
    kCVPixelBufferHeightKey as String: height,
])
writer.add(input)
guard writer.startWriting() else { fatalError("can't write \(output.path): \(String(describing: writer.error))") }
writer.startSession(atSourceTime: .zero)

let frames = Int(PlaceholderFrame.duration) * fps
let started = Date()
for frame in 0..<frames {
    while !input.isReadyForMoreMediaData { Thread.sleep(forTimeInterval: 0.002) }
    guard let pool = adaptor.pixelBufferPool else { fatalError("no pixel buffer pool") }
    var buffer: CVPixelBuffer?
    CVPixelBufferPoolCreatePixelBuffer(nil, pool, &buffer)
    guard let buffer else { fatalError("no pixel buffer") }
    CVPixelBufferLockBaseAddress(buffer, [])
    let context = makeContext(width: width, height: height, data: CVPixelBufferGetBaseAddress(buffer),
                              bytesPerRow: CVPixelBufferGetBytesPerRow(buffer))
    PlaceholderFrame.draw(at: Double(frame) / Double(fps), size: CGSize(width: width, height: height), in: context)
    CVPixelBufferUnlockBaseAddress(buffer, [])
    CVBufferSetAttachment(buffer, kCVImageBufferColorPrimariesKey, kCVImageBufferColorPrimaries_ITU_R_709_2, .shouldPropagate)
    CVBufferSetAttachment(buffer, kCVImageBufferTransferFunctionKey, kCVImageBufferTransferFunction_ITU_R_709_2, .shouldPropagate)
    CVBufferSetAttachment(buffer, kCVImageBufferYCbCrMatrixKey, kCVImageBufferYCbCrMatrix_ITU_R_709_2, .shouldPropagate)
    adaptor.append(buffer, withPresentationTime: CMTime(value: CMTimeValue(frame), timescale: CMTimeScale(fps)))
    if frame % (fps * 5) == 0 { print("frame \(frame)/\(frames)") }
}
input.markAsFinished()
let done = DispatchSemaphore(value: 0)
writer.finishWriting { done.signal() }
done.wait()
guard writer.status == .completed else { fatalError("writing failed: \(String(describing: writer.error))") }
print(String(format: "wrote %@ in %.0f s", output.path, Date().timeIntervalSince(started)))

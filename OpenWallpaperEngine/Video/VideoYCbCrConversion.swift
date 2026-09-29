import CoreVideo
import simd

/// How a bi-planar Y'CbCr video frame turns into the gamma-encoded RGB the BGRA output would have
/// produced: the colour matrix the frame is tagged with and the range its samples use.
struct VideoYCbCrConversion: Equatable {
    enum Matrix: Equatable {
        case bt601, bt709, bt2020

        /// Luma weights of red and blue (Kr, Kb).
        var weights: (red: Float, blue: Float) {
            switch self {
            case .bt601: (0.299, 0.114)
            case .bt709: (0.2126, 0.0722)
            case .bt2020: (0.2627, 0.0593)
            }
        }
    }

    enum Range: Equatable {
        /// Y' in 16…235, CbCr in 16…240 (of 255).
        case video
        /// Y' and CbCr in 0…255.
        case full
    }

    let matrix: Matrix
    let range: Range

    init(matrix: Matrix, range: Range) {
        self.matrix = matrix
        self.range = range
    }

    /// The conversion for a decoded frame, or nil when its format isn't a supported bi-planar one.
    init?(buffer: CVPixelBuffer) {
        guard CVPixelBufferGetPlaneCount(buffer) == 2,
              let range = Self.range(pixelFormat: CVPixelBufferGetPixelFormatType(buffer)) else { return nil }
        // Optional lookup: an untagged frame falls back to the size convention.
        let tag = CVBufferCopyAttachment(buffer, kCVImageBufferYCbCrMatrixKey, nil) as? String
        self.init(matrix: Self.matrix(attachment: tag, height: CVPixelBufferGetHeight(buffer)), range: range)
    }

    /// The matrix a frame's `kCVImageBufferYCbCrMatrixKey` attachment names. An untagged frame
    /// follows the usual convention: BT.601 below HD, BT.709 from HD up. SMPTE 240M is close
    /// enough to BT.709 that it takes that matrix.
    static func matrix(attachment: String?, height: Int) -> Matrix {
        switch attachment {
        case kCVImageBufferYCbCrMatrix_ITU_R_709_2 as String: .bt709
        case kCVImageBufferYCbCrMatrix_ITU_R_601_4 as String: .bt601
        case kCVImageBufferYCbCrMatrix_ITU_R_2020 as String: .bt2020
        case kCVImageBufferYCbCrMatrix_SMPTE_240M_1995 as String: .bt709
        default: height < 720 ? .bt601 : .bt709
        }
    }

    /// The range of a supported pixel format; nil for anything the YUV path can't sample.
    static func range(pixelFormat: OSType) -> Range? {
        switch pixelFormat {
        case kCVPixelFormatType_420YpCbCr8BiPlanarVideoRange: .video
        case kCVPixelFormatType_420YpCbCr8BiPlanarFullRange: .full
        default: nil
        }
    }

    /// What the kernel takes: `rgb = matrix * (ycbcr - offset)`, with samples normalised to 0…1
    /// and the range's scale folded into the matrix. Layout matches `VideoYCbCrUniforms` in
    /// VideoYCbCr.metal (three 16-byte columns, then a 16-byte offset).
    struct Uniforms: Equatable {
        var matrix: simd_float3x3
        var offset: SIMD3<Float>
    }

    var uniforms: Uniforms {
        let (kr, kb) = matrix.weights
        let kg = 1 - kr - kb
        let lumaScale: Float, chromaScale: Float, lumaOffset: Float
        switch range {
        case .video: (lumaScale, chromaScale, lumaOffset) = (255 / 219, 255 / 224, 16 / 255)
        case .full: (lumaScale, chromaScale, lumaOffset) = (1, 1, 0)
        }
        // Columns act on Y', Cb, Cr.
        let luma = SIMD3<Float>(1, 1, 1) * lumaScale
        let blue = SIMD3<Float>(0, -2 * kb * (1 - kb) / kg, 2 * (1 - kb)) * chromaScale
        let red = SIMD3<Float>(2 * (1 - kr), -2 * kr * (1 - kr) / kg, 0) * chromaScale
        return Uniforms(matrix: simd_float3x3(columns: (luma, blue, red)),
                        offset: SIMD3<Float>(lumaOffset, 128 / 255, 128 / 255))
    }

    /// The RGB of one sample, clamped like the kernel's output; samples are normalised to 0…1.
    func rgb(y: Float, cb: Float, cr: Float) -> SIMD3<Float> {
        let uniforms = uniforms
        return simd_clamp(uniforms.matrix * (SIMD3<Float>(y, cb, cr) - uniforms.offset),
                          SIMD3<Float>(repeating: 0), SIMD3<Float>(repeating: 1))
    }
}

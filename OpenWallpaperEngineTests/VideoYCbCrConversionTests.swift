import CoreVideo
import simd
import XCTest
@testable import OpenWallpaperEngine

final class VideoYCbCrConversionTests: XCTestCase {
    private typealias Conversion = VideoYCbCrConversion

    func testMatrixFollowsTheAttachment() {
        XCTAssertEqual(Conversion.matrix(attachment: kCVImageBufferYCbCrMatrix_ITU_R_709_2 as String, height: 480), .bt709)
        XCTAssertEqual(Conversion.matrix(attachment: kCVImageBufferYCbCrMatrix_ITU_R_601_4 as String, height: 2160), .bt601)
        XCTAssertEqual(Conversion.matrix(attachment: kCVImageBufferYCbCrMatrix_ITU_R_2020 as String, height: 1080), .bt2020)
        XCTAssertEqual(Conversion.matrix(attachment: kCVImageBufferYCbCrMatrix_SMPTE_240M_1995 as String, height: 1080), .bt709)
    }

    func testUntaggedMatrixFollowsTheFrameHeight() {
        XCTAssertEqual(Conversion.matrix(attachment: nil, height: 480), .bt601)
        XCTAssertEqual(Conversion.matrix(attachment: nil, height: 576), .bt601)
        XCTAssertEqual(Conversion.matrix(attachment: nil, height: 720), .bt709)
        XCTAssertEqual(Conversion.matrix(attachment: "unknown", height: 1080), .bt709)
    }

    func testRangeFollowsThePixelFormat() {
        XCTAssertEqual(Conversion.range(pixelFormat: kCVPixelFormatType_420YpCbCr8BiPlanarVideoRange), .video)
        XCTAssertEqual(Conversion.range(pixelFormat: kCVPixelFormatType_420YpCbCr8BiPlanarFullRange), .full)
        XCTAssertNil(Conversion.range(pixelFormat: kCVPixelFormatType_32BGRA))
        XCTAssertNil(Conversion.range(pixelFormat: kCVPixelFormatType_420YpCbCr10BiPlanarVideoRange))
    }

    func testBufferConversionReadsFormatAndTag() throws {
        var buffer: CVPixelBuffer?
        XCTAssertEqual(CVPixelBufferCreate(nil, 64, 32, kCVPixelFormatType_420YpCbCr8BiPlanarFullRange, nil, &buffer),
                       kCVReturnSuccess)
        let frame = try XCTUnwrap(buffer)
        XCTAssertEqual(Conversion(buffer: frame), Conversion(matrix: .bt601, range: .full))
        CVBufferSetAttachment(frame, kCVImageBufferYCbCrMatrixKey, kCVImageBufferYCbCrMatrix_ITU_R_2020,
                              .shouldPropagate)
        XCTAssertEqual(Conversion(buffer: frame), Conversion(matrix: .bt2020, range: .full))

        var bgra: CVPixelBuffer?
        XCTAssertEqual(CVPixelBufferCreate(nil, 64, 32, kCVPixelFormatType_32BGRA, nil, &bgra), kCVReturnSuccess)
        XCTAssertNil(Conversion(buffer: try XCTUnwrap(bgra)))
    }

    func testVideoRangeBlackWhiteAndGrey() {
        for matrix in [Conversion.Matrix.bt601, .bt709, .bt2020] {
            let conversion = Conversion(matrix: matrix, range: .video)
            assertEqual(conversion.rgb(y: 16 / 255, cb: 128 / 255, cr: 128 / 255), SIMD3(0, 0, 0))
            assertEqual(conversion.rgb(y: 235 / 255, cb: 128 / 255, cr: 128 / 255), SIMD3(1, 1, 1))
            let grey = Float(125.5 - 16) / 219
            assertEqual(conversion.rgb(y: 125.5 / 255, cb: 128 / 255, cr: 128 / 255), SIMD3(repeating: grey))
        }
    }

    func testFullRangeBlackAndWhite() {
        let conversion = Conversion(matrix: .bt709, range: .full)
        assertEqual(conversion.rgb(y: 0, cb: 128 / 255, cr: 128 / 255), SIMD3(0, 0, 0))
        assertEqual(conversion.rgb(y: 1, cb: 128 / 255, cr: 128 / 255), SIMD3(1, 1, 1))
    }

    /// BT.709 video-range 100% red is Y' 62.56, Cb 102.34, Cr 240 (Rec. ITU-R BT.709-6 §3).
    func testBT709VideoRangeRedFromPublishedCodes() {
        let conversion = Conversion(matrix: .bt709, range: .video)
        assertEqual(conversion.rgb(y: 62.5594 / 255, cb: 102.3361 / 255, cr: 240 / 255), SIMD3(1, 0, 0))
    }

    /// BT.601 video-range 100% green is Y' 144.55, Cb 53.8, Cr 34.2.
    func testBT601VideoRangeGreenFromPublishedCodes() {
        let conversion = Conversion(matrix: .bt601, range: .video)
        assertEqual(conversion.rgb(y: 144.553 / 255, cb: 53.797 / 255, cr: 34.214 / 255), SIMD3(0, 1, 0))
    }

    /// Encoding RGB with each matrix's forward equations and decoding it gives the colour back.
    func testRoundTripsEveryMatrixAndRange() {
        let colours: [SIMD3<Float>] = [SIMD3(1, 0, 0), SIMD3(0, 1, 0), SIMD3(0, 0, 1), SIMD3(0.25, 0.5, 0.75),
                                       SIMD3(0.9, 0.8, 0.1), SIMD3(1, 1, 0)]
        for matrix in [Conversion.Matrix.bt601, .bt709, .bt2020] {
            for range in [Conversion.Range.video, .full] {
                let conversion = Conversion(matrix: matrix, range: range)
                for colour in colours {
                    let (y, cb, cr) = encode(colour, matrix: matrix, range: range)
                    assertEqual(conversion.rgb(y: y, cb: cb, cr: cr), colour, "\(matrix) \(range) \(colour)")
                }
            }
        }
    }

    func testUniformsMatchTheMetalLayout() {
        XCTAssertEqual(MemoryLayout<Conversion.Uniforms>.size, 64)
        XCTAssertEqual(MemoryLayout<Conversion.Uniforms>.offset(of: \.offset), 48)
    }

    private func encode(_ rgb: SIMD3<Float>, matrix: Conversion.Matrix,
                        range: Conversion.Range) -> (Float, Float, Float) {
        let (kr, kb) = matrix.weights
        let luma = kr * rgb.x + (1 - kr - kb) * rgb.y + kb * rgb.z
        let cb = (rgb.z - luma) / (2 * (1 - kb))
        let cr = (rgb.x - luma) / (2 * (1 - kr))
        switch range {
        case .video: return ((16 + 219 * luma) / 255, (128 + 224 * cb) / 255, (128 + 224 * cr) / 255)
        case .full: return (luma, 128 / 255 + cb, 128 / 255 + cr)
        }
    }

    private func assertEqual(_ actual: SIMD3<Float>, _ expected: SIMD3<Float>, _ message: String = "",
                             file: StaticString = #filePath, line: UInt = #line) {
        XCTAssertLessThan(simd_reduce_max(simd_abs(actual - expected)), 2e-3,
                          "\(actual) != \(expected) \(message)", file: file, line: line)
    }
}

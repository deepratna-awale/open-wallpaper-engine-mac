import Metal
import os

/// Turns a decoded bi-planar Y'CbCr frame into an RGBA texture on the GPU, inside the frame's own
/// command buffer, so the scene samples the same RGB the BGRA output would have handed over.
///
/// The pipeline is built off the calling thread; until it is ready (or if it can't be built)
/// `state` says so and the stream keeps its previous picture or falls back to BGRA.
final class VideoYCbCrConverter: @unchecked Sendable {
    enum State { case building, ready, failed }

    private let device: MTLDevice
    /// Owns `pipeline` and `buildState`, written once by the build and read by the render thread.
    private let lock = OSAllocatedUnfairLock()
    private var pipeline: MTLComputePipelineState?
    private var buildState = State.building
    /// Output textures, rotated so each new frame is a new texture object (anything keyed on a
    /// texture's identity sees the change) and a frame still being read isn't overwritten.
    private var targets: [MTLTexture] = []
    private var nextTarget = 0
    private static let targetCount = 3

    init(device: MTLDevice) {
        self.device = device
        DispatchQueue.global(qos: .userInitiated).async { [self] in build() }
    }

    var state: State { lock.withLock { buildState } }

    private func build() {
        do {
            let library = try device.makeDefaultLibrary(bundle: Bundle(for: VideoYCbCrConverter.self))
            guard let function = library.makeFunction(name: "videoYCbCrToRGB") else {
                throw ConverterError.noFunction
            }
            let built = try device.makeComputePipelineState(function: function)
            lock.withLock { pipeline = built; buildState = .ready }
        } catch {
            OWELog.error(.scene, "Video Y'CbCr conversion unavailable, falling back to BGRA frames: \(error)")
            lock.withLock { buildState = .failed }
        }
    }

    /// Encodes the conversion of `luma` (r8Unorm) and `chroma` (rg8Unorm) into a fresh RGBA
    /// texture the size of `luma`; nil when the pipeline isn't ready or a texture can't be made.
    func convert(luma: MTLTexture, chroma: MTLTexture, conversion: VideoYCbCrConversion,
                 commandBuffer: MTLCommandBuffer) -> MTLTexture? {
        guard let pipeline = lock.withLock({ pipeline }),
              let output = target(width: luma.width, height: luma.height),
              let encoder = commandBuffer.makeComputeCommandEncoder() else { return nil }
        var uniforms = conversion.uniforms
        encoder.label = "Video Y'CbCr to RGB"
        encoder.setComputePipelineState(pipeline)
        encoder.setTexture(luma, index: 0)
        encoder.setTexture(chroma, index: 1)
        encoder.setTexture(output, index: 2)
        encoder.setBytes(&uniforms, length: MemoryLayout<VideoYCbCrConversion.Uniforms>.stride, index: 0)
        let width = pipeline.threadExecutionWidth
        let group = MTLSize(width: width, height: max(1, pipeline.maxTotalThreadsPerThreadgroup / width), depth: 1)
        let grid = MTLSize(width: (output.width + group.width - 1) / group.width,
                           height: (output.height + group.height - 1) / group.height, depth: 1)
        encoder.dispatchThreadgroups(grid, threadsPerThreadgroup: group)
        encoder.endEncoding()
        return output
    }

    /// The next output texture, reallocated when the video's size changes.
    private func target(width: Int, height: Int) -> MTLTexture? {
        if targets.first.map({ $0.width != width || $0.height != height }) ?? true {
            let descriptor = MTLTextureDescriptor.texture2DDescriptor(pixelFormat: .rgba8Unorm, width: width,
                                                                      height: height, mipmapped: false)
            descriptor.usage = [.shaderRead, .shaderWrite]
            descriptor.storageMode = .private
            targets = (0..<Self.targetCount).compactMap { _ in device.makeTexture(descriptor: descriptor) }
            nextTarget = 0
            guard targets.count == Self.targetCount else { targets = []; return nil }
        }
        defer { nextTarget = (nextTarget + 1) % targets.count }
        return targets[nextTarget]
    }

    private enum ConverterError: Error { case noFunction }
}

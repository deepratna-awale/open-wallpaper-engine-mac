import Foundation
import Metal
import MetalFX

/// Scales the scene target drawn at a render scale (`GSUpscaling`, `GSRenderScale`) up to its
/// full size after the scene pass, before the post-process, with MetalFX's spatial scaler.
/// Scalers are made on a background queue and cached per input size, output size and format; until
/// one is ready, or where MetalFX can't run (the GPU doesn't support it, or the frame is HDR's
/// RGBA16F for EDR), the frame is not upscaled here and the final composite scales it bilinearly.
/// One per renderer; `upscale` is called from the render thread.
final class SceneUpscaler: @unchecked Sendable {
    /// How a frame drawn below its target size reaches it.
    enum Path: Equatable {
        /// Drawn at its full size: nothing to scale.
        case none
        case metalFX
        /// The composite samples the smaller frame bilinearly onto the display.
        case bilinear
    }

    struct Key: Hashable {
        var input: SIMD2<Int>
        var output: SIMD2<Int>
        var format: UInt
    }

    /// A scaler and the texture it writes.
    final class Entry {
        let scaler: MTLFXSpatialScaler
        let output: MTLTexture
        init(scaler: MTLFXSpatialScaler, output: MTLTexture) {
            self.scaler = scaler
            self.output = output
        }
    }

    private let device: MTLDevice
    private let supportsMetalFX: Bool
    private let queue = DispatchQueue(label: "SceneUpscaler", qos: .utility)
    /// Owns `ready` and `pending`, shared by the render thread and `queue`.
    private let lock = NSLock()
    private var ready: [Key: Entry] = [:]
    private var pending: Set<Key> = []
    private var failed: Set<Key> = []
    /// Sizes and formats change only when the display, scene or setting does; a few cover them.
    private static let cacheLimit = 4

    init(device: MTLDevice) {
        self.device = device
        supportsMetalFX = Self.supportsMetalFX(device)
    }

    /// Whether `device` can run MetalFX's spatial scaler.
    static func supportsMetalFX(_ device: MTLDevice) -> Bool {
        MTLFXSpatialScalerDescriptor.supportsDevice(device)
    }

    /// The colour formats MetalFX's spatial scaler gets here: 8-bit LDR. The RGBA16F frame of an
    /// HDR scene (and display HDR's EDR output) is scaled bilinearly.
    static func scalesFormat(_ format: MTLPixelFormat) -> Bool {
        switch format {
        case .bgra8Unorm, .rgba8Unorm, .bgra8Unorm_srgb, .rgba8Unorm_srgb: return true
        default: return false
        }
    }

    /// The path a frame takes for `settings`, drawn in `format`, on a GPU that does or doesn't
    /// support MetalFX.
    static func path(settings: SceneRenderSettings, format: MTLPixelFormat, deviceSupportsMetalFX: Bool) -> Path {
        guard settings.drawnScale < 1 else { return .none }
        return deviceSupportsMetalFX && scalesFormat(format) ? .metalFX : .bilinear
    }

    func path(settings: SceneRenderSettings, format: MTLPixelFormat) -> Path {
        Self.path(settings: settings, format: format, deviceSupportsMetalFX: supportsMetalFX)
    }

    /// Encodes `input` scaled up to `outputSize` and returns the result, or nil when the frame
    /// isn't upscaled here (its scaler isn't ready yet, or can't be made): the caller then uses
    /// `input`, which the composite scales bilinearly.
    func upscale(_ input: MTLTexture, to outputSize: SIMD2<Int>, commandBuffer: MTLCommandBuffer) -> MTLTexture? {
        guard Self.scalesFormat(input.pixelFormat), supportsMetalFX else { return nil }
        let key = Key(input: SIMD2(input.width, input.height), output: outputSize, format: input.pixelFormat.rawValue)
        guard key.input != key.output else { return nil }
        guard let entry = entry(for: key, format: input.pixelFormat) else { return nil }
        entry.scaler.colorTexture = input
        entry.scaler.outputTexture = entry.output
        entry.scaler.encode(commandBuffer: commandBuffer)
        return entry.output
    }

    /// The ready scaler for `key`, or nil after starting to make it off the render thread.
    private func entry(for key: Key, format: MTLPixelFormat) -> Entry? {
        lock.lock()
        defer { lock.unlock() }
        if let entry = ready[key] { return entry }
        guard !pending.contains(key), !failed.contains(key) else { return nil }
        pending.insert(key)
        queue.async { [weak self] in self?.make(key, format: format) }
        return nil
    }

    private func make(_ key: Key, format: MTLPixelFormat) {
        let descriptor = MTLFXSpatialScalerDescriptor()
        descriptor.inputWidth = key.input.x
        descriptor.inputHeight = key.input.y
        descriptor.outputWidth = key.output.x
        descriptor.outputHeight = key.output.y
        descriptor.colorTextureFormat = format
        descriptor.outputTextureFormat = format
        descriptor.colorProcessingMode = .perceptual
        var entry: Entry?
        if let scaler = descriptor.makeSpatialScaler(device: device) {
            let texture = MTLTextureDescriptor.texture2DDescriptor(pixelFormat: format, width: key.output.x,
                                                                   height: key.output.y, mipmapped: false)
            texture.usage = scaler.outputTextureUsage.union(.shaderRead)
            texture.storageMode = .private
            if let output = device.makeTexture(descriptor: texture) {
                output.label = "Upscaled scene"
                entry = Entry(scaler: scaler, output: output)
            }
        }
        if entry == nil {
            OWELog.error(.render, "MetalFX can't scale \(key.input.x)×\(key.input.y) to \(key.output.x)×\(key.output.y); the frame is scaled bilinearly")
        }
        lock.lock()
        pending.remove(key)
        if let entry {
            if ready.count >= Self.cacheLimit { ready.removeAll() }
            ready[key] = entry
        } else {
            failed.insert(key)
        }
        lock.unlock()
    }
}

import Metal

/// The scene pass's depth buffer (docs/models-plan.md §2.4): made to match the scene target and
/// its samples, cleared to WE's far depth at the start of the pass and kept across its pauses (a
/// scene-reading layer ends and resumes the pass). With MSAA it resolves into `texture` whenever
/// the pass ends, as the colour does. `texture` is what the frame stages read afterwards
/// (`SceneFrameStageContext.sceneDepth`: the volumetrics' `_rt_volumetricsBack`). Render thread only.
final class SceneDepthBuffer {
    private let device: MTLDevice
    /// The single-sampled depth, shader-readable: the one the pass draws into without MSAA, the
    /// resolve target with it.
    private(set) var texture: MTLTexture?
    /// The multisampled depth the pass draws into with MSAA; nil without.
    private(set) var multisampled: MTLTexture?

    init(device: MTLDevice) {
        self.device = device
    }

    var residentBytes: Int { (texture?.allocatedSize ?? 0) + (multisampled?.allocatedSize ?? 0) }

    func releaseAll() {
        texture = nil
        multisampled = nil
    }

    /// Makes or keeps the textures for a scene target of `width`×`height` drawn with `sampleCount`
    /// samples. False (logged) when one can't be made; the pass then draws without depth.
    func prepare(width: Int, height: Int, sampleCount: Int) -> Bool {
        if texture?.width != width || texture?.height != height {
            texture = make(width: width, height: height, sampleCount: 1)
            multisampled = nil
        }
        if sampleCount > 1 {
            if multisampled?.width != width || multisampled?.height != height || multisampled?.sampleCount != sampleCount {
                multisampled = make(width: width, height: height, sampleCount: sampleCount)
            }
            return texture != nil && multisampled != nil
        }
        multisampled = nil
        return texture != nil
    }

    /// Attaches the depth to `pass`: cleared to WE's far depth when the pass starts, loaded when it
    /// resumes; stored, and resolved with MSAA.
    func attach(to pass: MTLRenderPassDescriptor, clear: Bool) {
        let attachment = pass.depthAttachment!
        attachment.loadAction = clear ? .clear : .load
        attachment.clearDepth = SceneDepthStates.clearDepth
        if let multisampled {
            attachment.texture = multisampled
            attachment.resolveTexture = texture
            attachment.depthResolveFilter = .sample0
            attachment.storeAction = .storeAndMultisampleResolve
        } else {
            attachment.texture = texture
            attachment.storeAction = .store
        }
    }

    private func make(width: Int, height: Int, sampleCount: Int) -> MTLTexture? {
        let descriptor = MTLTextureDescriptor.texture2DDescriptor(pixelFormat: SceneDepthStates.format, width: width,
                                                                  height: height, mipmapped: false)
        descriptor.storageMode = .private
        if sampleCount > 1 {
            descriptor.textureType = .type2DMultisample
            descriptor.sampleCount = sampleCount
            descriptor.usage = [.renderTarget]
        } else {
            descriptor.usage = [.renderTarget, .shaderRead]
        }
        guard let texture = device.makeTexture(descriptor: descriptor) else {
            OWELog.error(.scene, "Could not allocate the \(width)×\(height) scene depth (\(sampleCount) samples); drawing without depth")
            return nil
        }
        texture.label = sampleCount > 1 ? "scene depth (multisampled)" : "scene depth"
        return texture
    }
}

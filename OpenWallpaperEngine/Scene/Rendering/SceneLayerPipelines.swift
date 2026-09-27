import Metal

/// The pipelines the scene pass draws with natively (a layer's quad blended normally or
/// additively, and an unblended region copy), in each format the scene target can have: the
/// drawable's in LDR, RGBA16F in HDR (docs/lighting-plan.md §2.6). With WE's MSAA setting the
/// scene pass draws multisampled, and a perspective scene's pass has a depth buffer
/// (`SceneDepthStates`, docs/models-plan.md §2.4); the pipelines for a sample count above 1 or a
/// depth format are made when first asked for.
final class SceneLayerPipelines {
    struct Pipelines {
        let normal: MTLRenderPipelineState
        let additive: MTLRenderPipelineState
        let copy: MTLRenderPipelineState
        /// A layer quad drawn through a 3D camera (`sceneVertex3D`, `SceneLayerPlacement`); nil
        /// without that vertex function.
        let placedNormal: MTLRenderPipelineState?
        let placedAdditive: MTLRenderPipelineState?
    }

    private struct Variant: Hashable {
        var format: MTLPixelFormat
        var sampleCount: Int
        var depthFormat: MTLPixelFormat
    }

    private struct Functions {
        let vertex: MTLFunction
        let fragment: MTLFunction
        let copy: MTLFunction
        let placedVertex: MTLFunction?
    }

    private let byFormat: [MTLPixelFormat: Pipelines]
    private let fallback: Pipelines
    private let device: MTLDevice
    private let functions: Functions
    /// Made on first use, by the render thread only; nil for one that failed (logged once).
    private var variants: [Variant: Pipelines?] = [:]

    /// The pipelines for each of `formats`, the first of which `pipelines(for:)` falls back to.
    /// `placedVertex` is `sceneVertex3D`. Throws when one can't be made.
    init(device: MTLDevice, vertex: MTLFunction, fragment: MTLFunction, copyFragment: MTLFunction,
         placedVertex: MTLFunction? = nil, formats: [MTLPixelFormat]) throws {
        let functions = Functions(vertex: vertex, fragment: fragment, copy: copyFragment, placedVertex: placedVertex)
        var byFormat: [MTLPixelFormat: Pipelines] = [:]
        for format in formats where byFormat[format] == nil {
            byFormat[format] = try Self.make(device: device, functions: functions,
                                             variant: Variant(format: format, sampleCount: 1, depthFormat: .invalid))
        }
        guard let first = formats.first, let fallback = byFormat[first] else {
            throw ShaderCompilerError.failed(step: "metal", output: "no scene target format")
        }
        self.byFormat = byFormat
        self.fallback = fallback
        self.device = device
        self.functions = functions
    }

    /// The pipelines drawing into a single-sampled target of `format` without depth.
    func pipelines(for format: MTLPixelFormat?) -> Pipelines {
        format.flatMap { byFormat[$0] } ?? fallback
    }

    /// The pipelines drawing into a `sampleCount`-sample target of `format` with a `depthFormat`
    /// depth attachment (`.invalid`: none); nil when they can't be made (the caller draws
    /// single-sampled). Call on the render thread.
    func pipelines(for format: MTLPixelFormat, sampleCount: Int,
                   depthFormat: MTLPixelFormat = .invalid) -> Pipelines? {
        guard sampleCount > 1 || depthFormat != .invalid else { return pipelines(for: format) }
        let key = Variant(format: format, sampleCount: max(sampleCount, 1), depthFormat: depthFormat)
        if let known = variants[key] { return known }
        do {
            let made = try Self.make(device: device, functions: functions, variant: key)
            variants[key] = made
            return made
        } catch {
            let what = sampleCount > 1 ? "\(sampleCount)× MSAA" : "depth"
            OWELog.error(.scene, "The scene's \(what) pipelines can't be made; it draws without: \(error)")
            variants[key] = .some(nil)
            return nil
        }
    }

    /// The layer pipeline's descriptor in `format`: source-over blending.
    static func layerDescriptor(vertex: MTLFunction, fragment: MTLFunction, format: MTLPixelFormat) -> MTLRenderPipelineDescriptor {
        let descriptor = MTLRenderPipelineDescriptor()
        descriptor.vertexFunction = vertex
        descriptor.fragmentFunction = fragment
        let attachment = descriptor.colorAttachments[0]!
        attachment.pixelFormat = format
        attachment.isBlendingEnabled = true
        attachment.rgbBlendOperation = .add
        attachment.alphaBlendOperation = .add
        attachment.sourceRGBBlendFactor = .sourceAlpha
        attachment.sourceAlphaBlendFactor = .sourceAlpha
        attachment.destinationRGBBlendFactor = .oneMinusSourceAlpha
        attachment.destinationAlphaBlendFactor = .oneMinusSourceAlpha
        return descriptor
    }

    private static func make(device: MTLDevice, functions: Functions, variant: Variant) throws -> Pipelines {
        func blended(_ vertex: MTLFunction, additive: Bool) throws -> MTLRenderPipelineState {
            let descriptor = layerDescriptor(vertex: vertex, fragment: functions.fragment, format: variant.format)
            descriptor.rasterSampleCount = variant.sampleCount
            descriptor.depthAttachmentPixelFormat = variant.depthFormat
            if additive {
                descriptor.colorAttachments[0].sourceRGBBlendFactor = .sourceAlpha
                descriptor.colorAttachments[0].sourceAlphaBlendFactor = .one
                descriptor.colorAttachments[0].destinationRGBBlendFactor = .one
                descriptor.colorAttachments[0].destinationAlphaBlendFactor = .one
            }
            return try device.makeRenderPipelineState(descriptor: descriptor)
        }
        let copyDescriptor = MTLRenderPipelineDescriptor()
        copyDescriptor.vertexFunction = functions.vertex
        copyDescriptor.fragmentFunction = functions.copy
        copyDescriptor.colorAttachments[0].pixelFormat = variant.format
        copyDescriptor.rasterSampleCount = variant.sampleCount
        copyDescriptor.depthAttachmentPixelFormat = variant.depthFormat
        return Pipelines(normal: try blended(functions.vertex, additive: false),
                         additive: try blended(functions.vertex, additive: true),
                         copy: try device.makeRenderPipelineState(descriptor: copyDescriptor),
                         placedNormal: try functions.placedVertex.map { try blended($0, additive: false) },
                         placedAdditive: try functions.placedVertex.map { try blended($0, additive: true) })
    }
}

import Metal
import QuartzCore
import os

/// Counts the pipeline compiles that have landed, in any renderer. A frame drawn while a pipeline
/// was compiling draws that layer another way; the frame after it lands differs, so a change of
/// this count marks the scene changed (`SceneLayerFrameInputs.sceneChanged`). A counter, unlike a
/// "still compiling" check at the start and end of a frame, also catches a compile that starts
/// and lands between two checks.
enum ScenePipelineCompletions {
    private static let counter = OSAllocatedUnfairLock(initialState: UInt64(0))

    /// Called by every pipeline cache once a compile has finished (successfully or not).
    static func landed() { counter.withLock { $0 &+= 1 } }

    static var count: UInt64 { counter.withLock { $0 } }
}

/// Static-layer flattening (docs/efficiency-plan-2d.md WP2-B): the run of layers at the bottom of
/// the scene whose inputs haven't changed is drawn once into a cached copy of the scene target;
/// while every layer of the run stays clean, a frame starts from that copy instead of the clear
/// colour and skips those layers (their effects included).
///
/// Exact: the copy holds precisely what the run drew, and the key holds everything the run's
/// pixels can depend on besides the layers' own inputs (which the layer analysis tracks: a layer
/// that goes dirty ends the run, so the key changes and the copy is dropped the same frame).
///
/// Live edits stay instant: any user-property change (the Scene Inspector's edits, a preset, a
/// reset) drops the copy, and a new one is only taken once edits have been quiet for
/// `quietSeconds`, off the edit's hot path.
///
/// One full-scene target per renderer (the plan caps it at two). Render thread only.
final class SceneFlattening {
    /// What the cached pixels were drawn from.
    struct Key: Equatable {
        /// Layer indices of the run, in draw order, with whether each was visible.
        var layers: [Int]
        var visible: [Bool]
        var clearColor: SIMD3<Float>
        var width: Int
        var height: Int
        var pixelFormat: MTLPixelFormat
        /// Scene pixels per scene unit, and the detail scale effects are drawn at.
        var pixelsPerUnit: Float
        var detailScale: Float
        var settings: SceneRenderSettings
        /// The renderer's content generation: new content never reuses a copy.
        var generation: Int
    }

    /// What the frame does with the run.
    enum Plan: Equatable {
        /// Draw every layer as usual.
        case draw
        /// Draw as usual, then keep a copy of the scene target right after the run's last layer.
        case capture(Key)
        /// Start from the copy and skip the run's layers.
        case restore(Key)
    }

    /// Off (for comparisons and the benchmark's "before" rows) with `OWE_SCENE_FLATTEN=0`.
    var isEnabled = ProcessInfo.processInfo.environment["OWE_SCENE_FLATTEN"] != "0"
    /// How long user-property edits must be quiet before a copy is taken again.
    var quietSeconds: CFTimeInterval = 0.5

    private(set) var cached: MTLTexture?
    private var cachedKey: Key?
    private var lastCandidate: Key?
    private var propertiesRevision: UInt64?
    private var editedAt: CFTimeInterval = -.infinity

    /// Layers restored from the copy this frame, and copies taken so far.
    private(set) var flattenedThisFrame = 0
    private(set) var captures = 0

    init() {}

    /// Decides this frame's plan. `candidate` is the clean run at the bottom of the scene (nil or
    /// empty when there is none, or flattening can't apply this frame).
    func plan(candidate: Key?, propertiesRevision revision: UInt64, now: CFTimeInterval) -> Plan {
        flattenedThisFrame = 0
        if propertiesRevision != revision {
            if propertiesRevision != nil { editedAt = now }
            propertiesRevision = revision
            cachedKey = nil
        }
        guard isEnabled, let candidate, !candidate.layers.isEmpty else {
            drop()
            return .draw
        }
        defer { lastCandidate = candidate }
        if cachedKey == candidate, cached != nil {
            flattenedThisFrame = candidate.layers.count
            return .restore(candidate)
        }
        cachedKey = nil
        // Only a run that was also clean last frame, and not while edits are live.
        guard lastCandidate == candidate, now - editedAt >= quietSeconds else { return .draw }
        return .capture(candidate)
    }

    /// Copies `scene` (the run just drawn) into the cache. Encodes a blit into `commandBuffer`.
    func capture(_ key: Key, from scene: MTLTexture, device: MTLDevice, commandBuffer: MTLCommandBuffer) {
        if cached?.width != scene.width || cached?.height != scene.height || cached?.pixelFormat != scene.pixelFormat {
            let descriptor = MTLTextureDescriptor.texture2DDescriptor(pixelFormat: scene.pixelFormat, width: scene.width,
                                                                      height: scene.height, mipmapped: false)
            descriptor.usage = [.shaderRead]
            descriptor.storageMode = .private
            cached = device.makeTexture(descriptor: descriptor)
            cached?.label = "Flattened layers"
        }
        guard let cached, let blit = commandBuffer.makeBlitCommandEncoder() else {
            cachedKey = nil
            return
        }
        blit.copy(from: scene, to: cached)
        blit.endEncoding()
        cachedKey = key
        captures += 1
    }

    /// Copies the cache into `scene`, which the scene pass then loads instead of clearing.
    func restore(into scene: MTLTexture, commandBuffer: MTLCommandBuffer) -> Bool {
        guard let cached, cached.width == scene.width, cached.height == scene.height,
              cached.pixelFormat == scene.pixelFormat, let blit = commandBuffer.makeBlitCommandEncoder() else {
            drop()
            return false
        }
        blit.copy(from: cached, to: scene)
        blit.endEncoding()
        return true
    }

    /// Frees the copy (content change, memory pressure, flattening off).
    func drop() {
        cached = nil
        cachedKey = nil
        lastCandidate = nil
        flattenedThisFrame = 0
    }

    /// The run of layers (by index, in draw order) at the bottom of the scene that can be drawn
    /// from the copy: it stops at the first layer that isn't `eligible` or isn't clean.
    static func run(count: Int, eligible: (Int) -> Bool, clean: (Int) -> Bool) -> [Int] {
        var run: [Int] = []
        for index in 0..<count {
            guard eligible(index), clean(index) else { break }
            run.append(index)
        }
        return run
    }
}

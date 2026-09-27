import simd

/// WE's camera layers (docs/models-plan.md §2.3): every visible one plays its path file, and the
/// last visible one in scene order is the scene's camera.
///
/// **Playback** (the layer's update, `wallpaper64.exe` 0x1401f2ad0, only while it is visible):
/// 1. A path finished since the last frame (a "single" clock) is rewound and a new one picked; so
///    is one when none plays yet. `queuemode` "sequential" takes the next visible path, wrapping;
///    "random" draws from a shuffle bag of the visible paths, refilled when empty, never the path
///    it drew last unless that is the only one left.
/// 2. The path's clock advances (the timeline clock, `SceneTimelineClock`) and its channels are
///    sampled between whole frames. A component without keyframes follows the layer's world
///    matrix: eye = its translation, centre = eye − 5·normalize(row 2), up = normalize(row 1).
/// 3. The result is written back into the layer: `origin` = eye and `angles` those of
///    `lookAt(eye, centre, up)`, so the camera moves through its own transform. A perspective
///    scene takes the path's `fov` channel (50 without one); `zoom` is an orthographic scene's.
///
/// **The camera** (0x140189220…0x140189402): the active layer's world matrix gives eye = row 3,
/// centre = row 3 − row 2, up = row 1 (it looks down its local −z; parents apply), and its fov is
/// the playing path's, else the layer's own. World matrices are M3's (`SceneTransformHierarchy3D`).
final class SceneCameraLayers {
    /// The active layer's camera this frame.
    struct Camera: Equatable {
        var id: String
        var pose: SceneCameraPose
        /// Degrees, before the clamp.
        var fov: Float
    }

    /// What the rig asks of the frame about one layer.
    struct FrameInput {
        var deltaTime: Float
        /// The layer's own `visible` this frame (scripts included, ancestors not: WE tests the
        /// layer's own flag and condition).
        var isVisible: (String) -> Bool
        /// An object's own transform this frame where scripts or timelines set it; nil keeps the
        /// authored one (and, for a camera layer, what its paths wrote back).
        var live: SceneTransformHierarchy3D.Live
        /// A camera layer's `fov` a script set.
        var fov: (String) -> Float?
    }

    private final class Path {
        /// The path's clock (+0xf8); nil when its options give no duration, which WE rejects.
        var clock: SceneTimelineClock?
        var eye: SceneTimelineAnimation?
        var center: SceneTimelineAnimation?
        var up: SceneTimelineAnimation?
        var fovChannel: SceneTimelineAnimation?
        /// `visible`, resolved at load: a hidden path isn't queued.
        let visible: Bool
        /// The path's fov (+0x33c): 50 until its channel sets it.
        var fov = Float(SceneCameraDefaults.fov)

        init(_ path: WECameraLayerPath, values: SceneValueContext, layer: String) {
            visible = Self.flag(path.visible, in: values) ?? true
            clock = SceneTimelineClock(options: path.options)
            func animation(_ document: SceneTimelineDocument?, _ name: String) -> SceneTimelineAnimation? {
                guard let document else { return nil }
                do {
                    return try SceneTimelineAnimation(document: document, staticValue: nil)
                } catch {
                    OWELog.error(.scene, "Camera layer \(layer): path \(path.name ?? "?")'s \(name) can't play: \(error)")
                    return nil
                }
            }
            eye = animation(path.eye, "eye")
            center = animation(path.center, "center")
            up = animation(path.up, "up")
            fovChannel = animation(path.fov, "fov")
        }

        static func flag(_ raw: SceneRawValue?, in values: SceneValueContext) -> Bool? {
            guard let raw else { return nil }
            if let source = raw.userBindingSource { return SceneValueResolver.resolve(source, in: values).float != 0 }
            return raw.literalBool
        }
    }

    private final class Layer {
        let object: SceneCameraLayerObject
        let fov: Float
        let paths: [Path]
        /// The visible paths with a clock, in file order.
        let queue: [Int]
        let sequential: Bool
        /// The playing path (+0x2e0); nil before the first and while none can play.
        var current: Int?
        /// The random queue's bag (+0x328) and the path it drew last (+0x340, +0x344).
        var bag: [Int]
        var last: Int?
        var random: SceneCameraLayers.SplitMix
        /// The origin and angles the paths wrote back, which the layer keeps (+0x128, +0x140).
        var writtenOrigin: SIMD3<Float>?
        var writtenAngles: SIMD3<Float>?

        init(_ object: SceneCameraLayerObject, values: SceneValueContext, seed: UInt64) {
            self.object = object
            let raw = object.authored.values[.fov]
            let resolved = raw?.userBindingSource.map { SceneValueResolver.resolve($0, in: values).float }
            fov = resolved ?? Float(object.authored.fov)
            let paths = (object.pathFile?.paths ?? []).map { Path($0, values: values, layer: object.id) }
            self.paths = paths
            queue = paths.indices.filter { paths[$0].visible && paths[$0].clock != nil }
            sequential = object.authored.queueMode == .sequential
            bag = queue
            random = SceneCameraLayers.SplitMix(state: seed)
        }
    }

    private let layers: [Layer]
    private let transforms: SceneTransformHierarchy3D

    /// `transforms` holds every object's authored transform and parent (`SceneSpatialContent.transforms`).
    init(_ objects: [SceneCameraLayerObject], transforms: SceneTransformHierarchy3D, values: SceneValueContext) {
        self.transforms = transforms
        layers = objects.sorted { $0.order < $1.order }.enumerated().map { index, object in
            Layer(object, values: values, seed: 0x9E37_79B9_7F4A_7C15 &* UInt64(index + 1))
        }
    }

    var isEmpty: Bool { layers.isEmpty }

    /// Plays every visible layer's paths, then returns the active layer's camera; nil when no
    /// camera layer is visible.
    func update(_ input: FrameInput) -> Camera? {
        var active: Layer?
        for layer in layers where input.isVisible(layer.object.id) {
            play(layer, input: input)
            active = layer
        }
        guard let active else { return nil }
        let world = worldMatrix(active, input: input)
        let row = { (i: Int) in SIMD3(world[i].x, world[i].y, world[i].z) }
        let pose = SceneCameraPose(eye: row(3), center: row(3) - row(2), up: row(1))
        let pathFov: Float? = active.current.map { active.paths[$0].fov }
        let fov: Float = pathFov ?? input.fov(active.object.id) ?? active.fov
        return Camera(id: active.object.id, pose: pose, fov: fov)
    }

    /// The layer's origin and angles its paths wrote back, if they did (tests, scripts).
    func writtenBack(_ id: String) -> (origin: SIMD3<Float>, angles: SIMD3<Float>)? {
        guard let layer = layers.first(where: { $0.object.id == id }),
              let origin = layer.writtenOrigin, let angles = layer.writtenAngles else { return nil }
        return (origin, angles)
    }

    /// The index of the path `id` plays, nil for none (tests).
    func playingPath(_ id: String) -> Int? {
        layers.first { $0.object.id == id }?.current
    }

    // MARK: - Playback

    private func play(_ layer: Layer, input: FrameInput) {
        guard !layer.queue.isEmpty else { return }
        // A finished path is rewound and the queue steps on from it (the index stays for "sequential").
        var picks = layer.current == nil
        if let current = layer.current, var clock = layer.paths[current].clock, clock.flags.contains(.finished) {
            clock.flags.remove(.finished)
            clock.time = 0
            layer.paths[current].clock = clock
            picks = true
        }
        if picks { layer.current = next(layer) }
        guard let index = layer.current else { return }
        let path = layer.paths[index]
        guard var clock = path.clock else { return }
        clock.advance(by: input.deltaTime)
        path.clock = clock

        let world = worldMatrix(layer, input: input)
        let row = { (i: Int) in SIMD3(world[i].x, world[i].y, world[i].z) }
        var eye = row(3)
        var center = eye - 5 * simd_normalize(row(2))
        var up = simd_normalize(row(1))
        Self.sample(&path.eye, on: clock, into: &eye)
        Self.sample(&path.center, on: clock, into: &center)
        Self.sample(&path.up, on: clock, into: &up)
        layer.writtenOrigin = eye
        layer.writtenAngles = SceneWorldMatrix.lookAtAngles(eye: eye, center: center, up: up)
        if var channel = path.fovChannel, channel.channels.first.map({ !$0.keyframes.isEmpty }) ?? false {
            path.fov = channel.components(on: clock).x
            path.fovChannel = channel
        }
    }

    /// The next path to play, WE's queue step (0x1401f2bab…0x1401f2e70).
    private func next(_ layer: Layer) -> Int? {
        if layer.sequential {
            var index = layer.current ?? -1
            for _ in layer.paths.indices {
                index = (index + 1) % layer.paths.count
                if layer.queue.contains(index) { return index }
            }
            return nil
        }
        if layer.bag.isEmpty { layer.bag = layer.queue }
        var pick = Int(layer.random.next() % UInt64(layer.bag.count))
        for _ in layer.bag.indices where layer.bag[pick] == layer.last {
            pick = (pick + 1) % layer.bag.count
        }
        let index = layer.bag.remove(at: pick)
        layer.last = index
        return index
    }

    /// Components of `animation` that have keyframes replace `value`'s.
    private static func sample(_ animation: inout SceneTimelineAnimation?, on clock: SceneTimelineClock,
                               into value: inout SIMD3<Float>) {
        guard var channels = animation else { return }
        let sampled = channels.components(on: clock)
        for component in 0..<min(channels.channels.count, 3) where !channels.channels[component].keyframes.isEmpty {
            value[component] = sampled[component]
        }
        animation = channels
    }

    /// The layer's world matrix: its parents' times its own transform, the written-back origin
    /// and angles standing in for the authored ones, scripts and timelines over both.
    private func worldMatrix(_ layer: Layer, input: FrameInput) -> simd_float4x4 {
        let id = layer.object.id
        var own = transforms.nodes[id]?.local ?? .identity
        if let origin = layer.writtenOrigin { own.origin = origin }
        if let angles = layer.writtenAngles { own.angles = angles }
        return transforms.world(of: id, local: input.live(id) ?? own, live: input.live)
    }

    /// A seeded generator for the random queue: WE's own generator (behind 0x140077e10) isn't
    /// reproduced, only its bag [I: the order WE draws is its generator's].
    struct SplitMix {
        var state: UInt64

        mutating func next() -> UInt64 {
            state &+= 0x9E37_79B9_7F4A_7C15
            var z = state
            z = (z ^ (z >> 30)) &* 0xBF58_476D_1CE4_E5B9
            z = (z ^ (z >> 27)) &* 0x94D0_49BB_1331_11EB
            return z ^ (z >> 31)
        }
    }
}

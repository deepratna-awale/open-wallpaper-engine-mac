import simd

/// A Puppet Warp image's skeleton in motion (docs/models-plan.md §2.8, §2.13, §4.3 M6/P2): its
/// animation layers evaluated every frame the layer is visible (0x1401fdf90), the local and
/// model-space bone matrices WE keeps (puppet+0x310, +0x2c8) and the bone palette the mesh is
/// drawn with (`ScenePuppetPose`, puppet+0x2f8). Scripts reach it through `SceneScriptRigCommand`s
/// and read it back through `SceneScriptRigFeedback`. Render thread only.
final class ScenePuppetAnimator {
    let skeleton: SceneSkeleton
    private(set) var stack: SceneAnimationLayerStack
    /// Each bone's local matrix as last evaluated or set (`getLocalBoneTransform`).
    private(set) var locals: [simd_float4x4]
    /// Each bone's model-space matrix (`getBoneTransform` before the object's world).
    private(set) var worlds: [simd_float4x4]
    private(set) var pose: ScenePuppetPose
    /// What the last `advance` did besides posing.
    private(set) var lastUpdate = SceneAnimationLayerUpdate()

    /// An authored layer's bound values: user bindings and `animation` timelines on `rate`,
    /// `blend` and `visible`, re-read every frame until a script sets the field.
    private struct Binding {
        var rate: SceneRawValue?
        var blend: SceneRawValue?
        var visible: SceneRawValue?
        var rateTimeline: SceneTimelineAnimation?
        var blendTimeline: SceneTimelineAnimation?
    }

    private var bindings: [Int: Binding] = [:]
    /// Local matrices scripts set this frame, laid over the evaluated pose once.
    private var pendingLocals: [Int: simd_float4x4] = [:]
    /// Model-space matrices `setBoneTransform` set: that bone's palette entry only, its children
    /// untouched (0x14020f350). Kept until the next evaluation or local write recomputes the bones.
    private var worldOverrides: [Int: simd_float4x4] = [:]
    private var nextScriptKey = 1 << 20

    /// `layers` are the image's authored `animationlayers`; one naming no clip of `clips` makes
    /// no layer (WE's parser, 0x1402230fe), and is reported through `missing`.
    init(skeleton: MDLSkeleton, clips: [MDLAnimation], layers: [WEAnimationLayer],
         missing: (WEAnimationLayer) -> Void = { _ in }) {
        let skeleton = SceneSkeleton(skeleton)
        self.skeleton = skeleton
        stack = SceneAnimationLayerStack(skeleton: skeleton, clips: clips)
        locals = skeleton.bindLocal
        worlds = skeleton.bindWorld
        pose = .bind(boneCount: skeleton.boneCount)
        for (position, authored) in layers.enumerated() {
            guard let id = authored.animation, let clip = stack.clipIndex(id: id) else {
                missing(authored)
                continue
            }
            let key = authored.id ?? position
            let layer = SceneAnimationLayer(key: key, name: authored.name ?? "", clip: clip, animation: clips[clip],
                                            additive: authored.additive, blendIn: authored.blendIn,
                                            blendOut: authored.blendOut, blendTime: Float(authored.blendTime),
                                            rate: Float(authored.rate), blend: Float(authored.blend),
                                            visible: authored.visible)
            stack.insert(layer, autosort: authored.autosort ?? false, index: authored.index)
            bindings[key] = Binding(rate: authored.values[.rate], blend: authored.values[.blend],
                                    visible: authored.values[.visible],
                                    rateTimeline: Self.timeline(authored.values[.rate]),
                                    blendTimeline: Self.timeline(authored.values[.blend]))
        }
    }

    /// A bound value's keyframe timeline, run on its own clock (docs/timeline-plan.md §2).
    private static func timeline(_ raw: SceneRawValue?) -> SceneTimelineAnimation? {
        guard let raw, let json = raw.animation else { return nil }
        do {
            // Only a string `value` matters to a timeline (`relative`).
            var staticValue: SceneJSON?
            if case .object(let object) = raw, let text = object.value?.literalString { staticValue = .string(text) }
            return try SceneTimelineAnimation(json: json, staticValue: staticValue)
        } catch {
            OWELog.error(.scene, "An animation layer's timeline can't play: \(error)")
            return nil
        }
    }

    /// One frame (`delta` scene seconds): the bound values, the layers, then scripts' bone writes.
    /// A rig with layers is posed from its bind pose every frame, which replaces what scripts set
    /// before; one without keeps its bones as scripts leave them [I: 0x1401fdf90 wasn't traced].
    func advance(delta: Float, values: SceneValueContext) {
        resolveBindings(delta: delta, values: values)
        var update = SceneAnimationLayerUpdate()
        if !stack.layers.isEmpty {
            let transforms = stack.evaluate(delta: delta, update: &update)
            locals = transforms.map(\.matrix)
            worldOverrides.removeAll()
        }
        for (bone, matrix) in pendingLocals where bone < locals.count { locals[bone] = matrix }
        pendingLocals.removeAll()
        lastUpdate = update
        recompute()
    }

    private func resolveBindings(delta: Float, values: SceneValueContext) {
        for (key, binding) in bindings {
            var binding = binding
            let rate = binding.rateTimeline.map { timeline -> Float in
                var timeline = timeline
                timeline.clock.advance(by: delta)
                binding.rateTimeline = timeline
                return timeline.value().first ?? 1
            } ?? binding.rate?.userBindingSource.map { SceneValueResolver.resolve($0, in: values).float }
            let blend = binding.blendTimeline.map { timeline -> Float in
                var timeline = timeline
                timeline.clock.advance(by: delta)
                binding.blendTimeline = timeline
                return timeline.value().first ?? 1
            } ?? binding.blend?.userBindingSource.map { SceneValueResolver.resolve($0, in: values).float }
            let visible = binding.visible?.userBindingSource.map { SceneValueResolver.resolve($0, in: values).float != 0 }
            bindings[key] = binding
            stack.update(key: key) { layer in
                if let rate { layer.rate = rate }
                if let blend { layer.blend = blend }
                if let visible { layer.visible = visible }
            }
        }
    }

    /// Worlds from the locals, then `setBoneTransform`'s overrides, then the palette.
    private func recompute() {
        var worlds = skeleton.worlds(locals: locals)
        var palette = skeleton.palette(worlds: worlds)
        for (bone, matrix) in worldOverrides where bone < worlds.count {
            worlds[bone] = matrix
            palette[bone] = matrix * skeleton.inverseBind[bone]
        }
        self.worlds = worlds
        let next = ScenePuppetPose(bones: palette, bonesAlpha: pose.bonesAlpha)
        if next != pose { pose = next }
    }

    // MARK: - Scripts

    /// A script's call (`IImageLayer`, `IAnimationLayer`), in the order scripts made them.
    func perform(_ command: SceneScriptRigCommand) {
        switch command {
        case let .createLayer(key, clip, config, singlePlay):
            guard let index = stack.clipIndex(named: clip) else { return }
            var layer = SceneAnimationLayer(key: key, name: config.name ?? clip, clip: index,
                                            animation: stack.clips[index], additive: config.additive,
                                            blendIn: config.blendIn, blendOut: config.blendOut,
                                            blendTime: config.blendTime, rate: config.rate, blend: config.blend,
                                            visible: config.visible)
            layer.removesWhenFinished = singlePlay
            stack.insert(layer, autosort: config.autosort, index: nil)
            nextScriptKey = max(nextScriptKey, key + 1)
        case .destroyLayer(let key):
            stack.remove(key: key)
            bindings[key] = nil
        case let .setLayer(key, field, value):
            // A script's write replaces the field's binding from then on.
            switch field {
            case .rate:
                bindings[key]?.rate = nil
                bindings[key]?.rateTimeline = nil
                stack.update(key: key) { $0.rate = value }
            case .blend:
                bindings[key]?.blend = nil
                bindings[key]?.blendTimeline = nil
                stack.update(key: key) { $0.blend = value }
            case .visible:
                bindings[key]?.visible = nil
                stack.update(key: key) { $0.visible = value != 0 }
            }
        case let .playback(key, action):
            stack.update(key: key) { layer in
                switch action {
                case .play: layer.clock.play()
                case .pause: layer.clock.pause()
                case .stop: layer.clock.stop()
                case .setFrame(let frame): layer.clock.setFrame(frame)
                }
            }
        case let .setLocal(bone, matrix):
            guard bone >= 0, bone < locals.count else { return }
            pendingLocals[bone] = matrix
            locals[bone] = matrix
            worldOverrides.removeAll()
            recompute()
        case let .setWorld(bone, matrix):
            guard bone >= 0, bone < locals.count else { return }
            worldOverrides[bone] = matrix
            recompute()
        }
    }

    /// The layers as scripts see them, in evaluation order.
    var layerStates: [SceneScriptRigFeedback.Layer] {
        stack.layers.map { layer in
            SceneScriptRigFeedback.Layer(key: layer.key, name: layer.name, clip: layer.clip, time: layer.clock.time,
                                         frame: layer.clock.frame, flags: layer.clock.flags, rate: layer.rate,
                                         blend: layer.blend, visible: layer.visible)
        }
    }
}

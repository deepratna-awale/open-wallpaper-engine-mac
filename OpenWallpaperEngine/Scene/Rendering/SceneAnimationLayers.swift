import simd

/// One animation layer of a skinned object: a clip of the `.mdl` played on its own clock and laid
/// over the pose with a weight (docs/models-plan.md §2.8; the layer object 0x14026c680, its
/// properties 0x14026c980). Models and Puppet Warp images use the same layers.
struct SceneAnimationLayer: Equatable {
    /// Stable within its stack: the authored `id`, or one a script's layer was given.
    var key: Int
    var name: String
    /// The clip's index in the stack's `clips`.
    let clip: Int
    /// WE's clip clock (layer+0xf8: 0x1401a9f60 advances it, 0x140170580 samples it), which is the
    /// timelines' clock: mode, fps, frame count and events come from the clip.
    var clock: SceneTimelineClock
    var additive: Bool
    /// Ramps the weight up over the first `min(duration/2, blendTime)` seconds; a clip that isn't
    /// "single" ramps once (the flag clears when the ramp reaches 1).
    var blendIn: Bool
    /// Ramps the weight down over the last `min(duration/2, blendTime)` seconds; kept only for
    /// "single" clips (0x140223548).
    var blendOut: Bool
    var blendTime: Float
    /// Animatable; any float (a negative rate plays backwards).
    var rate: Float
    /// Animatable; 1 replaces, (0, 1) nlerps from the pose below, 0 skips the layer.
    var blend: Float
    /// An invisible layer neither advances nor applies.
    var visible: Bool
    /// `playSingleAnimation`: the layer goes once its clip finished [I].
    var removesWhenFinished = false

    init(key: Int, name: String, clip: Int, animation: MDLAnimation, additive: Bool = false, blendIn: Bool = false,
         blendOut: Bool = false, blendTime: Float = 0.5, rate: Float = 1, blend: Float = 1, visible: Bool = true) {
        self.key = key
        self.name = name
        self.clip = clip
        clock = Self.clock(for: animation)
        self.additive = additive
        self.blendIn = blendIn
        self.blendOut = blendOut && animation.mode == .single
        self.blendTime = blendTime
        self.rate = rate
        self.blend = blend
        self.visible = visible
    }

    /// The clip's clock (0x1401a8c10): `frames / fps` seconds, its mode, its events at
    /// `frame / fps`. A clip without a positive fps or duration gets a clock that never moves.
    static func clock(for animation: MDLAnimation) -> SceneTimelineClock {
        var flags: SceneTimelineClock.Flags = []
        switch animation.mode {
        case .mirror: flags.insert(.mirror)
        case .single: flags.insert(.single)
        case .loop: break
        }
        let fps = animation.fps
        let frameDuration: Float = fps > 0 ? 1 / fps : 1
        let duration: Float = fps > 0 ? Float(animation.frames) / fps : 0
        let events = animation.events.map {
            SceneTimelineClock.Event(name: $0.name, frame: $0.frame, time: $0.frame * frameDuration)
        }
        return SceneTimelineClock(frameDuration: frameDuration, duration: max(0, duration),
                                  length: Int32(clamping: animation.frames), flags: flags, events: events)
    }

    /// The weight this frame (0x14026c8b0): `blend`, times the blend-in ramp
    /// `min(time / min(duration/2, blendTime), 1)` and the blend-out ramp
    /// `min((duration − time) / min(duration/2, blendTime), 1)`; a ramp whose `min(duration,
    /// blendTime)` is not above FLT_EPSILON is 1. Mutating: a looping clip's blend-in ends once
    /// its ramp reached 1.
    mutating func weight() -> Float {
        let epsilon: Float = 1.1920929e-07
        let duration = clock.duration, time = clock.time
        var weight = blend
        if blendIn {
            var ramp: Float = 1
            if min(duration, blendTime) > epsilon {
                ramp = min(time / min(duration * 0.5, blendTime), 1)
            }
            weight = ramp * blend
            if !clock.flags.contains(.single), ramp >= 1 { blendIn = false }
        }
        if blendOut, min(duration, blendTime) > epsilon {
            weight *= min((duration - time) / min(duration * 0.5, blendTime), 1)
        }
        return weight
    }
}

/// What one frame of a stack did besides posing: clip events crossed, layers whose clip reached
/// its end (`addEndedCallback`), and layers removed because their single clip finished.
struct SceneAnimationLayerUpdate: Equatable {
    struct Event: Equatable {
        var layer: Int
        var name: String
        var frame: Float
    }

    var events: [Event] = []
    var ended: [Int] = []
    var removed: [Int] = []
}

/// A skinned object's animation layers in evaluation order and the pose they make
/// (docs/models-plan.md §2.8; the update 0x14021c480 for models, 0x1401fdf90 for puppets).
///
/// Each frame the pose starts from the bind pose; every visible layer advances its clock by
/// `delta × rate`, samples its clip between the two frames around its time (translation and
/// scale lerped, rotation nlerped), and applies it to the bones whose track is enabled with its
/// weight `w`: `w = 1` replaces (0x1401f89a0), additive layers add their clip's change from the
/// bind pose scaled by `w` (0x1401f9820), any other non-zero `w` nlerps from the pose (0x1401f9020),
/// `w = 0` skips the layer.
struct SceneAnimationLayerStack: Equatable {
    let skeleton: SceneSkeleton
    let clips: [MDLAnimation]
    private(set) var layers: [SceneAnimationLayer] = []

    init(skeleton: SceneSkeleton, clips: [MDLAnimation]) {
        self.skeleton = skeleton
        self.clips = clips
    }

    /// The clip with that id, what an authored layer's `animation` names.
    func clipIndex(id: UInt64) -> Int? { clips.firstIndex { $0.id == id } }

    /// The clip a script names: its name, else a number as its id [I].
    func clipIndex(named name: String) -> Int? {
        clips.firstIndex { $0.name == name } ?? UInt64(name).flatMap(clipIndex(id:))
    }

    func index(ofLayer key: Int) -> Int? { layers.firstIndex { $0.key == key } }

    /// Adds a layer where WE's parser puts it (0x14022375c): `autosort` before the trailing run
    /// of additive layers, else at `index` clamped to the list, else at the end. Returns its index.
    @discardableResult
    mutating func insert(_ layer: SceneAnimationLayer, autosort: Bool = false, index: Int? = nil) -> Int {
        let position: Int
        if autosort {
            var end = layers.count
            while end > 0, layers[end - 1].additive { end -= 1 }
            position = end
        } else if let index {
            position = max(0, min(index, max(layers.count - 1, 0)))
        } else {
            position = layers.count
        }
        layers.insert(layer, at: min(position, layers.count))
        return position
    }

    /// Removes the layer; false when there is none.
    @discardableResult
    mutating func remove(key: Int) -> Bool {
        guard let index = index(ofLayer: key) else { return false }
        layers.remove(at: index)
        return true
    }

    mutating func update(key: Int, _ change: (inout SceneAnimationLayer) -> Void) {
        guard let index = index(ofLayer: key) else { return }
        change(&layers[index])
    }

    /// Advances every visible layer by `delta` seconds and returns the pose, one transform per bone.
    mutating func evaluate(delta: Float, update: inout SceneAnimationLayerUpdate) -> [SceneBoneTransform] {
        var morphs: [SceneMorphWeights] = []
        return evaluate(delta: delta, update: &update, morphs: &morphs, kind: .model)
    }

    /// The same, with each layer's morph tracks laid over `morphs` (`applyMorphs`) as it applies.
    mutating func evaluate(delta: Float, update: inout SceneAnimationLayerUpdate, morphs: inout [SceneMorphWeights],
                           kind: SceneMorphRig.Kind) -> [SceneBoneTransform] {
        var pose = skeleton.bindPose
        var index = 0
        while index < layers.count {
            guard layers[index].visible else {
                index += 1
                continue
            }
            let key = layers[index].key
            let before = layers[index].clock
            let crossed = layers[index].clock.advance(by: delta * layers[index].rate)
            let after = layers[index].clock
            update.events += crossed.map { .init(layer: key, name: $0.name, frame: $0.frame) }
            if Self.ended(before: before, after: after) { update.ended.append(key) }
            let weight = layers[index].weight()
            apply(layers[index], weight: weight, to: &pose)
            if !morphs.isEmpty { applyMorphs(layers[index], weight: weight, to: &morphs, kind: kind) }
            if layers[index].removesWhenFinished, after.flags.contains(.finished) {
                layers.remove(at: index)
                update.removed.append(key)
                continue
            }
            index += 1
        }
        return pose
    }

    /// Whether the clip reached its end this frame (0x14021c6e6…0x14021c743): not when it was
    /// paused or finished before; a single clip when it finished, a mirror when it turned, a loop
    /// when its time went down (it wrapped, or it plays backwards).
    static func ended(before: SceneTimelineClock, after: SceneTimelineClock) -> Bool {
        guard before.flags.isDisjoint(with: [.paused, .finished]) else { return false }
        if before.flags.contains(.single) { return after.flags.contains(.finished) }
        if before.flags.contains(.mirror) { return before.flags.contains(.reversed) != after.flags.contains(.reversed) }
        return before.time > after.time
    }

    /// The clip's pose at the clock's position for every bone; nil where the track is disabled
    /// or missing (the bone keeps what is below).
    func sample(_ layer: SceneAnimationLayer) -> [SceneBoneTransform?] {
        let clip = clips[layer.clip]
        let position = layer.clock.samplePosition
        let t = position.fraction
        return (0..<skeleton.boneCount).map { bone -> SceneBoneTransform? in
            guard bone < clip.boneTracks.count else { return nil }
            let track = clip.boneTracks[bone]
            let frames = track.samples.count / MDLBonePose.floatCount
            guard !track.isDisabled, frames > 0 else { return nil }
            let a = SceneBoneTransform(track.pose(at: Self.frame(position.frame0, frames)))
            let b = SceneBoneTransform(track.pose(at: Self.frame(position.frame1, frames)))
            return SceneBoneTransform.blend(a, b, t)
        }
    }

    private static func frame(_ frame: Int32, _ count: Int) -> Int { max(0, min(Int(frame), count - 1)) }

    /// Lays one layer's sample over `pose` with `weight`.
    func apply(_ layer: SceneAnimationLayer, weight: Float, to pose: inout [SceneBoneTransform]) {
        guard weight != 0 else { return }
        let samples = sample(layer)
        for bone in pose.indices {
            guard let sample = samples[bone] else { continue }
            if layer.additive {
                pose[bone] = Self.add(sample, over: pose[bone], bind: skeleton.bindPose[bone], weight: weight)
            } else if weight == 1 {
                pose[bone] = sample
            } else {
                pose[bone] = SceneBoneTransform.blend(pose[bone], sample, weight)
            }
        }
    }

    /// 0x1401f9820: translation and scale gain `w · (sample − bind)`; the rotation is composed with
    /// the sample's rotation away from the bind pose, nlerped from the identity by `w` (shorter
    /// arc) [I: the order of the two quaternion products; it doesn't matter for rotations about
    /// one axis, which every library puppet's are].
    static func add(_ sample: SceneBoneTransform, over pose: SceneBoneTransform, bind: SceneBoneTransform,
                    weight: Float) -> SceneBoneTransform {
        let delta = (sample.rotation * bind.rotation.inverse).normalized
        let scaled = SceneBoneTransform.nlerp(SceneBoneTransform.identity.rotation, delta, weight)
        return SceneBoneTransform(translation: pose.translation + (sample.translation - bind.translation) * weight,
                                  rotation: (scaled * pose.rotation).normalized,
                                  scale: pose.scale + (sample.scale - bind.scale) * weight)
    }
}

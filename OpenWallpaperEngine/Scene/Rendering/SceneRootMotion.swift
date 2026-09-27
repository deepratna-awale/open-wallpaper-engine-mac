import simd

/// A clip's root motion (docs/models-plan.md §2.8 "Root motion"): the model editor's Motion root
/// bone and axes (`MDLAnimation.Flag`, the clip record `MDLAnimation.Reference`). WE's model
/// update (0x14021c480) calls 0x140225900 after each visible layer whose clip has root-motion
/// flags, while the object's `rootmotion` is on. It takes the flagged axes out of the root bone's
/// pose and moves the object by them instead:
/// - the root's local translation gains `(start − current)·w` on each flagged position axis,
///   componentwise, the model-space position difference added to the local translation;
/// - with yaw (0x8000) its local rotation is pre-multiplied by `YB · YA⁻¹`, which takes the yaw
///   the root gained since the start frame out of it;
/// - the object's origin gains the frame's root displacement on the flagged axes, through the
///   object's world rotation and scale, times `w` and the weight the later layers leave; its yaw
///   gains the frame's yaw change the same way.
///
/// The root's matrices here are WE's (0x140267580, 0x140267f00): the clip's own samples chained up
/// the parents with translation and rotation only (no scale). Matrices are column-vector (`simd`
/// and glm: column i is WE's row i), so WE's row-major products appear reversed.
///
/// WE's captures (docs/test-risks.md MG4, the editor's own `.mdl`s) follow this frame by frame for
/// each position axis and for all axes together. Yaw alone is the open point: there the capture
/// keeps the object's yaw (see §2.8).
struct SceneRootMotion: Equatable {
    /// The root bone.
    let bone: Int
    /// The clip's `MDLAnimation.Flag`s.
    let flags: UInt32
    /// The root's matrix at the start frame (ref+0x1c), its rotation's inverse (ref+0x5c) and its
    /// matrix at the end frame (ref+0x80).
    let start: simd_float4x4
    let startRotationInverse: simd_float3x3
    let end: simd_float4x4
    /// The frame the root's previous matrix starts at on the layer's first frame, when the clip
    /// has a frame offset: `start + offset`, or 0 with Match loop (0x14022618d…0x1402261cf).
    let firstFrame: Int?

    /// A layer's root-motion state (the layer's flag 0x80000000 and +0x148, +0x14c).
    struct State: Equatable {
        /// Whether the previous frame ran root motion for this layer (it then has `previous`).
        var active = false
        /// The layer's clock time last frame; a later time below it is a loop.
        var previousTime: Float = 0
        /// The root's matrix last frame.
        var previous = matrix_identity_float4x4
    }

    /// What root motion moved the object by since the load: its origin (in its parent's space)
    /// and its yaw, about its own y axis (radians, wrapped as WE wraps `angles.y`).
    struct Motion: Equatable {
        var origin = SIMD3<Float>(repeating: 0)
        var yaw: Float = 0

        var isZero: Bool { origin == SIMD3(repeating: 0) && yaw == 0 }

        /// `local` moved by the motion: the origin offset, and the yaw WE applies to `angles`,
        /// `rotate(R(angles), yaw, y)` read back as angles (0x140215020, 0x1401e2500, 0x1401e23d0;
        /// with `angles.x` and `angles.z` both zero that is `angles.y + yaw`).
        func applied(to local: SceneLocalTransform3D) -> SceneLocalTransform3D {
            var result = local
            result.origin += origin
            guard yaw != 0 else { return result }
            if abs(local.angles.x) + abs(local.angles.z) < 0.0001 {
                result.angles.y = fmodf(local.angles.y + yaw, 2 * .pi)
                return result
            }
            let (row0, row1, row2) = SceneWorldMatrix.rows(local.angles)
            let rotation = simd_float3x3(row0, row1, row2) * SceneRootMotion.yawMatrix(sin: sin(yaw), cos: cos(yaw))
            result.angles = SceneWorldMatrix.angles(row0: rotation.columns.0, row1: rotation.columns.1,
                                                    row2: rotation.columns.2)
            return result
        }
    }

    /// The clip's root motion; nil when it has none: no root-motion flag, no clip record (WE
    /// dereferences the missing record; its capture showed such a model never loading, MG4), or
    /// no root bone.
    init?(clip: MDLAnimation, clips: [MDLAnimation], skeleton: SceneSkeleton) {
        guard clip.flags & MDLAnimation.Flag.rootMotion != 0, let reference = clip.reference,
              reference.rootBone >= 0, Int(reference.rootBone) < skeleton.boneCount else { return nil }
        bone = Int(reference.rootBone)
        flags = clip.flags
        // 0x1402651b7…0x140265232: Match loop reads this clip's first and last frames, else the
        // source clip's Start and End frames.
        let matchLoop = clip.flags & MDLAnimation.Flag.matchLoop != 0
        let source = matchLoop || Int(reference.animation) >= clips.count ? clip : clips[Int(reference.animation)]
        let startFrame = matchLoop ? 0 : Int(reference.startFrame)
        let endFrame = matchLoop ? Int(clip.frames) : Int(reference.endFrame)
        start = Self.rootMatrix(source, skeleton: skeleton, bone: bone, frame0: startFrame, frame1: startFrame, fraction: 0)
        startRotationInverse = Self.rotation(start).inverse
        end = Self.rootMatrix(source, skeleton: skeleton, bone: bone, frame0: endFrame, frame1: endFrame, fraction: 0)
        firstFrame = reference.frameOffset == 0 ? nil : (matchLoop ? 0 : Int(reference.startFrame + reference.frameOffset))
    }

    /// One layer's frame (0x140225900): `clip` sampled at `frame0`…`frame1` by `fraction` at clock
    /// `time`, `weight` the layer's and `remaining` what the later layers leave of it. Changes the
    /// root in `pose`, the layer's `state` and the object's `motion`; `objectWorld` is the
    /// object's world rotation and scale.
    func apply(clip: MDLAnimation, skeleton: SceneSkeleton, frame0: Int, frame1: Int, fraction: Float, time: Float,
               weight: Float, remaining: Float, objectWorld: simd_float3x3, pose: inout [SceneBoneTransform],
               state: inout State, motion: inout Motion) {
        let current = Self.rootMatrix(clip, skeleton: skeleton, bone: bone, frame0: frame0, frame1: frame1, fraction: fraction)
        let currentRotation = Self.rotation(current)
        let startRotation = Self.rotation(start)
        let startTranslation = Self.translation(start), currentTranslation = Self.translation(current)
        // The yaw the root gained since the start (YA), and the start's own (YB: the identity but
        // for rounding); M takes the first out.
        let gained = Self.yaw(currentRotation * startRotationInverse)
        let own = Self.yaw(startRotation * startRotationInverse)
        let removal = own * gained.transpose
        if bone < pose.count {
            let axes: [UInt32] = [MDLAnimation.Flag.rootPositionX, MDLAnimation.Flag.rootPositionY, MDLAnimation.Flag.rootPositionZ]
            for (axis, flag) in axes.enumerated() where flags & flag != 0 {
                pose[bone].translation[axis] += (startTranslation[axis] - currentTranslation[axis]) * weight
            }
            if flags & MDLAnimation.Flag.rootRotationY != 0 {
                // The SoA quaternion product at 0x140225ec8 (not normalised).
                pose[bone].rotation = simd_quatf(removal) * pose[bone].rotation
            }
        }
        // The previous matrix: last frame's, else the start (or the offset frame).
        var previous = state.previous
        if !state.active {
            previous = firstFrame.map {
                Self.rootMatrix(clip, skeleton: skeleton, bone: bone, frame0: $0, frame1: $0, fraction: 0)
            } ?? start
        }
        var previousRotation = Self.rotation(previous)
        var loop = SIMD3<Float>(repeating: 0)
        if state.previousTime > time {
            // The clip looped: carry the whole clip's displacement over, and take the previous
            // rotation back to the start (0x140226267…0x1402263cb).
            loop = Self.translation(end) - startTranslation
            previousRotation = previousRotation * Self.rotation(end).inverse * startRotation
        }
        let gainedBefore = Self.yaw(previousRotation * startRotationInverse)
        let scaled = weight * remaining
        if flags & (MDLAnimation.Flag.rootPositionX | MDLAnimation.Flag.rootPositionY | MDLAnimation.Flag.rootPositionZ) != 0 {
            let step: SIMD3<Float> = loop + (currentTranslation - Self.translation(previous))
                - gained * startTranslation + gainedBefore * startTranslation
            var moved = removal * step
            if flags & MDLAnimation.Flag.rootPositionX == 0 { moved.x = 0 }
            if flags & MDLAnimation.Flag.rootPositionY == 0 { moved.y = 0 }
            if flags & MDLAnimation.Flag.rootPositionZ == 0 { moved.z = 0 }
            motion.origin += objectWorld * moved * scaled
        }
        if flags & MDLAnimation.Flag.rootRotationY != 0 {
            // The yaw change since last frame, Euler y of `gainedBefore⁻¹ · gained` (0x14022689f).
            let change = gainedBefore.transpose * gained
            let columns = change.columns
            let angle = atan2(-columns.0.z, (columns.1.z * columns.1.z + columns.2.z * columns.2.z).squareRoot())
            motion.yaw = fmodf(motion.yaw + angle * scaled, 2 * .pi)
        }
        state.previous = current
    }

    // MARK: - Matrices

    /// The root's matrix in the clip (0x140267f00; 0x140267580 for one frame): each bone's sample
    /// between the two frames, translation lerped and rotation nlerped, as `T · R` without its
    /// scale, chained up the parents. A bone without a track keeps its bind pose.
    static func rootMatrix(_ clip: MDLAnimation, skeleton: SceneSkeleton, bone: Int, frame0: Int, frame1: Int,
                           fraction: Float) -> simd_float4x4 {
        var matrix = matrix_identity_float4x4
        var index: Int? = bone
        var visited = 0
        while let current = index, current >= 0, current < skeleton.boneCount, visited <= skeleton.boneCount {
            var local = skeleton.bindPose[current]
            if current < clip.boneTracks.count {
                let track = clip.boneTracks[current]
                let count = track.samples.count / MDLBonePose.floatCount
                if count > 0 {
                    let a = SceneBoneTransform(track.pose(at: max(0, min(frame0, count - 1))))
                    let b = SceneBoneTransform(track.pose(at: max(0, min(frame1, count - 1))))
                    local = SceneBoneTransform.blend(a, b, fraction)
                }
            }
            local.scale = SIMD3(repeating: 1)
            matrix = local.matrix * matrix
            index = skeleton.parents[current]
            visited += 1
        }
        return matrix
    }

    static func rotation(_ matrix: simd_float4x4) -> simd_float3x3 {
        simd_float3x3(SIMD3(matrix.columns.0.x, matrix.columns.0.y, matrix.columns.0.z),
                      SIMD3(matrix.columns.1.x, matrix.columns.1.y, matrix.columns.1.z),
                      SIMD3(matrix.columns.2.x, matrix.columns.2.y, matrix.columns.2.z))
    }

    static func translation(_ matrix: simd_float4x4) -> SIMD3<Float> {
        SIMD3(matrix.columns.3.x, matrix.columns.3.y, matrix.columns.3.z)
    }

    /// The yaw of a rotation (0x140225ab5…0x140225b7a): its z axis projected on the ground plane
    /// and normalised, `f`, as the rotation about y taking z to it. The identity when z is
    /// vertical [I: WE divides by zero there].
    static func yaw(_ rotation: simd_float3x3) -> simd_float3x3 {
        let axis = rotation.columns.2
        let length = (axis.x * axis.x + axis.z * axis.z).squareRoot()
        guard length > 0 else { return matrix_identity_float3x3 }
        return yawMatrix(sin: axis.x / length, cos: axis.z / length)
    }

    /// The rotation about y with that sine and cosine: columns (c, 0, −s), (0, 1, 0), (s, 0, c).
    static func yawMatrix(sin s: Float, cos c: Float) -> simd_float3x3 {
        simd_float3x3(SIMD3(c, 0, -s), SIMD3(0, 1, 0), SIMD3(s, 0, c))
    }
}

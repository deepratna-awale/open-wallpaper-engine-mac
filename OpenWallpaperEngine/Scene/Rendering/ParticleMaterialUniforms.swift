import Foundation
import simd

/// The particle-specific uniforms of WE's particle shaders for one system and frame: matrices,
/// the orthographic view, `g_Orientation*` and `g_RenderVar0/1`.
struct ParticleMaterialUniforms {
    /// Scene units (y up) to clip space. The translated vertex stage flips y (GL rows), so the
    /// top of the scene maps to GL's bottom.
    let modelViewProjection: simd_float4x4
    let renderVars: [Int: SIMD4<Float>]
    let eyePosition: SIMD3<Float>
    /// `g_OrientationRight` and `g_OrientationUp`: the renderer's orientation (`ParticleOrientation`;
    /// by default the scene camera's axes, 2D scenes look down −z with y up) through the emitter's
    /// scale and rotation (`ParticleSystemRuntime.drawLinear`). WE expands a sprite along them in the
    /// system's own space and draws it through the system's model matrix; the particles here are in
    /// scene space, so the axes carry it.
    let orientationRight: SIMD3<Float>
    let orientationUp: SIMD3<Float>
    /// `g_OrientationForward`: the renderer's (`ParticleOrientation`); (0, 0, 1) facing the camera.
    let orientationForward: SIMD3<Float>

    /// `g_ViewUp`, `g_ViewRight` and `g_ViewForward` in the system's space (`frame(from:)`).
    let viewUp: SIMD3<Float>
    let viewRight: SIMD3<Float>
    let viewForward: SIMD3<Float>

    /// A system drawn through a 3D camera (docs/models-plan.md §2.12): a perspective scene's
    /// camera, or the temporary one of a `perspective` system in an orthographic scene. WE draws a
    /// system's vertices through its model matrix and the camera; here the particles are simulated
    /// in the scene's plane, placed by the object's 2D transform, so `model` carries them from
    /// there to where the object's 3D world matrix puts them (identity when the two agree).
    struct Placement: Equatable {
        var camera: SceneFrameCamera
        var model = matrix_identity_float4x4

        /// A camera direction in the particles' own space, normalised.
        func direction(_ vector: SIMD3<Float>) -> SIMD3<Float> {
            let linear = simd_float3x3(SIMD3(model.columns.0.x, model.columns.0.y, model.columns.0.z),
                                       SIMD3(model.columns.1.x, model.columns.1.y, model.columns.1.z),
                                       SIMD3(model.columns.2.x, model.columns.2.y, model.columns.2.z))
            guard abs(linear.determinant) > 1e-12 else { return vector }
            let local = linear.inverse * vector
            let length = simd_length(local)
            return length > 1e-12 ? local / length : vector
        }

        /// The camera's eye in the particles' own space (`g_EyePosition`, which trails face).
        var eye: SIMD3<Float> {
            guard abs(model.determinant) > 1e-12 else { return camera.eye }
            let local = model.inverse * SIMD4(camera.eye, 1)
            return SIMD3(local.x, local.y, local.z) / local.w
        }
    }

    /// The scene camera's axes, as WE binds them to particles.
    static let orientationRight = SIMD3<Float>(1, 0, 0)
    /// How far in front of the scene the eye sits. The view is orthographic, so view rays are
    /// parallel; a distant eye keeps the shaders' eye-to-particle directions (trail and rope
    /// facing) parallel to them too.
    static let eyeDistance: Float = 100_000

    init(plan: ParticleMaterialPlan, system: ParticleSystemRuntime, sceneSize: SIMD2<Float>,
         texture0: BuiltinTextureInfo?, placement: Placement? = nil) {
        let size = simd_max(sceneSize, SIMD2(1, 1))
        let axes: (right: SIMD3<Float>, up: SIMD3<Float>, forward: SIMD3<Float>)
        if let placement {
            let camera = placement.camera
            modelViewProjection = PassMatrices.shaderViewProjection(camera.viewProjection) * placement.model
            eyePosition = placement.eye
            let forward = placement.direction(camera.forward), up = placement.direction(camera.up)
            axes = system.configuration.orientation.axes(linear: system.drawLinear, cameraForward: forward, cameraUp: up)
            // The view-projection flips y as the 2D one does (see `viewUp2D`).
            viewUp = -up
            viewRight = placement.direction(simd_cross(camera.forward, camera.up))
            viewForward = forward
        } else {
            modelViewProjection = PassMatrices.ortho(left: 0, right: size.x, bottom: size.y, top: 0)
            eyePosition = SIMD3(size.x / 2, size.y / 2, Self.eyeDistance)
            axes = system.configuration.orientation.axes(linear: system.drawLinear)
            viewUp = Self.viewUp2D
            viewRight = Self.orientationRight
            viewForward = SIMD3(0, 0, -1)
        }
        orientationRight = axes.right
        orientationUp = axes.up
        orientationForward = axes.forward
        var renderVars: [Int: SIMD4<Float>] = [:]
        switch plan.format {
        case .sprite: renderVars[0] = plan.trailLengths
        case .rope: renderVars[0] = ParticleRecordWriter.ropeRenderVar(system)
        }
        renderVars[1] = Self.spriteSheetRenderVar(plan.spriteSheet, texture: texture0)
        self.renderVars = renderVars
    }

    /// `g_RenderVar1`: `(frame width, frame height, frame count, frame height / width)`, frame
    /// sizes in texture coordinates of the allocated texture; without a sheet only the texture's
    /// aspect ratio.
    static func spriteSheetRenderVar(_ sheet: SpriteSheet?, texture: BuiltinTextureInfo?) -> SIMD4<Float> {
        let allocated = simd_max(texture?.allocatedSize ?? SIMD2(1, 1), SIMD2(1, 1))
        let content = simd_max(texture?.contentSize ?? allocated, SIMD2(1, 1))
        guard let sheet, sheet.columns > 0, sheet.rows > 0, sheet.frames > 0 else {
            return SIMD4(0, 0, 0, content.y / content.x)
        }
        let columns = Float(sheet.columns), rows = Float(sheet.rows)
        let frame = SIMD2(content.x / columns, content.y / rows)
        return SIMD4(frame.x / allocated.x, frame.y / allocated.y, Float(sheet.frames), frame.y / frame.x)
    }

    /// `g_ViewUp`: the scene direction that points up in the clip space the shaders see.
    /// `modelViewProjection` puts the top of the scene at GL's bottom (the translated stage flips
    /// it back), so that is scene −y. Screen coordinates derived from the clip position
    /// (`v_ScreenCoord`) then run top-down like Metal's texture rows, and the refraction offsets
    /// that `ComputeScreenRefractionTangents` builds from this axis follow them.
    static let viewUp2D = SIMD3<Float>(0, -1, 0)

    /// The frame's built-ins with this system's view.
    func frame(from frame: BuiltinFrameContext) -> BuiltinFrameContext {
        var result = frame
        result.eyePosition = eyePosition
        result.viewUp = viewUp
        result.viewRight = viewRight
        result.viewForward = viewForward
        return result
    }

    /// The block members `patch` writes, looked up once per layout.
    struct Members {
        let right, up, forward, eye, renderVar0, renderVar1: UniformMember?

        init(_ layout: UniformLayout) {
            right = layout.members["g_OrientationRight"]
            up = layout.members["g_OrientationUp"]
            forward = layout.members["g_OrientationForward"]
            eye = layout.members["g_EyePosition"]
            renderVar0 = layout.members["g_RenderVar0"]
            renderVar1 = layout.members["g_RenderVar1"]
        }
    }

    /// Writes the values `UniformProgram` doesn't: WE's particle-only uniforms, and the ones that
    /// change with the system every frame.
    func patch(_ bytes: inout [UInt8], members: Members) {
        let values: [(UniformMember?, [Float])] = [
            (members.right, Self.flat(orientationRight)),
            (members.up, Self.flat(orientationUp)),
            (members.forward, Self.flat(orientationForward)),
            (members.eye, Self.flat(eyePosition)),
            (members.renderVar0, Self.flat(renderVars[0] ?? .zero)),
            (members.renderVar1, Self.flat(renderVars[1] ?? .zero)),
        ]
        for (member, components) in values {
            guard let member else { continue }
            UniformWriter.write(components, member: member, into: &bytes)
        }
    }

    private static func flat(_ v: SIMD3<Float>) -> [Float] { [v.x, v.y, v.z] }
    private static func flat(_ v: SIMD4<Float>) -> [Float] { [v.x, v.y, v.z, v.w] }
}

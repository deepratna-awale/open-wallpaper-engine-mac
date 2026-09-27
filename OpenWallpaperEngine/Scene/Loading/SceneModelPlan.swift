import Foundation
import simd

/// A model object's `.mdl` ready to draw (docs/models-plan.md §2.6, §4.3 M5): each mesh with the
/// material its object's `skin` picks, planned through WE's shader (`ModelMaterialPlan`), its
/// interleaved vertices and indices as the file has them, the model's box, and the skeleton,
/// clips and attachment points its animation layers and children use. Shared by every object
/// drawing the same `.mdl` with the same skin. A final class so the renderer can key state on it.
final class SceneModelPlan {
    struct Mesh {
        /// The mesh's index in the `.mdl`.
        let index: Int
        let material: ModelMaterialPlan
        let format: MDLVertexFormat
        let vertexData: Data
        let indexData: Data
        let usesUInt32Indices: Bool
        let indexCount: Int
    }

    /// The `.mdl` path, for logging.
    let path: String
    /// The meshes that draw, in WE's draw-list order (`drawOrder`): the ones whose material
    /// doesn't translate are left out (logged).
    let meshes: [Mesh]
    /// The model's box (the union of its meshes', or unbounded; `MDLModel.bounds`).
    let bounds: MDLBounds
    let skeleton: MDLSkeleton?
    let clips: [MDLAnimation]
    let attachments: [MDLAttachment]

    init(path: String, meshes: [Mesh], bounds: MDLBounds, skeleton: MDLSkeleton?, clips: [MDLAnimation] = [],
         attachments: [MDLAttachment] = []) {
        self.path = path
        self.meshes = Self.drawOrder(meshes)
        self.bounds = bounds
        self.skeleton = skeleton
        self.clips = clips
        self.attachments = attachments
    }

    /// WE's translucent flag (0x140225241): every mesh blending normal or alpha-to-coverage clears
    /// it, so a model is translucent only when none of its meshes is opaque.
    var isTranslucent: Bool { !meshes.contains { $0.material.isOpaque } }

    /// The layers whose image a mesh samples (`_rt_imageLayerComposite_<id>_a`), by object id.
    var compositeLayerIDs: Set<String> {
        Set(meshes.flatMap { mesh in
            mesh.material.pass.textures.values.compactMap { input -> String? in
                if case .fbo(let name) = input { return ModelMaterialPlanBuilder.compositeLayerID(name) }
                return nil
            }
        })
    }

    /// The skeleton's bone count (0 without one).
    var boneCount: Int { skeleton?.bones.count ?? 0 }

    /// WE's mesh draw list (sorted with 0x14021a620, which orders a mesh with an opaque material
    /// before one with a translucent material and leaves the rest as they are): the opaque meshes
    /// first, then the translucent ones, each in file order [I: stable].
    static func drawOrder(_ meshes: [Mesh]) -> [Mesh] {
        meshes.filter { $0.material.isOpaque } + meshes.filter { !$0.material.isOpaque }
    }

    /// The animator that poses this model from its object's animation layers; nil for a model
    /// without bones. A layer naming no clip of the `.mdl` makes no layer (logged).
    func makeAnimator(layers: [WEAnimationLayer], objectName: String) -> ScenePuppetAnimator? {
        guard let skeleton, !skeleton.bones.isEmpty else { return nil }
        return ScenePuppetAnimator(skeleton: skeleton, clips: clips, layers: layers) { [path] layer in
            OWELog.error(.scene, "Model \(objectName) (\(path)) has no clip \(layer.animation.map(String.init) ?? "(none)") for "
                         + "animation layer \(layer.name ?? "?"); WE makes no layer for it")
        }
    }
}

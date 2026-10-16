import simd

/// What a model is hit tested with besides its world matrix, read once from its `.mdl`
/// (docs/scenescript-plan.md §4.8, "Models"): its box, `MDLModel.bounds` (the union of its meshes'
/// boxes, ±131072 without one; model data +0x1b8 / +0x1c4).
struct SceneScriptCursorShape: Equatable {
    enum Kind: Equatable {
        /// A model object and its box.
        case model(MDLBounds)
    }

    var kind: Kind

    /// A model object's shape.
    static func model(_ mdl: MDLModel) -> Self {
        Self(kind: .model(mdl.bounds))
    }
}

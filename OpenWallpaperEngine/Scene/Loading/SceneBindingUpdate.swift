import Foundation

/// What a change of user properties needs, from the binding table (`UserPropertyBindingTable`):
/// the owners whose bound values are applied in place, the objects rebuilt on their own, and a
/// whole-content rebuild or re-parse only for the app's own keys and scene-wide structural bindings.
struct SceneBindingUpdate: Equatable {
    /// A rebuild or re-parse of the whole scene: the app's own keys (`SceneChangeImpact.impact(of:)`),
    /// or a structural binding of the scene itself (`general`).
    var impact: SceneChangeImpact = .none
    /// Objects a structural binding change rebuilds, off the render thread, swapped in alone.
    var rebuild: Set<Int> = []
    /// Every owner a changed binding reads: each moves to a new binding revision, and takes its
    /// uniform and object values in place.
    var owners: Set<UserPropertyBindingOwner> = []

    init() {}

    /// The update for `keys`. A declared property no binding reads (only scripts do) needs nothing
    /// here: the renderer hands it to the scripts.
    init(keys: [String], table: UserPropertyBindingTable) {
        var properties = Set<String>()
        for key in keys {
            let own = SceneChangeImpact.impact(of: key)
            if own == .rebuildContent, !key.hasPrefix("_owe_") {
                properties.insert(key)
            } else {
                impact = max(impact, own)
            }
        }
        for (owner, dependency) in table.changes(for: properties) {
            owners.insert(owner)
            guard dependency == .structural else { continue }
            switch owner {
            case .object(let id): rebuild.insert(id)
            case .scene: impact = max(impact, .rebuildContent)
            }
        }
    }

    /// Nothing to do but hand the scripts the change.
    var isEmpty: Bool { impact == .none && rebuild.isEmpty && owners.isEmpty }
}

import Foundation

/// A texture slot of a layer bound to a `scenetexture` or `usershortcut` property.
public struct UserTextureBinding: Hashable, Sendable {
    public var layer: Int
    /// The material's texture slot (0, the albedo, is the one WE's editor binds).
    public var slot: Int

    public init(layer: Int, slot: Int = 0) {
        self.layer = layer
        self.slot = slot
    }
}

/// Binding texture slots to user textures and shortcuts. WE's editor binds a layer's albedo
/// texture (Advanced Texture Settings › Albedo › Bind User Property, `onTextureContextMenu`) and
/// keeps the link in the object's `instance.usertextures`, one entry per slot, beside WE's own
/// system textures (`{"name": "$mediaThumbnail", "type": "system"}`): a `scenetexture` link is the
/// property's key, a `usershortcut` link `{"name": key, "type": "usershortcut"}`.
extension UserPropertyAuthoring {
    /// The layers that can take a user texture: images (a solid placeholder is an image).
    public var textureLayers: [SceneLayer] {
        session.outline.layers.filter { $0.kind == .image }
    }

    /// The slots bound to `key`.
    public func textureBindings(of key: String) -> [UserTextureBinding] {
        textureLayers.flatMap { layer in
            Self.userTextures(in: session.value("instance", of: layer.id)).enumerated().compactMap { slot, entry in
                Self.linkedKey(entry) == key ? UserTextureBinding(layer: layer.id, slot: slot) : nil
            }
        }
    }

    /// The property a slot is bound to, if any (a system texture is none).
    public func textureProperty(of binding: UserTextureBinding) -> String? {
        let entries = Self.userTextures(in: session.value("instance", of: binding.layer))
        return entries.indices.contains(binding.slot) ? Self.linkedKey(entries[binding.slot]) : nil
    }

    /// Binds a slot to the user texture or shortcut `key`, replacing what it had; one undo step.
    public func bindTexture(_ binding: UserTextureBinding, to key: String, actionName: String) {
        guard let property = property(key), property.kind.bindsTexture else { return }
        let link: SceneJSONValue = property.kind == .userShortcut
            ? .object(["name": .string(key), "type": .string(UserPropertyDraft.Kind.userShortcut.rawValue)])
            : .string(key)
        session.editOverlay(actionName: actionName) { overlay in
            setUserTexture(link, binding, in: &overlay)
        }
    }

    /// Unbinds a slot: the layer shows its own texture again.
    public func unbindTexture(_ binding: UserTextureBinding, actionName: String) {
        guard textureProperty(of: binding) != nil else { return }
        session.editOverlay(actionName: actionName) { overlay in
            setUserTexture(nil, binding, in: &overlay)
        }
    }

    /// Re-points every slot bound to `key` at `newKey` (inside a rename's undo step).
    func renameTextureBindings(_ key: String, to newKey: String, in overlay: inout SceneEditOverlay) {
        for binding in textureBindings(of: key) {
            let entries = Self.userTextures(in: session.value("instance", of: binding.layer))
            let link: SceneJSONValue
            if case .object(var fields) = entries[binding.slot] {
                fields["name"] = .string(newKey)
                link = .object(fields)
            } else {
                link = .string(newKey)
            }
            setUserTexture(link, binding, in: &overlay)
        }
    }

    private func setUserTexture(_ link: SceneJSONValue?, _ binding: UserTextureBinding,
                                in overlay: inout SceneEditOverlay) {
        let layerID = binding.layer
        let current = overlay.field("instance", of: layerID)
            ?? SceneFieldBinding.literal(of: session.authoredOutline.layer(layerID)?.fields["instance"])
        var instance: [String: SceneJSONValue] = [:]
        if case .object(let fields)? = current { instance = fields }
        var entries = Self.userTextures(in: current)
        while entries.count <= binding.slot { entries.append(.null) }
        entries[binding.slot] = link ?? .null
        while entries.last == .null { entries.removeLast() }
        instance["usertextures"] = entries.isEmpty ? nil : .array(entries)
        let authored = SceneFieldBinding.literal(of: session.authoredOutline.layer(layerID)?.fields["instance"])
        let next: SceneJSONValue? = instance.isEmpty ? nil : .object(instance)
        overlay.setField("instance", to: next == authored ? nil : (next ?? .object([:])), of: layerID)
    }

    /// An `instance`'s `usertextures` entries (null for a slot without one).
    static func userTextures(in instance: SceneJSONValue?) -> [SceneJSONValue] {
        guard case .object(let fields)? = instance, case .array(let entries)? = fields["usertextures"] else { return [] }
        return entries
    }

    /// The property a `usertextures` entry names: a key, or `{"name", "type": "usershortcut"}`.
    static func linkedKey(_ entry: SceneJSONValue) -> String? {
        switch entry {
        case .string(let key): return key.isEmpty ? nil : key
        case .object(let fields):
            guard fields["type"]?.stringValue == UserPropertyDraft.Kind.userShortcut.rawValue else { return nil }
            return fields["name"]?.stringValue
        default: return nil
        }
    }
}

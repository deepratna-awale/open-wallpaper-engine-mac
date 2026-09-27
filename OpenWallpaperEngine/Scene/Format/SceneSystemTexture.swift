import Foundation

/// A texture WE supplies at run time, which a `usertextures` entry binds to a texture slot by name:
/// `{"name": "$mediaThumbnail", "type": "system"}`. The now-playing artwork and the one before it.
enum SceneSystemTexture: String, CaseIterable {
    case mediaThumbnail = "$mediaThumbnail"
    case mediaPreviousThumbnail = "$mediaPreviousThumbnail"

    /// The name of the system texture a `usertextures` array binds to `slot`; nil when the slot has
    /// none or a user property's texture (a plain string).
    static func name(in userTextures: SceneJSON?, slot: Int) -> String? {
        guard case .array(let entries)? = userTextures, slot < entries.count,
              case .object(let entry) = entries[slot], case .string("system")? = entry["type"],
              case .string(let name)? = entry["name"] else { return nil }
        return name
    }
}

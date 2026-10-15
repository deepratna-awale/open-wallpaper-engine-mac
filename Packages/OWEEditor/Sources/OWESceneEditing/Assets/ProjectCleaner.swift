import Foundation

/// WE's Clean Project for the files the editor keeps (`EditorAssetStore`): the ones nothing
/// uses, which it offers to move to the Trash ("The following assets appear to be unused by your
/// project…"). The editor never writes into the wallpaper itself, so its own files are the
/// project's files that can go unused.
///
/// A file is used when a used document names it: the scene, the edits (draft and saved), then,
/// transitively, every used JSON file of the store (a model names its material, a material its
/// textures and shader, an effect its materials). A document names a file by any string in it,
/// key or value, equal to the file's path, to it without its extension, or to either without its
/// first folder: WE's own ways of naming one (`models/editor/a.json`, the texture `editor/a` of
/// `materials/editor/a.png`, the mask `masks/editor_a`, the shader `effects/x` of
/// `shaders/effects/x.frag`). A `.tex-json` goes with its `.tex`.
public enum ProjectCleaner {
    /// The store's files no root names, by scene path, sorted.
    public static func unusedAssets(in store: EditorAssetStore, roots: [Data]) -> [EditorAssetStore.Asset] {
        let assets = store.assets()
        var names = Set<String>()
        for root in roots { collectStrings(in: root, into: &names) }
        var used = Set<String>()
        var changed = true
        while changed {
            changed = false
            for asset in assets where !used.contains(asset.path) && isNamed(asset.path, by: names) {
                used.insert(asset.path)
                changed = true
                if asset.path.lowercased().hasSuffix(".json"), let data = try? Data(contentsOf: asset.url) {
                    // Optional: a JSON file that can't be read names nothing (it is still kept).
                    collectStrings(in: data, into: &names)
                }
            }
        }
        return assets.filter { !used.contains($0.path) }
    }

    /// Whether any of `names` (lowercased) names `path`.
    static func isNamed(_ path: String, by names: Set<String>) -> Bool {
        var lowered = path.lowercased()
        if lowered.hasSuffix(".tex-json") { lowered = String(lowered.dropLast("-json".count)) }
        let bare = (lowered as NSString).deletingPathExtension
        var candidates = [lowered, bare]
        if let slash = lowered.firstIndex(of: "/") {
            let inner = String(lowered[lowered.index(after: slash)...])
            candidates += [inner, (inner as NSString).deletingPathExtension]
        }
        return candidates.contains(where: names.contains)
    }

    /// Every string of a JSON document, keys included, lowercased; nothing when it isn't JSON.
    static func collectStrings(in data: Data, into names: inout Set<String>) {
        // Optional: a root that isn't JSON (WE's tolerant files are read leniently) names nothing.
        guard let root = try? WETolerantJSON.object(from: data) else { return }
        var stack: [Any] = [root]
        while let next = stack.popLast() {
            switch next {
            case let string as String:
                names.insert(string.lowercased())
            case let array as [Any]:
                stack += array
            case let object as [String: Any]:
                for (key, value) in object {
                    names.insert(key.lowercased())
                    stack.append(value)
                }
            default:
                break
            }
        }
    }

    /// Moves the files to the Trash, as WE moves them to the recycle bin; returns the ones moved.
    public static func trash(_ assets: [EditorAssetStore.Asset]) throws -> [EditorAssetStore.Asset] {
        var moved: [EditorAssetStore.Asset] = []
        for asset in assets {
            try FileManager.default.trashItem(at: asset.url, resultingItemURL: nil)
            moved.append(asset)
        }
        return moved
    }
}

import Foundation

/// The settings identities of local (non-Workshop) wallpapers, kept by the app: a generated id per
/// wallpaper folder, so editing the wallpaper's project.json (title, tags, content rating) keeps
/// its user properties, presets, editor overlay, display and screen saver options.
///
/// Stored in the app's defaults (`defaultsKey`) as `[folder path: entry]`, not in the wallpaper's
/// folder: library folders are read only (`LibraryFolders`). An entry remembers the folder's file
/// node (volume and inode), so a folder moved or renamed on its volume keeps its id, and the
/// identity its project derives (`WallpaperSettingsIdentity(directory:projectData:)`), so an
/// unedited wallpaper moved to another volume keeps it too. A copy of a folder (Save as Local
/// Wallpaper, a Finder copy) is a new node at a new path while the original is still there: it
/// gets an id of its own.
enum LocalWallpaperIdentities {
    static let defaultsKey = "LocalWallpaperIdentities"

    private static let lock = NSLock()

    /// The id of the local wallpaper in `directory`, registered on first sight. `derived` is its
    /// project's derived identity.
    static func identity(directory: URL, derived: String, contentKnown: Bool, defaults: UserDefaults) -> String {
        lock.lock()
        defer { lock.unlock() }
        var entries = defaults.dictionary(forKey: defaultsKey) as? [String: [String: String]] ?? [:]
        let path = directory.standardizedFileURL.path
        let content = contentKnown ? derived : nil
        if var entry = entries[path], let id = entry["id"] {
            if let content, entry["content"] != content {
                entry["content"] = content
                entries[path] = entry
                defaults.set(entries, forKey: defaultsKey)
            }
            return id
        }
        let node = fileNode(directory)
        let missing = entries.filter { $0.key != path && !FileManager.default.fileExists(atPath: $0.key) }
        // The same folder at a new path (moved or renamed on its volume), else an unedited
        // wallpaper whose old folder is gone (moved to another volume); only a single candidate.
        var moved = node.map { node in missing.filter { $0.value["node"] == node } } ?? [:]
        if moved.isEmpty, let content { moved = missing.filter { $0.value["content"] == content } }
        if moved.count == 1, case let (oldPath, old)? = moved.first, let id = old["id"] {
            entries[oldPath] = nil
            entries[path] = entry(id: id, node: node, content: content)
            defaults.set(entries, forKey: defaultsKey)
            OWELog.info(.library, "Settings identity \(id) follows its wallpaper from \(oldPath) to \(path)")
            return id
        }
        let id = "local-" + UUID().uuidString.lowercased()
        entries[path] = entry(id: id, node: node, content: content)
        defaults.set(entries, forKey: defaultsKey)
        return id
    }

    private static func entry(id: String, node: String?, content: String?) -> [String: String] {
        var entry = ["id": id]
        entry["node"] = node
        entry["content"] = content
        return entry
    }

    /// The folder's volume and inode: unchanged when it is moved or renamed on its volume.
    static func fileNode(_ directory: URL) -> String? {
        guard let attributes = try? FileManager.default.attributesOfItem(atPath: directory.path), // gone: no node
              let inode = attributes[.systemFileNumber] as? NSNumber else { return nil }
        let volume = (try? directory.resourceValues(forKeys: [.volumeUUIDStringKey]))?.volumeUUIDString // no UUID: device number
            ?? (attributes[.systemNumber] as? NSNumber)?.stringValue ?? "?"
        return "\(volume):\(inode)"
    }
}

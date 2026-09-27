import Foundation

/// The Installed library as `InstalledLibrary` lists it, re-reading a folder's project.json only
/// when its modification date changed, and remembering the facts the Installed tab filters and
/// sorts by (size on disk, customizable properties) with it.
///
/// The Installed tab used to rescan and decode every project.json several times per redraw, and
/// sorting by size walked each folder once per comparison. A pass here lists the library folder
/// and reads one modification date per wallpaper, so the view stays as fresh as before: a folder
/// that appears, disappears or has its project.json rewritten shows up on the next pass.
///
/// Main-thread only (it belongs to the Installed tab's view model); not thread-safe.
final class InstalledLibraryCache {
    private struct Entry {
        /// project.json's modification date; nil when it's missing.
        let projectModified: Date?
        /// The folder's own modification date, which moves when files are added or removed in it.
        let folderModified: Date?
        /// Nil when the folder isn't a listed wallpaper (not a wallpaper type).
        let wallpaper: WEWallpaper?
        var size: Int?
        var hasCustomizableProperties: Bool?
    }

    private var entries: [URL: Entry] = [:]

    /// The listed wallpapers in `directory`, in folder order, without `dependencyIds`.
    func wallpapers(in directory: URL, hiding dependencyIds: Set<String>) -> [WEWallpaper] {
        let folders: [URL]
        do {
            folders = try FileManager.default.contentsOfDirectory(
                at: directory, includingPropertiesForKeys: [.contentModificationDateKey], options: .skipsHiddenFiles)
        } catch {
            OWELog.error(.library, "Can't list the wallpaper library at \(directory.path): \(error)")
            entries.removeAll()
            return []
        }
        var seen = Set<URL>()
        var result: [WEWallpaper] = []
        for folder in folders {
            seen.insert(folder)
            guard !dependencyIds.contains(folder.lastPathComponent) else { continue }
            if let wallpaper = entry(for: folder).wallpaper {
                result.append(wallpaper)
            }
        }
        entries = entries.filter { seen.contains($0.key) }
        return result
    }

    /// The wallpaper's size on disk, measured once per change of its folder or project.json.
    func size(of wallpaper: WEWallpaper) -> Int {
        let folder = wallpaper.wallpaperDirectory
        if let size = entries[folder]?.size { return size }
        let size = wallpaper.wallpaperSize
        entries[folder]?.size = size
        return size
    }

    /// Whether project.json has user properties besides the scheme colour, read once per change.
    func hasCustomizableProperties(_ wallpaper: WEWallpaper) -> Bool {
        let folder = wallpaper.wallpaperDirectory
        if let known = entries[folder]?.hasCustomizableProperties { return known }
        let value = wallpaper.hasCustomizableProperties
        entries[folder]?.hasCustomizableProperties = value
        return value
    }

    private func entry(for folder: URL) -> Entry {
        let projectModified = Self.modificationDate(of: folder.appending(path: "project.json"))
        let folderModified = Self.modificationDate(of: folder)
        if let cached = entries[folder], cached.projectModified == projectModified {
            if cached.folderModified == folderModified { return cached }
            // Files came or went: the project is the same but the size may not be.
            let refreshed = Entry(projectModified: projectModified, folderModified: folderModified,
                                  wallpaper: cached.wallpaper, size: nil,
                                  hasCustomizableProperties: cached.hasCustomizableProperties)
            entries[folder] = refreshed
            return refreshed
        }
        let entry = Entry(projectModified: projectModified, folderModified: folderModified,
                          wallpaper: InstalledLibrary.wallpaper(at: folder, hiding: []),
                          size: nil, hasCustomizableProperties: nil)
        entries[folder] = entry
        return entry
    }

    private static func modificationDate(of url: URL) -> Date? {
        // A missing file has no date, which is itself a state the entry records.
        try? url.resourceValues(forKeys: [.contentModificationDateKey]).contentModificationDate
    }
}

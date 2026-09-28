import Foundation
import Combine

enum WallpaperStorage {
    private static let customPathKey = "CustomWallpapersDirectory"

    static var defaultDirectory: URL {
        FileManager.default.urls(for: .documentDirectory, in: .userDomainMask)[0]
            .appending(path: "Open Wallpaper Engine")
    }

    static var directory: URL {
        if let customPath = UserDefaults.app.string(forKey: customPathKey), !customPath.isEmpty {
            return URL(fileURLWithPath: customPath, isDirectory: true)
        }
        return defaultDirectory
    }

    static var usesCustomDirectory: Bool {
        UserDefaults.app.string(forKey: customPathKey) != nil
    }

    /// The storage folder can't be used: it is on a volume that isn't connected, or can't be created.
    enum Unavailable: LocalizedError {
        case volumeNotMounted(directory: URL, volume: URL)
        case notCreatable(directory: URL, reason: String)

        var errorDescription: String? {
            switch self {
            case .volumeNotMounted(let directory, let volume):
                return String(localized: "The Wallpaper Storage folder \(directory.path) is on \(volume.lastPathComponent), which isn't connected. Connect it, or choose another folder in Settings → General.",
                              comment: "The first %@ is a folder path, the second a disk name")
            case .notCreatable(let directory, let reason):
                return String(localized: "Can't create the Wallpaper Storage folder \(directory.path): \(reason)",
                              comment: "The first %@ is a folder path, the second the system's reason")
            }
        }
    }

    /// The `/Volumes/<name>` a folder lives on when that volume isn't mounted; nil otherwise.
    /// Creating the folder then would put it on the startup disk instead, under a stale mount point.
    static func unmountedVolume(of directory: URL, fileManager: FileManager = .default) -> URL? {
        let components = directory.standardizedFileURL.pathComponents
        guard components.count >= 3, components[0] == "/", components[1] == "Volumes" else { return nil }
        let volume = URL(fileURLWithPath: "/Volumes", isDirectory: true).appending(path: components[2], directoryHint: .isDirectory)
        guard fileManager.fileExists(atPath: volume.path) else { return volume }
        let resolved = volume.resolvingSymlinksInPath()
        // `/Volumes/Macintosh HD` links to `/`, which is a volume too.
        do {
            return try resolved.resourceValues(forKeys: [.isVolumeKey]).isVolume == true ? nil : volume
        } catch {
            OWELog.error(.library, "Can't tell whether \(volume.path) is mounted: \(error)")
            return volume
        }
    }

    /// The storage folder, created when it is missing. Throws instead of falling back to another
    /// place, so nothing is ever downloaded anywhere but the folder the user chose.
    static func availableDirectory(_ directory: URL = directory, fileManager: FileManager = .default) throws -> URL {
        if let volume = unmountedVolume(of: directory, fileManager: fileManager) {
            throw Unavailable.volumeNotMounted(directory: directory, volume: volume)
        }
        do {
            try fileManager.createDirectory(at: directory, withIntermediateDirectories: true)
        } catch {
            throw Unavailable.notCreatable(directory: directory, reason: error.localizedDescription)
        }
        return directory
    }

    static func setDirectory(_ newDirectory: URL, moveExisting: Bool) throws -> (source: URL, destination: URL)? {
        let fileManager = FileManager.default
        let sourceDirectory = directory.standardizedFileURL
        let destinationDirectory = newDirectory.standardizedFileURL
        guard sourceDirectory != destinationDirectory else { return nil }

        try fileManager.createDirectory(at: destinationDirectory, withIntermediateDirectories: true)
        if moveExisting, fileManager.fileExists(atPath: sourceDirectory.path) {
            let moved = try moveContents(from: sourceDirectory, to: destinationDirectory, fileManager: fileManager)
            // Merged rather than moved when the destination has one; it lists which of the moved
            // items are dependencies.
            try WorkshopDependencyIndex.carry(from: sourceDirectory, to: destinationDirectory, movedItems: moved)
        }
        UserDefaults.app.set(destinationDirectory.path, forKey: customPathKey)
        return moveExisting ? (sourceDirectory, destinationDirectory) : nil
    }

    /// Whether a storage item moves with the folder: the wallpapers, and the app's own hidden data
    /// (`.owe-*`: the assets cache with its info file, SteamCMD's staging, converted packages).
    /// Other hidden files (`.DS_Store`, `._*`, `.Trashes`…) belong to the old folder, the dependency
    /// index is merged by `WorkshopDependencyIndex.carry`, and half-finished work (a download
    /// being unpacked, a staging copy) is left behind: it is rebuilt when needed.
    static func movesWithStorage(_ name: String) -> Bool {
        guard name.hasPrefix(".") else { return true }
        guard name.hasPrefix(".owe") else { return false }
        if name == WorkshopDependencyIndex.fileName { return false }
        if name == WallpaperEngineAssetsDownload.downloadFolderName { return false }
        return !name.hasPrefix(".owe-incoming-") && !name.hasSuffix(".partial")
    }

    /// Moves what `movesWithStorage` keeps from `source` into `destination`, never over an item of
    /// the same name. Returns the names moved.
    @discardableResult
    static func moveContents(from source: URL, to destination: URL,
                             fileManager: FileManager = .default) throws -> Set<String> {
        let items = try fileManager.contentsOfDirectory(at: source, includingPropertiesForKeys: nil)
        var moved = Set<String>()
        for item in items where movesWithStorage(item.lastPathComponent) {
            let target = destination.appending(path: item.lastPathComponent)
            guard !fileManager.fileExists(atPath: target.path) else { continue }
            try fileManager.moveItem(at: item, to: target)
            moved.insert(item.lastPathComponent)
        }
        return moved
    }

    static func resetToDefault() {
        UserDefaults.app.removeObject(forKey: customPathKey)
    }
}

final class DownloadedWallpaperIndex: ObservableObject {
    static let shared = DownloadedWallpaperIndex()

    @Published private(set) var ids: Set<String>
    /// Steam's tags of installed Workshop wallpapers, by Workshop id (`InstalledWorkshopTagSync`).
    @Published private(set) var workshopTags: [String: InstalledWorkshopTags]
    private let storageKey = "DownloadedWorkshopWallpaperIds"
    private let dateStorageKey = "DownloadedWorkshopWallpaperDates"
    private let tagsStorageKey = "DownloadedWorkshopWallpaperTags"
    private var downloadDates: [String: Date]
    private let defaults: UserDefaults
    private let libraryDirectory: () -> URL

    init(defaults: UserDefaults = .app,
         libraryDirectory: @escaping () -> URL = { FileManager.default.wallpapersDirectory }) {
        self.defaults = defaults
        self.libraryDirectory = libraryDirectory
        ids = Set(defaults.stringArray(forKey: storageKey) ?? [])
        downloadDates = Self.decodeDates(defaults.dictionary(forKey: dateStorageKey))
        workshopTags = Self.decodeTags(defaults.data(forKey: tagsStorageKey))
        if ids.isEmpty || downloadDates.isEmpty {
            rebuildFromLibrary()
        }
    }

    func contains(_ workshopId: String) -> Bool {
        ids.contains(workshopId)
    }

    func insert(_ workshopId: String) {
        ids.insert(workshopId)
        if downloadDates[workshopId] == nil {
            downloadDates[workshopId] = .now
        }
        save()
    }

    func dateAdded(for directory: URL) -> Date {
        let workshopId = directory.lastPathComponent
        if let date = downloadDates[workshopId] {
            return date
        }
        return (try? directory.resourceValues(forKeys: [.contentModificationDateKey]))?.contentModificationDate ?? .distantPast
    }

    func workshopTags(for workshopId: String) -> InstalledWorkshopTags? {
        workshopTags[workshopId]
    }

    func setWorkshopTags(_ entries: [String: InstalledWorkshopTags]) {
        guard !entries.isEmpty else { return }
        workshopTags.merge(entries) { _, new in new }
        saveTags()
    }

    func remove(directory: URL) {
        let workshopId = directory.lastPathComponent
        if workshopTags.removeValue(forKey: workshopId) != nil {
            saveTags()
        }
        guard ids.remove(workshopId) != nil else { return }
        downloadDates.removeValue(forKey: workshopId)
        save()
    }

    func reloadFromLibrary() {
        ids.removeAll()
        downloadDates.removeAll()
        rebuildFromLibrary()
    }

    private func rebuildFromLibrary() {
        guard let directories = try? FileManager.default.contentsOfDirectory(
            at: libraryDirectory(),
            includingPropertiesForKeys: nil,
            options: [.skipsHiddenFiles]
        ) else { return }

        let downloadedDirectories = directories.compactMap { directory -> URL? in
            let workshopId = directory.lastPathComponent
            guard workshopId.allSatisfy(\.isNumber),
                  FileManager.default.fileExists(atPath: directory.appending(path: "project.json").path) else {
                return nil
            }
            return directory
        }
        ids = Set(downloadedDirectories.map(\.lastPathComponent))
        for directory in downloadedDirectories {
            let workshopId = directory.lastPathComponent
            if downloadDates[workshopId] == nil {
                downloadDates[workshopId] = (try? directory.resourceValues(forKeys: [.contentModificationDateKey]))?.contentModificationDate ?? .now
            }
        }
        save()
    }

    private func save() {
        defaults.set(ids.sorted(), forKey: storageKey)
        defaults.set(
            downloadDates.mapValues(\.timeIntervalSince1970),
            forKey: dateStorageKey
        )
    }

    private func saveTags() {
        do {
            defaults.set(try JSONEncoder().encode(workshopTags), forKey: tagsStorageKey)
        } catch {
            OWELog.error(.library, "Can't save the installed wallpapers' Workshop tags: \(error)")
        }
    }

    /// The stored tags; a list that doesn't decode is dropped and read again from Steam.
    private static func decodeTags(_ data: Data?) -> [String: InstalledWorkshopTags] {
        guard let data else { return [:] }
        do {
            return try JSONDecoder().decode([String: InstalledWorkshopTags].self, from: data)
        } catch {
            OWELog.error(.library, "Can't read the installed wallpapers' Workshop tags: \(error)")
            return [:]
        }
    }

    private static func decodeDates(_ storedDates: [String: Any]?) -> [String: Date] {
        (storedDates ?? [:]).reduce(into: [:]) { dates, entry in
            guard let timestamp = entry.value as? Double else { return }
            dates[entry.key] = Date(timeIntervalSince1970: timestamp)
        }
    }
}

/// Tracks favorited wallpapers, keyed by an arbitrary caller-chosen ID (local wallpaper directory
/// path, or "workshop-<id>" for not-yet-downloaded Workshop items).
final class FavoritesStore: ObservableObject {
    static let shared = FavoritesStore()

    @Published private(set) var ids: Set<String>
    private let storageKey = "FavoriteWallpaperIds"

    private init() {
        ids = Set(UserDefaults.app.stringArray(forKey: storageKey) ?? [])
    }

    func contains(_ id: String) -> Bool {
        ids.contains(id)
    }

    func toggle(_ id: String) {
        if ids.contains(id) {
            ids.remove(id)
        } else {
            ids.insert(id)
        }
        UserDefaults.app.set(ids.sorted(), forKey: storageKey)
    }

    /// A Workshop wallpaper keeps one identity whether or not it is installed, so favouriting it in
    /// the Workshop tab and in the local library refer to the same entry.
    static func key(for wallpaper: WEWallpaper) -> String {
        if let id = wallpaper.project.workshopid?.rawValue, !id.isEmpty, id.allSatisfy(\.isNumber) {
            return "workshop-\(id)"
        }
        let folder = wallpaper.wallpaperDirectory.lastPathComponent
        if !folder.isEmpty, folder.allSatisfy(\.isNumber) { return "workshop-\(folder)" }
        return wallpaper.wallpaperDirectory.path
    }

    func contains(_ wallpaper: WEWallpaper) -> Bool {
        ids.contains(Self.key(for: wallpaper)) || ids.contains(wallpaper.wallpaperDirectory.path)
    }

    func toggle(_ wallpaper: WEWallpaper) {
        if contains(wallpaper) {
            // Older builds keyed local copies by path; drop both so it cannot stay half-favourited.
            ids.remove(Self.key(for: wallpaper))
            ids.remove(wallpaper.wallpaperDirectory.path)
        } else {
            ids.insert(Self.key(for: wallpaper))
        }
        UserDefaults.app.set(ids.sorted(), forKey: storageKey)
    }
}

/// Whether a wallpaper's project.json declares any user-editable properties beyond the default color scheme.
func projectHasCustomizableProperties(at wallpaperDirectory: URL) -> Bool {
    guard let root = WEProjectFileCache.shared.root(in: wallpaperDirectory),
          let properties = (root["general"] as? [String: Any])?["properties"] as? [String: Any] else { return false }
    return properties.keys.contains { $0 != "schemecolor" }
}

extension FileManager {
    /// The configured directory for storing wallpaper packages.
    /// Created when missing, unless its volume isn't connected; code that writes into it checks
    /// `WallpaperStorage.availableDirectory()` for the reason.
    var wallpapersDirectory: URL {
        let dir = WallpaperStorage.directory
        guard !fileExists(atPath: dir.path) else { return dir }
        do {
            _ = try WallpaperStorage.availableDirectory(dir, fileManager: self)
        } catch {
            OWELog.error(.library, "\(error.localizedDescription)")
        }
        return dir
    }
}

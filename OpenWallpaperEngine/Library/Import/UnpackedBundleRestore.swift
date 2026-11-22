import Foundation
import OWESceneEditing

/// A wallpaper an earlier version unpacked: its `.pkg` was extracted into loose files, listed in
/// `.owe-bundle.json`, and moved into `.owe-source/` (or deleted). Scenes now play from their
/// package as downloaded, so each one gets its package back and loses the loose copy.
struct UnpackedBundle: Equatable, Sendable {
    let directory: URL
    /// nil for a local import, which has nowhere to download the package from.
    let workshopId: String?
    /// `scene.pkg`, or the package of the scene file project.json names.
    let packageName: String
    /// The scene file project.json names, which the package must hold.
    let sceneFile: String
    let title: String

    static let manifestName = ".owe-bundle.json"
    static let sourceFolderName = ".owe-source"
    /// Where a fetched package waits, hidden, until the loose copy can go.
    static let restoredPrefix = ".owe-restored-"

    /// What of the manifest the restore reads.
    struct Manifest: Decodable {
        var sourcePackage: String
        var extractedFiles: [String]
    }

    var manifestURL: URL { directory.appending(path: Self.manifestName) }
    var packageURL: URL { directory.appending(path: packageName) }
    /// The package fetched for it, before it takes `packageURL`'s place.
    var restoredURL: URL { directory.appending(path: Self.restoredPrefix + packageName) }
    /// The original package an earlier version kept.
    var archivedURL: URL { directory.appending(path: Self.sourceFolderName).appending(path: packageName) }

    /// The unpacked wallpapers in `storage`, in folder-name order, but those with edits
    /// (`hasEdits`), which keep their loose copy as it is. Reads each folder's manifest and
    /// project; call off the main thread.
    static func scan(storage: URL, fileManager: FileManager = .default,
                     hasEdits: (URL) -> Bool = { UnpackedBundle.hasEditorEdits($0) }) -> [UnpackedBundle] {
        guard let entries = OWELog.attempt(.importer, "Unpacked wallpapers: listing \(storage.path(percentEncoded: false))",
                                           quietIfMissing: true, {
            try fileManager.contentsOfDirectory(at: storage, includingPropertiesForKeys: [.isDirectoryKey],
                                                options: [.skipsHiddenFiles])
        }) else { return [] }
        return entries
            .sorted { $0.lastPathComponent < $1.lastPathComponent }
            .compactMap { bundle(at: $0, fileManager: fileManager) }
            .filter { bundle in
                guard hasEdits(bundle.directory) else { return true }
                OWELog.info(.importer, "Unpacked wallpapers: \(bundle.directory.lastPathComponent) has editor or Scene Edit edits; its loose copy stays as it is")
                return false
            }
    }

    /// Whether the wallpaper in `directory` has edits: a Wallpaper Editor overlay or draft, or
    /// Scene Edit / Export's object edits in its stored properties (any display's).
    static func hasEditorEdits(_ directory: URL, defaults: UserDefaults = .app,
                               overlays: SceneEditOverlayStore = SceneEditOverlayFiles.defaultStore) -> Bool {
        let identity = WallpaperSettingsIdentity.resolve(directory: directory, defaults: defaults)
        if FileManager.default.fileExists(atPath: overlays.fileURL(for: identity.rawValue).path(percentEncoded: false))
            || SceneEditDraftStore(saved: overlays).hasDraft(for: identity.rawValue) {
            return true
        }
        let key = identity.key(.userProperties)
        return defaults.dictionaryRepresentation().contains { name, value in
            guard name == key || name.hasPrefix(key + ".") else { return false }
            return (value as? [String: Any])?.keys.contains { $0.hasPrefix("_owe_scene_object_") } ?? false
        }
    }

    /// What `scan` finds in `storage`, each with the package already on disk for it, if any.
    static func scanWithPackages(storage: URL) -> [(bundle: UnpackedBundle, packageOnDisk: URL?)] {
        scan(storage: storage).map { (bundle: $0, packageOnDisk: $0.packageOnDisk()) }
    }

    /// The folder as an unpacked wallpaper, when it is one.
    static func bundle(at directory: URL, fileManager: FileManager = .default) -> UnpackedBundle? {
        let manifestURL = directory.appending(path: manifestName)
        guard fileManager.fileExists(atPath: manifestURL.path(percentEncoded: false)) else { return nil }
        guard let manifest = readManifest(manifestURL) else { return nil }
        guard let project = OWELog.attempt(.importer, "Unpacked wallpapers: project.json of \(directory.lastPathComponent)", {
            try WEProject.read(in: directory)
        }) else { return nil }
        let sceneFile = project.file
        guard sceneFile.lowercased().hasSuffix(".json") else { return nil }
        let packageName = (sceneFile as NSString).deletingPathExtension + ".pkg"
        // The manifest names the same package; anything else isn't a bundle this restores.
        guard manifest.sourcePackage == packageName, isPlainName(packageName) else {
            OWELog.error(.importer, "Unpacked wallpapers: \(directory.lastPathComponent) names \(manifest.sourcePackage), not \(packageName); left as it is")
            return nil
        }
        // The folder is named for the item Steam installed; project.json's id can be empty or point
        // at the author's earlier upload, so it's only the fallback.
        let isWorkshopId = { (id: String) in !id.isEmpty && id.allSatisfy { $0.isASCII && $0.isNumber } }
        let workshopId = [directory.lastPathComponent, project.workshopid?.rawValue].compactMap { $0 }.first(where: isWorkshopId)
        return UnpackedBundle(directory: directory, workshopId: workshopId, packageName: packageName,
                              sceneFile: sceneFile, title: project.title)
    }

    private static func readManifest(_ url: URL) -> Manifest? {
        OWELog.attempt(.importer, "Unpacked wallpapers: \(url.path(percentEncoded: false))") {
            try JSONDecoder().decode(Manifest.self, from: Data(contentsOf: url))
        }
    }

    private static func isPlainName(_ name: String) -> Bool {
        !name.isEmpty && !name.contains("/") && !name.contains("\\") && !name.hasPrefix(".")
    }

    /// Whether `url` is a package that holds the scene: it parses, and it has `sceneFile`.
    func isUsablePackage(_ url: URL) -> Bool {
        guard FileManager.default.fileExists(atPath: url.path(percentEncoded: false)) else { return false }
        do {
            let parser = try PKGParser(url: url)
            let wanted = sceneFile.replacingOccurrences(of: "\\", with: "/")
            return parser.fileList.contains {
                $0.replacingOccurrences(of: "\\", with: "/").caseInsensitiveCompare(wanted) == .orderedSame
            }
        } catch {
            OWELog.error(.importer, "Unpacked wallpapers: \(url.path(percentEncoded: false)) isn't a usable package: \(error)")
            return false
        }
    }

    /// A package already on disk to restore from, without a download: one fetched earlier, the
    /// one an earlier version kept in `.owe-source`, or the package itself.
    func packageOnDisk() -> URL? {
        [restoredURL, archivedURL, packageURL].first(where: isUsablePackage)
    }

    /// Puts `package` (a usable package in the folder) in place as the wallpaper's package, then
    /// deletes the loose files the manifest lists, the manifest and `.owe-source`, and the folders
    /// that leaves empty. project.json must still read. Returns whether the folder is now as
    /// downloaded. Reads and writes files: call it off the main thread.
    @discardableResult
    func finish(with package: URL, fileManager: FileManager = .default) -> Bool {
        guard isUsablePackage(package) else { return false }
        guard OWELog.attempt(.importer, "Unpacked wallpapers: project.json of \(directory.lastPathComponent)", {
            try WEProject.read(in: directory)
        }) != nil else { return false }
        guard let manifest = Self.readManifest(manifestURL) else { return false }
        do {
            if package.standardizedFileURL != packageURL.standardizedFileURL {
                try? fileManager.removeItem(at: packageURL)
                try fileManager.moveItem(at: package, to: packageURL)
            }
        } catch {
            OWELog.error(.importer, "Unpacked wallpapers: can't put \(packageName) back in \(directory.lastPathComponent): \(error)")
            return false
        }
        OWELog.info(.importer, "Unpacked wallpapers: \(packageName) is back in \(directory.lastPathComponent)")
        guard let root = ContainedPath.canonical(directory) else { return false }
        let rootURL = URL(fileURLWithPath: root, isDirectory: true)
        var removed = 0
        var parents = Set<String>()
        for relative in manifest.extractedFiles {
            let normalized = relative.replacingOccurrences(of: "\\", with: "/")
            let components = normalized.split(separator: "/").map(String.init)
            // Only plain paths inside the folder, never through a link: what the unpacking wrote.
            guard !components.isEmpty, !normalized.hasPrefix("/"),
                  !components.contains(where: { $0 == ".." || $0 == "." }),
                  normalized.caseInsensitiveCompare(packageName) != .orderedSame,
                  normalized.caseInsensitiveCompare("project.json") != .orderedSame,
                  ContainedPath.hasNoLinks(below: rootURL, relativePath: normalized) else { continue }
            let file = rootURL.appending(path: normalized)
            guard fileManager.fileExists(atPath: file.path(percentEncoded: false)) else { continue }
            do {
                try fileManager.removeItem(at: file)
                removed += 1
                if components.count > 1 { parents.insert(components.dropLast().joined(separator: "/")) }
            } catch {
                OWELog.error(.importer, "Unpacked wallpapers: can't remove \(normalized) in \(directory.lastPathComponent): \(error)")
            }
        }
        removeEmptyFolders(parents, in: rootURL, fileManager: fileManager)
        try? fileManager.removeItem(at: directory.appending(path: Self.sourceFolderName))
        do {
            try fileManager.removeItem(at: manifestURL)
        } catch {
            OWELog.error(.importer, "Unpacked wallpapers: can't remove the manifest of \(directory.lastPathComponent): \(error)")
            return false
        }
        OWELog.info(.importer, "Unpacked wallpapers: \(directory.lastPathComponent) plays from its package again; \(removed) loose files removed")
        return true
    }

    /// Removes each of `folders` (relative paths) and its parents while they're empty, stopping at
    /// the wallpaper's folder.
    private func removeEmptyFolders(_ folders: Set<String>, in root: URL, fileManager: FileManager) {
        // Deepest first, so a parent is emptied before it is looked at.
        var pending = folders
        for folder in folders {
            var components = folder.split(separator: "/").map(String.init)
            while components.count > 1 {
                components.removeLast()
                pending.insert(components.joined(separator: "/"))
            }
        }
        for folder in pending.sorted(by: { $0.split(separator: "/").count > $1.split(separator: "/").count }) {
            let url = root.appending(path: folder)
            guard !ContainedPath.isSymbolicLink(url),
                  let contents = try? fileManager.contentsOfDirectory(atPath: url.path(percentEncoded: false)) else { continue }
            // Finder's own file doesn't keep a folder.
            guard contents.allSatisfy({ $0 == ".DS_Store" }) else { continue }
            try? fileManager.removeItem(at: url)
        }
    }
}

/// What the restore needs from the Workshop download path; `WorkshopDownloadService` in the app.
@MainActor
protocol UnpackedBundleDownloading: AnyObject {
    /// Whether the Steam login is there to download with.
    var isLoggedIn: Bool { get }
    /// Downloads the item and copies its `packageName` to `destination`. Calls back on the main
    /// queue with whether the package landed.
    func fetchPackage(workshopId: String, packageName: String, to destination: URL,
                      completion: @escaping @MainActor @Sendable (Bool) -> Void)
}

extension WorkshopDownloadService: UnpackedBundleDownloading {}

/// Gives unpacked wallpapers their package back one at a time, with no prompt: a package already on
/// disk is used, else the Workshop item is downloaded again. The loose copy goes only once the
/// package is in hand and holds the scene, and never while the wallpaper is shown: that one waits
/// until it isn't. Whatever can't be done (no Steam login, a local import, an item gone from the
/// Workshop, a failed download) keeps its loose copy and is tried again on a later launch; what
/// only lacked the login, as soon as there is one (`steamLoginAvailable`).
@MainActor
final class UnpackedBundleRestorer {
    private let downloader: UnpackedBundleDownloading
    private let isShown: (URL) -> Bool
    /// Finishes a bundle whose package is in hand; runs off the main thread.
    private let finish: @Sendable (UnpackedBundle, URL) -> Void
    private var queue: [UnpackedBundle] = []
    /// Bundles whose package is in hand but which were shown; finished once they're not.
    private(set) var pending: [(bundle: UnpackedBundle, package: URL)] = []
    /// Bundles left as they are this launch.
    private(set) var skipped: [UnpackedBundle] = []
    /// Whether bundles were skipped because there was no Steam login.
    private(set) var waitsForLogin = false
    private var isRunning = false
    private var onFinished: (() -> Void)?

    init(downloader: UnpackedBundleDownloading,
         isShown: @escaping (URL) -> Bool,
         finish: @escaping @Sendable (UnpackedBundle, URL) -> Void = UnpackedBundleRestorer.finishInBackground) {
        self.downloader = downloader
        self.isShown = isShown
        self.finish = finish
    }

    /// Restores `bundles`; `packageOnDisk` finds a package already there (off the main thread in
    /// the app, `UnpackedBundle.packageOnDisk`).
    func run(_ bundles: [(bundle: UnpackedBundle, packageOnDisk: URL?)], onFinished: (() -> Void)? = nil) {
        self.onFinished = onFinished
        isRunning = true
        waitsForLogin = false
        skipped = []
        var downloads: [UnpackedBundle] = []
        // A bundle still waiting on its wallpaper has its package in hand.
        for (bundle, package) in bundles where !pending.contains(where: { $0.bundle == bundle }) {
            if let package {
                OWELog.info(.importer, "Unpacked wallpapers: \(bundle.directory.lastPathComponent) has its package on disk")
                ready(bundle, package: package)
            } else if bundle.workshopId == nil {
                OWELog.info(.importer, "Unpacked wallpapers: \(bundle.directory.lastPathComponent) is a local import with no package; its loose copy stays")
                skipped.append(bundle)
            } else {
                downloads.append(bundle)
            }
        }
        queue = downloads
        next()
    }

    /// Call when a Steam login becomes available: if an earlier run skipped bundles for want of
    /// one, runs again over what `scan` (off the main thread) finds now, since wallpapers may have
    /// been edited, updated or deleted meanwhile.
    func steamLoginAvailable(scan: @escaping @Sendable () -> [(bundle: UnpackedBundle, packageOnDisk: URL?)],
                             onFinished: (() -> Void)? = nil) {
        guard waitsForLogin, !isRunning else { return }
        waitsForLogin = false
        isRunning = true
        self.onFinished = onFinished
        DispatchQueue.global(qos: .utility).async {
            let bundles = scan()
            OWELog.info(.importer, "Unpacked wallpapers: logged in to Steam; \(bundles.count) to give their package back")
            DispatchQueue.main.async { [weak self] in self?.run(bundles, onFinished: self?.onFinished) }
        }
    }

    /// Call when the shown wallpapers change: finishes what was waiting on them.
    func shownWallpapersChanged() {
        let ready = pending.filter { !isShown($0.bundle.directory) }
        pending.removeAll { item in ready.contains { $0.bundle == item.bundle } }
        for item in ready {
            OWELog.info(.importer, "Unpacked wallpapers: \(item.bundle.directory.lastPathComponent) is no longer shown; finishing")
            finish(item.bundle, item.package)
        }
    }

    private func ready(_ bundle: UnpackedBundle, package: URL) {
        if isShown(bundle.directory) {
            OWELog.info(.importer, "Unpacked wallpapers: \(bundle.directory.lastPathComponent) is shown; finishing once it isn't")
            pending.append((bundle, package))
        } else {
            finish(bundle, package)
        }
    }

    private func next() {
        guard !queue.isEmpty else { return done() }
        // Also partway through: Steam can end the login meanwhile.
        guard downloader.isLoggedIn else {
            OWELog.info(.importer, "Unpacked wallpapers: no Steam login; \(queue.count) wallpaper(s) keep their loose copy until the next login")
            skipped += queue
            queue = []
            waitsForLogin = true
            return done()
        }
        let bundle = queue.removeFirst()
        guard let workshopId = bundle.workshopId else { return next() }
        OWELog.info(.importer, "Unpacked wallpapers: downloading \(bundle.packageName) of \(workshopId) again")
        downloader.fetchPackage(workshopId: workshopId, packageName: bundle.packageName,
                                to: bundle.restoredURL) { [weak self] landed in
            guard let self else { return }
            if landed {
                self.ready(bundle, package: bundle.restoredURL)
            } else {
                OWELog.info(.importer, "Unpacked wallpapers: \(workshopId) didn't download; its loose copy stays until a later launch")
                self.skipped.append(bundle)
                if !self.downloader.isLoggedIn { self.waitsForLogin = true }
            }
            self.next()
        }
    }

    private func done() {
        isRunning = false
        onFinished?()
        onFinished = nil
    }

    /// Finishes a bundle off the main thread; a package that doesn't hold the scene is deleted, so
    /// a later launch downloads it again.
    nonisolated static func finishInBackground(_ bundle: UnpackedBundle, _ package: URL) {
        DispatchQueue.global(qos: .utility).async {
            if !bundle.finish(with: package), package == bundle.restoredURL, !bundle.isUsablePackage(package) {
                try? FileManager.default.removeItem(at: package)
            }
        }
    }
}

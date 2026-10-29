import Foundation
import Combine

/// Workshop downloads and previews, through the Steam helper with the app's Steam login
/// (`SteamAccount`). Main-actor state; the helper runs on `downloadQueue` and `previewQueue`,
/// which use only the nonisolated members and hand their results back on the main queue.
@MainActor
class WorkshopDownloadService: ObservableObject {
    /// Whether there is a Steam login to download with.
    @Published private(set) var isLoggedIn = false
    @Published private(set) var steamUsername: String = ""
    @Published var downloadProgress: [String: DownloadState] = [:]
    @Published var previewProgress: Set<String> = []
    @Published var queuedDownloadIds: [String] = []
    @Published var activeDownloadId: String?
    @Published var downloadTitles: [String: String] = [:]
    @Published var downloadItems: [String: DownloadItem] = [:]
    @Published var downloadStartedAt: [String: Date] = [:]
    @Published var downloadPercentages: [String: Double] = [:]
    /// Where each finished download landed in the Wallpaper Storage folder, for Show in Finder and
    /// Set as Wallpaper in the Downloads tab.
    @Published var downloadFolders: [String: URL] = [:]
    /// The app's Steam login, which downloads go through.
    @Published private(set) var steamLogin: SteamLogin?

    enum DownloadState: Equatable {
        case downloading(status: String)
        case completed
        case failed(String)
    }

    struct DownloadItem {
        let title: String
        let previewURL: URL?
        let creatorId: String?
        let subscriptions: Int
        let fileSize: Int
    }

    nonisolated private static let previewCacheLimit = 250 * 1024 * 1024
    private let previewQueue = DispatchQueue(label: "steam.preview.download")
    private let downloadQueue = DispatchQueue(label: "steam.workshop.download")
    private var requestedPreviewId: String?
    /// Which library items came in only as another wallpaper's dependency.
    let dependencyIndex: WorkshopDependencyIndex

    /// Every item that came into the storage folder (or was already there when downloaded again),
    /// on the main queue.
    let itemInstalled = PassthroughSubject<URL, Never>()

    /// The id of an item the user downloaded or kept as their own (not a required item), on the
    /// main queue after `itemInstalled`: Wallpaper Engine subscribes to it (`SteamWorkshopLists`).
    let userItemDownloaded = PassthroughSubject<String, Never>()

    /// Ids Steam reported as removed or private, on the main queue before the download's
    /// completion runs.
    let itemUnavailable = PassthroughSubject<String, Never>()

    /// Fires on the main queue when a Steam login comes in: at launch or a new login.
    let loginSucceeded = PassthroughSubject<Void, Never>()

    /// Steam no longer accepts the Steam login (a download said so), on the main queue.
    let steamLoginRejected = PassthroughSubject<Void, Never>()

    /// An installed item whose files an update just replaced, on the main queue after `itemInstalled`.
    let itemUpdated = PassthroughSubject<URL, Never>()

    /// The queued and running downloads that update an installed item (`updateWorkshopItem`).
    private var updateIds = Set<String>()

    nonisolated private let helperDownloads: SteamHelperDownloading
    /// The Wallpaper Storage folder every download goes into; throws when it can't be used.
    nonisolated private let storageDirectory: @Sendable () throws -> URL
    nonisolated private let previewCacheRoot: URL
    private let downloadedIndex: DownloadedWallpaperIndex
    private let presentPreview: @MainActor (WEWallpaper) -> Void

    init(dependencyIndex: WorkshopDependencyIndex = WorkshopDependencyIndex(),
         helperDownloads: SteamHelperDownloading = ProcessSteamHelperDownloader(),
         storageDirectory: @escaping @Sendable () throws -> URL = { try WallpaperStorage.availableDirectory() },
         previewCacheRoot: URL = WorkshopItemInstaller.previewCacheRoot,
         downloadedIndex: DownloadedWallpaperIndex = .shared,
         presentPreview: @escaping @MainActor (WEWallpaper) -> Void = { AppDelegate.shared.showWorkshopPreview($0) }) {
        self.dependencyIndex = dependencyIndex
        self.helperDownloads = helperDownloads
        self.storageDirectory = storageDirectory
        self.previewCacheRoot = previewCacheRoot
        self.downloadedIndex = downloadedIndex
        self.presentPreview = presentPreview
    }

    /// Downloads go through the Steam helper with `login` from now on; nil stops them.
    func useSteamLogin(_ login: SteamLogin?) {
        guard login != steamLogin else { return }
        steamLogin = login
        steamUsername = login?.accountName ?? ""
        isLoggedIn = login != nil
        if login != nil { loginSucceeded.send() }
    }

    /// Runs `work` on the queue Workshop downloads use, so another Steam download (installing the
    /// assets) never runs beside one of them.
    func enqueueSteamWork(_ work: @escaping @Sendable () -> Void) {
        downloadQueue.async(execute: work)
    }

    /// The status of a download waiting its turn, and of one being moved into the storage folder;
    /// the Downloads tab tells these phases by them.
    nonisolated static let queuedStatus = String(localized: "Queued", comment: "Download status: waiting for other downloads")
    nonisolated static let installingStatus = String(localized: "Moving into Wallpaper Storage…", comment: "Download status; Wallpaper Storage is the name of the library folder setting")

    /// Download a workshop item by its ID. `onCompleted` fires on the main thread with the wallpaper's
    /// destination directory on success, or `nil` if the download was skipped or failed.
    /// `asDependency` marks a download a wallpaper needs rather than one the user asked for; such an
    /// item stays out of the Installed list until the user downloads it themselves.
    func downloadWorkshopItem(
        workshopId: String,
        asDependency: Bool = false,
        title: String? = nil,
        previewURL: URL? = nil,
        creatorId: String? = nil,
        subscriptions: Int = 0,
        fileSize: Int = 0,
        onCompleted: (@MainActor @Sendable (URL?) -> Void)? = nil
    ) {
        enqueue(workshopId: workshopId, isUpdate: false, asDependency: asDependency, title: title, previewURL: previewURL,
                creatorId: creatorId, subscriptions: subscriptions, fileSize: fileSize, onCompleted: onCompleted)
    }

    /// Downloads Steam's newer version of an installed item over the installed one
    /// (`WorkshopUpdateChecker`), as Steam updates Wallpaper Engine's subscriptions. It is listed in
    /// the Downloads tab like a download.
    func updateWorkshopItem(workshopId: String, title: String?, previewURL: URL?) {
        enqueue(workshopId: workshopId, isUpdate: true, asDependency: false, title: title, previewURL: previewURL,
                creatorId: nil, subscriptions: 0, fileSize: 0, onCompleted: nil)
    }

    private func enqueue(workshopId: String, isUpdate: Bool, asDependency: Bool, title: String?, previewURL: URL?,
                         creatorId: String?, subscriptions: Int, fileSize: Int,
                         onCompleted: (@MainActor @Sendable (URL?) -> Void)?) {
        guard let login = steamLogin else {
            onCompleted?(nil)
            return
        }
        guard !queuedDownloadIds.contains(workshopId), activeDownloadId != workshopId else {
            onCompleted?(nil)
            return
        }

        if let title {
            downloadTitles[workshopId] = title
            downloadItems[workshopId] = DownloadItem(
                title: title,
                previewURL: previewURL,
                creatorId: creatorId,
                subscriptions: subscriptions,
                fileSize: fileSize
            )
        }
        queuedDownloadIds.append(workshopId)
        if isUpdate { updateIds.insert(workshopId) } else { updateIds.remove(workshopId) }
        downloadPercentages[workshopId] = 0
        downloadProgress[workshopId] = .downloading(status: Self.queuedStatus)

        downloadQueue.async { [weak self] in
            guard let self = self else { return }
            DispatchQueue.main.async {
                self.activeDownloadId = workshopId
                self.downloadStartedAt[workshopId] = .now
                self.downloadProgress[workshopId] = .downloading(
                    status: String(localized: "Authenticating…", comment: "Download status: logging in to Steam"))
            }
            let result = Result {
                try self.downloadIntoStorage(workshopId, login: login, replacing: isUpdate)
            }
            DispatchQueue.main.async {
                self.queuedDownloadIds.removeAll { $0 == workshopId }
                if self.activeDownloadId == workshopId {
                    self.activeDownloadId = nil
                }
                self.finishDownload(workshopId, isUpdate: isUpdate, asDependency: asDependency, result: result,
                                    onCompleted: onCompleted)
            }
        }
    }

    /// Starts a failed download again with what the first attempt knew about the item.
    func retryDownload(_ workshopId: String) {
        guard case .failed = downloadProgress[workshopId] else { return }
        let item = downloadItems[workshopId]
        if updateIds.contains(workshopId) {
            return updateWorkshopItem(workshopId: workshopId, title: item?.title ?? downloadTitles[workshopId],
                                      previewURL: item?.previewURL)
        }
        downloadWorkshopItem(workshopId: workshopId, title: item?.title ?? downloadTitles[workshopId],
                             previewURL: item?.previewURL, creatorId: item?.creatorId,
                             subscriptions: item?.subscriptions ?? 0, fileSize: item?.fileSize ?? 0)
    }

    /// Retry All Failed in the Downloads tab, in the order they are listed.
    func retryFailedDownloads(_ workshopIds: [String]) {
        for workshopId in workshopIds { retryDownload(workshopId) }
    }

    /// Clear Completed in the Downloads tab: forgets the finished downloads' rows. The items stay
    /// in the library.
    func clearCompletedDownloads() {
        let completed = downloadProgress.compactMap { $0.value == .completed ? $0.key : nil }
        for workshopId in completed {
            downloadProgress[workshopId] = nil
            downloadPercentages[workshopId] = nil
            downloadStartedAt[workshopId] = nil
            downloadFolders[workshopId] = nil
        }
    }

    /// Downloads a Workshop item again only to restore the package a converted bundle was made from:
    /// the package goes into `<wallpaperDirectory>/.owe-source/`, the live files stay untouched.
    /// Runs after other downloads at background priority; `completion` runs on the main queue.
    func fetchArchivedPackage(workshopId: String, packageName: String, into wallpaperDirectory: URL,
                              completion: @escaping @MainActor @Sendable (Bool) -> Void) {
        guard let login = steamLogin,
              !packageName.contains("/"), !packageName.contains("\\"), !packageName.hasPrefix(".") else {
            return completion(false)
        }
        downloadQueue.async(qos: .background) { [weak self] in
            guard let self else { return }
            let landed: Bool
            do {
                let storage = try self.storageDirectory()
                let staging = WorkshopItemInstaller.stagingDirectory(in: storage)
                defer { WorkshopItemInstaller.removeStaging(staging) }
                try FileManager.default.createDirectory(at: staging, withIntermediateDirectories: true)
                let package = try self.helperDownload(workshopId, login: login, into: staging, validate: true)
                    .appending(path: packageName)
                guard FileManager.default.fileExists(atPath: package.path(percentEncoded: false)) else {
                    throw DownloadError.failed("\(packageName) isn't in the download")
                }
                guard ContainedPath.hasNoLinks(below: wallpaperDirectory,
                                               relativePath: WallpaperPackageConverter.sourceFolderName) else {
                    throw DownloadError.failed("\(WallpaperPackageConverter.sourceFolderName) is a symbolic link")
                }
                let folder = wallpaperDirectory.appending(path: WallpaperPackageConverter.sourceFolderName)
                try FileManager.default.createDirectory(at: folder, withIntermediateDirectories: true)
                // Copied beside the destination, then renamed in: a half-copied package never counts.
                let incoming = folder.appending(path: ".incoming-" + UUID().uuidString)
                try FileManager.default.copyItem(at: package, to: incoming)
                let destination = folder.appending(path: packageName)
                try? FileManager.default.removeItem(at: destination)
                try FileManager.default.moveItem(at: incoming, to: destination)
                landed = true
            } catch {
                OWELog.error(.workshop, "Workshop item \(workshopId) package refresh failed: \(error.localizedDescription)")
                landed = false
            }
            DispatchQueue.main.async { completion(landed) }
        }
    }

    /// Downloads into a staging folder inside the storage folder and moves the finished item to
    /// `<storage>/<id>`, or, `replacing`, in place of the installed one. Call on `downloadQueue`:
    /// downloads share the one staging folder.
    nonisolated private func downloadIntoStorage(_ workshopId: String, login: SteamLogin,
                                                 replacing: Bool = false) throws -> WorkshopItemInstaller.Outcome {
        // No fallback: without the storage folder the download doesn't start.
        let storage = try storageDirectory()
        let staging = WorkshopItemInstaller.stagingDirectory(in: storage)
        defer { WorkshopItemInstaller.removeStaging(staging) }
        try FileManager.default.createDirectory(at: staging, withIntermediateDirectories: true)
        if replacing { try Self.stageInstalledCopy(of: workshopId, from: storage, into: staging) }

        let downloaded = try helperDownload(workshopId, login: login, into: staging, validate: true) { [weak self] chunk in
            guard let percentage = SteamHelperDownload.progress(in: chunk) else { return }
            let status = Self.downloadingStatus(percentage)
            DispatchQueue.main.async { [weak self] in
                guard let self else { return }
                // Only changed values are published: the output repeats its progress.
                if self.downloadProgress[workshopId] != .downloading(status: status) {
                    self.downloadProgress[workshopId] = .downloading(status: status)
                }
                if self.downloadPercentages[workshopId] != percentage {
                    self.downloadPercentages[workshopId] = percentage
                }
            }
        }
        DispatchQueue.main.async {
            self.downloadProgress[workshopId] = .downloading(status: Self.installingStatus)
            self.downloadPercentages[workshopId] = 1
        }
        // The storage folder as it is now, in case it changed while the item downloaded.
        if replacing {
            return try WorkshopItemInstaller.replace(itemAt: downloaded, workshopId: workshopId, into: storageDirectory())
        }
        return try WorkshopItemInstaller.install(itemAt: downloaded, workshopId: workshopId, into: storageDirectory())
    }

    /// For an update, a copy of the installed item where the download goes: DepotDownloader checks
    /// the files already there against Steam's manifest and fetches only the chunks that changed.
    /// Not for a converted bundle (`WallpaperPackageConverter`), whose files no longer match the
    /// Workshop's; that downloads in full. On APFS the copy is a clone.
    nonisolated static func stageInstalledCopy(of workshopId: String, from storage: URL, into staging: URL) throws {
        let installed = storage.appending(path: workshopId, directoryHint: .isDirectory)
        let manifest = installed.appending(path: WallpaperPackageConverter.manifestName)
        guard FileManager.default.fileExists(atPath: installed.path),
              !FileManager.default.fileExists(atPath: manifest.path) else { return }
        let item = WorkshopItemInstaller.contentDirectory(in: staging, workshopId: workshopId)
        try FileManager.default.createDirectory(at: item.deletingLastPathComponent(), withIntermediateDirectories: true)
        try FileManager.default.copyItem(at: installed, to: item)
    }

    private func finishDownload(_ workshopId: String, isUpdate: Bool, asDependency: Bool,
                                result: Result<WorkshopItemInstaller.Outcome, Error>,
                                onCompleted: (@MainActor @Sendable (URL?) -> Void)?) {
        let outcome: WorkshopItemInstaller.Outcome
        switch result {
        case .success(let installed):
            outcome = installed
        case .failure(let error):
            OWELog.error(.workshop, "Workshop item \(workshopId) didn't download: \(error.localizedDescription)")
            downloadProgress[workshopId] = .failed(error.localizedDescription)
            if case DownloadError.itemUnavailable = error { itemUnavailable.send(workshopId) }
            onCompleted?(nil)
            return
        }
        let destination = outcome.directory
        let isNew = outcome.isNewInstall
        if isNew {
            DispatchQueue.global(qos: .utility).async {
                WallpaperPreparation.prepare(wallpaperDirectory: destination)
            }
        }
        if isUpdate {
            // An update leaves the item as it was: the user's own download, or a dependency.
            updateIds.remove(workshopId)
            OWELog.info(.workshop, "Updated Workshop item \(workshopId)")
        } else if asDependency {
            dependencyIndex.recordDependencyDownload(workshopId, copiedIntoLibrary: isNew)
        } else {
            dependencyIndex.recordUserDownload(workshopId)
        }
        if isNew { downloadedIndex.markContentDownloaded(workshopId) }
        downloadProgress[workshopId] = .completed
        downloadFolders[workshopId] = destination
        downloadedIndex.insert(workshopId)
        itemInstalled.send(destination)
        if !asDependency, !isUpdate { userItemDownloaded.send(workshopId) }
        if isUpdate { itemUpdated.send(destination) }
        onCompleted?(destination)
    }

    /// Downloads `workshopId` with the Steam helper into `WorkshopItemInstaller.contentDirectory`
    /// under `installDirectory`, and returns that folder. A failed download leaves nothing there.
    nonisolated private func helperDownload(_ workshopId: String, login: SteamLogin, into installDirectory: URL, validate: Bool,
                                            onOutput: @escaping @Sendable (String) -> Void = { _ in }) throws -> URL {
        let item = WorkshopItemInstaller.contentDirectory(in: installDirectory, workshopId: workshopId)
        try FileManager.default.createDirectory(at: item, withIntermediateDirectories: true)
        let run = helperDownloads.run(arguments: SteamHelperDownload.workshopArguments(workshopId: workshopId, directory: item,
                                                                                        validate: validate),
                                      login: login, cancellation: ProcessCancellation(), onOutput: onOutput)
        OWELog.info(.workshop, "Steam helper download [\(workshopId)] exit=\(run.exitCode)\n\(SteamSecretRedactor.redact(run.output, secrets: [login.refreshToken]))")
        SteamHelperDownload.removeBookkeeping(in: item)
        let outcome = SteamHelperDownload.outcome(output: run.output, exitCode: run.exitCode,
                                                  downloaded: SteamHelperDownload.hasFiles(in: item))
        guard outcome != .downloaded else { return item }
        do {
            try FileManager.default.removeItem(at: item)
        } catch {
            OWELog.error(.workshop, "Can't remove the failed download \(item.path): \(error)")
        }
        switch outcome {
        case .downloaded:
            return item
        case .unavailable:
            throw DownloadError.itemUnavailable(.removedOrPrivate)
        case .loginRejected:
            DispatchQueue.main.async { self.steamLoginRejected.send() }
            throw SteamHelperError(code: .tokenRejected, message: "Steam rejected the login for a download.")
        case .notOwned:
            throw DownloadError.failed(String(localized: "This Steam account can't download Wallpaper Engine items.",
                                              comment: "Download error"))
        case .failed(let message):
            throw DownloadError.failed(message)
        }
    }

    /// `Downloading… 45%`.
    nonisolated private static func downloadingStatus(_ fraction: Double) -> String {
        let percent: String = fraction.formatted(.percent.precision(.fractionLength(0)))
        return String(localized: "Downloading… \(percent)", comment: "Download status; %@ is a percentage")
    }

    func previewWorkshopItem(workshopId: String) {
        prepareWorkshopPreview(workshopId: workshopId, presentWhenReady: true)
    }

    private func prepareWorkshopPreview(workshopId: String, presentWhenReady: Bool) {
        guard let login = steamLogin else { return }

        if presentWhenReady {
            requestedPreviewId = workshopId
        }
        guard !previewProgress.contains(workshopId) else { return }
        previewProgress.insert(workshopId)

        previewQueue.async { [weak self] in
            guard let self = self else { return }

            let cacheRoot = self.previewCacheRoot
            let sourcePath = WorkshopItemInstaller.contentDirectory(in: cacheRoot, workshopId: workshopId)

            do {
                try FileManager.default.createDirectory(at: cacheRoot, withIntermediateDirectories: true)
                try self.trimPreviewCache(at: cacheRoot, keeping: workshopId)
                if !FileManager.default.fileExists(atPath: sourcePath.path) {
                    _ = try self.helperDownload(workshopId, login: login, into: cacheRoot, validate: false)
                }
                let size = try self.directorySize(at: sourcePath)
                guard size <= Self.previewCacheLimit else {
                    try FileManager.default.removeItem(at: sourcePath)
                    throw PreviewError.exceedsCacheLimit
                }
                try self.trimPreviewCache(at: cacheRoot, keeping: workshopId)

                let project = try WEProject.read(in: sourcePath)
                self.finishPreview(workshopId, with: .success(WEWallpaper(using: project, where: sourcePath)), presentWhenReady: presentWhenReady)
            } catch {
                self.finishPreview(workshopId, with: .failure(error), presentWhenReady: presentWhenReady)
            }
        }
    }

    /// Moves a Workshop preview the user chose to keep out of the preview cache into the storage
    /// folder, as the user's own download. Returns nil when `wallpaper` isn't a cached preview.
    func keepPreview(_ wallpaper: WEWallpaper) throws -> WEWallpaper? {
        let source = wallpaper.wallpaperDirectory
        guard WorkshopItemInstaller.isPreview(source, cacheRoot: previewCacheRoot) else { return nil }
        let workshopId = source.lastPathComponent
        let outcome = try WorkshopItemInstaller.install(itemAt: source, workshopId: workshopId, into: storageDirectory())
        let destination = outcome.directory
        if outcome.isNewInstall {
            DispatchQueue.global(qos: .utility).async {
                WallpaperPreparation.prepare(wallpaperDirectory: destination)
            }
        }
        dependencyIndex.recordUserDownload(workshopId)
        downloadedIndex.insert(workshopId)
        itemInstalled.send(destination)
        userItemDownloaded.send(workshopId)
        OWELog.info(.workshop, "Kept Workshop preview \(workshopId) in \(destination.path)")
        return WEWallpaper(using: wallpaper.project, where: destination)
    }

    nonisolated private func finishPreview(
        _ workshopId: String,
        with result: Result<WEWallpaper, Error>,
        presentWhenReady: Bool
    ) {
        DispatchQueue.main.async {
            self.previewProgress.remove(workshopId)
            switch result {
            case .success(let wallpaper):
                if presentWhenReady, self.requestedPreviewId == workshopId {
                    self.presentPreview(wallpaper)
                }
            case .failure(let error):
                if presentWhenReady, self.requestedPreviewId == workshopId {
                    self.downloadProgress[workshopId] = .failed(error.localizedDescription)
                }
            }
        }
    }

    nonisolated private func trimPreviewCache(at cacheRoot: URL, keeping workshopId: String) throws {
        let contentDirectory = WorkshopItemInstaller.contentRoot(in: cacheRoot)
        guard FileManager.default.fileExists(atPath: contentDirectory.path) else { return }

        var cacheSize = try directorySize(at: cacheRoot)
        let entries = try FileManager.default.contentsOfDirectory(
            at: contentDirectory,
            includingPropertiesForKeys: [.contentModificationDateKey],
            options: .skipsHiddenFiles
        )
        let oldestFirst = entries
            .filter { $0.lastPathComponent != workshopId }
            .sorted {
                let firstDate = (try? $0.resourceValues(forKeys: [.contentModificationDateKey]))?.contentModificationDate ?? .distantPast
                let secondDate = (try? $1.resourceValues(forKeys: [.contentModificationDateKey]))?.contentModificationDate ?? .distantPast
                return firstDate < secondDate
            }

        for entry in oldestFirst where cacheSize > Self.previewCacheLimit {
            try FileManager.default.removeItem(at: entry)
            cacheSize = try directorySize(at: cacheRoot)
        }
    }

    nonisolated private func directorySize(at directory: URL) throws -> Int {
        let keys: Set<URLResourceKey> = [.isRegularFileKey, .totalFileAllocatedSizeKey, .fileAllocatedSizeKey]
        guard let enumerator = FileManager.default.enumerator(
            at: directory,
            includingPropertiesForKeys: Array(keys),
            options: [.skipsHiddenFiles]
        ) else {
            return 0
        }

        var totalSize = 0
        for case let fileURL as URL in enumerator {
            let values = try fileURL.resourceValues(forKeys: keys)
            guard values.isRegularFile == true else { continue }
            totalSize += values.totalFileAllocatedSize ?? values.fileAllocatedSize ?? 0
        }
        return totalSize
    }
}

private enum DownloadError: LocalizedError {
    case failed(String)
    /// Steam said the item was removed or made private.
    case itemUnavailable(WorkshopItemAvailability.Reason)

    var errorDescription: String? {
        switch self {
        case .failed(let message): return message
        case .itemUnavailable(let reason): return reason.message
        }
    }
}

private enum PreviewError: LocalizedError {
    case exceedsCacheLimit

    var errorDescription: String? {
        switch self {
        case .exceedsCacheLimit: return String(localized: "Preview exceeds the 250 MB cache limit.")
        }
    }
}

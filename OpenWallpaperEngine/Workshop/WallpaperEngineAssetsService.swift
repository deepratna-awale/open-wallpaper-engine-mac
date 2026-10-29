import Foundation
import Combine

/// Installs, updates and removes the Wallpaper Engine assets scenes need, and reports which copy
/// is in use (`WallpaperEngineAssets`). The download is the parts of the user's own Steam copy the
/// cache keeps, fetched through the Steam login; only its `assets` subset is kept and the rest is
/// deleted.
@MainActor
final class WallpaperEngineAssetsService: ObservableObject {
    enum Phase: Equatable {
        case idle
        case downloading(status: String, progress: WallpaperEngineAssetsDownload.Progress?)
        case copying
        case failed(String)
    }

    struct Status: Equatable {
        var resolution: WallpaperEngineAssets.Resolution?
        var info: WallpaperEngineAssetsCache.Info?
        /// The chosen install folder, set or not valid.
        var chosenFolder: String?
        var cacheSize: Int64?
        var freeSpace: Int64?
    }

    enum Failure: LocalizedError, Equatable {
        /// No Steam login, or Steam no longer accepts it.
        case notLoggedIn
        case notOwned
        /// The download failed; Steam's or the helper's message.
        case steam(String)
        /// Looking up the current build failed, so nothing was downloaded.
        case updateCheckFailed(String)

        var errorDescription: String? {
            switch self {
            case .notLoggedIn:
                return String(localized: "Log in to Steam first, then install the assets.", comment: "Assets install error")
            case .notOwned:
                return String(localized: "This Steam account doesn't own Wallpaper Engine. The assets come from your own copy: buy it on Steam, or choose the folder of an install.",
                              comment: "Assets install error")
            case .steam(let message):
                return message
            case .updateCheckFailed(let reason):
                return String(localized: "Couldn't check for a Wallpaper Engine update, so nothing was downloaded: \(reason) To download anyway, choose Re-download.",
                              comment: "Assets update check error; %@ is the reason Steam gave")
            }
        }
    }

    @Published private(set) var status = Status()
    @Published private(set) var phase: Phase = .idle
    /// Why the last install failed, for the action offered beside the message (e.g. "Log In").
    @Published private(set) var lastFailure: Failure?
    /// The outcome of the last "Update from Steam" that found nothing to download.
    @Published private(set) var notice: String?
    /// Fires when the asset tree in use changed, so wallpapers can reload.
    let assetsChanged = PassthroughSubject<Void, Never>()

    private let workshopDownloads: WorkshopDownloadService
    /// The Steam login's connection, for the current build.
    private let steamHelper: SteamHelperClient?
    private let helperDownloads: SteamHelperDownloading
    private let storageDirectory: () throws -> URL
    private let defaults: UserDefaults
    private var cancellation: ProcessCancellation?
    private var loginCancellable: AnyCancellable?

    /// Settings › Assets: install the assets by themselves after a Steam login (on by default).
    static let autoInstallKey = "InstallsWallpaperEngineAssetsAfterLogin"
    /// The onboarding's "Also add Wallpaper Engine's default wallpapers" (on by default).
    static let addsDefaultWallpapersKey = "OnboardingAddsDefaultWallpapers"
    /// The Steam account the last install found doesn't own Wallpaper Engine; logging in with it
    /// again doesn't retry by itself.
    static let notOwnedAccountKey = "WallpaperEngineAssetsNotOwnedAccount"

    /// `automaticInstallAllowed` is off under XCTest unless a test turns it on.
    init(workshopDownloads: WorkshopDownloadService,
         steamHelper: SteamHelperClient? = nil,
         helperDownloads: SteamHelperDownloading = ProcessSteamHelperDownloader(),
         storageDirectory: @escaping () throws -> URL = { try WallpaperStorage.availableDirectory() },
         defaults: UserDefaults = .app,
         automaticInstallAllowed: Bool = !WallpaperEngineAssets.isTesting) {
        self.workshopDownloads = workshopDownloads
        self.steamHelper = steamHelper
        self.helperDownloads = helperDownloads
        self.storageDirectory = storageDirectory
        self.defaults = defaults
        refresh()
        guard automaticInstallAllowed else { return }
        loginCancellable = workshopDownloads.loginSucceeded.sink { [weak self] in self?.installAfterLoginIfNeeded() }
    }

    enum AutomaticInstallDecision: Equatable {
        case install(includingDefaultWallpapers: Bool)
        case turnedOff
        case busy
        case folderChosen
        case cached
        case notOwned
        case storageUnavailable
    }

    /// Whether a login starts the Steam install by itself: only when it is turned on, nothing is
    /// running, and no assets are there (no chosen folder, no cache), and not again for an account
    /// that doesn't own Wallpaper Engine.
    func automaticInstallDecision() -> AutomaticInstallDecision {
        guard defaults.object(forKey: Self.autoInstallKey) as? Bool ?? true else { return .turnedOff }
        guard !isBusy else { return .busy }
        if let chosen = defaults.string(forKey: WallpaperEngineAssets.chosenFolderKey), !chosen.isEmpty {
            return .folderChosen
        }
        guard let cache = cacheDirectory else { return .storageUnavailable }
        if WallpaperEngineAssets.isAssetTree(cache) { return .cached }
        if let account = defaults.string(forKey: Self.notOwnedAccountKey), account == workshopDownloads.steamUsername {
            return .notOwned
        }
        let includes: Bool = defaults.object(forKey: Self.addsDefaultWallpapersKey) as? Bool ?? true
        return .install(includingDefaultWallpapers: includes)
    }

    /// Called after each successful Steam login.
    func installAfterLoginIfNeeded() {
        let decision = automaticInstallDecision()
        switch decision {
        case .install(let includes):
            OWELog.info(.library, "Assets: installing from Steam after login")
            installFromSteam(includingDefaultWallpapers: includes)
        case .notOwned:
            fail(.notOwned)
        case .turnedOff, .busy, .folderChosen, .cached, .storageUnavailable:
            break
        }
    }

    var isMissing: Bool { status.resolution == nil }

    var isBusy: Bool {
        switch phase {
        case .downloading, .copying: return true
        case .idle, .failed: return false
        }
    }

    /// The cache folder, when the storage folder can be used.
    private var cacheDirectory: URL? {
        do {
            return WallpaperEngineAssets.cacheDirectory(in: try storageDirectory())
        } catch {
            OWELog.error(.library, "Assets: \(error.localizedDescription)")
            return nil
        }
    }

    /// Reads the state again; sizes are measured off the main thread.
    func refresh() {
        let storage: URL? = cacheDirectory?.deletingLastPathComponent()
        let chosen = defaults.string(forKey: WallpaperEngineAssets.chosenFolderKey)
        let resolution = WallpaperEngineAssets.isTesting
            ? WallpaperEngineAssets.current
            : WallpaperEngineAssets.resolve(chosenPath: chosen, storage: storage, testOverride: nil, isTesting: false)
        let cache = storage.map(WallpaperEngineAssets.cacheDirectory(in:))
        status = Status(resolution: resolution,
                        info: cache.flatMap { WallpaperEngineAssetsCache.readInfo(cache: $0) },
                        chosenFolder: chosen,
                        cacheSize: nil,
                        freeSpace: nil)
        guard let storage else { return }
        DispatchQueue.global(qos: .utility).async { [weak self] in
            let cacheURL = WallpaperEngineAssets.cacheDirectory(in: storage)
            let size: Int64? = FileManager.default.fileExists(atPath: cacheURL.path)
                ? WallpaperEngineAssetsCache.size(of: cacheURL) : nil
            let free: Int64? = Self.freeSpace(at: storage)
            DispatchQueue.main.async { [weak self] in
                self?.status.cacheSize = size
                self?.status.freeSpace = free
            }
        }
    }

    nonisolated private static func freeSpace(at url: URL) -> Int64? {
        do {
            return try url.resourceValues(forKeys: [.volumeAvailableCapacityForImportantUsageKey])
                .volumeAvailableCapacityForImportantUsage
        } catch {
            OWELog.error(.library, "Can't read the free space at \(url.path): \(error)")
            return nil
        }
    }

    /// Uses a Wallpaper Engine install (or its `assets` folder) in place.
    func chooseFolder(_ folder: URL) throws {
        guard WallpaperEngineAssets.isAssetTree(WallpaperEngineAssets.assetsFolder(of: folder)) else {
            throw WallpaperEngineAssetsCache.Failure.notAnInstall(folder)
        }
        defaults.set(folder.standardizedFileURL.path, forKey: WallpaperEngineAssets.chosenFolderKey)
        changed()
    }

    /// Stops using the chosen folder; the cache (if any) takes over.
    func forgetChosenFolder() {
        defaults.removeObject(forKey: WallpaperEngineAssets.chosenFolderKey)
        changed()
    }

    /// The default wallpapers the assets install added that are still in the storage folder.
    var defaultWallpapers: [String] {
        guard let storage = cacheDirectory?.deletingLastPathComponent() else { return [] }
        return (status.info?.defaultProjects ?? []).filter {
            FileManager.default.fileExists(atPath: storage.appending(path: $0).path)
        }
    }

    /// Deletes the cache (it can be downloaded again at any time) and, when asked, moves the
    /// default wallpapers it added to the Trash.
    func removeCache(includingDefaultWallpapers: Bool) {
        guard let cache = cacheDirectory else { return }
        if includingDefaultWallpapers {
            let storage = cache.deletingLastPathComponent()
            for name in defaultWallpapers {
                do {
                    try FileManager.default.trashItem(at: storage.appending(path: name), resultingItemURL: nil)
                } catch {
                    OWELog.error(.library, "Can't move the default wallpaper \(name) to the Trash: \(error)")
                }
            }
        }
        WallpaperEngineAssetsCache.removeIfPresent(cache)
        changed()
    }

    func cancel() {
        cancellation?.cancel()
    }

    /// Downloads the parts of the user's Wallpaper Engine copy the cache keeps through the Steam
    /// login, and keeps its assets in the cache. With `includingDefaultWallpapers`, the copy's default
    /// wallpapers (never application ones) also move into the storage folder; without, they are
    /// deleted with the rest of the download. A complete Steam copy is only downloaded again when
    /// Steam has a newer build, unless `force` (Re-download, to repair a damaged copy).
    func installFromSteam(includingDefaultWallpapers: Bool = true, force: Bool = false) {
        guard !isBusy else { return }
        notice = nil
        guard let login = workshopDownloads.steamLogin else { return fail(.notLoggedIn) }
        lastFailure = nil
        let storage: URL
        do {
            storage = try storageDirectory()
        } catch {
            return fail(.steam(error.localizedDescription))
        }
        let token = ProcessCancellation()
        cancellation = token
        let cache = WallpaperEngineAssets.cacheDirectory(in: storage)
        let installed = WallpaperEngineAssetsCache.readInfo(cache: cache)
        let checksFirst = WallpaperEngineAssetsUpdateCheck.needsLookup(force: force, installed: installed,
                                                                       assetsComplete: WallpaperEngineAssets.isAssetTree(cache))
        phase = .downloading(status: checksFirst
                                ? String(localized: "Checking for updates…", comment: "Assets update check status")
                                : String(localized: "Authenticating…", comment: "Download status: logging in to Steam"),
                             progress: nil)
        var job = InstallJob(login: login, downloader: helperDownloads, storage: storage,
                             includesDefaultWallpapers: includingDefaultWallpapers, cancellation: token)
        // The app info has the current build: looked up before the download is queued, to compare
        // with the cache's and to record.
        Task { [weak self] in
            guard let self else { return }
            let build = await self.currentBuild()
            if token.isCancelled { return self.finishInstall(.failure(CancellationError()), cancelled: true) }
            switch build {
            case .success(let build):
                if checksFirst,
                   case .upToDate(let build) = WallpaperEngineAssetsUpdateCheck.decision(
                       installed: WallpaperEngineAssetsCache.readInfo(cache: cache),
                       assetsComplete: WallpaperEngineAssets.isAssetTree(cache), currentBuild: build) {
                    return self.finishInstall(.success(.upToDate(build: build)), cancelled: false)
                }
                job.currentBuild = build
            case .failure(let error):
                guard !checksFirst else { return self.finishInstall(.failure(error), cancelled: false) }
                OWELog.error(.library, "Assets: no current build to record: \(error.localizedDescription)")
            }
            self.phase = .downloading(status: String(localized: "Authenticating…", comment: "Download status: logging in to Steam"),
                                      progress: nil)
            self.enqueue(job, cancellation: token)
        }
    }

    /// Wallpaper Engine's current public build, through the Steam login.
    private func currentBuild() async -> Result<String, Error> {
        guard let steamHelper else { return .failure(Failure.updateCheckFailed("No Steam helper.")) }
        do {
            let info = try await steamHelper.appInfo(appID: UInt32(WallpaperEngineAssetsDownload.appID))
            guard let build = info.publicBuildID, !build.isEmpty else {
                return .failure(Failure.updateCheckFailed("Steam has no public build of Wallpaper Engine."))
            }
            return .success(build)
        } catch let error as SteamHelperError where error.needsNewSignIn {
            return .failure(Failure.notLoggedIn)
        } catch {
            return .failure(Failure.updateCheckFailed(error.localizedDescription))
        }
    }

    private func enqueue(_ job: InstallJob, cancellation token: ProcessCancellation) {
        workshopDownloads.enqueueSteamWork { [weak self] in
            let result = job.run(
                onProgress: { [weak self] progress in
                    DispatchQueue.main.async { [weak self] in self?.showDownloadProgress(progress) }
                },
                onCopying: { DispatchQueue.main.async { [weak self] in self?.phase = .copying } })
            DispatchQueue.main.async { [weak self] in self?.finishInstall(result, cancelled: token.isCancelled) }
        }
    }

    private func showDownloadProgress(_ progress: WallpaperEngineAssetsDownload.Progress) {
        guard case .downloading = phase else { return }
        let percent: String = progress.fraction.formatted(.percent.precision(.fractionLength(0)))
        phase = .downloading(status: String(localized: "Downloading… \(percent)", comment: "Download status; %@ is a percentage"),
                             progress: progress)
    }

    private func finishInstall(_ result: Result<InstallJob.Outcome, Error>, cancelled: Bool) {
        cancellation = nil
        switch result {
        case .success(.upToDate(let build)):
            phase = .idle
            OWELog.info(.library, "Assets are up to date (build \(build)); nothing downloaded")
            notice = String(localized: "Wallpaper Engine assets are up to date (build \(build)).",
                            comment: "Assets update check result; %@ is Steam's build number")
            refresh()
        case .success(.installed):
            defaults.removeObject(forKey: Self.notOwnedAccountKey)
            phase = .idle
            OWELog.info(.library, "Assets installed from Steam")
            changed()
        case .failure(let error):
            if cancelled || error is CancellationError {
                phase = .idle
            } else {
                let failure = error as? Failure
                if failure == .notOwned {
                    defaults.set(workshopDownloads.steamUsername, forKey: Self.notOwnedAccountKey)
                }
                if failure == .notLoggedIn { workshopDownloads.steamLoginRejected.send() }
                lastFailure = failure
                OWELog.error(.library, "Assets install failed: \(error.localizedDescription)")
                phase = .failed(error.localizedDescription)
            }
            refresh()
        }
    }

    private func fail(_ failure: Failure) {
        lastFailure = failure
        phase = .failed(failure.errorDescription ?? "")
    }

    private func changed() {
        notice = nil
        refresh()
        assetsChanged.send()
    }
}

/// One install run, off the main thread: download the parts the cache keeps through the Steam
/// login, copy the subset, delete the download.
private struct InstallJob {
    let login: SteamLogin
    let downloader: SteamHelperDownloading
    let storage: URL
    let includesDefaultWallpapers: Bool
    let cancellation: ProcessCancellation
    /// Steam's current build, recorded with the cache.
    var currentBuild: String?

    enum Outcome: Equatable {
        case installed
        case upToDate(build: String)
    }

    func run(onProgress: @escaping @Sendable (WallpaperEngineAssetsDownload.Progress) -> Void,
             onCopying: () -> Void) -> Result<Outcome, Error> {
        let download = WallpaperEngineAssetsDownload.downloadDirectory(in: storage)
        // Only the assets are kept; the rest goes right away.
        defer { WallpaperEngineAssetsCache.removeIfPresent(download) }
        do {
            WallpaperEngineAssetsCache.removeIfPresent(download)
            try FileManager.default.createDirectory(at: download, withIntermediateDirectories: true)
            try downloadWithSteamHelper(into: download, onProgress: onProgress)
            onCopying()
            let cache = WallpaperEngineAssets.cacheDirectory(in: storage)
            let previous = WallpaperEngineAssetsCache.readInfo(cache: cache)?.defaultProjects ?? []
            var info = WallpaperEngineAssetsCache.Info(origin: .steam, installedAt: .now, steamBuildID: currentBuild)
            try WallpaperEngineAssetsCache.fill(cache, from: download, info: info, isCancelled: { cancellation.isCancelled })
            // The download is deleted next, so the default wallpapers move rather than copy.
            var imported = WallpaperEngineDefaultProjects.ImportResult()
            if includesDefaultWallpapers {
                imported = try WallpaperEngineDefaultProjects.importProjects(from: download, into: storage, move: true)
                OWELog.info(.library, "Default wallpapers: \(imported.imported.count) added, \(imported.existing.count) already there, \(imported.unsupported.count) unsupported")
            } else {
                OWELog.info(.library, "Default wallpapers not added: the user left them out")
            }
            let kept = previous.filter { FileManager.default.fileExists(atPath: storage.appending(path: $0).path) }
            info.defaultProjects = kept + imported.imported.filter { !kept.contains($0) }
            try WallpaperEngineAssetsCache.writeInfo(info, cache: cache)
            return .success(.installed)
        } catch {
            return .failure(error)
        }
    }

    /// Downloads the parts of Wallpaper Engine the cache keeps (`SteamHelperDownload.assetsFileList`)
    /// into `download`.
    private func downloadWithSteamHelper(into download: URL,
                                         onProgress: @escaping @Sendable (WallpaperEngineAssetsDownload.Progress) -> Void) throws {
        // Inside the download folder, so it goes with it; DepotDownloader only writes what the list names.
        let fileList = download.appending(path: ".owe-filelist.txt")
        try Data(SteamHelperDownload.assetsFileList.utf8).write(to: fileList)
        let run = downloader.run(arguments: SteamHelperDownload.assetsArguments(directory: download, fileList: fileList),
                                 login: login, cancellation: cancellation) { chunk in
            if let fraction = SteamHelperDownload.progress(in: chunk) {
                onProgress(WallpaperEngineAssetsDownload.Progress(fraction: fraction))
            }
        }
        OWELog.info(.workshop, "Steam helper assets download exit=\(run.exitCode)\n\(SteamSecretRedactor.redact(run.output, secrets: [login.refreshToken]))")
        if cancellation.isCancelled { throw CancellationError() }
        let present = WallpaperEngineAssets.isAssetTree(download.appending(path: "assets"))
        switch SteamHelperDownload.outcome(output: run.output, exitCode: run.exitCode, downloaded: present) {
        case .downloaded: break
        case .notOwned: throw WallpaperEngineAssetsService.Failure.notOwned
        case .loginRejected: throw WallpaperEngineAssetsService.Failure.notLoggedIn
        case .unavailable: throw WallpaperEngineAssetsService.Failure.steam(run.output)
        case .failed(let message): throw WallpaperEngineAssetsService.Failure.steam(message)
        }
    }
}

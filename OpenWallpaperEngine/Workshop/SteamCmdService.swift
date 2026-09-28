import Foundation
import Combine

class SteamCmdService: ObservableObject {
    @Published var steamCmdPath: String?
    @Published var isLoggedIn = false
    @Published var steamUsername: String = ""
    @Published var loginError: String?
    @Published var isLoggingIn = false
    @Published var downloadProgress: [String: DownloadState] = [:]
    @Published var previewProgress: Set<String> = []
    @Published var queuedDownloadIds: [String] = []
    @Published var activeDownloadId: String?
    @Published var downloadTitles: [String: String] = [:]
    @Published var downloadItems: [String: DownloadItem] = [:]
    @Published var downloadStartedAt: [String: Date] = [:]
    @Published var downloadPercentages: [String: Double] = [:]

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

    /// The account name of the last successful login, kept to reuse steamcmd's cached session.
    /// The password is never stored: steamcmd keeps its own login token after the first login.
    private let account: SteamCmdAccountMemory
    private static let previewCacheLimit = 250 * 1024 * 1024
    private let previewQueue = DispatchQueue(label: "steamcmd.preview.download")
    private let downloadQueue = DispatchQueue(label: "steamcmd.workshop.download")
    private var requestedPreviewId: String?
    /// Which library items came in only as another wallpaper's dependency.
    let dependencyIndex: WorkshopDependencyIndex

    /// Every item that came into the storage folder (or was already there when downloaded again),
    /// on the main queue.
    let itemInstalled = PassthroughSubject<URL, Never>()

    /// Fires on the main queue after each successful login: with a password, the Terminal login's
    /// cached session, or the session restored at launch.
    let loginSucceeded = PassthroughSubject<Void, Never>()

    private let runner: SteamCmdRunning
    /// The Wallpaper Storage folder every download goes into; throws when it can't be used.
    private let storageDirectory: () throws -> URL
    private let previewCacheRoot: URL
    private let downloadedIndex: DownloadedWallpaperIndex
    private let presentPreview: @MainActor (WEWallpaper) -> Void
    /// Where `detectSteamCmd` looks.
    private let locator: () -> SteamCmdLocator
    /// Whether detection falls back to the login shell's `PATH`; off when the search is redirected.
    private let asksLoginShell: Bool

    init(dependencyIndex: WorkshopDependencyIndex = WorkshopDependencyIndex(),
         runner: SteamCmdRunning = ProcessSteamCmdRunner(),
         storageDirectory: @escaping () throws -> URL = { try WallpaperStorage.availableDirectory() },
         previewCacheRoot: URL = WorkshopItemInstaller.previewCacheRoot,
         downloadedIndex: DownloadedWallpaperIndex = .shared,
         presentPreview: @escaping @MainActor (WEWallpaper) -> Void = { AppDelegate.shared.showWorkshopPreview($0) },
         locator: @escaping () -> SteamCmdLocator = { SteamCmdLocator.standard() },
         asksLoginShell: Bool = SteamCmdLocator.searchRoot(environment: ProcessInfo.processInfo.environment) == nil,
         account: SteamCmdAccountMemory = .keychain,
         restoresSession: Bool = true) {
        self.account = account
        self.locator = locator
        self.asksLoginShell = asksLoginShell
        self.dependencyIndex = dependencyIndex
        self.runner = runner
        self.storageDirectory = storageDirectory
        self.previewCacheRoot = previewCacheRoot
        self.downloadedIndex = downloadedIndex
        self.presentPreview = presentPreview
        // Without it the service starts with no steamcmd and logged out, for the caller to set up.
        guard restoresSession else { return }
        // The session is restored once detection is done: a steamcmd found only through the login
        // shell arrives later, and restoring before it would never log in.
        detectSteamCmd { [weak self] _ in self?.attemptCachedLogin() }
    }

    /// Runs steamcmd with `script` on its stdin; nothing of the script shows in the process list.
    private func runSteamCmd(script: SteamCmdScript, timeout: TimeInterval = 30) -> (output: String, exitCode: Int32) {
        guard let cmdPath = steamCmdPath else { return ("", -1) }
        let run = runner.run(executable: URL(fileURLWithPath: cmdPath), script: script, timeout: timeout)
        return (run.output, run.exitCode)
    }

    /// Automatically try cached session if we have a saved username and steamcmd is installed.
    private func attemptCachedLogin() {
        guard isInstalled, !isLoggedIn, !isLoggingIn else { return }
        if let saved = account.load() {
            loginWithCachedSession(username: saved)
        }
    }

    /// The account of the last successful login, whose SteamCMD session may still be cached.
    var rememberedAccount: String? {
        if !steamUsername.isEmpty { return steamUsername }
        return account.load()
    }

    /// Logs in with the remembered account's cached session unless logged in already.
    /// `completion` runs on the main queue with whether a session is there.
    func restoreSession(completion: @escaping (Bool) -> Void) {
        if isLoggedIn { return completion(true) }
        guard isInstalled, !isLoggingIn, let username = rememberedAccount else { return completion(false) }
        loginWithCachedSession(username: username, completion: completion)
    }

    /// Another steamcmd run found the cached login gone (e.g. the assets install): the app shows
    /// the account as logged out again.
    func sessionExpired() {
        isLoggedIn = false
        loginError = String(localized: "SteamCMD has no saved login for this account. Log in again.",
                            comment: "Login error after SteamCMD reported its cached login missing")
    }

    /// What a steamcmd `login` printed. Success needs SteamCMD's own login confirmation: other
    /// lines end in "OK" too ("Loading Steam API...OK"), and steamcmd exits 0 after `quit` even
    /// when the login failed.
    enum LoginOutcome: Equatable {
        case loggedIn
        case guardCodeRequired
        case invalidPassword
        case noCachedLogin
        case failed
    }

    static func loginOutcome(output: String) -> LoginOutcome {
        if output.contains("Steam Guard") || output.contains("Two-factor") || output.contains("two-factor") {
            return .guardCodeRequired
        }
        if output.contains("Invalid Password") || output.contains("InvalidPassword") { return .invalidPassword }
        if output.contains("Cached credentials not found") || output.contains("No cached credentials")
            || output.contains("password prompt disabled") {
            return .noCachedLogin
        }
        let lines = output.components(separatedBy: .newlines).map { $0.trimmingCharacters(in: .whitespacesAndNewlines) }
        if lines.contains(where: { $0.hasPrefix("Logging in user") && $0.contains("FAILED") }) { return .failed }
        let confirmed = lines.contains { line in
            line.hasPrefix("Logged in OK") || line.hasPrefix("Waiting for user info...OK")
                || (line.hasPrefix("Logging in user") && line.hasSuffix("...OK"))
        }
        return confirmed ? .loggedIn : .failed
    }

    /// Finds steamcmd (`SteamCmdLocator`), then, when none of the known places has one, asks the
    /// user's login shell on a background queue. `completion` runs on the main queue once the
    /// search is done, with whether a steamcmd was found.
    func detectSteamCmd(completion: ((Bool) -> Void)? = nil) {
        let locator = locator()
        if let path = locator.locate() {
            if steamCmdPath != path { steamCmdPath = path }
            completion?(true)
            return
        }
        guard asksLoginShell else {
            steamCmdPath = nil
            completion?(false)
            return
        }
        DispatchQueue.global(qos: .utility).async { [weak self] in
            let path = SteamCmdLocator.loginShellLookup()
            DispatchQueue.main.async {
                guard let self else { return }
                if self.steamCmdPath != path { self.steamCmdPath = path }
                completion?(path != nil)
            }
        }
    }

    var isInstalled: Bool { steamCmdPath != nil }

    /// Runs `work` on the queue Workshop downloads use, so another steamcmd session (installing
    /// the assets) never runs beside one of them.
    func enqueueSteamCmdWork(_ work: @escaping () -> Void) {
        downloadQueue.async(execute: work)
    }

    @Published var pathError: String?

    /// The status of a download waiting its turn, and of one being moved into the storage folder;
    /// the Downloads tab tells these phases by them.
    /// The login error that asks for a Steam Guard code; the login form offers the code field for it.
    static let guardCodeRequiredError = String(localized: "Steam Guard code required",
                                               comment: "Login error; Steam Guard is Steam's two-factor authentication")
    static let queuedStatus = String(localized: "Queued", comment: "Download status: waiting for other downloads")
    static let installingStatus = String(localized: "Moving into Wallpaper Storage…", comment: "Download status; Wallpaper Storage is the name of the library folder setting")

    func setCustomPath(_ path: String) {
        guard FileManager.default.fileExists(atPath: path) else {
            pathError = String(localized: "File not found at selected path.")
            return
        }
        // Make executable if needed (e.g. steamcmd.sh from Steam package)
        if !FileManager.default.isExecutableFile(atPath: path) {
            do {
                try FileManager.default.setAttributes([.posixPermissions: 0o755], ofItemAtPath: path)
            } catch {
                OWELog.error(.workshop, "Can't make \(path) executable: \(error)")
            }
        }
        guard SteamCmdLocator.isExecutableFile(path) else {
            pathError = String(localized: "The selected file isn't a program that can run.",
                               comment: "Error after choosing a steamcmd binary")
            return
        }
        pathError = nil
        UserDefaults.app.set(path, forKey: SteamCmdLocator.customPathKey)
        steamCmdPath = path
    }

    /// Attempt login with username and password. Steam Guard code is optional.
    /// Neither is stored: steamcmd caches a login token, which `loginWithCachedSession` reuses.
    func login(username: String, password: String, guardCode: String? = nil) {
        guard steamCmdPath != nil else { return }

        let code = guardCode.flatMap { $0.isEmpty ? nil : $0 }
        var script = SteamCmdScript.withoutPasswordPrompt()
        do {
            try script.append("login", [username, password] + (code.map { [$0] } ?? []))
        } catch {
            loginError = error.localizedDescription
            return
        }

        isLoggingIn = true
        loginError = nil
        steamUsername = username

        downloadQueue.async { [weak self] in
            guard let self = self else { return }

            let (rawOutput, exitCode) = self.runSteamCmd(script: script, timeout: 60)
            let output = SteamSecretRedactor.redact(rawOutput, secrets: [password] + (code.map { [$0] } ?? []))

            DispatchQueue.main.async {
                self.isLoggingIn = false
                switch Self.loginOutcome(output: output) {
                case .loggedIn:
                    self.isLoggedIn = true
                    self.loginError = nil
                    self.rememberAccount(username)
                    self.loginSucceeded.send()
                case .guardCodeRequired:
                    self.loginError = Self.guardCodeRequiredError
                case .invalidPassword, .noCachedLogin:
                    self.loginError = String(localized: "Invalid username or password")
                case .failed:
                    self.loginError = String(localized: "Login failed. Check credentials and try again.")
                }
                if !self.isLoggedIn {
                    OWELog.error(.workshop, "steamcmd login failed (exit \(exitCode)):\n\(output)")
                }
            }
        }
    }

    private func rememberAccount(_ username: String) {
        do {
            try account.save(username)
        } catch {
            OWELog.error(.workshop, "Can't keep the steamcmd account for the next launch: \(error)")
        }
    }

    /// Try login with cached session (no password needed if previously authenticated).
    /// `failureMessage` replaces the default error when the session isn't there.
    func loginWithCachedSession(username: String, failureMessage: String? = nil,
                                completion: ((Bool) -> Void)? = nil) {
        guard steamCmdPath != nil else { completion?(false); return }

        var script = SteamCmdScript.withoutPasswordPrompt()
        do {
            try script.append("login", [username])
        } catch {
            loginError = error.localizedDescription
            completion?(false)
            return
        }

        isLoggingIn = true
        loginError = nil
        steamUsername = username

        DispatchQueue.global(qos: .userInitiated).async { [weak self] in
            guard let self = self else { return }

            let (output, exitCode) = self.runSteamCmd(script: script, timeout: 30)

            DispatchQueue.main.async {
                self.isLoggingIn = false
                if Self.loginOutcome(output: output) == .loggedIn {
                    self.isLoggedIn = true
                    self.rememberAccount(username)
                    self.loginSucceeded.send()
                    completion?(true)
                } else {
                    OWELog.error(.workshop, "steamcmd cached login failed (exit \(exitCode)):\n\(output)")
                    self.isLoggedIn = false
                    self.loginError = failureMessage
                        ?? String(localized: "Cached session expired. Please log in with password.")
                    completion?(false)
                }
            }
        }
    }

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
        onCompleted: ((URL?) -> Void)? = nil
    ) {
        guard let cmdPath = steamCmdPath, isLoggedIn else {
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
        downloadPercentages[workshopId] = 0
        downloadProgress[workshopId] = .downloading(status: Self.queuedStatus)

        downloadQueue.async { [weak self] in
            guard let self = self else { return }
            DispatchQueue.main.async {
                self.activeDownloadId = workshopId
                self.downloadStartedAt[workshopId] = .now
                self.downloadProgress[workshopId] = .downloading(status: String(localized: "Starting steamcmd…", comment: "Download status; steamcmd is a program name"))
            }
            let result = Result { try self.downloadIntoStorage(workshopId, steamCmd: URL(fileURLWithPath: cmdPath)) }
            DispatchQueue.main.async {
                self.queuedDownloadIds.removeAll { $0 == workshopId }
                if self.activeDownloadId == workshopId {
                    self.activeDownloadId = nil
                }
                self.finishDownload(workshopId, asDependency: asDependency, result: result, onCompleted: onCompleted)
            }
        }
    }

    /// Runs steamcmd into a staging folder inside the storage folder and moves the finished item to
    /// `<storage>/<id>`. Call on `downloadQueue`: downloads share the one staging folder.
    private func downloadIntoStorage(_ workshopId: String, steamCmd: URL) throws -> WorkshopItemInstaller.Outcome {
        // No fallback: without the storage folder the download doesn't start.
        let storage = try storageDirectory()
        let staging = WorkshopItemInstaller.stagingDirectory(in: storage)
        defer { WorkshopItemInstaller.removeStaging(staging) }
        try FileManager.default.createDirectory(at: staging, withIntermediateDirectories: true)

        let script = try Self.workshopDownloadScript(installDirectory: staging, username: steamUsername,
                                                     workshopId: workshopId, validate: true)
        // Output arrives in chunks as steamcmd reports progress.
        let run = runner.run(executable: steamCmd, script: script, timeout: nil) { [weak self] chunk in
            let status = self?.parseProgress(chunk)
            let percentage = self?.parseDownloadPercentage(chunk)
            guard status != nil || percentage != nil else { return }
            DispatchQueue.main.async {
                if let status { self?.downloadProgress[workshopId] = .downloading(status: status) }
                if let percentage { self?.downloadPercentages[workshopId] = percentage }
            }
        }
        OWELog.info(.workshop, "steamcmd download [\(workshopId)] exit=\(run.exitCode)\n\(run.output)")

        let downloaded = WorkshopItemInstaller.contentDirectory(inSteamCmdRoot: staging, workshopId: workshopId)
        guard FileManager.default.fileExists(atPath: downloaded.path) else {
            throw DownloadError.steamCmdFailed(Self.failureMessage(output: run.output, exitCode: run.exitCode))
        }
        DispatchQueue.main.async {
            self.downloadProgress[workshopId] = .downloading(status: Self.installingStatus)
            self.downloadPercentages[workshopId] = 1
        }
        // The storage folder as it is now, in case it changed while steamcmd ran.
        return try WorkshopItemInstaller.install(itemAt: downloaded, workshopId: workshopId, into: storageDirectory())
    }

    private func finishDownload(_ workshopId: String, asDependency: Bool,
                                result: Result<WorkshopItemInstaller.Outcome, Error>,
                                onCompleted: ((URL?) -> Void)?) {
        let outcome: WorkshopItemInstaller.Outcome
        switch result {
        case .success(let installed):
            outcome = installed
        case .failure(let error):
            OWELog.error(.workshop, "Workshop item \(workshopId) didn't download: \(error.localizedDescription)")
            downloadProgress[workshopId] = .failed(error.localizedDescription)
            onCompleted?(nil)
            return
        }
        let destination = outcome.directory
        let isNew = outcome.isNewInstall
        if isNew {
            DispatchQueue.global(qos: .utility).async {
                WallpaperPackageConverter.convertIfNeeded(wallpaperDirectory: destination)
            }
        }
        if asDependency {
            dependencyIndex.recordDependencyDownload(workshopId, copiedIntoLibrary: isNew)
        } else {
            dependencyIndex.recordUserDownload(workshopId)
        }
        downloadProgress[workshopId] = .completed
        downloadedIndex.insert(workshopId)
        itemInstalled.send(destination)
        onCompleted?(destination)
    }

    /// The line of steamcmd's output that says why no item came out of it.
    private static func failureMessage(output: String, exitCode: Int32) -> String {
        let lines = output.components(separatedBy: "\n").map { $0.trimmingCharacters(in: .whitespaces) }
        if let errorLine = lines.first(where: { $0.contains("ERROR") || $0.contains("FAILED") }) {
            return errorLine
        }
        if exitCode != 0 {
            return lines.last(where: { !$0.isEmpty })
                ?? String(localized: "steamcmd exited with code \(exitCode).", comment: "Download error; steamcmd is a program name")
        }
        return String(localized: "steamcmd finished without downloading the item.", comment: "Download error; steamcmd is a program name")
    }

    func previewWorkshopItem(workshopId: String) {
        prepareWorkshopPreview(workshopId: workshopId, presentWhenReady: true)
    }

    private func prepareWorkshopPreview(workshopId: String, presentWhenReady: Bool) {
        guard steamCmdPath != nil, isLoggedIn else { return }

        if presentWhenReady {
            requestedPreviewId = workshopId
        }
        guard !previewProgress.contains(workshopId) else { return }
        previewProgress.insert(workshopId)

        previewQueue.async { [weak self] in
            guard let self = self else { return }

            let cacheRoot = self.previewCacheRoot
            let sourcePath = WorkshopItemInstaller.contentDirectory(inSteamCmdRoot: cacheRoot, workshopId: workshopId)

            do {
                try FileManager.default.createDirectory(at: cacheRoot, withIntermediateDirectories: true)
                try self.trimPreviewCache(at: cacheRoot, keeping: workshopId)
            } catch {
                self.finishPreview(workshopId, with: .failure(error), presentWhenReady: presentWhenReady)
                return
            }

            if !FileManager.default.fileExists(atPath: sourcePath.path) {
                let script: SteamCmdScript
                do {
                    script = try Self.workshopDownloadScript(
                        installDirectory: cacheRoot,
                        username: self.steamUsername,
                        workshopId: workshopId,
                        validate: false
                    )
                } catch {
                    self.finishPreview(workshopId, with: .failure(error), presentWhenReady: presentWhenReady)
                    return
                }
                let (output, exitCode) = self.runSteamCmd(script: script, timeout: 300)

                guard exitCode == 0, FileManager.default.fileExists(atPath: sourcePath.path) else {
                    let errorLine = output.components(separatedBy: "\n")
                        .first(where: { $0.contains("ERROR") || $0.contains("FAILED") })
                        ?? String(localized: "Preview download failed.")
                    self.finishPreview(workshopId, with: .failure(PreviewError.downloadFailed(errorLine)), presentWhenReady: presentWhenReady)
                    return
                }
            }

            do {
                let size = try self.directorySize(at: sourcePath)
                guard size <= Self.previewCacheLimit else {
                    try FileManager.default.removeItem(at: sourcePath)
                    throw PreviewError.exceedsCacheLimit
                }
                try self.trimPreviewCache(at: cacheRoot, keeping: workshopId)

                let projectURL = sourcePath.appending(path: "project.json")
                let project = try JSONDecoder().decode(WEProject.self, from: Data(contentsOf: projectURL))
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
                WallpaperPackageConverter.convertIfNeeded(wallpaperDirectory: destination)
            }
        }
        dependencyIndex.recordUserDownload(workshopId)
        downloadedIndex.insert(workshopId)
        itemInstalled.send(destination)
        OWELog.info(.workshop, "Kept Workshop preview \(workshopId) in \(destination.path)")
        return WEWallpaper(using: wallpaper.project, where: destination)
    }

    /// Logs in with the cached session and downloads one Wallpaper Engine workshop item.
    private static func workshopDownloadScript(
        installDirectory: URL,
        username: String,
        workshopId: String,
        validate: Bool
    ) throws -> SteamCmdScript {
        var script = SteamCmdScript.withoutPasswordPrompt()
        try script.append("@sSteamCmdForcePlatformType", ["windows"])
        try script.append("force_install_dir", [installDirectory.path])
        try script.append("login", [username])
        try script.append("workshop_download_item",
                          ["\(WorkshopAPIService.wallpaperEngineAppId)", workshopId] + (validate ? ["validate"] : []))
        return script
    }

    private func finishPreview(
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

    private func trimPreviewCache(at cacheRoot: URL, keeping workshopId: String) throws {
        let contentDirectory = WorkshopItemInstaller.contentRoot(inSteamCmdRoot: cacheRoot)
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

    private func directorySize(at directory: URL) throws -> Int {
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

    /// Parse steamcmd output lines into human-readable progress.
    private func parseProgress(_ output: String) -> String? {
        let trimmed = output.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return nil }

        if trimmed.contains("Logging in") || trimmed.contains("Logged in") {
            return String(localized: "Authenticating…", comment: "Download status: logging in to Steam")
        }
        if trimmed.contains("Downloading item") || trimmed.contains("workshop_download_item") {
            return String(localized: "Requesting download…", comment: "Download status")
        }
        if trimmed.contains("Downloading") || trimmed.contains("downloading") {
            if let percentage = parseDownloadPercentage(trimmed) {
                let percent: String = percentage.formatted(.percent.precision(.fractionLength(0)))
                return String(localized: "Downloading… \(percent)", comment: "Download status; %@ is a percentage")
            }
            return String(localized: "Downloading…", comment: "Download status")
        }
        if trimmed.contains("Validating") || trimmed.contains("validating") {
            return String(localized: "Validating…", comment: "Download status: steamcmd checks the downloaded files")
        }
        if trimmed.contains("Success") {
            return String(localized: "Download complete, importing…", comment: "Download status")
        }
        if trimmed.contains("Update state") {
            // Generic state update
            if trimmed.contains("0x5") { return String(localized: "Validating…", comment: "Download status: steamcmd checks the downloaded files") }
            if trimmed.contains("0x61") { return String(localized: "Downloading…", comment: "Download status") }
            if trimmed.contains("0x101") { return String(localized: "Committing…", comment: "Download status: steamcmd writes the finished files") }
        }
        return nil
    }

    private func parseDownloadPercentage(_ output: String) -> Double? {
        guard let range = output.range(of: "progress:\\s*([0-9]+(?:\\.[0-9]+)?)", options: .regularExpression) else {
            return nil
        }
        let value = output[range]
            .replacingOccurrences(of: "progress:", with: "")
            .trimmingCharacters(in: .whitespacesAndNewlines)
        guard let percentage = Double(value) else { return nil }
        return min(max(percentage / 100, 0), 1)
    }

}

private enum DownloadError: LocalizedError {
    case steamCmdFailed(String)

    var errorDescription: String? {
        switch self {
        case .steamCmdFailed(let message): return message
        }
    }
}

private enum PreviewError: LocalizedError {
    case downloadFailed(String)
    case exceedsCacheLimit

    var errorDescription: String? {
        switch self {
        case .downloadFailed(let message): return message
        case .exceedsCacheLimit: return String(localized: "Preview exceeds the 250 MB cache limit.")
        }
    }
}

/// Where the account name of the last login is kept (the Keychain in the app); tests keep it in
/// memory.
struct SteamCmdAccountMemory {
    let load: () -> String?
    let save: (String) throws -> Void

    static var keychain: SteamCmdAccountMemory {
        let secret = SteamCredentials.steamCmdAccount()
        return SteamCmdAccountMemory(load: { secret.load() }, save: { try secret.save($0) })
    }
}

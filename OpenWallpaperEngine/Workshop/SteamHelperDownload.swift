import Foundation

/// Runs one `owe-steam-helper download` (SteamHelper/README.md): DepotDownloader logged on with the
/// app's Steam login, which goes to its stdin. `WorkshopDownloadService` and the assets install take it as
/// a dependency, so tests can stand in a fake.
protocol SteamHelperDownloading: Sendable {
    /// Blocks until the helper exits; `onOutput` receives the output as it arrives, on a
    /// background queue, and `cancellation` stops the helper.
    func run(arguments: [String], login: SteamLogin, cancellation: ProcessCancellation,
             onOutput: @escaping @Sendable (String) -> Void) -> ProcessRun
}

/// Runs the bundled helper (`SteamHelperLocator`).
struct ProcessSteamHelperDownloader: SteamHelperDownloading {
    func run(arguments: [String], login: SteamLogin, cancellation: ProcessCancellation,
             onOutput: @escaping @Sendable (String) -> Void) -> ProcessRun {
        guard let executable = SteamHelperLocator.executable() else {
            return ProcessRun(output: SteamHelperError(code: .helperMissing, message: "").errorDescription ?? "",
                               exitCode: -1)
        }
        let input: Data
        do {
            input = try SteamHelperDownload.standardInput(for: login)
        } catch {
            return ProcessRun(output: "Can't encode the Steam login: \(error)", exitCode: -1)
        }
        return ProcessRunner.runProcess(executable: executable, arguments: ["download"] + arguments,
                                                standardInput: input, timeout: nil, cancellation: cancellation,
                                                onOutput: onOutput)
    }
}

/// What the app asks DepotDownloader for, and how its output reads. Pure, so tests cover it
/// without running the helper.
enum SteamHelperDownload {
    enum Outcome: Equatable {
        case downloaded
        /// Steam no longer accepts the login: the user logs in again.
        case loginRejected
        /// A Workshop item that was removed or made private.
        case unavailable
        /// The account doesn't own the app.
        case notOwned
        case failed(String)
    }

    /// The folder DepotDownloader keeps its bookkeeping in, inside `-dir`.
    static let bookkeepingFolderName = ".DepotDownloader"

    /// The assets depot (and everything else of the app), and the one with the UI strings.
    static let assetsDepots = ["431961", "431966"]

    /// What the asset cache and the default wallpapers are made from (`WallpaperEngineAssetsCache`,
    /// `WallpaperEngineDefaultProjects`); the rest of the app isn't downloaded.
    static let assetsFileList = [
        #"regex:^assets/"#,
        #"regex:^locale/ui_[^/]*\.json$"#,
        "regex:^\(NSRegularExpression.escapedPattern(for: WallpaperEngineAssetsCache.installTemplatesPath))/",
        #"regex:^projects/defaultprojects/"#,
        "regex:^\(NSRegularExpression.escapedPattern(for: WallpaperEngineAssetsCache.installSnippetsPath))/",
    ].joined(separator: "\n") + "\n"

    /// The first line of the helper's stdin.
    static func standardInput(for login: SteamLogin) throws -> Data {
        struct Line: Encodable { let accountName, refreshToken: String }
        return try JSONEncoder().encode(Line(accountName: login.accountName, refreshToken: login.refreshToken)) + Data("\n".utf8)
    }

    /// One Workshop item, its files straight into `directory`.
    static func workshopArguments(workshopId: String, directory: URL, validate: Bool) -> [String] {
        ["-app", "\(WorkshopAPIService.wallpaperEngineAppId)", "-pubfile", workshopId, "-dir", directory.path]
            + (validate ? ["-validate"] : [])
    }

    /// The parts of Wallpaper Engine in `fileList` (a file holding `assetsFileList`), into `directory`.
    static func assetsArguments(directory: URL, fileList: URL) -> [String] {
        ["-app", "\(WorkshopAPIService.wallpaperEngineAppId)"]
            + assetsDepots.flatMap { ["-depot", $0] }
            + ["-dir", directory.path, "-filelist", fileList.path, "-validate"]
    }

    /// What a finished run came to; `downloaded` says whether the files are there. The lines it
    /// reads are DepotDownloader's; `DownloadMessagesTests` (SteamHelper/Tests) checks they're still printed.
    static func outcome(output: String, exitCode: Int32, downloaded: Bool) -> Outcome {
        // Any failed logon prints "Unable to get steam3 credentials"; only this one is the login's.
        if output.contains("Access token was rejected") { return .loginRejected }
        if output.contains("Unable to locate manifest ID for published file") { return .unavailable }
        if output.contains("is not available from this account") { return .notOwned }
        if exitCode == 0, downloaded { return .downloaded }
        let lines = output.components(separatedBy: .newlines).map { $0.trimmingCharacters(in: .whitespaces) }
        if let line = lines.last(where: { $0.hasPrefix("Error") || $0.contains("failed") || $0.contains("Unable to") }) {
            return .failed(line)
        }
        if let last = lines.last(where: { !$0.isEmpty }) { return .failed(last) }
        return .failed(String(localized: "Steam finished without downloading the item.",
                              comment: "Download error"))
    }

    /// The last of DepotDownloader's progress lines in `chunk` (` 45.12% path`), as a fraction.
    static func progress(in chunk: String) -> Double? {
        var latest: Double?
        for line in chunk.split(whereSeparator: \.isNewline) {
            let trimmed = line.drop { $0 == " " }
            guard let percent = trimmed.firstIndex(of: "%"), let value = Double(trimmed[..<percent]) else { continue }
            latest = min(max(value / 100, 0), 1)
        }
        return latest
    }

    /// Whether `directory` holds anything but DepotDownloader's bookkeeping.
    static func hasFiles(in directory: URL) -> Bool {
        let names: [String]
        do {
            names = try FileManager.default.contentsOfDirectory(atPath: directory.path)
        } catch {
            return false
        }
        return names.contains { $0 != bookkeepingFolderName }
    }

    /// Deletes DepotDownloader's bookkeeping from a finished download.
    static func removeBookkeeping(in directory: URL) {
        let folder = directory.appending(path: bookkeepingFolderName)
        guard FileManager.default.fileExists(atPath: folder.path) else { return }
        do {
            try FileManager.default.removeItem(at: folder)
        } catch {
            OWELog.error(.workshop, "Can't remove \(folder.path): \(error)")
        }
    }
}

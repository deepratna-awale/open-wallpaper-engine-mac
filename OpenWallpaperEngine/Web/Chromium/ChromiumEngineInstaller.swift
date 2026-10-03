import Combine
import Foundation

/// Installs the optional Chromium web engine (CEF) on demand, the way `SteamCmdInstaller`
/// installs SteamCMD: nothing of CEF ships with the app.
///
/// Layout under `<Application Support>/Open Wallpaper Engine/ChromiumEngine` (or the isolated
/// sibling `AppStorageLocation` picks):
///
///     <version>/Chromium Embedded Framework.framework   one folder per installed CEF version
///     <version>/LICENSE.txt
///     <version>/.owe-chromium-engine.json                written last: marks a complete install
///     .state.json                                        the active and the previous version
///     .profile/                                          CEF's profile (cookies, cache)
///     .staging-<uuid>/                                   one install in progress
///
/// An install downloads to `.partial`, checks the SHA-256 pinned in `ChromiumEnginePin`, unpacks
/// into the staging folder and only then renames the result into place, so a cancelled, failed
/// or mismatched download never leaves a half install. Replacing an existing folder of the same
/// version keeps the old one until the new one is in place, and puts it back if that fails. Only
/// the active and the previous version are kept.
///
/// Updates follow the app: when an app release pins a new build, `needsUpdate` turns on and
/// Update installs the new pin. There is no "latest".
@MainActor
final class ChromiumEngineInstaller: ObservableObject {
    enum Phase: Equatable {
        case idle
        case downloading(fraction: Double?)
        case verifying
        case unpacking
        case installed
        case failed(String)
    }

    nonisolated static var defaultRoot: URL {
        AppStorageLocation.current.supportDirectory.appending(path: "ChromiumEngine", directoryHint: .isDirectory)
    }

    @Published private(set) var phase: Phase = .idle
    /// The active install's version, nil without one.
    @Published private(set) var installedVersion: String?
    /// Bytes every installed version takes together, nil without any.
    @Published private(set) var installedSize: Int64?

    let root: URL
    /// The build this app release wants, nil on an architecture with no pin.
    let pin: ChromiumEnginePin?
    private let downloader: SteamCmdPackageDownloading
    private let trash: (URL) throws -> Void
    private var task: Task<Void, Never>?

    init(root: URL = ChromiumEngineInstaller.defaultRoot,
         pin: ChromiumEnginePin? = ChromiumEnginePin.current(),
         downloader: SteamCmdPackageDownloading = URLSessionSteamCmdDownloader(),
         trash: @escaping (URL) throws -> Void = { try FileManager.default.trashItem(at: $0, resultingItemURL: nil) }) {
        self.root = root
        self.pin = pin
        self.downloader = downloader
        self.trash = trash
        refresh()
    }

    var isBusy: Bool {
        switch phase {
        case .downloading, .verifying, .unpacking: return true
        case .idle, .installed, .failed: return false
        }
    }

    /// Whether the pinned build is the active install.
    var isCurrent: Bool { pin != nil && installedVersion == pin?.version }

    /// An older (or other) build is installed and this release pins a different one.
    var needsUpdate: Bool { installedVersion != nil && !isCurrent && pin != nil }

    /// The active install's folder, nil without one.
    var activeInstall: URL? {
        installedVersion.map { root.appending(path: $0, directoryHint: .isDirectory) }
    }

    /// CEF's profile folder.
    var profileDirectory: URL { root.appending(path: ".profile", directoryHint: .isDirectory) }

    /// Re-reads what is on disk.
    func refresh() {
        let state = ChromiumEngineInstallState.read(in: root)
        let previousVersion = installedVersion
        if let active = state.active, ChromiumEnginePackage.manifest(in: root.appending(path: active)) != nil {
            installedVersion = active
        } else {
            installedVersion = nil
        }
        // Web wallpapers move to the engine that is now there (`WebEngineRouter`).
        if installedVersion != previousVersion {
            NotificationCenter.default.post(name: .chromiumEngineChanged, object: nil)
        }
        let versions = ChromiumEngineInstallJob.installedVersions(in: root)
        installedSize = versions.isEmpty ? nil : versions.reduce(Int64(0)) {
            $0 + SteamCmdPackage.size(of: root.appending(path: $1, directoryHint: .isDirectory))
        }
    }

    // MARK: Install, update, cancel, remove

    /// Installs the pinned build; also what Update does.
    func install() {
        guard !isBusy, let pin else { return }
        phase = .downloading(fraction: nil)
        let job = ChromiumEngineInstallJob(root: root, pin: pin, downloader: downloader)
        task = Task { [weak self] in
            do {
                try await job.run(
                    progress: { fraction in Task { @MainActor in self?.showDownload(fraction) } },
                    phase: { phase in Task { @MainActor in self?.showStep(phase) } })
                self?.finish(.success(()))
            } catch {
                self?.finish(.failure(error))
            }
        }
    }

    func update() {
        install()
    }

    /// The running install awaits `wait()` in tests.
    func wait() async {
        await task?.value
    }

    func cancel() {
        task?.cancel()
    }

    /// Moves every installed version and CEF's profile to the Trash.
    func remove() throws {
        guard !isBusy else { return }
        if FileManager.default.fileExists(atPath: root.path) {
            try trash(root)
        }
        phase = .idle
        refresh()
    }

    private func showDownload(_ fraction: Double?) {
        guard case .downloading = phase else { return }
        phase = .downloading(fraction: fraction)
    }

    private func showStep(_ step: Phase) {
        guard isBusy else { return }
        phase = step
    }

    private func finish(_ result: Result<Void, Error>) {
        task = nil
        switch result {
        case .success:
            OWELog.info(.web, "Chromium engine \(pin?.version ?? "?") installed under \(root.path)")
            phase = .installed
        case .failure(let error) where error is CancellationError:
            OWELog.info(.web, "Chromium engine install cancelled")
            phase = .idle
        case .failure(let error):
            OWELog.error(.web, "Chromium engine install failed: \(error)")
            phase = .failed(Self.message(for: error))
        }
        refresh()
    }

    /// A message the user can act on: offline and a full disk get their own.
    nonisolated static func message(for error: Error) -> String {
        if let urlError = error as? URLError {
            switch urlError.code {
            case .notConnectedToInternet, .networkConnectionLost, .cannotFindHost, .cannotConnectToHost,
                 .dnsLookupFailed, .timedOut, .internationalRoamingOff, .dataNotAllowed:
                return String(localized: "Can't reach the server to download the Chromium engine. Check your internet connection and try again.",
                              comment: "Chromium engine install error")
            default:
                break
            }
        }
        if case URLSessionSteamCmdDownloader.Failure.httpStatus(let code) = error {
            return String(localized: "The download server answered with HTTP status \(code).",
                          comment: "Chromium engine install error; %lld is an HTTP status code")
        }
        let nsError = error as NSError
        if (nsError.domain == NSCocoaErrorDomain && nsError.code == NSFileWriteOutOfSpaceError)
            || (nsError.domain == NSPOSIXErrorDomain && nsError.code == Int(ENOSPC))
            || (error as? URLError)?.code == .cannotWriteToFile {
            return String(localized: "There isn't enough free disk space to install the Chromium engine.",
                          comment: "Chromium engine install error")
        }
        return error.localizedDescription
    }
}

/// `.state.json`: which install is active and which one came before it.
struct ChromiumEngineInstallState: Codable, Equatable {
    var active: String?
    var previous: String?

    static let fileName = ".state.json"

    static func read(in root: URL) -> ChromiumEngineInstallState {
        guard let data = try? Data(contentsOf: root.appending(path: fileName)),
              let state = try? JSONDecoder().decode(Self.self, from: data) else { return ChromiumEngineInstallState() }
        return state
    }

    func write(in root: URL) throws {
        try JSONEncoder().encode(self).write(to: root.appending(path: Self.fileName), options: .atomic)
    }
}

/// The work of one install, off the main actor.
struct ChromiumEngineInstallJob: Sendable {
    let root: URL
    let pin: ChromiumEnginePin
    let downloader: SteamCmdPackageDownloading

    static let stagingPrefix = ".staging-"

    func run(progress: @escaping @Sendable (Double?) -> Void,
             phase: @escaping @Sendable (ChromiumEngineInstaller.Phase) -> Void) async throws {
        let fileManager = FileManager.default
        try fileManager.createDirectory(at: root, withIntermediateDirectories: true)
        Self.removeStaleStaging(in: root)
        let staging = root.appending(path: "\(Self.stagingPrefix)\(UUID().uuidString)", directoryHint: .isDirectory)
        try fileManager.createDirectory(at: staging, withIntermediateDirectories: false)
        defer { Self.remove(staging) }

        let partial = staging.appending(path: pin.archiveName + ".partial")
        try await downloader.download(pin.downloadURL, to: partial, progress: progress)
        try Task.checkCancellation()

        phase(.verifying)
        try ChromiumEnginePackage.verify(partial, sha256: pin.sha256)
        let archive = staging.appending(path: pin.archiveName)
        try fileManager.moveItem(at: partial, to: archive)
        ChromiumEnginePackage.removeQuarantine(fromVerified: archive)
        try Task.checkCancellation()

        phase(.unpacking)
        let scratch = staging.appending(path: "scratch", directoryHint: .isDirectory)
        try fileManager.createDirectory(at: scratch, withIntermediateDirectories: false)
        let unpacked = staging.appending(path: "unpacked", directoryHint: .isDirectory)
        try ChromiumEnginePackage.unpack(archive, pin: pin, scratch: scratch, into: unpacked)
        try Task.checkCancellation()

        try commit(unpacked, staging: staging)
    }

    /// Renames `unpacked` into place, records it as active and prunes. A folder of the same
    /// version is set aside first and restored if the rename fails.
    func commit(_ unpacked: URL, staging: URL) throws {
        let fileManager = FileManager.default
        let target = root.appending(path: pin.version, directoryHint: .isDirectory)
        let setAside = staging.appending(path: "replaced", directoryHint: .isDirectory)
        let hadTarget = fileManager.fileExists(atPath: target.path)
        if hadTarget {
            try fileManager.moveItem(at: target, to: setAside)
        }
        do {
            try fileManager.moveItem(at: unpacked, to: target)
        } catch {
            if hadTarget {
                do {
                    try fileManager.moveItem(at: setAside, to: target)
                } catch let restoreError {
                    OWELog.error(.web, "Can't restore the Chromium engine at \(target.path): \(restoreError)")
                }
            }
            throw error
        }
        var state = ChromiumEngineInstallState.read(in: root)
        if state.active != pin.version {
            state.previous = state.active
            state.active = pin.version
        }
        try state.write(in: root)
        Self.prune(in: root, keeping: [state.active, state.previous].compactMap { $0 })
    }

    /// Version folders under `root`: every visible folder.
    static func installedVersions(in root: URL) -> [String] {
        let names = (try? FileManager.default.contentsOfDirectory(atPath: root.path)) ?? []
        return names.filter { name in
            var isDirectory: ObjCBool = false
            return !name.hasPrefix(".")
                && FileManager.default.fileExists(atPath: root.appending(path: name).path, isDirectory: &isDirectory)
                && isDirectory.boolValue
        }.sorted()
    }

    /// Deletes every version folder not in `keeping`.
    static func prune(in root: URL, keeping: [String]) {
        for version in installedVersions(in: root) where !keeping.contains(version) {
            OWELog.info(.web, "Removing Chromium engine \(version)")
            remove(root.appending(path: version, directoryHint: .isDirectory))
        }
    }

    /// Staging folders a crashed or killed install left behind.
    static func removeStaleStaging(in root: URL) {
        let names = (try? FileManager.default.contentsOfDirectory(atPath: root.path)) ?? []
        for name in names where name.hasPrefix(stagingPrefix) {
            remove(root.appending(path: name, directoryHint: .isDirectory))
        }
    }

    private static func remove(_ url: URL) {
        guard FileManager.default.fileExists(atPath: url.path) else { return }
        do {
            try FileManager.default.removeItem(at: url)
        } catch {
            OWELog.error(.web, "Can't remove \(url.path): \(error)")
        }
    }
}

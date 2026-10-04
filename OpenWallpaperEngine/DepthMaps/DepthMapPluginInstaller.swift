import Combine
import CoreML
import Foundation
import OWEEditor

/// Installs the optional Depth Map Generation plugin on demand, the way `ChromiumEngineInstaller`
/// installs the Chromium engine: nothing of the model ships with the app, and it is off until the
/// user installs it in Settings › Plugins.
///
/// Layout: `DepthMapPluginLayout`, under `<Application Support>/Open Wallpaper Engine/Plugins/
/// DepthMaps` (or the isolated sibling `AppStorageLocation` picks, so an isolated copy has its
/// own). An install downloads every file of the pinned `.mlpackage` (`DepthMapModelPin`) into a
/// staging folder, checks each against its SHA-256, compiles the package (`MLModel.compileModel`)
/// and only then renames the result into place, so a cancelled, failed or mismatched download
/// never leaves a half install. Replacing a folder of the same version keeps the old one until
/// the new one is in place. Only the active and the previous version are kept.
@MainActor
final class DepthMapPluginInstaller: ObservableObject {
    enum Phase: Equatable {
        case idle
        case downloading(fraction: Double?)
        case compiling
        case installed
        case failed(String)
    }

    nonisolated static var defaultRoot: URL {
        DepthMapPluginLayout.root(supportDirectory: AppStorageLocation.current.supportDirectory)
    }

    @Published private(set) var phase: Phase = .idle
    @Published private(set) var installedVersion: String?
    @Published private(set) var installedSize: Int64?

    let root: URL
    let pin: DepthMapModelPin
    private let downloader: SteamCmdPackageDownloading
    private let compile: @Sendable (URL) async throws -> URL
    private let trash: (URL) throws -> Void
    private var task: Task<Void, Never>?

    init(root: URL = DepthMapPluginInstaller.defaultRoot,
         pin: DepthMapModelPin = .pinned,
         downloader: SteamCmdPackageDownloading = URLSessionSteamCmdDownloader(),
         compile: @escaping @Sendable (URL) async throws -> URL = { try await MLModel.compileModel(at: $0) },
         trash: @escaping (URL) throws -> Void = { try FileManager.default.trashItem(at: $0, resultingItemURL: nil) }) {
        self.root = root
        self.pin = pin
        self.downloader = downloader
        self.compile = compile
        self.trash = trash
        refresh()
    }

    var isBusy: Bool {
        switch phase {
        case .downloading, .compiling: return true
        case .idle, .installed, .failed: return false
        }
    }

    var isCurrent: Bool { installedVersion == pin.version }
    var needsUpdate: Bool { installedVersion != nil && !isCurrent }
    var activeInstall: URL? { installedVersion.map { root.appending(path: $0, directoryHint: .isDirectory) } }

    func refresh() {
        installedVersion = DepthMapPluginLayout.activeModel(in: root)?.version
        let versions = DepthMapPluginInstallJob.installedVersions(in: root)
        installedSize = versions.isEmpty ? nil : versions.reduce(Int64(0)) {
            $0 + SteamCmdPackage.size(of: root.appending(path: $1, directoryHint: .isDirectory))
        }
    }

    // MARK: Install, update, cancel, remove

    func install() {
        guard !isBusy else { return }
        phase = .downloading(fraction: 0)
        let job = DepthMapPluginInstallJob(root: root, pin: pin, downloader: downloader, compile: compile)
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

    func wait() async {
        await task?.value
    }

    func cancel() {
        task?.cancel()
    }

    /// Moves every installed version to the Trash.
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
            OWELog.info(.app, "Depth Map Generation \(pin.version) installed under \(root.path)")
            phase = .installed
        case .failure(let error) where error is CancellationError:
            OWELog.info(.app, "Depth Map Generation install cancelled")
            phase = .idle
        case .failure(let error):
            OWELog.error(.app, "Depth Map Generation install failed: \(error)")
            phase = .failed(Self.message(for: error))
        }
        refresh()
    }

    nonisolated static func message(for error: Error) -> String {
        if let urlError = error as? URLError {
            switch urlError.code {
            case .notConnectedToInternet, .networkConnectionLost, .cannotFindHost, .cannotConnectToHost,
                 .dnsLookupFailed, .timedOut, .internationalRoamingOff, .dataNotAllowed:
                return String(localized: "Can’t reach Hugging Face to download the depth model. Check your internet connection and try again.",
                              table: "DepthMaps", comment: "Depth Map Generation install error")
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
            || (nsError.domain == NSPOSIXErrorDomain && nsError.code == Int(ENOSPC)) {
            return String(localized: "There isn’t enough free disk space to install the depth model.",
                          table: "DepthMaps", comment: "Depth Map Generation install error")
        }
        return error.localizedDescription
    }
}

/// The work of one install, off the main actor.
struct DepthMapPluginInstallJob: Sendable {
    enum Failure: LocalizedError, Equatable {
        case checksumMismatch(path: String)
        case compileFailed(String)

        var errorDescription: String? {
            switch self {
            case .checksumMismatch:
                return String(localized: "The depth model download doesn’t match the version this app expects, so it wasn’t installed. Try again later.",
                              table: "DepthMaps", comment: "Depth Map Generation install error: a downloaded file's checksum is wrong")
            case .compileFailed(let reason):
                return String(localized: "The depth model can’t be prepared for this Mac: \(reason)",
                              table: "DepthMaps", comment: "Depth Map Generation install error; %@ is the system's reason")
            }
        }
    }

    let root: URL
    let pin: DepthMapModelPin
    let downloader: SteamCmdPackageDownloading
    let compile: @Sendable (URL) async throws -> URL

    func run(progress: @escaping @Sendable (Double?) -> Void,
             phase: @escaping @Sendable (DepthMapPluginInstaller.Phase) -> Void) async throws {
        let fileManager = FileManager.default
        try fileManager.createDirectory(at: root, withIntermediateDirectories: true)
        Self.removeStaleStaging(in: root)
        let staging = root.appending(path: "\(DepthMapPluginLayout.stagingPrefix)\(UUID().uuidString)", directoryHint: .isDirectory)
        try fileManager.createDirectory(at: staging, withIntermediateDirectories: false)
        defer { Self.remove(staging) }

        // Every file of the package, each checked against its own pin before it is kept.
        let package = staging.appending(path: pin.packageName, directoryHint: .isDirectory)
        let total = Double(max(pin.downloadSize, 1))
        var done: Int64 = 0
        var checksums: [String: String] = [:]
        for file in pin.files {
            let destination = package.appending(path: file.path)
            try fileManager.createDirectory(at: destination.deletingLastPathComponent(), withIntermediateDirectories: true)
            let partial = destination.appendingPathExtension("partial")
            let before = done
            try await downloader.download(pin.downloadURL(for: file), to: partial) { fraction in
                progress((Double(before) + Double(file.size) * (fraction ?? 0)) / total)
            }
            try Task.checkCancellation()
            do {
                try ChromiumEnginePackage.verify(partial, sha256: file.sha256)
            } catch {
                throw Failure.checksumMismatch(path: file.path)
            }
            try fileManager.moveItem(at: partial, to: destination)
            checksums[file.path] = file.sha256
            done += file.size
            progress(Double(done) / total)
        }
        phase(.compiling)
        let compiled: URL
        do {
            compiled = try await compile(package)
        } catch let error as CancellationError {
            throw error
        } catch {
            throw Failure.compileFailed(error.localizedDescription)
        }
        try Task.checkCancellation()
        let unpacked = staging.appending(path: "unpacked", directoryHint: .isDirectory)
        try fileManager.createDirectory(at: unpacked, withIntermediateDirectories: false)
        try fileManager.moveItem(at: compiled, to: unpacked.appending(path: DepthMapPluginLayout.compiledModelName, directoryHint: .isDirectory))
        try Data(pin.notice.utf8).write(to: unpacked.appending(path: DepthMapPluginLayout.noticeName))
        let manifest = DepthMapPluginLayout.Manifest(version: pin.version, repository: DepthMapModelPin.repository,
                                                     revision: pin.revision, files: checksums)
        try JSONEncoder().encode(manifest).write(to: unpacked.appending(path: DepthMapPluginLayout.manifestName), options: .atomic)
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
                    OWELog.error(.app, "Can't restore the depth model at \(target.path): \(restoreError)")
                }
            }
            throw error
        }
        var state = DepthMapPluginLayout.State.read(in: root)
        if state.active != pin.version {
            state.previous = state.active
            state.active = pin.version
        }
        try state.write(in: root)
        Self.prune(in: root, keeping: [state.active, state.previous].compactMap { $0 })
    }

    static func installedVersions(in root: URL) -> [String] {
        let names = (try? FileManager.default.contentsOfDirectory(atPath: root.path)) ?? []
        return names.filter { name in
            var isDirectory: ObjCBool = false
            return !name.hasPrefix(".")
                && FileManager.default.fileExists(atPath: root.appending(path: name).path, isDirectory: &isDirectory)
                && isDirectory.boolValue
        }.sorted()
    }

    static func prune(in root: URL, keeping: [String]) {
        for version in installedVersions(in: root) where !keeping.contains(version) {
            OWELog.info(.app, "Removing depth model \(version)")
            remove(root.appending(path: version, directoryHint: .isDirectory))
        }
    }

    static func removeStaleStaging(in root: URL) {
        let names = (try? FileManager.default.contentsOfDirectory(atPath: root.path)) ?? []
        for name in names where name.hasPrefix(DepthMapPluginLayout.stagingPrefix) {
            remove(root.appending(path: name, directoryHint: .isDirectory))
        }
    }

    private static func remove(_ url: URL) {
        guard FileManager.default.fileExists(atPath: url.path) else { return }
        do {
            try FileManager.default.removeItem(at: url)
        } catch {
            OWELog.error(.app, "Can't remove \(url.path): \(error)")
        }
    }
}

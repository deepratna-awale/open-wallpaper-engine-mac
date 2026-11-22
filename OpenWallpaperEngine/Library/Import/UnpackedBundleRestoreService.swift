import Combine
import Foundation

/// When the wallpapers an earlier version unpacked get their package back (`UnpackedBundleRestorer`):
/// a while after launch, and again when a Steam login it lacked becomes available. The user can keep
/// the loose copies instead of downloading the packages (`keepsLooseCopiesKey`).
@MainActor
final class UnpackedBundleRestoreService {
    typealias Found = (bundle: UnpackedBundle, packageOnDisk: URL?)

    /// What a login is needed for.
    struct Waiting: Equatable, Sendable {
        let count: Int
        /// About what the downloads come to: a package holds the same files unpacked.
        let bytes: Int64
    }

    /// Whether wallpapers unpacked earlier keep playing from their loose files instead of being
    /// downloaded again.
    nonisolated static let keepsLooseCopiesKey = "KeepsUnpackedWallpapers"

    private let restorer: UnpackedBundleRestorer
    private let defaults: UserDefaults
    private let launchDelay: TimeInterval
    private let scan: @Sendable () -> [Found]
    /// What the scan at launch found, until its run.
    private var launchBundles: [Found]?
    private var loginCancellable: AnyCancellable?

    init(downloader: UnpackedBundleDownloading, loginSucceeded: AnyPublisher<Void, Never>,
         defaults: UserDefaults = .app, launchDelay: TimeInterval = 30,
         isShown: @escaping (URL) -> Bool,
         finish: @escaping @Sendable (UnpackedBundle, URL) -> Void = UnpackedBundleRestorer.finishInBackground,
         scan: @escaping @Sendable () -> [Found] = { UnpackedBundle.scanWithPackages(storage: FileManager.default.wallpapersDirectory) }) {
        self.defaults = defaults
        self.launchDelay = launchDelay
        self.scan = scan
        restorer = UnpackedBundleRestorer(
            downloader: downloader, isShown: isShown,
            mayDownload: { !defaults.bool(forKey: Self.keepsLooseCopiesKey) }, finish: finish)
        // The run at launch finds the login restored then by itself.
        loginCancellable = loginSucceeded
            .receive(on: DispatchQueue.main)
            .sink { [weak self] in MainActor.assumeIsolated { self?.resume() } }
    }

    private var keepsLooseCopies: Bool { defaults.bool(forKey: Self.keepsLooseCopiesKey) }

    /// At launch: looks for unpacked wallpapers and restores them after the delay, so the Steam
    /// login restored at launch has had its turn.
    func start() {
        let scan = scan
        DispatchQueue.global(qos: .utility).async { [weak self] in
            let found = scan()
            guard !found.isEmpty else { return }
            OWELog.info(.importer, "Unpacked wallpapers: \(found.count) to give their package back")
            DispatchQueue.main.async { [weak self] in
                guard let self else { return }
                self.launchBundles = found
                DispatchQueue.main.asyncAfter(deadline: .now() + self.launchDelay) { [weak self] in
                    self?.runAtLaunch()
                }
            }
        }
    }

    /// The user logged in, or no longer keeps the loose copies: what waits starts at once.
    func startDownloads() {
        if launchBundles != nil { runAtLaunch() } else { resume() }
    }

    func shownWallpapersChanged() {
        restorer.shownWallpapersChanged()
    }

    /// What waits for a Steam login, once the login saved has been tried: nil with a login that
    /// works (or that only lacks the network), with nothing to download, or with the loose copies kept.
    func waitingForLogin(account: SteamAccount) async -> Waiting? {
        guard !keepsLooseCopies else { return nil }
        await account.waitUntilRestored()
        guard account.status == .signedOut else { return nil }
        let scan = scan
        let waiting = await Task.detached(priority: .utility) {
            let downloads = scan().filter { $0.packageOnDisk == nil && $0.bundle.workshopId != nil }.map(\.bundle)
            return Waiting(count: downloads.count, bytes: downloads.reduce(0) { $0 + $1.looseSize() })
        }.value
        return waiting.count > 0 && account.status == .signedOut ? waiting : nil
    }

    private func runAtLaunch() {
        guard let bundles = launchBundles else { return }
        launchBundles = nil
        restorer.run(bundles)
    }

    private func resume() {
        restorer.resumeDownloads(scan: scan)
    }
}

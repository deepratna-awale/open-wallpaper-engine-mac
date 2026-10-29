import Combine
import Foundation

/// Keeps installed Workshop wallpapers up to date, as Steam does for Wallpaper Engine's
/// subscriptions. With the Steam login, when it comes in and every `interval` after, asks Steam when
/// each installed item last changed (GetPublishedFileDetails) and downloads the newer ones over the installed copies (`WorkshopDownloadService.updateWorkshopItem`).
@MainActor
final class WorkshopUpdateChecker {
    typealias Fetch = ([String]) async throws -> [WorkshopItem]

    private let downloads: WorkshopDownloadService
    private let index: DownloadedWallpaperIndex
    private let fetch: Fetch
    private let interval: Duration
    private var loop: Task<Void, Never>?
    private var loginCancellable: AnyCancellable?

    init(downloads: WorkshopDownloadService,
         index: DownloadedWallpaperIndex = .shared,
         fetch: @escaping Fetch = { try await WorkshopAPIService().getItemDetails(inBatches: $0) },
         interval: Duration = .seconds(6 * 60 * 60)) {
        self.downloads = downloads
        self.index = index
        self.fetch = fetch
        self.interval = interval
    }

    /// Checks whenever a Steam login comes in, then every `interval` while there is one.
    func start() {
        loginCancellable = downloads.$isLoggedIn
            .removeDuplicates()
            .sink { [weak self] isLoggedIn in
                MainActor.assumeIsolated { self?.loginChanged(isLoggedIn) }
            }
    }

    private func loginChanged(_ isLoggedIn: Bool) {
        loop?.cancel()
        loop = nil
        guard isLoggedIn else { return }
        let interval = interval
        loop = Task { [weak self] in
            while !Task.isCancelled {
                await self?.checkNow()
                do {
                    try await Task.sleep(for: interval)
                } catch {
                    return
                }
            }
        }
    }

    /// The items Steam changed after their installed files were downloaded.
    nonisolated static func outdated(_ items: [WorkshopItem], downloadedAt: (String) -> Date?) -> [WorkshopItem] {
        items.filter { item in
            guard let updated = item.timeUpdated, let downloaded = downloadedAt(item.id) else { return false }
            return Date(timeIntervalSince1970: TimeInterval(updated)) > downloaded
        }
    }

    /// Asks Steam about every installed item and updates the outdated ones. A failed request ends
    /// the check; the next one asks again.
    func checkNow() async {
        let ids = index.ids.sorted()
        guard !ids.isEmpty else { return }
        let outdated: [WorkshopItem]
        do {
            outdated = Self.outdated(try await fetch(ids), downloadedAt: index.contentDate(for:))
        } catch {
            OWELog.error(.workshop, "Can't check \(ids.count) installed Workshop items for updates: \(error)")
            return
        }
        for item in outdated {
            OWELog.info(.workshop, "Workshop item \(item.id) changed on Steam since it was downloaded; updating it")
            downloads.updateWorkshopItem(workshopId: item.id, title: item.title,
                                         previewURL: item.previewURL.flatMap(URL.init(string:)))
        }
    }
}

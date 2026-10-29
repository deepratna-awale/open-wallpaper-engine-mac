import Foundation

/// Wallpaper Engine downloads an item as soon as the account subscribes to it anywhere: in the
/// Steam app, on the website or on the phone. So does the app, from Steam's notice to the Steam
/// login (`SteamHelperClient.setWorkshopSubscribeHandler`). An unsubscribe elsewhere leaves the
/// installed item, which the user deletes here.
@MainActor
final class SteamSubscriptionDownloads {
    typealias Details = (_ workshopId: String) async throws -> WorkshopItem?
    typealias Download = (_ workshopId: String, _ item: WorkshopItem?) -> Void

    private let isInstalled: (String) -> Bool
    private let details: Details
    private let download: Download

    init(isInstalled: @escaping (String) -> Bool, details: @escaping Details, download: @escaping Download) {
        self.isInstalled = isInstalled
        self.details = details
        self.download = download
    }

    /// The app's own: into the library through `downloads`, with the item's title and preview for
    /// the Downloads tab.
    convenience init(downloads: WorkshopDownloadService, steam: SteamHelperClient) {
        let api = WorkshopAPIService(steam: steam)
        self.init(isInstalled: { [weak downloads] id in
                      DownloadedWallpaperIndex.shared.contains(id) && downloads?.dependencyIndex.contains(id) != true
                  },
                  details: { try await api.getItemDetails(workshopIds: [$0]).first },
                  download: { [weak downloads] id, item in
                      downloads?.downloadWorkshopItem(workshopId: id, title: item?.title, previewURL: item?.previewImageURL,
                                                      creatorId: item?.creatorId, subscriptions: item?.subscriptions ?? 0,
                                                      fileSize: item?.fileSize ?? 0)
                  })
    }

    /// The account subscribed to `workshopId`: it is downloaded unless the library has it.
    func subscribed(_ workshopId: String) async {
        guard !isInstalled(workshopId) else { return }
        var item: WorkshopItem?
        do {
            item = try await details(workshopId)
        } catch {
            OWELog.error(.workshop, "No details for Workshop item \(workshopId), downloading it without: \(error)")
        }
        guard !isInstalled(workshopId) else { return }
        OWELog.info(.workshop, "Downloading Workshop item \(workshopId), which the Steam account subscribed to")
        download(workshopId, item)
    }
}

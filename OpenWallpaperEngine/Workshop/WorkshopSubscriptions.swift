import Foundation

/// The user's Workshop lists, from `IPublishedFileService/GetUserFiles/v1`: subscriptions with
/// `type=mysubscriptions` (`subscribed` always answers `{"response":{}}`), and favourites with
/// `type=myfavorites`, the list Wallpaper Engine's heart writes (`setFavorited` in its UI, Steam's
/// favourited-items query in `wallpaperui.exe`). It needs the Steam login and the account's SteamID64;
/// an empty answer is treated as "Steam didn't return the list".
enum WorkshopSubscriptions {
    /// Which of the account's lists GetUserFiles returns.
    enum List: String {
        case subscriptions = "mysubscriptions"
        case favorites = "myfavorites"

        /// The list's `list_type` in PublishedFile.Subscribe and Unsubscribe (Steam's
        /// `k_EUCMListSubscribed` and `k_EUCMListFavorites`).
        var listType: Int {
            switch self {
            case .subscriptions: 1
            case .favorites: 2
            }
        }
    }

    /// The probe's answer, kept so an account Steam returns nothing for doesn't show the option again.
    static let probeResultKey = "WorkshopSubscriptionsProbe.mysubscriptions"

    enum Outcome: Equatable {
        case items([String])
        /// Steam answered without any subscriptions.
        case empty
    }

    enum ProbeResult: String {
        case items
        case empty
    }

    /// The query of one GetUserFiles page.
    static func queryItems(steamID: String, page: Int, perPage: Int = 100,
                           list: List = .subscriptions) -> [URLQueryItem] {
        [
            URLQueryItem(name: "steamid", value: steamID),
            URLQueryItem(name: "appid", value: String(WorkshopAPIService.wallpaperEngineAppId)),
            URLQueryItem(name: "type", value: list.rawValue),
            URLQueryItem(name: "page", value: String(page)),
            URLQueryItem(name: "numperpage", value: String(perPage)),
            URLQueryItem(name: "return_short_description", value: "false"),
        ]
    }

    /// The parameters of PublishedFile.Subscribe (`adding`) or Unsubscribe for `workshopId` on
    /// `list`. Steam isn't asked to tell the account's Steam clients, nor to add required items:
    /// the app downloads those itself.
    static func changeItems(workshopId: String, list: List, adding: Bool) -> [URLQueryItem] {
        var items = [
            URLQueryItem(name: "publishedfileid", value: workshopId),
            URLQueryItem(name: "list_type", value: String(list.listType)),
            URLQueryItem(name: "appid", value: String(WorkshopAPIService.wallpaperEngineAppId)),
            URLQueryItem(name: "notify_client", value: "false"),
        ]
        if adding { items.append(URLQueryItem(name: "include_dependencies", value: "false")) }
        return items
    }

    /// The subscribed ids in a GetUserFiles response; `.empty` for `{"response":{}}` or no files.
    static func outcome(from data: Data) throws -> Outcome {
        guard let json = try JSONSerialization.jsonObject(with: data) as? [String: Any],
              let response = json["response"] as? [String: Any] else { return .empty }
        let files = response["publishedfiledetails"] as? [[String: Any]] ?? []
        let ids = files.compactMap { file -> String? in
            if let id = file["publishedfileid"] as? String { return id }
            return (file["publishedfileid"] as? NSNumber)?.stringValue
        }.filter(WorkshopCollection.isID)
        return ids.isEmpty ? .empty : .items(ids)
    }

    /// A SteamID64 of an individual account: 17 digits from 7656119….
    static func isSteamID64(_ text: String) -> Bool {
        text.count == 17 && text.hasPrefix("7656119") && text.allSatisfy { $0.isASCII && $0.isNumber }
    }
}

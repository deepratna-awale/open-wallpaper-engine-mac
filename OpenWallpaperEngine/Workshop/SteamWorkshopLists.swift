import Combine
import Foundation

/// The account's rating of a Workshop item.
enum WorkshopVote: Equatable, Sendable {
    case up
    case down

    /// The ratings in a PublishedFile.GetUserVoteSummary `{"response": {"summaries": […]}}`; an
    /// item rated neither way is left out.
    static func votes(from data: Data) throws -> [String: WorkshopVote] {
        guard let json = try JSONSerialization.jsonObject(with: data) as? [String: Any],
              let response = json["response"] as? [String: Any] else { return [:] }
        var votes: [String: WorkshopVote] = [:]
        for summary in response["summaries"] as? [[String: Any]] ?? [] {
            guard let id = (summary["publishedfileid"] as? String) ?? (summary["publishedfileid"] as? NSNumber)?.stringValue
            else { continue }
            if summary["vote_for"] as? Bool == true {
                votes[id] = .up
            } else if summary["vote_against"] as? Bool == true {
                votes[id] = .down
            }
        }
        return votes
    }
}

/// Wallpaper Engine's Workshop actions change the Steam account, and so do the app's: a download
/// subscribes to the item, Unsubscribe unsubscribes, the heart adds it to or removes it from the
/// account's favourites, and Rate Up / Rate Down vote. Each goes through the Steam login when there
/// is one. Without it, or when Steam refuses, the action still happens in the app and the failure
/// is logged.
@MainActor
final class SteamWorkshopLists: ObservableObject {
    typealias ChangeList = (_ workshopId: String, _ list: WorkshopSubscriptions.List, _ isOn: Bool) async throws -> Void
    typealias Vote = (_ vote: WorkshopVote, _ workshopId: String) async throws -> Void
    typealias LoadVotes = (_ workshopIds: [String]) async throws -> [String: WorkshopVote]

    /// The account's rating of each item asked about (`loadVotes`) or rated here.
    @Published private(set) var votes: [String: WorkshopVote] = [:]

    private let isLoggedIn: () -> Bool
    private let changeList: ChangeList
    private let sendVote: Vote
    private let fetchVotes: LoadVotes
    private var cancellables: Set<AnyCancellable> = []

    init(isLoggedIn: @escaping () -> Bool, changeList: @escaping ChangeList, vote: @escaping Vote,
         loadVotes: @escaping LoadVotes) {
        self.isLoggedIn = isLoggedIn
        self.changeList = changeList
        sendVote = vote
        fetchVotes = loadVotes
    }

    /// The app's own: through `steam`, while `downloads` has the Steam login.
    convenience init(downloads: WorkshopDownloadService, steam: SteamHelperClient) {
        let api = WorkshopAPIService(steam: steam)
        self.init(isLoggedIn: { [weak downloads] in downloads?.isLoggedIn == true },
                  changeList: { try await api.setItem($0, on: $1, $2) },
                  vote: { try await api.vote($0, on: $1) },
                  loadVotes: { try await api.votes(on: $0) })
    }

    var canChangeAccount: Bool { isLoggedIn() }

    /// Follows the app's actions: a download of the user's own (not a required item) subscribes,
    /// and a heart on a Workshop item favourites it.
    func follow(downloads userDownloads: PassthroughSubject<String, Never>, favorites: FavoritesStore) {
        userDownloads
            .sink { [weak self] id in
                MainActor.assumeIsolated { self?.change(id, on: .subscriptions, true) }
            }
            .store(in: &cancellables)
        favorites.toggled
            .sink { [weak self] change in
                guard let id = WallpaperEngineFavorites.workshopID(forKey: change.key) else { return }
                MainActor.assumeIsolated { self?.change(id, on: .favorites, change.isFavorite) }
            }
            .store(in: &cancellables)
    }

    /// Unsubscribes from the Workshop items the user deleted from the library.
    func unsubscribe(from workshopIds: [String]) {
        for id in workshopIds { change(id, on: .subscriptions, false) }
    }

    /// Adds `workshopId` to `list`, or takes it off; nothing without the Steam login.
    func setItem(_ workshopId: String, on list: WorkshopSubscriptions.List, _ isOn: Bool) async throws {
        guard isLoggedIn() else { return }
        try await changeList(workshopId, list, isOn)
        OWELog.info(.workshop, "\(isOn ? "Added" : "Removed") Workshop item \(workshopId) \(isOn ? "to" : "from") the Steam account's \(list.rawValue)")
    }

    /// Rates `workshopId`; the rating shows once Steam took it.
    func vote(_ vote: WorkshopVote, on workshopId: String) async throws {
        guard isLoggedIn() else { return }
        try await sendVote(vote, workshopId)
        votes[workshopId] = vote
    }

    /// Rates `workshopId` in the background (a menu command).
    func rate(_ vote: WorkshopVote, on workshopId: String) {
        Task {
            do {
                try await self.vote(vote, on: workshopId)
            } catch {
                OWELog.error(.workshop, "Steam didn't take the rating of Workshop item \(workshopId): \(error)")
            }
        }
    }

    /// Asks Steam how the account rated the `workshopIds` not asked about yet (one request).
    func loadVotes(for workshopIds: [String]) async {
        let ids = workshopIds.filter { votes[$0] == nil }
        guard isLoggedIn(), !ids.isEmpty else { return }
        do {
            for (id, vote) in try await fetchVotes(ids) { votes[id] = vote }
        } catch {
            OWELog.error(.workshop, "Can't read the Steam account's ratings of \(ids.count) Workshop items: \(error)")
        }
    }

    /// `setItem` in the background.
    private func change(_ workshopId: String, on list: WorkshopSubscriptions.List, _ isOn: Bool) {
        Task {
            do {
                try await setItem(workshopId, on: list, isOn)
            } catch {
                OWELog.error(.workshop, "Steam didn't change Workshop item \(workshopId) on the account's \(list.rawValue): \(error)")
            }
        }
    }
}

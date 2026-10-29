import Foundation

/// Imports Wallpaper Engine's favourites (the Steam account's favourited Workshop items, see
/// `WallpaperEngineFavorites`) into My Favourites, after asking. It needs the Steam login; without
/// it there is no source and nothing is offered.
/// Steam is asked first, and the question is only put when it returned favourites that aren't
/// favourites here yet, so an account with none, or one already imported, is never asked.
@MainActor
final class WallpaperEngineFavoritesImportModel: ObservableObject {
    enum Phase: Equatable {
        case idle
        case checking
        /// Waiting for the user's answer to import `count` new favourites.
        case asking(count: Int)
        case imported(count: Int)
        /// Steam returned favourites, and every one is a favourite here already.
        case upToDate
        /// Steam returned no favourites (none, or a private list).
        case noFavorites
        case failed(String)
    }

    @Published private(set) var phase: Phase = .idle
    /// Bound to the question's alert.
    @Published var isAsking = false
    /// The SteamID64 to read, from the last `refreshSource()`.
    @Published private(set) var steamID: String?

    private var pending: [String] = []
    private let store: FavoritesStore
    private let fetch: (String) async throws -> WorkshopSubscriptions.Outcome
    private let loginSteamID: () -> String?

    init(store: FavoritesStore, fetch: @escaping (String) async throws -> WorkshopSubscriptions.Outcome,
         loginSteamID: @escaping () -> String?) {
        self.store = store
        self.fetch = fetch
        self.loginSteamID = loginSteamID
        refreshSource()
    }

    /// The app's own wiring: its favourites and Steam login.
    convenience init(steamCmd: SteamCmdService, steam: SteamHelperClient) {
        let api = WorkshopAPIService(steam: steam)
        self.init(store: .shared,
                  fetch: { try await api.getFavoritedItemIDs(steamID: $0) },
                  loginSteamID: { [weak steamCmd] in steamCmd?.steamLogin?.steamID })
    }

    /// Whether favourites can be read: the user is logged in to Steam.
    var isSourceAvailable: Bool { steamID != nil }

    var isChecking: Bool { phase == .checking }

    /// Looks again for the account, after a login or a logout.
    func refreshSource() {
        steamID = loginSteamID()
    }

    /// Asks Steam for the favourites; puts the question only when some are new here.
    func check() async {
        refreshSource()
        guard let steamID, phase != .checking, !isAsking else { return }
        phase = .checking
        do {
            switch try await fetch(steamID) {
            case .empty:
                phase = .noFavorites
            case .items(let ids):
                let keys = WallpaperEngineFavorites.keys(forWorkshopIDs: ids)
                pending = keys.filter { !store.contains($0) }
                if keys.isEmpty {
                    phase = .noFavorites
                } else if pending.isEmpty {
                    phase = .upToDate
                } else {
                    phase = .asking(count: pending.count)
                    isAsking = true
                }
            }
        } catch {
            OWELog.error(.workshop, "Wallpaper Engine favourites didn't load: \(error.localizedDescription)")
            phase = .failed(error.localizedDescription)
        }
    }

    /// The user said yes: merges the new favourites, keeping the ones already there.
    func importPending() {
        let added = store.merge(pending)
        OWELog.info(.library, "Imported \(added) Wallpaper Engine favourites")
        pending = []
        isAsking = false
        phase = .imported(count: added)
    }

    /// The user said no; nothing changes, and checking again asks again.
    func decline() {
        pending = []
        isAsking = false
        phase = .idle
    }
}

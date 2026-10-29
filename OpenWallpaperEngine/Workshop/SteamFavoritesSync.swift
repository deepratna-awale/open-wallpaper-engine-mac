import AppKit
import Foundation

/// Wallpaper Engine's favourites are the Steam account's (`WallpaperEngineFavorites`), and Steam
/// doesn't tell a client when they change elsewhere (the website, the phone). So the app reads the
/// account's list with the Steam login, when the login comes, when the app comes forward and every
/// 30 minutes, and applies what changed since the last read: a new favourite gets the heart, one
/// taken off loses it. The first read for an account only remembers the list, so hearts from
/// before the login stay as they are (the favourites import brings the account's in). An empty
/// answer, which a private list gives too, changes nothing.
@MainActor
final class SteamFavoritesSync {
    typealias Fetch = (_ steamID: String) async throws -> WorkshopSubscriptions.Outcome

    nonisolated static let interval: Duration = .seconds(30 * 60)
    /// Coming forward reads again only this long after the last read.
    nonisolated static let activationGap: TimeInterval = 2 * 60

    private let store: FavoritesStore
    private let defaults: UserDefaults
    private let fetch: Fetch
    private let loginSteamID: () -> String?
    private let now: () -> Date
    private var isReading = false
    private var lastRead: Date?
    private var timer: Task<Void, Never>?
    private var activation: NSObjectProtocol?

    init(store: FavoritesStore, defaults: UserDefaults = .app, fetch: @escaping Fetch,
         loginSteamID: @escaping () -> String?, now: @escaping () -> Date = Date.init) {
        self.store = store
        self.defaults = defaults
        self.fetch = fetch
        self.loginSteamID = loginSteamID
        self.now = now
    }

    /// The app's own: its favourites, through `steam` with the login `account` has.
    convenience init(account: SteamAccount) {
        let api = WorkshopAPIService(steam: account.client)
        self.init(store: .shared, fetch: { try await api.getFavoritedItemIDs(steamID: $0) },
                  loginSteamID: { [weak account] in account?.login?.steamID })
    }

    /// Reads every 30 minutes and when the app comes forward.
    func start() {
        timer = Task { [weak self] in
            while !Task.isCancelled {
                try? await Task.sleep(for: Self.interval)
                await self?.read()
            }
        }
        activation = NotificationCenter.default.addObserver(forName: NSApplication.didBecomeActiveNotification,
                                                            object: nil, queue: .main) { [weak self] _ in
            MainActor.assumeIsolated {
                guard let self, self.lastRead.map({ self.now().timeIntervalSince($0) >= Self.activationGap }) ?? true else { return }
                Task { await self.read() }
            }
        }
    }

    /// Reads the account's favourites and applies what changed since the last read.
    func read() async {
        guard let steamID = loginSteamID(), !isReading else { return }
        isReading = true
        defer { isReading = false }
        lastRead = now()
        let outcome: WorkshopSubscriptions.Outcome
        do {
            outcome = try await fetch(steamID)
        } catch {
            OWELog.error(.workshop, "Can't read the Steam account's favourites: \(error)")
            return
        }
        guard case .items(let ids) = outcome, loginSteamID() == steamID else { return }
        let key = "SteamFavorites.\(steamID)"
        let current = Set(ids.filter(WorkshopCollection.isID))
        defer { defaults.set(current.sorted(), forKey: key) }
        guard let previous = defaults.stringArray(forKey: key).map(Set.init) else { return }
        let added = store.merge(WallpaperEngineFavorites.keys(forWorkshopIDs: current.subtracting(previous).sorted()))
        let removed = store.remove(WallpaperEngineFavorites.keys(forWorkshopIDs: previous.subtracting(current).sorted()))
        if added + removed > 0 {
            OWELog.info(.library, "Steam favourites changed elsewhere: \(added) added, \(removed) removed")
        }
    }
}

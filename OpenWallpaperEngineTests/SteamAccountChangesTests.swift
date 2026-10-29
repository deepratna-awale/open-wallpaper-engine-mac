import XCTest
@testable import OpenWallpaperEngine

/// What the Steam account changes elsewhere (the Steam app, the website, the phone) reaching the
/// app: subscriptions download, favourites move the hearts.
@MainActor
final class SteamAccountChangesTests: XCTestCase {
    private var defaultsSuite: String!
    private var defaults: UserDefaults!
    private var favorites: FavoritesStore!
    private var steamFavorites: WorkshopSubscriptions.Outcome = .empty
    private var steamID: String? = "76561190000000001"
    private var reads = 0

    override func setUp() async throws {
        try await super.setUp()
        defaultsSuite = "owe-tests-\(UUID().uuidString)"
        defaults = try XCTUnwrap(UserDefaults(suiteName: defaultsSuite))
        favorites = FavoritesStore(defaults: defaults)
    }

    override func tearDown() async throws {
        UserDefaults().removePersistentDomain(forName: defaultsSuite)
        try await super.tearDown()
    }

    private func makeSync() -> SteamFavoritesSync {
        SteamFavoritesSync(store: favorites, defaults: defaults,
                           fetch: { [unowned self] _ in
                               reads += 1
                               return steamFavorites
                           },
                           loginSteamID: { [unowned self] in steamID })
    }

    // MARK: Favourites

    func testTheFirstReadOnlyRemembersTheAccountsFavourites() async {
        favorites.merge(["workshop-1000000009", "/Wallpapers/mine"])
        steamFavorites = .items(["1000000001", "1000000002"])

        await makeSync().read()

        XCTAssertEqual(favorites.ids, ["workshop-1000000009", "/Wallpapers/mine"])
    }

    func testLaterReadsApplyWhatChangedElsewhere() async {
        let sync = makeSync()
        favorites.merge(["workshop-1000000001", "workshop-1000000009"])
        steamFavorites = .items(["1000000001", "1000000002"])
        await sync.read()

        steamFavorites = .items(["1000000002", "1000000003"])
        await sync.read()

        XCTAssertEqual(favorites.ids, ["workshop-1000000003", "workshop-1000000009"],
                       "1000000003 was favourited elsewhere, 1000000001 unfavourited; 1000000009 was never on Steam")
    }

    func testAnEmptyAnswerChangesNothing() async {
        let sync = makeSync()
        favorites.merge(["workshop-1000000001"])
        steamFavorites = .items(["1000000001"])
        await sync.read()

        steamFavorites = .empty
        await sync.read()
        XCTAssertEqual(favorites.ids, ["workshop-1000000001"])

        steamFavorites = .items(["1000000001", "1000000002"])
        await sync.read()
        XCTAssertEqual(favorites.ids, ["workshop-1000000001", "workshop-1000000002"])
    }

    func testEachAccountHasItsOwnLastRead() async {
        let sync = makeSync()
        steamFavorites = .items(["1000000001"])
        await sync.read()

        steamID = "76561190000000002"
        steamFavorites = .items(["1000000002"])
        await sync.read()

        XCTAssertTrue(favorites.ids.isEmpty, "a first read for the other account changes nothing")
    }

    func testNoReadWithoutTheLogin() async {
        steamID = nil
        await makeSync().read()
        XCTAssertEqual(reads, 0)
    }

    // MARK: Subscriptions

    func testASubscriptionDownloadsWithItsDetails() async {
        var downloads: [(String, String?)] = []
        let subscriptions = SteamSubscriptionDownloads(
            isInstalled: { $0 == "1000000001" },
            details: { id in
                WorkshopItem(id: id, title: "Deadlock", previewURL: nil, tags: [], subscriptions: 0, fileSize: 0,
                             creatorAppId: 431960, creatorId: nil, description: nil, votesUp: 0, votesDown: 0)
            },
            download: { id, item in downloads.append((id, item?.title)) })

        await subscriptions.subscribed("1000000001")
        await subscriptions.subscribed("3826203207")

        XCTAssertEqual(downloads.map(\.0), ["3826203207"], "an installed item isn't downloaded again")
        XCTAssertEqual(downloads.first?.1, "Deadlock")
    }

    func testASubscriptionDownloadsWithoutDetailsSteamDidntGive() async {
        struct Failure: Error {}
        var downloads: [String] = []
        let subscriptions = SteamSubscriptionDownloads(isInstalled: { _ in false }, details: { _ in throw Failure() },
                                                       download: { id, _ in downloads.append(id) })

        await subscriptions.subscribed("3826203207")

        XCTAssertEqual(downloads, ["3826203207"])
    }
}

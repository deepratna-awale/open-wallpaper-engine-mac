import XCTest
@testable import OpenWallpaperEngine

/// Wallpaper Engine's favourites (the Steam account's favourited Workshop items) read with
/// GetUserFiles, mapped to `workshop-<id>` and merged into a favourites store on fixture defaults.
@MainActor
final class WallpaperEngineFavoritesImportTests: XCTestCase {
    private var suiteName: String!
    private var defaults: UserDefaults!

    override func setUp() async throws {
        suiteName = "app.openwallpaperengine.isolated.tests.we-favorites-\(UUID().uuidString)"
        defaults = try XCTUnwrap(UserDefaults(suiteName: suiteName))
    }

    override func tearDown() async throws {
        defaults.removePersistentDomain(forName: suiteName)
    }

    private func favoritesFixture() throws -> Data {
        try Data(contentsOf: Fixtures.url("Workshop/api/user-files-favorites.json"))
    }

    // MARK: Reading and mapping

    func testTheQueryAsksForFavouritesWithoutTheKey() {
        let query = WorkshopSubscriptions.queryItems(steamID: "76561190000000001", page: 1, list: .favorites)
        let values = Dictionary(uniqueKeysWithValues: query.map { ($0.name, $0.value ?? "") })
        XCTAssertEqual(values["type"], "myfavorites")
        XCTAssertEqual(values["appid"], "431960")
        XCTAssertEqual(values["steamid"], "76561190000000001")
        XCTAssertNil(values["key"])
    }

    func testFavouritesMapToWorkshopKeysOnce() throws {
        guard case .items(let ids) = try WorkshopSubscriptions.outcome(from: try favoritesFixture()) else {
            return XCTFail("the fixture lists favourites")
        }
        XCTAssertEqual(WallpaperEngineFavorites.keys(forWorkshopIDs: ids), ["workshop-3000000021", "workshop-3000000022"])
        XCTAssertEqual(WallpaperEngineFavorites.keys(forWorkshopIDs: ["12", "", "abc", "12"]), ["workshop-12"])
    }

    // MARK: Merging

    func testMergingKeepsExistingFavouritesAndIsIdempotent() {
        defaults.set(["workshop-1", "/Users/me/Wallpapers/local"], forKey: "FavoriteWallpaperIds")
        let store = FavoritesStore(defaults: defaults)
        XCTAssertEqual(store.merge(["workshop-1", "workshop-2", "workshop-3"]), 2)
        XCTAssertEqual(store.ids, ["workshop-1", "workshop-2", "workshop-3", "/Users/me/Wallpapers/local"])
        XCTAssertEqual(store.merge(["workshop-2", "workshop-3"]), 0)
        XCTAssertEqual(Set(defaults.stringArray(forKey: "FavoriteWallpaperIds") ?? []), store.ids)
        XCTAssertEqual(FavoritesStore(defaults: defaults).ids, store.ids, "the merge is saved")
    }

    // MARK: Asking

    private func model(store: FavoritesStore, steamID: String? = "76561190000000001",
                       answer: @escaping () throws -> WorkshopSubscriptions.Outcome) -> WallpaperEngineFavoritesImportModel {
        WallpaperEngineFavoritesImportModel(store: store, fetch: { _ in try answer() }, loginSteamID: { steamID })
    }

    func testNoSourceWithoutTheSteamLogin() async {
        var asked = false
        let import_ = model(store: FavoritesStore(defaults: defaults), steamID: nil) { asked = true; return .items(["5"]) }
        XCTAssertFalse(import_.isSourceAvailable)
        await import_.check()
        XCTAssertEqual(import_.phase, .idle)
        XCTAssertFalse(import_.isAsking)
        XCTAssertFalse(asked, "Steam isn't asked without a source")
    }

    func testNoQuestionWhenSteamHasNoFavourites() async {
        let import_ = model(store: FavoritesStore(defaults: defaults)) { .empty }
        XCTAssertTrue(import_.isSourceAvailable)
        await import_.check()
        XCTAssertEqual(import_.phase, .noFavorites)
        XCTAssertFalse(import_.isAsking)
    }

    func testAsksForTheNewFavouritesThenMergesThemOnce() async throws {
        defaults.set(["workshop-3000000021", "workshop-9"], forKey: "FavoriteWallpaperIds")
        let store = FavoritesStore(defaults: defaults)
        let data = try favoritesFixture()
        let import_ = model(store: store) { try WorkshopSubscriptions.outcome(from: data) }

        await import_.check()
        XCTAssertEqual(import_.phase, .asking(count: 1))
        XCTAssertTrue(import_.isAsking)
        import_.importPending()
        XCTAssertEqual(import_.phase, .imported(count: 1))
        XCTAssertFalse(import_.isAsking)
        XCTAssertEqual(store.ids, ["workshop-3000000021", "workshop-3000000022", "workshop-9"])

        await import_.check()
        XCTAssertEqual(import_.phase, .upToDate, "importing again finds nothing new and doesn't ask")
        XCTAssertFalse(import_.isAsking)
        XCTAssertEqual(store.ids.count, 3)
    }

    func testDecliningChangesNothing() async throws {
        let store = FavoritesStore(defaults: defaults)
        let data = try favoritesFixture()
        let import_ = model(store: store) { try WorkshopSubscriptions.outcome(from: data) }
        await import_.check()
        XCTAssertEqual(import_.phase, .asking(count: 2))
        import_.decline()
        XCTAssertEqual(import_.phase, .idle)
        XCTAssertTrue(store.ids.isEmpty)
        XCTAssertNil(defaults.stringArray(forKey: "FavoriteWallpaperIds"))
    }

    func testAFailedRequestDoesNotAsk() async {
        let import_ = model(store: FavoritesStore(defaults: defaults)) { throw WorkshopAPIError.requestFailed }
        await import_.check()
        guard case .failed = import_.phase else { return XCTFail("expected a failure, got \(import_.phase)") }
        XCTAssertFalse(import_.isAsking)
    }
}

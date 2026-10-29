import Combine
import XCTest
@testable import OpenWallpaperEngine

/// The app's Workshop actions change the Steam account as Wallpaper Engine's do.
@MainActor
final class SteamWorkshopListsTests: XCTestCase {
    private struct Change: Equatable {
        let id: String
        let list: WorkshopSubscriptions.List
        let isOn: Bool
    }

    private var changes: [Change] = []
    private var votesSent: [String: WorkshopVote] = [:]
    private var voteRequests: [[String]] = []
    private var isLoggedIn = true
    private var defaultsSuite: String!
    private var favorites: FavoritesStore!
    private var lists: SteamWorkshopLists!

    override func setUp() async throws {
        try await super.setUp()
        defaultsSuite = "owe-tests-\(UUID().uuidString)"
        favorites = FavoritesStore(defaults: UserDefaults(suiteName: defaultsSuite)!)
        lists = SteamWorkshopLists(
            isLoggedIn: { [unowned self] in isLoggedIn },
            changeList: { [unowned self] id, list, isOn in changes.append(Change(id: id, list: list, isOn: isOn)) },
            vote: { [unowned self] vote, id in votesSent[id] = vote },
            loadVotes: { [unowned self] ids in
                voteRequests.append(ids)
                return ids.contains("1000000002") ? ["1000000002": .down] : [:]
            })
    }

    override func tearDown() async throws {
        UserDefaults().removePersistentDomain(forName: defaultsSuite)
        try await super.tearDown()
    }

    func testADownloadSubscribes() async throws {
        let downloads = PassthroughSubject<String, Never>()
        lists.follow(downloads: downloads, favorites: favorites)

        downloads.send("1000000001")

        try await sleepUntil("the subscription is sent") { @Sendable @MainActor in !changes.isEmpty }
        XCTAssertEqual(changes, [Change(id: "1000000001", list: .subscriptions, isOn: true)])
    }

    func testTheHeartOnAWorkshopItemFavouritesItOnSteam() async throws {
        lists.follow(downloads: PassthroughSubject(), favorites: favorites)

        favorites.toggle("workshop-1000000001")
        favorites.toggle("/Users/me/Wallpapers/local")
        favorites.merge(["workshop-1000000003"])
        favorites.toggle("workshop-1000000001")

        try await sleepUntil("both changes are sent") { @Sendable @MainActor in changes.count == 2 }
        XCTAssertEqual(changes, [Change(id: "1000000001", list: .favorites, isOn: true),
                                 Change(id: "1000000001", list: .favorites, isOn: false)])
    }

    func testDeletingUnsubscribes() async throws {
        lists.unsubscribe(from: ["1000000001", "1000000002"])

        try await sleepUntil("both are unsubscribed") { @Sendable @MainActor in changes.count == 2 }
        XCTAssertEqual(Set(changes.map(\.id)), ["1000000001", "1000000002"])
        XCTAssertTrue(changes.allSatisfy { $0.list == .subscriptions && !$0.isOn })
    }

    func testNothingChangesWithoutTheSteamLogin() async throws {
        isLoggedIn = false

        try await lists.setItem("1000000001", on: .subscriptions, true)
        try await lists.vote(.up, on: "1000000001")
        await lists.loadVotes(for: ["1000000001"])

        XCTAssertEqual(changes, [])
        XCTAssertEqual(votesSent, [:])
        XCTAssertEqual(voteRequests, [])
        XCTAssertFalse(lists.canChangeAccount)
    }

    func testRatingShowsOnceSteamTookIt() async throws {
        try await lists.vote(.up, on: "1000000001")

        XCTAssertEqual(votesSent, ["1000000001": .up])
        XCTAssertEqual(lists.votes["1000000001"], .up)
    }

    func testRatingsAreReadOnceForItemsNotKnownYet() async {
        await lists.loadVotes(for: ["1000000001", "1000000002"])
        await lists.loadVotes(for: ["1000000002", "1000000003"])

        XCTAssertEqual(voteRequests, [["1000000001", "1000000002"], ["1000000003"]])
        XCTAssertEqual(lists.votes, ["1000000002": .down])
    }

    // MARK: - Requests

    func testSubscribeAndUnsubscribeParameters() throws {
        let subscribe = SteamServiceBody(WorkshopSubscriptions.changeItems(workshopId: "1000000001", list: .favorites, adding: true))
        let unsubscribe = SteamServiceBody(WorkshopSubscriptions.changeItems(workshopId: "1000000001", list: .subscriptions, adding: false))

        XCTAssertEqual(subscribe.fields, [
            "publishedfileid": .text("1000000001"), "list_type": .number(2), "appid": .number(431960),
            "notify_client": .bool(false), "include_dependencies": .bool(false),
        ])
        XCTAssertEqual(unsubscribe.fields, [
            "publishedfileid": .text("1000000001"), "list_type": .number(1), "appid": .number(431960),
            "notify_client": .bool(false),
        ])
    }

    func testVoteSummaryReadsEachItemsRating() throws {
        let data = Data(#"""
        {"response": {"summaries": [
            {"publishedfileid": "1000000001", "vote_for": true},
            {"publishedfileid": "1000000002", "vote_against": true},
            {"publishedfileid": "1000000003", "reported": true}
        ]}}
        """#.utf8)

        XCTAssertEqual(try WorkshopVote.votes(from: data), ["1000000001": .up, "1000000002": .down])
        XCTAssertEqual(try WorkshopVote.votes(from: Data(#"{"response": {}}"#.utf8)), [:])
    }

    func testFavouriteKeysNameTheirWorkshopItem() {
        XCTAssertEqual(WallpaperEngineFavorites.workshopID(forKey: "workshop-1000000001"), "1000000001")
        XCTAssertNil(WallpaperEngineFavorites.workshopID(forKey: "/Users/me/Wallpapers/1000000001"))
        XCTAssertNil(WallpaperEngineFavorites.workshopID(forKey: "workshop-abc"))
    }
}

import XCTest
@testable import OpenWallpaperEngine

/// Next and Previous Wallpaper: the per-display history, the random pick and the routing between
/// the playlist and the library.
@MainActor
final class WallpaperStepTests: XCTestCase {
    private func wallpaper(_ name: String) -> WEWallpaper {
        WEWallpaper(using: WEProject(file: "scene.json", preview: "p.jpg", title: name, type: "scene"),
                    where: URL(fileURLWithPath: "/tmp/owe-step/\(name)"))
    }

    private func names(_ wallpapers: [WEWallpaper]) -> [String] {
        wallpapers.map(\.project.title)
    }

    // MARK: - History

    func testHistoryPushAndBack() {
        var history = WallpaperHistory()
        let (a, b, c) = (wallpaper("a"), wallpaper("b"), wallpaper("c"))
        history.push(a, for: "1")
        history.push(b, for: "1")
        history.push(b, for: "1") // already on top
        history.push(c, for: "1")
        XCTAssertEqual(history.previous(for: "1", showing: c)?.project.title, "b")
        XCTAssertEqual(history.back(for: "1", showing: c)?.project.title, "b")
        XCTAssertEqual(history.back(for: "1", showing: b)?.project.title, "a")
        XCTAssertNil(history.back(for: "1", showing: a))
        XCTAssertNil(history.previous(for: "1", showing: a))
    }

    func testHistoryIsPerDisplay() {
        var history = WallpaperHistory()
        history.push(wallpaper("a"), for: "1")
        history.push(wallpaper("b"), for: "1")
        XCTAssertNil(history.previous(for: "2", showing: wallpaper("b")))
        XCTAssertEqual(history.previous(for: "1", showing: wallpaper("b"))?.project.title, "a")
    }

    func testHistoryKeepsTheNewestTwenty() {
        var history = WallpaperHistory()
        for index in 0..<30 { history.push(wallpaper("\(index)"), for: "1") }
        XCTAssertEqual(history.stacks["1"]?.count, WallpaperHistory.capacity)
        XCTAssertEqual(history.stacks["1"]?.first?.project.title, "10")
        XCTAssertEqual(history.stacks["1"]?.last?.project.title, "29")
    }

    func testHistoryIgnoresTheMissingWallpaperPlaceholder() {
        var history = WallpaperHistory()
        history.push(WallpaperViewModel.defaultWallpaper, for: "1")
        XCTAssertNil(history.stacks["1"])
    }

    // MARK: - Random pick

    func testRandomPickNeverReturnsTheCurrentWallpaper() {
        let shown = [wallpaper("a"), wallpaper("b"), wallpaper("c")]
        for index in 0..<2 {
            let pick = WallpaperViewModel.randomPick(from: shown, excluding: shown[1], random: { _ in index })
            XCTAssertNotEqual(pick?.project.title, "b")
        }
        XCTAssertNil(WallpaperViewModel.randomPick(from: [shown[1]], excluding: shown[1]))
        XCTAssertNil(WallpaperViewModel.randomPick(from: [], excluding: shown[1]))
    }

    func testRandomPickComesFromTheShownList() {
        let shown = [wallpaper("x"), wallpaper("y")]
        var seen: Set<String> = []
        for index in 0..<2 {
            let pick = WallpaperViewModel.randomPick(from: shown, excluding: wallpaper("other"), random: { _ in index })
            seen.insert(pick?.project.title ?? "")
        }
        XCTAssertEqual(seen, ["x", "y"])
    }

    // MARK: - Routing

    private func model(showing current: WEWallpaper) -> WallpaperViewModel {
        let model = WallpaperViewModel(persistsWallpapers: false)
        model.setWallpaper(current, for: model.selectedScreenIds)
        return model
    }

    func testOutsideAPlaylistNextPicksRandomlyAndPreviousGoesBack() {
        let (a, b, c) = (wallpaper("a"), wallpaper("b"), wallpaper("c"))
        let model = model(showing: a)
        XCTAssertFalse(model.stepsThroughPlaylist)
        XCTAssertFalse(model.canStepToPreviousWallpaper)

        model.stepToNextWallpaper(shown: [a, b, c], random: { $0.lowerBound })
        XCTAssertEqual(model.currentWallpaper.project.title, "b")
        XCTAssertTrue(model.canStepToPreviousWallpaper)

        model.stepToNextWallpaper(shown: [a, b, c], random: { $0.upperBound - 1 })
        XCTAssertEqual(model.currentWallpaper.project.title, "c")

        model.stepToPreviousWallpaper()
        XCTAssertEqual(model.currentWallpaper.project.title, "b")
        model.stepToPreviousWallpaper()
        XCTAssertEqual(model.currentWallpaper.project.title, "a")
        XCTAssertFalse(model.canStepToPreviousWallpaper)
        XCTAssertFalse(model.canStepToNextWallpaper(shown: [a]))
        XCTAssertTrue(model.canStepToNextWallpaper(shown: [a, b]))
    }

    func testInAPlaylistNextAndPreviousStepThroughIt() {
        let items = (0..<3).map { wallpaper("p\($0)") }
        let model = model(showing: wallpaper("library"))
        model.playlists = [WallpaperPlaylist(name: "p", items: items.map { WallpaperPlaylistItem(wallpaper: $0) })]
        model.activePlaylistID = model.playlists[0].id
        model.playlistEnabled = true
        XCTAssertTrue(model.stepsThroughPlaylist)
        XCTAssertTrue(model.canStepToPreviousWallpaper)

        model.stepToNextWallpaper(shown: [wallpaper("library"), wallpaper("other")])
        XCTAssertEqual(model.currentWallpaper.project.title, "p1")
        model.stepToPreviousWallpaper()
        XCTAssertEqual(model.currentWallpaper.project.title, "p0")
    }

    private func playlistModel(rotating: Bool, shuffle: Bool = false, repeats: Bool = true)
        -> (WallpaperViewModel, [WEWallpaper]) {
        let items = (0..<3).map { wallpaper("p\($0)") }
        let model = model(showing: wallpaper("library"))
        model.playlists = [WallpaperPlaylist(name: "p", items: items.map { WallpaperPlaylistItem(wallpaper: $0) })]
        model.activePlaylistID = model.playlists[0].id
        model.playlistShuffle = shuffle
        model.playlistRepeats = repeats
        model.playlistEnabled = rotating
        return (model, items)
    }

    func testShowingAPlaylistItemStepsThroughThePlaylistWhenNotRotating() {
        let (model, items) = playlistModel(rotating: false)
        model.setWallpaper(items[0], for: model.selectedScreenIds)
        XCTAssertTrue(model.stepsThroughPlaylist)
        let shown = [wallpaper("library"), wallpaper("other")]
        model.stepToNextWallpaper(shown: shown, random: { $0.lowerBound })
        XCTAssertEqual(model.currentWallpaper.project.title, "p1")
        model.stepToNextWallpaper(shown: shown, random: { $0.lowerBound })
        XCTAssertEqual(model.currentWallpaper.project.title, "p2")
        model.stepToPreviousWallpaper()
        XCTAssertEqual(model.currentWallpaper.project.title, "p1")
    }

    func testShowingAWallpaperOutsideThePlaylistUsesRandomAndHistory() {
        let (model, _) = playlistModel(rotating: false)
        XCTAssertFalse(model.stepsThroughPlaylist)
        let (library, other) = (wallpaper("library"), wallpaper("other"))
        model.stepToNextWallpaper(shown: [library, other], random: { $0.lowerBound })
        XCTAssertEqual(model.currentWallpaper.project.title, "other")
        model.stepToPreviousWallpaper()
        XCTAssertEqual(model.currentWallpaper.project.title, "library")
    }

    func testMenuStepsMatchThePlaylistButtons() {
        let (menu, _) = playlistModel(rotating: true)
        let (buttons, _) = playlistModel(rotating: true)
        for _ in 0..<4 {
            menu.stepToNextWallpaper(shown: [])
            buttons.nextPlaylistWallpaper()
            XCTAssertEqual(menu.currentWallpaper.project.title, buttons.currentWallpaper.project.title)
        }
        for _ in 0..<4 {
            menu.stepToPreviousWallpaper()
            buttons.previousPlaylistWallpaper()
            XCTAssertEqual(menu.currentWallpaper.project.title, buttons.currentWallpaper.project.title)
        }
    }

    func testPlaylistRepeatWrapsAtTheEnds() {
        let (model, _) = playlistModel(rotating: true, repeats: true)
        model.stepToPreviousWallpaper() // 0 -> 2
        XCTAssertEqual(model.currentWallpaper.project.title, "p2")
        model.stepToNextWallpaper(shown: []) // 2 -> 0
        XCTAssertEqual(model.currentWallpaper.project.title, "p0")
    }

    func testPlaylistWithoutRepeatStopsAtTheEnd() {
        let (model, _) = playlistModel(rotating: true, repeats: false)
        model.stepToNextWallpaper(shown: [])
        model.stepToNextWallpaper(shown: [])
        XCTAssertEqual(model.currentWallpaper.project.title, "p2")
        model.stepToNextWallpaper(shown: [wallpaper("library"), wallpaper("other")])
        XCTAssertEqual(model.currentWallpaper.project.title, "p2")
        XCTAssertFalse(model.playlistEnabled)
    }

    func testShuffledPlaylistNextStaysInThePlaylist() {
        let (model, items) = playlistModel(rotating: true, shuffle: true)
        let titles = Set(names(items))
        for _ in 0..<10 {
            model.stepToNextWallpaper(shown: [wallpaper("library"), wallpaper("other")])
            XCTAssertTrue(titles.contains(model.currentWallpaper.project.title))
        }
    }
}

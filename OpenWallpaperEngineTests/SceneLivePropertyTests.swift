import XCTest
@testable import OpenWallpaperEngine

/// Showing a wallpaper's properties with nothing changed changes nothing, so it rebuilds nothing.
@MainActor
final class SceneLivePropertyTests: XCTestCase {
    func testPublishingSendsOnlyRealChanges() {
        let running = ["a": "1", "b": "x"]
        let defaults = ["c": "true", "d": ""]
        XCTAssertEqual(WallpaperPropertyTargets.changes(["a": "1", "c": "true", "d": ""], from: running, defaults: defaults), [:],
                       "a missing key stands for its default")
        XCTAssertEqual(WallpaperPropertyTargets.changes(["a": "2", "c": "false", "e": "0"], from: running, defaults: defaults),
                       ["a": "2", "c": "false", "e": "0"])
    }

    /// Opening the properties panel of a running wallpaper, with nothing changed, rebuilds nothing:
    /// it used to hand the wallpaper every value it shows, a label's "" among them, which a
    /// visibility read and so rebuilt the whole scene.
    func testOpeningThePropertiesRebuildsNothing() throws {
        let directory = Fixtures.url("Scenes/live-properties")
        defer { Fixtures.removeStoredSettings(for: directory) }
        let project = try JSONDecoder().decode(WEProject.self, from: Fixtures.data("Scenes/live-properties/project.json"))
        let wallpaper = WEWallpaper(using: project, where: directory)
        let model = SceneWallpaperViewModel(wallpaper: wallpaper)
        let key = model.propertyStoreKey
        let running = WallpaperServices.shared.userProperties(wallpaper: key)
        XCTAssertEqual(running["showeffect"], "true")
        var posted: [[String]] = []
        let token = NotificationCenter.default.addObserver(forName: .sceneUserPropertiesDidChange, object: nil, queue: nil) { note in
            guard note.userInfo?["wallpaper"] as? String == key else { return }
            posted.append(note.userInfo?["keys"] as? [String] ?? [])
        }
        defer { NotificationCenter.default.removeObserver(token) }
        RunLoop.main.run(until: Date().addingTimeInterval(0.2))
        posted.removeAll()
        let panel = SceneUserPropertiesModel(wallpaper: wallpaper, scopes: [.shared])
        RunLoop.main.run(until: Date().addingTimeInterval(0.3))
        XCTAssertFalse(panel.properties.isEmpty)
        XCTAssertEqual(WallpaperServices.shared.userProperties(wallpaper: key), running)
        XCTAssertEqual(posted.map { model.impact(of: $0) }.filter { $0 > .none }, [], "rebuilds: \(posted)")
        // A real change still reaches the wallpaper.
        panel.set("0.5", forID: "red")
        XCTAssertEqual(WallpaperServices.shared.userProperties(wallpaper: key)["red"], "0.5")
    }
}

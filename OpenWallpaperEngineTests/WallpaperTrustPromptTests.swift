import XCTest
@testable import OpenWallpaperEngine

/// A web wallpaper runs only once the user trusted it, whatever case project.json writes its type in.
@MainActor
final class WallpaperTrustPromptTests: XCTestCase {
    func testCapitalisedWebTypeStillAsksFirst() throws {
        let folder = FileManager.default.temporaryDirectory.appending(path: "TrustPrompt-\(UUID().uuidString)", directoryHint: .isDirectory)
        try FileManager.default.createDirectory(at: folder, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: folder) } // Test scratch.
        let model = WallpaperViewModel(persistsWallpapers: false)
        let screen = model.selectedScreenId

        model.nextCurrentWallpaper = WEWallpaper(using: WEProject(file: "index.html", title: "Page", type: "Web"), where: folder)
        XCTAssertNil(model.wallpapers[screen], "an untrusted web wallpaper waits for the user")

        model.nextCurrentWallpaper = WEWallpaper(using: WEProject(file: "a.mp4", title: "Clip", type: "Video"), where: folder)
        XCTAssertEqual(model.wallpapers[screen]?.project.title, "Clip")
    }
}

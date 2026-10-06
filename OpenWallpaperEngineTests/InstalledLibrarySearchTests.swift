import XCTest
@testable import OpenWallpaperEngine

/// The Installed tab's search matches title, type, description, tags, Workshop id and folder name,
/// ignoring case and diacritics.
final class InstalledLibrarySearchTests: XCTestCase {
    private func wallpaper(title: String, description: String? = nil, folder: String = "folder") -> WEWallpaper {
        var project = WEProject(file: "scene.json", title: title, type: "scene")
        project.description = description
        project.workshopid = .int(1234)
        return WEWallpaper(using: project, where: URL(fileURLWithPath: "/library/\(folder)"))
    }

    func testMatchesIgnoringCaseAndDiacritics() {
        let cafe = wallpaper(title: "Café Night")
        XCTAssertTrue(InstalledLibraryModel.matchesSearch("cafe", wallpaper: cafe, tags: []))
        XCTAssertTrue(InstalledLibraryModel.matchesSearch("NIGHT", wallpaper: cafe, tags: []))
        XCTAssertFalse(InstalledLibraryModel.matchesSearch("day", wallpaper: cafe, tags: []))
    }

    func testMatchesEveryField() {
        let item = wallpaper(title: "Title", description: "Rainy street", folder: "my-folder")
        XCTAssertTrue(InstalledLibraryModel.matchesSearch("rainy", wallpaper: item, tags: []))
        XCTAssertTrue(InstalledLibraryModel.matchesSearch("anime", wallpaper: item, tags: ["Anime"]))
        XCTAssertTrue(InstalledLibraryModel.matchesSearch("23", wallpaper: item, tags: []))
        XCTAssertTrue(InstalledLibraryModel.matchesSearch("my-folder", wallpaper: item, tags: []))
        XCTAssertTrue(InstalledLibraryModel.matchesSearch("scene", wallpaper: item, tags: []))
    }
}

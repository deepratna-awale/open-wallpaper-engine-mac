import XCTest
@testable import OpenWallpaperEngine

/// A Workshop preset item listed beside its base wallpaper (`Tests/Fixtures/Library/preset-item`:
/// 3332091404 "Pixels - Green Forest" over 3122339805 "Pixels"). Both run from the base's folder,
/// so the Installed tab tells them apart by their own folders: the grid's tile ids, the selection
/// and Unsubscribe.
@MainActor
final class InstalledPresetTileTests: XCTestCase {
    private let storageKey = "CustomWallpapersDirectory"
    private let presetId = "3332091404"
    private let baseId = "3122339805"
    private var savedStorage: String?
    private var root: URL!
    private var suite: String!
    private var defaults: UserDefaults!

    override func setUp() async throws {
        savedStorage = UserDefaults.app.string(forKey: storageKey)
        root = FileManager.default.temporaryDirectory.appending(path: "owe-preset-tile-\(UUID().uuidString)", directoryHint: .isDirectory)
        try FileManager.default.copyItem(at: Fixtures.url("Library/preset-item"), to: root)
        UserDefaults.app.set(root.path, forKey: storageKey)
        suite = "owe-tests-\(UUID().uuidString)"
        defaults = UserDefaults(suiteName: suite)
    }

    override func tearDown() async throws {
        UserDefaults.app.set(savedStorage, forKey: storageKey)
        defaults.removePersistentDomain(forName: suite)
        try FileManager.default.removeItem(at: root)
    }

    private func library() -> InstalledLibraryModel {
        let filters = FilterResultsViewModel()
        filters.reset()
        return InstalledLibraryModel(filters: filters, steamCmd: SteamCmdService(), presentation: ContentPresentation(),
                                     folders: InstalledFolderStore(defaults: defaults))
    }

    /// The grid's `ForEach` ids: with the base's folder for both, one of the two tiles drew blank.
    func testThePresetAndItsBaseHaveTheirOwnTileIds() throws {
        let wallpapers = library().displayedWallpapers
        XCTAssertEqual(Set(wallpapers.map { $0.settingsDirectory.lastPathComponent }), [presetId, baseId])
        XCTAssertEqual(Set(wallpapers.map(\.wallpaperDirectory)).count, 1, "both play from the base")
        XCTAssertEqual(Set(wallpapers.map(\.settingsDirectory)).count, wallpapers.count)
    }

    /// Selecting the preset leaves the base out, so Unsubscribe Selected removes only the preset's folder.
    func testSelectingThePresetSelectsOnlyThePreset() throws {
        let library = library()
        let preset = try XCTUnwrap(library.displayedWallpapers.first { $0.isWorkshopPreset })
        let base = try XCTUnwrap(library.displayedWallpapers.first { !$0.isWorkshopPreset })
        library.toggleSelection(for: preset)
        XCTAssertTrue(library.isSelected(preset))
        XCTAssertFalse(library.isSelected(base))
        XCTAssertEqual(library.selectedWallpaperItems().map(\.project.title), ["Pixels - Green Forest"])
        XCTAssertEqual(library.selectedWallpapers.map(\.lastPathComponent), [presetId])
        XCTAssertEqual(library.wallpapersActedOn(from: base).map(\.project.title), ["Pixels"])
    }
}

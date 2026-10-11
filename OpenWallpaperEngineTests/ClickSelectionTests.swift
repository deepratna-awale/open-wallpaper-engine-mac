import AppKit
import XCTest
@testable import OpenWallpaperEngine

/// Finder's click selection, shared by the Installed, Workshop and Discover grids, and the
/// Discover rows' ⇧-click ranges, which reached only into the Workshop tab's page before.
@MainActor
final class ClickSelectionTests: XCTestCase {
    func testModifiersPickTheKind() {
        XCTAssertEqual(ClickSelection.kind(of: []), .replace)
        XCTAssertEqual(ClickSelection.kind(of: .shift), .extend)
        XCTAssertEqual(ClickSelection.kind(of: .command), .toggle)
        XCTAssertEqual(ClickSelection.kind(of: .control), .toggle)
        XCTAssertEqual(ClickSelection.kind(of: [.command, .shift]), .toggle, "⌘ wins")
        XCTAssertEqual(ClickSelection.kind(of: [.shift, .capsLock]), .extend, "other keys don't count")
    }

    func testToggleAndRangeFromTheAnchor() {
        let order = ["a", "b", "c", "d", "e"]
        var selected = Set<String>()
        var anchor: String?
        XCTAssertFalse(ClickSelection.apply(.replace, on: "b", in: order, selected: &selected, anchor: &anchor),
                       "a plain click is the tab's")
        XCTAssertTrue(ClickSelection.apply(.extend, on: "b", in: order, selected: &selected, anchor: &anchor))
        XCTAssertEqual(selected, ["b"], "no anchor yet: just it")
        XCTAssertEqual(anchor, "b")
        ClickSelection.apply(.extend, on: "d", in: order, selected: &selected, anchor: &anchor)
        XCTAssertEqual(selected, ["b", "c", "d"])
        ClickSelection.apply(.extend, on: "a", in: order, selected: &selected, anchor: &anchor)
        XCTAssertEqual(selected, ["a", "b"], "redrawn from the same anchor")
        ClickSelection.apply(.toggle, on: "e", in: order, selected: &selected, anchor: &anchor)
        XCTAssertEqual(selected, ["a", "b", "e"])
        ClickSelection.apply(.toggle, on: "a", in: order, selected: &selected, anchor: &anchor)
        XCTAssertEqual(selected, ["b", "e"])
        XCTAssertEqual(anchor, "a")
        ClickSelection.apply(.extend, on: "c", in: order, selected: &selected, anchor: &anchor)
        XCTAssertEqual(selected, ["a", "b", "c"])
    }

    func testDiscoverRowsSelectRanges() throws {
        let root = FileManager.default.temporaryDirectory.appending(path: "owe-click-\(UUID().uuidString)", directoryHint: .isDirectory)
        try FileManager.default.createDirectory(at: root, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: root) } // cleanup of a temp folder; nothing to report
        let steamCmd = SteamCmdService(dependencyIndex: WorkshopDependencyIndex(libraryDirectory: { root }),
                                       storageDirectory: { root }, previewCacheRoot: root,
                                       presentPreview: { _ in }, restoresSession: false)
        let model = WorkshopViewModel(steamCmd: steamCmd, searchPage: { _, _, _, _, _ in [] })
        let row = (1...5).map(Self.item)
        XCTAssertTrue(model.items.isEmpty, "the Workshop tab's page holds none of the row")

        model.selectItem(row[1], in: row, kind: .replace)
        XCTAssertEqual(model.selectedItemIds, ["2"])
        model.selectItem(row[3], in: row, kind: .extend)
        XCTAssertEqual(model.selectedItemIds, ["2", "3", "4"])
        model.selectItem(row[4], in: row, kind: .toggle)
        XCTAssertEqual(model.selectedItemIds, ["2", "3", "4", "5"])
        model.selectItem(row[0], in: row, kind: .replace)
        XCTAssertEqual(model.selectedItemIds, ["1"])
    }

    private static func item(_ number: Int) -> WorkshopItem {
        WorkshopItem(id: "\(number)", title: "Item \(number)", previewURL: nil, tags: ["Wallpaper", "Scene", "Everyone"],
                     subscriptions: 0, fileSize: 0, creatorAppId: nil, creatorId: "author", description: nil,
                     votesUp: 0, votesDown: 0)
    }
}

import XCTest
@testable import OpenWallpaperEngine

/// Objects without an `id` are known by their index in `objects`, everywhere: parent links, text
/// property keys, visibility and the spatial content (docs/roadmap.md item 23).
@MainActor
final class SceneIDLessObjectTests: XCTestCase {
    private let json = #"""
    {"camera": {}, "general": {}, "objects": [
      {"name": "parent", "origin": "0 0 5"},
      {"name": "child", "parent": 0},
      {"name": "clock", "text": {"value": "12:00"}, "font": "a.ttf", "pointsize": 20},
      {"name": "date", "text": {"value": "Mon"}, "font": "b.ttf", "pointsize": 30}
    ]}
    """#

    private func scene() throws -> WEScene {
        try decodeTolerant(WEScene.self, from: Data(json.utf8))
    }

    func testIdentityIsTheIndex() throws {
        let objects = try scene().objects
        XCTAssertEqual(objects.enumerated().map { SceneObjectIdentity.id(of: $1, at: $0) }, [0, 1, 2, 3])
        XCTAssertEqual(SceneObjectIdentity.assigningFallbackIDs(objects).map(\.id), [0, 1, 2, 3])
    }

    func testParentLinkResolvesWithoutIDs() throws {
        let content = SceneSpatialContentBuilder(readFile: { _ in nil }, wallpaperName: "test")
            .build(try scene(), context: PropertyContext())
        XCTAssertEqual(SceneWorldMatrix.translation(content.transforms.world(of: "1")), SIMD3(0, 0, 5),
                       "the child inherits its id-less parent's origin")
    }

    func testTextKeysAreDistinct() throws {
        let values = SceneWallpaperViewModel.userPropertyValues(stored: [:], declared: [:], scene: try scene())
        XCTAssertEqual(values["_owe_text_2_font"], "a.ttf")
        XCTAssertEqual(values["_owe_text_3_font"], "b.ttf")
        XCTAssertEqual(values["_owe_text_2_size"], "20.0")
        XCTAssertEqual(values["_owe_text_3_size"], "30.0")
        XCTAssertNil(values["_owe_text_-1_font"])
    }

    func testVisibilityKeysEachObject() throws {
        let visibility = SceneUserVisibility(objects: try scene().objects)
        let values = ["_owe_text_3_enabled": "false"]
        let resolved = visibility.resolve { values[$0] }
        XCTAssertEqual(resolved.objects, ["0": true, "1": true, "2": true, "3": false])
    }
}

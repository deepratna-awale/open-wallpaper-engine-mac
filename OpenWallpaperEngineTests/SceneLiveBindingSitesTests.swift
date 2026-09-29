import XCTest
@testable import OpenWallpaperEngine

/// A user property read only where the renderer re-resolves it every frame doesn't rebuild the content.
final class SceneLiveBindingSitesTests: XCTestCase {
    private func contentProperties(_ json: String) throws -> Set<String> {
        let document = try JSONDecoder().decode(SceneJSON.self, from: Data(json.utf8))
        return SceneWallpaperViewModel.contentUserProperties(in: document)
    }

    func testPerFrameSitesDontRebuild() throws {
        let names = try contentProperties(#"""
        {"objects": [
          {"id": 1, "image": "models/a.json",
           "origin": {"user": "x", "value": "0 0 0"},
           "scale": {"user": "s", "value": "1 1 1"},
           "angles": {"user": "r", "value": "0 0 0"},
           "color": {"user": "tint", "value": "1 1 1"},
           "alpha": {"user": "fade", "value": 1},
           "brightness": {"user": "glow", "value": 1}}
        ]}
        """#)
        XCTAssertEqual(names, [])
    }

    func testBakedSitesStillRebuild() throws {
        let names = try contentProperties(#"""
        {"general": {"bloom": {"user": "bloom", "value": true}},
         "objects": [
          {"id": 1, "image": "models/a.json",
           "visible": {"user": "show", "value": true},
           "size": {"user": "size", "value": "10 10"},
           "effects": [{"file": "e.json", "passes": [{"constantshadervalues": {"speed": {"user": "speed", "value": 1}}}]}]},
          {"id": 2, "text": {"value": "hi"}, "color": {"user": "textcolour", "value": "1 1 1"}},
          {"id": 3, "light": "point", "origin": {"user": "lightpos", "value": "0 0 0"}}
        ]}
        """#)
        XCTAssertEqual(names, ["bloom", "show", "size", "speed", "textcolour", "lightpos"])
    }

    func testPropertyAlsoReadAtBakedSiteRebuilds() throws {
        let names = try contentProperties(#"""
        {"objects": [
          {"id": 1, "image": "models/a.json", "alpha": {"user": "p", "value": 1}},
          {"id": 2, "image": "models/b.json", "visible": {"user": "p", "value": true}}
        ]}
        """#)
        XCTAssertEqual(names, ["p"])
    }
}

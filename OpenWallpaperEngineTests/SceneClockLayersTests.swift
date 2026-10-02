import XCTest
@testable import OpenWallpaperEngine

final class SceneClockLayersTests: XCTestCase {
    func testScriptsThatReadTheDateAreClocks() {
        for source in ["var d = new Date(); return d.getHours();", "return Date.now()",
                       "let t = new Date();", "x.getUTCMinutes()", "return d.toLocaleTimeString()"] {
            XCTAssertTrue(SceneClockLayers.readsDate(source), source)
        }
        for source in ["return engine.runtime * 2;", "return value.toUpperCase();", "var updated = 1;"] {
            XCTAssertFalse(SceneClockLayers.readsDate(source), source)
        }
    }

    func testFindsTheTextLayersWhoseScriptReadsTheDate() throws {
        let json = #"""
        {"objects": [
          {"id": 5, "text": {"value": "", "script": "export function update() { return new Date().getHours(); }"}},
          {"id": 6, "text": {"value": "", "script": "export function update(v) { return v; }"}},
          {"id": 7, "text": "static"},
          {"id": 8, "image": "a.json", "visible": {"value": true, "script": "return new Date().getHours() > 6;"}}
        ]}
        """#
        let document = try JSONDecoder().decode(SceneJSON.self, from: Data(json.utf8))
        XCTAssertEqual(SceneClockLayers.ids(in: document), ["5"])
    }
}

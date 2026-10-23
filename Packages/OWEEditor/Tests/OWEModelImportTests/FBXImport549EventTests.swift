import Foundation
import OWEModelImport
import OWESceneEditing
import WEFormat
import XCTest

/// Capture 549 (c): Add Event "flapmid" at frame 15 on the animation "Scene" (`FBXImport549`).
final class FBXImport549EventTests: XCTestCase {
    /// `editor.events: [{animation: "Scene", frame: 15, id: 29, name: "flapmid"}]`, keyed to the
    /// source animation, read and written as it is.
    func testTheEventIsReadAndWrittenAsWEWroteIt() throws {
        let config = try FBXImport549.config("siblings.json")
        XCTAssertEqual(config.animationMapping, ["Scene": 52])
        XCTAssertEqual(config.events, [ModelImportConfig.Event(id: 29, name: "flapmid", frame: 15, animation: 52)])
        func events(_ data: Data) throws -> NSArray? {
            ((try JSONSerialization.jsonObject(with: data) as? [String: Any])?["editor"] as? [String: Any])?["events"] as? NSArray
        }
        XCTAssertEqual(try events(try config.jsonData()), try events(try Data(contentsOf: try FBXImport549.fixture("siblings.json"))))
    }

    /// WE compiles the event as `{"frame":15,"name":"flapmid"}` at 15 / 30 fps = 0.5, into the
    /// first record not named "Scene" (its name test is inverted): the clip "Scene (Clip 54)".
    func testTheEventCompilesAsWEsDoes() throws {
        let (ours, theirs, output) = try FBXImport549.compiled("siblings", config: try FBXImport549.config("siblings.json"))
        XCTAssertEqual(theirs.animations.map(\.name), ["Scene", "Scene (Clip 54)"])
        XCTAssertEqual(theirs.animations.map { $0.events.map(\.0) }, [[], [0.5]])
        XCTAssertEqual(theirs.animations.map { $0.events.map(\.1) }, [[], [#"{"frame":15,"name":"flapmid"}"#]])
        XCTAssertEqual(ours.animations.map { $0.events.map(\.0) }, theirs.animations.map { $0.events.map(\.0) })
        XCTAssertEqual(ours.animations.map { $0.events.map(\.1) }, theirs.animations.map { $0.events.map(\.1) })

        // The event's bytes, from its count to the end of the clip record, are WE's.
        let mine = output.mdl, wes = try Data(contentsOf: try FBXImport549.fixture("siblings.mdl"))
        func tail(_ data: Data) throws -> Data {
            let at = try XCTUnwrap(data.range(of: Data(#"{"frame""#.utf8))).lowerBound
            return data.subdata(in: (at - 8)..<data.count)
        }
        XCTAssertEqual(try tail(mine), try tail(wes))
    }

    /// An event keyed to a clip goes in that clip; one on an animation with no other record is
    /// left out, as WE's compiler leaves it.
    func testEventsGoWhereWEsCompilerPutsThem() throws {
        var config = try FBXImport549.config("siblings.json")
        config.events = [ModelImportConfig.Event(id: 30, name: "onclip", frame: 3, animation: 26)]
        let clipped = try FBXImport549.compiled("siblings", config: config).ours
        XCTAssertEqual(clipped.animations.map { $0.events.map(\.1) }, [[], [#"{"frame":3,"name":"onclip"}"#]])
        config.clips = []
        config.events = [ModelImportConfig.Event(id: 29, name: "flapmid", frame: 15, animation: 52)]
        let alone = try FBXImport549.compiled("siblings", config: config).ours
        XCTAssertEqual(alone.animations.map(\.events.count), [0])
    }

    /// The player's reader takes WE's record as it is: the time in seconds and the JSON, which
    /// scripts get parsed (the clip clock, `SceneAnimationLayer.clock`, fires it at 0.5 s).
    func testThePlayerReadsWEsEvent() throws {
        let model = try MDLReader.read(Data(contentsOf: try FBXImport549.fixture("siblings.mdl")))
        let events = (model.animations ?? []).map(\.events)
        XCTAssertEqual(events, [[], [MDLAnimation.Event(frame: 0.5, name: #"{"frame":15,"name":"flapmid"}"#)]])
    }
}

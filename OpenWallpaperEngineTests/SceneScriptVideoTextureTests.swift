import JavaScriptCore
import XCTest
import simd
@testable import OpenWallpaperEngine

/// `IImageLayer.getVideoTexture` (objects-layers.js) and its way to the layer's player, plus the
/// script fixtures in `Tests/Fixtures/SceneScript/members`, one per member that used to be a stub.
final class SceneScriptVideoTextureTests: XCTestCase {
    private func scene() -> SceneScriptSceneDescription {
        var background = SceneScriptObjectDescription.make(.image, id: 1, name: "background")
        background.videoDuration = 2
        let clock = SceneScriptObjectDescription.make(.text, id: 2, name: "clock", parentID: 1)
        let group = SceneScriptObjectDescription.make(.group, id: 5, name: "group")
        var puppet = SceneScriptObjectDescription.make(.image, id: 6, name: "puppet")
        puppet.rig = SceneScriptRigTests.rig
        let plain = SceneScriptObjectDescription.make(.image, id: 7, name: "plain", values: [.size: [200, 100]])
        return SceneScriptSceneDescription(objects: [background, clock, group, puppet, plain])
    }

    private func fixture() throws -> SceneScriptObjectFixture {
        let f = try SceneScriptObjectFixture(FakeSceneScriptObjectHost(scene: scene()))
        f.runtime.load()
        return f
    }

    private func string(_ f: SceneScriptObjectFixture, _ script: String) -> String? { f.evaluate(script)?.toString() }

    private func videoCommands(_ f: SceneScriptObjectFixture) -> [SceneScriptObjectCommand] {
        f.host.takeCommands().filter {
            if case .video = $0 { return true }
            return false
        }
    }

    func testMemberFixtures() throws {
        _ = try Fixtures.assets()
        for member in ["setParent", "lookAt", "lookAtYaw", "rotateObjectSpace", "transformAttachmentToTexture", "getVideoTexture"] {
            let f = try fixture()
            // The plain layer sits 50 left of and 25 below the puppet's bind-pose grip (31, 7).
            let slot = try XCTUnwrap(f.model.slot(forObjectID: 7))
            let base = SceneScriptObjectTable.index(slot: slot, field: SceneScriptObjectTable.Layout.worldMatrix)
            let world = simd_float4x4(columns: (SIMD4(1, 0, 0, 0), SIMD4(0, 1, 0, 0), SIMD4(0, 0, 1, 0), SIMD4(-19, -18, 0, 1)))
            for column in 0..<4 { for row in 0..<4 { f.store.table.values[base + column * 4 + row] = world[column][row] } }
            let source = try String(contentsOf: Fixtures.url("SceneScript/members/\(member).js"), encoding: .utf8)
            XCTAssertEqual(string(f, source), "ok", member)
            XCTAssertEqual(string(f, "Array.from(__rt.objects.UNSUPPORTED).some(function (m) { return m.endsWith('.\(member)'); })"),
                           "false", "\(member) is a stub")
        }
    }

    func testVideoTextureClockAndCallbacks() throws {
        _ = try Fixtures.assets()
        let f = try fixture()
        f.evaluate("""
            var video = thisScene.getLayer('background').getVideoTexture(), ends = 0;
            video.addEndedCallback(function () { ends += 1; });
            """)
        for _ in 0..<90 { f.runtime.frame(deltaTime: 1.0 / 30) }
        XCTAssertEqual(Double(string(f, "video.getCurrentTime()") ?? "") ?? -1, 1, accuracy: 1e-3, "looped once in 3 s")
        XCTAssertEqual(string(f, "[ends, video.isPlaying()].join()"), "1,true")

        f.evaluate("video.loop = false; video.rate = 2;")
        for _ in 0..<30 { f.runtime.frame(deltaTime: 1.0 / 30) }
        XCTAssertEqual(string(f, "[ends, video.isPlaying(), video.getCurrentTime()].join()"), "2,false,2",
                       "a video that doesn't loop holds its end")
        f.evaluate("video.play();")
        XCTAssertEqual(string(f, "[video.isPlaying(), video.getCurrentTime()].join()"), "true,0", "and restarts on play")
    }

    func testVideoTextureCommandsReachTheHost() throws {
        let f = try fixture()
        let slot = try XCTUnwrap(f.model.slot(forObjectID: 1))
        _ = f.host.takeCommands()
        f.evaluate("""
            var video = thisScene.getLayer('background').getVideoTexture();
            video.pause(); video.play(); video.stop(); video.setCurrentTime(0.5); video.rate = 0.5; video.loop = false;
            video.setCurrentTime(NaN); video.rate = 'x';
            """)
        f.runtime.frame(deltaTime: 1.0 / 60)
        XCTAssertEqual(videoCommands(f), [.video(slot: slot, .pause), .video(slot: slot, .play), .video(slot: slot, .stop),
                                          .video(slot: slot, .seek(0.5)), .video(slot: slot, .rate(0.5)),
                                          .video(slot: slot, .loop(false))])
    }

    func testCommandDecoding() {
        XCTAssertEqual(SceneVideoTextureCommand(numbers: [3, -1]), .seek(0))
        XCTAssertEqual(SceneVideoTextureCommand(numbers: [5, 1]), .loop(true))
        XCTAssertNil(SceneVideoTextureCommand(numbers: [3]))
        XCTAssertNil(SceneVideoTextureCommand(numbers: [9]))
        XCTAssertNil(SceneVideoTextureCommand(numbers: [4, .nan]))
    }

    /// The length a video texture reports comes from its MP4's `mvhd` (version 0 and 1).
    func testMP4Duration() {
        func movie(version: UInt8, timescale: UInt32, duration: UInt64) -> Data {
            func be(_ value: UInt64, _ count: Int) -> [UInt8] { (0..<count).map { UInt8(truncatingIfNeeded: value >> (8 * UInt64(count - 1 - $0))) } }
            let times = version == 1 ? be(0, 16) + be(UInt64(timescale), 4) + be(duration, 8)
                : be(0, 8) + be(UInt64(timescale), 4) + be(duration, 4)
            let mvhd = [version, 0, 0, 0] + times
            let mvhdBox = be(UInt64(mvhd.count + 8), 4) + Array("mvhd".utf8) + mvhd
            let ftyp = be(16, 4) + Array("ftypisom".utf8) + be(0, 4)
            return Data(ftyp + be(UInt64(mvhdBox.count + 8), 4) + Array("moov".utf8) + mvhdBox)
        }
        XCTAssertEqual(MP4Duration.seconds(of: movie(version: 0, timescale: 600, duration: 1500)), 2.5)
        XCTAssertEqual(MP4Duration.seconds(of: movie(version: 1, timescale: 1000, duration: 4000)), 4)
        XCTAssertNil(MP4Duration.seconds(of: Data("not a movie".utf8)))
    }
}

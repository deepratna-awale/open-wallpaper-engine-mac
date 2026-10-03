import CoreGraphics
import XCTest
@testable import OWEEditor
@testable import OWESceneEditing

/// The puppet editor's table holds every text it shows in every language the app ships, and its
/// workspace edits go through the session's undo.
final class PuppetEditorTests: XCTestCase {
    private static var sources: URL {
        URL(fileURLWithPath: #filePath).deletingLastPathComponent().deletingLastPathComponent().deletingLastPathComponent()
            .deletingLastPathComponent().appending(path: "Sources/OWEEditor")
    }

    private func catalog() throws -> [String: [String: Any]] {
        let data = try Data(contentsOf: Self.sources.appending(path: "Resources/Puppets.xcstrings"))
        let json = try XCTUnwrap(try JSONSerialization.jsonObject(with: data) as? [String: Any])
        XCTAssertEqual(json["sourceLanguage"] as? String, "en")
        return try XCTUnwrap(json["strings"] as? [String: [String: Any]])
    }

    /// `PL("…")` keys in the puppet editor's sources (`\(number)` is an integer, anything else a string).
    private func usedKeys() throws -> Set<String> {
        var keys = Set<String>()
        let regex = try NSRegularExpression(pattern: #"PL\("((?:[^"\\]|\\\([^)]*\))*)"\)"#)
        let folder = Self.sources.appending(path: "Puppets")
        let files = try FileManager.default.contentsOfDirectory(at: folder, includingPropertiesForKeys: nil)
            .filter { $0.pathExtension == "swift" }
        XCTAssertFalse(files.isEmpty)
        for file in files {
            let text = try String(contentsOf: file, encoding: .utf8)
            for match in regex.matches(in: text, range: NSRange(text.startIndex..., in: text)) {
                var key = String(text[Range(match.range(at: 1), in: text)!])
                key = key.replacingOccurrences(of: #"\\\(number\)"#, with: "%lld", options: .regularExpression)
                key = key.replacingOccurrences(of: #"\\\([^)]*\)"#, with: "%@", options: .regularExpression)
                keys.insert(key)
            }
        }
        return keys
    }

    func testEveryPuppetKeyIsInTheTable() throws {
        let catalog = try catalog()
        let used = try usedKeys()
        XCTAssertGreaterThan(used.count, 100)
        XCTAssertTrue(used.subtracting(catalog.keys).isEmpty, "not in the table: \(used.subtracting(catalog.keys).sorted())")
        XCTAssertTrue(Set(catalog.keys).subtracting(used).isEmpty, "unused: \(Set(catalog.keys).subtracting(used).sorted())")
    }

    func testEveryPuppetKeyIsTranslatedIntoEveryLanguage() throws {
        var problems: [String] = []
        let specifier = try NSRegularExpression(pattern: #"%(?:\d+\$)?(?:lld|@)"#)
        func arguments(_ text: String) -> [String] {
            specifier.matches(in: text, range: NSRange(text.startIndex..., in: text))
                .map { String(text[Range($0.range, in: text)!]) }.sorted()
        }
        for (key, entry) in try catalog() {
            let localizations = entry["localizations"] as? [String: [String: Any]] ?? [:]
            for language in EditorLocalizationTests.languages {
                let unit = localizations[language]?["stringUnit"] as? [String: Any]
                guard let value = unit?["value"] as? String, !value.isEmpty, unit?["state"] as? String == "translated" else {
                    problems.append("\(language): “\(key)”")
                    continue
                }
                if arguments(value) != arguments(key) { problems.append("\(language): “\(key)” has \(arguments(value))") }
            }
        }
        XCTAssertTrue(problems.isEmpty, problems.sorted().joined(separator: "\n"))
    }

    func testEnglishTextResolves() {
        XCTAssertEqual(PL("Puppet Warp"), "Puppet Warp")
        XCTAssertEqual(PuppetWorkspace.Tool.weights.title, "Weights")
    }

    // MARK: Workspace

    /// A 64 × 128 picture, opaque in a centred 32 × 96 block.
    private static func source() -> PuppetSource {
        var pixels = [UInt8](repeating: 0, count: 4 * 64 * 128)
        for y in 16..<112 {
            for x in 16..<48 {
                let i = 4 * (y * 64 + x)
                pixels[i] = 200; pixels[i + 1] = 100; pixels[i + 2] = 50; pixels[i + 3] = 255
            }
        }
        let texture = PuppetImage(width: 64, height: 128, pixels: pixels)
        return PuppetSource(modelPath: "models/block.json", material: "materials/block.json", rigPath: nil, image: texture.cgImage,
                            texture: texture, imageSize: SIMD2(64, 128))
    }

    @MainActor
    private func session() throws -> SceneEditSession {
        let undoManager = UndoManager()
        undoManager.groupsByEvent = false
        let scene = Data(#"{"general": {"orthogonalprojection": {"width": 100, "height": 100}}, "objects": [{"id": 1, "image": "models/block.json"}]}"#.utf8)
        return SceneEditSession(outline: try SceneOutline(sceneData: scene), undoManager: undoManager)
    }

    @MainActor
    func testCreatingAndEditingAPuppetIsUndoable() throws {
        let session = try session()
        let workspace = PuppetWorkspace(session: session, layerID: 1, source: Self.source())
        defer { workspace.stop() }
        XCTAssertNil(workspace.document)
        workspace.meshOptions.spacing = 12
        workspace.createPuppet()
        let created = try XCTUnwrap(session.puppet(of: 1))
        XCTAssertGreaterThan(created.mesh.vertices.count, 8)
        XCTAssertTrue(created.problems.isEmpty, "a new puppet can be saved at once: \(created.problems)")
        XCTAssertEqual(created.material, "materials/block.json")
        // Every vertex lies on the opaque block (±16 × ±48, padded by two pixels).
        XCTAssertTrue(created.mesh.vertices.allSatisfy { abs($0.position.x) <= 19 && abs($0.position.y) <= 51 })

        workspace.edit("Add Bone") { $0.addBone(named: "arm", parent: 0, head: SIMD2(0, 20), angle: .pi / 2) }
        workspace.autoWeights()
        XCTAssertEqual(session.puppet(of: 1)?.bones.count, 2)
        // A drag is a draft: nothing is stored until it ends, then once.
        workspace.draft { $0.moveVertex(0, to: SIMD2(5, 5), textureLayout: true) }
        workspace.draft { $0.moveVertex(0, to: SIMD2(6, 6), textureLayout: true) }
        XCTAssertNotEqual(session.puppet(of: 1)?.mesh.vertices[0].position, SIMD2(6, 6))
        workspace.endDraft("Move Vertices")
        XCTAssertEqual(session.puppet(of: 1)?.mesh.vertices[0].position, SIMD2(6, 6))

        session.undo() // the move
        XCTAssertNotEqual(workspace.document?.mesh.vertices[0].position, SIMD2(6, 6), "the workspace follows undo")
        session.undo() // the weights
        session.undo() // the bone
        XCTAssertEqual(workspace.document?.bones.count, 1)
        session.undo() // the creation
        XCTAssertNil(workspace.document)
        session.redo()
        XCTAssertEqual(workspace.document, created)
    }

    @MainActor
    func testAnimatingSetsKeysAndLayers() throws {
        let session = try session()
        let workspace = PuppetWorkspace(session: session, layerID: 1, source: Self.source())
        defer { workspace.stop() }
        workspace.createPuppet()
        workspace.tool = .animate
        workspace.addClip()
        XCTAssertEqual(workspace.document?.clips.count, 1)
        XCTAssertEqual(workspace.document?.layers.count, 1, "the first animation gets a layer, so the wallpaper plays it")
        workspace.frame = 10
        var turned = try XCTUnwrap(workspace.keyTransform(of: 0))
        turned.euler.z = 0.5
        workspace.setPoseKey(bone: 0, transform: turned, draft: false)
        XCTAssertEqual(workspace.clip?.tracks[0].keys[10], turned)
        XCTAssertEqual(workspace.keyFrames, [10])
        workspace.deleteKey()
        XCTAssertTrue(workspace.keyFrames.isEmpty)
        workspace.updateClip("Change Frame Rate") { $0.fps = 24 }
        XCTAssertEqual(workspace.clip?.fps, 24)
    }
}

import Foundation
import OWEModelImport
import OWESceneEditing
import XCTest

/// WE's default projects keep their models' sources beside the `.mdl`s WE's resource compiler
/// wrote from them (`projects/defaultprojects/*/models/**`: an FBX or OBJ, its configuration
/// JSON and the `.mdl`). Compiling each source here must give WE's meshes: the same formats,
/// vertices and indices. These are WE's files, so they aren't in the repository: the tests read
/// them from a Wallpaper Engine install (`OWE_WE_INSTALL`, the `wallpaper_engine` folder) and skip
/// without one.
final class WEDefaultProjectModelTests: XCTestCase {
    static var projects: URL? {
        guard let install = ProcessInfo.processInfo.environment["OWE_WE_INSTALL"], !install.isEmpty else { return nil }
        let url = URL(fileURLWithPath: install).appending(path: "projects/defaultprojects", directoryHint: .isDirectory)
        return FileManager.default.fileExists(atPath: url.path) ? url : nil
    }

    /// Every source with a compiled `.mdl` beside it.
    static func pairs() throws -> [(source: URL, mdl: URL)] {
        guard let projects else { throw XCTSkip("OWE_WE_INSTALL isn't set to a Wallpaper Engine install") }
        var pairs: [(URL, URL)] = []
        let enumerator = FileManager.default.enumerator(at: projects, includingPropertiesForKeys: nil)
        while let url = enumerator?.nextObject() as? URL {
            guard ModelFileLoader.fileExtensions.contains(url.pathExtension.lowercased()) else { continue }
            let mdl = url.deletingPathExtension().appendingPathExtension("mdl")
            if FileManager.default.fileExists(atPath: mdl.path) { pairs.append((url, mdl)) }
        }
        return pairs.sorted { $0.0.path < $1.0.path }
    }

    static func config(for source: URL) throws -> (ModelImportConfig, [[String: String]]) {
        let url = source.deletingPathExtension().appendingPathExtension("json")
        guard let data = try? Data(contentsOf: url) else { return (.missing, []) }
        let config = try ModelImportConfig(json: data)
        var skins: [[String: String]] = []
        if case .array(let list)? = config.other["skins"] {
            for case .object(let skin) in list {
                skins.append(skin.compactMapValues(\.stringValue))
            }
        }
        return (config, skins)
    }

    /// Meshes whose joined vertices differ from WE's although their format, triangles and
    /// layout agree (docs/model-import.md): which of two near-equal corners Assimp's joining
    /// keeps and how its tangent smoothing breaks ties at exactly 45° depend on its spatial sort's
    /// order, and three OBJs without a configuration are `MDLV0014`-era output that WE's editor
    /// compiles anew (`MDLV0023`) before it uses them.
    static let knownDivergences: Set<String> = [
        "arsenal/models/pistols/pistols.fbx#0", "arsenal/models/pistols/pistols.fbx#5",
        "audiophile/models/audiophile/bars.obj#0", "dna_fragment/models/dna/dna.fbx#0",
        "audiophile/models/audiophile/flow.obj#0", "fantasticcar/models/dome/dome.obj#0",
        "fantasticcar/models/util/shadow.obj#0",
    ]

    func testEveryDefaultProjectSourceCompilesToWEsMeshes() throws {
        let pairs = try Self.pairs()
        XCTAssertGreaterThan(pairs.count, 20)
        var report: [String] = []
        var exact = 0, identical = 0
        var largest: Float = 0
        for (source, mdl) in pairs {
            let name = source.path.components(separatedBy: "defaultprojects/").last ?? source.lastPathComponent
            let (config, skins) = try Self.config(for: source)
            let loaded = try ModelFileLoader.load(contentsOf: source)
            let output = try ModelCompiler.compile(loaded, config: config, folder: "x", skins: skins)
            let ours = try MDLTestReader.read(output.mdl)
            let theirs = try MDLTestReader.read(try Data(contentsOf: mdl))
            guard ours.meshes.count == theirs.meshes.count else {
                report.append("\(name): \(ours.meshes.count) meshes, WE \(theirs.meshes.count)")
                continue
            }
            XCTAssertEqual(ours.legacyFormat, theirs.legacyFormat, name)
            for (index, (a, b)) in zip(ours.meshes, theirs.meshes).enumerated() {
                XCTAssertEqual(a.materials.count, b.materials.count, "\(name) mesh \(index)")
                XCTAssertEqual(a.format, b.format, "\(name) mesh \(index): format")
                XCTAssertEqual(a.indices.count, b.indices.count, "\(name) mesh \(index): index count")
                var problems: [String] = []
                if a.vertices.count != b.vertices.count { problems.append("vertex bytes \(a.vertices.count) vs \(b.vertices.count)") }
                if a.indices != b.indices { problems.append("indices differ") }
                if a.vertices.count == b.vertices.count, a.format == b.format {
                    let difference = Self.largestDifference(a.vertices, b.vertices, stride: Self.stride(a.format), format: a.format)
                    if difference.value > 1e-3 { problems.append("vertex values differ by \(difference.value) at \(difference.attribute)") }
                }
                let key = "\(name)#\(index)"
                if problems.isEmpty {
                    exact += 1
                    if a.vertices == b.vertices { identical += 1 }
                    largest = max(largest, Self.largestDifference(a.vertices, b.vertices, stride: Self.stride(a.format), format: a.format).value)
                    XCTAssertFalse(Self.knownDivergences.contains(key), "\(key) now matches WE: drop it from knownDivergences")
                } else if !Self.knownDivergences.contains(key) {
                    report.append("\(key): " + problems.joined(separator: "; "))
                }
            }
        }
        XCTAssert(report.isEmpty, report.joined(separator: "\n"))
        print("WE default projects: \(exact) meshes match WE's (\(identical) byte for byte, the others within \(largest)), \(Self.knownDivergences.count) known divergences")
        XCTAssertGreaterThanOrEqual(exact, 20)
    }

    static let attributes: [(mask: UInt32, size: Int, name: String)] = [
        (0x1, 12, "position"), (0x10000, 16, "positionVec4"), (0x2000000, 12, "positionC1"), (0x2, 12, "normal"),
        (0x4, 16, "tangent"), (0x800000, 16, "blendIndices"), (0x1000000, 16, "blendWeights"), (0x8, 8, "uv"), (0x10, 12, "uvVec3"),
        (0x20, 16, "uvVec4"),
    ]

    static func stride(_ format: UInt32) -> Int { attributes.reduce(0) { format & $1.mask != 0 ? $0 + $1.size : $0 } }

    /// The largest difference of any float and the attribute it is in.
    static func largestDifference(_ a: Data, _ b: Data, stride: Int, format: UInt32) -> (value: Float, attribute: String) {
        let fa = a.withUnsafeBytes { Array($0.bindMemory(to: Float.self)) }
        let fb = b.withUnsafeBytes { Array($0.bindMemory(to: Float.self)) }
        var worst: Float = 0, attribute = ""
        let names: [String] = attributes.flatMap { format & $0.mask != 0 ? Array(repeating: $0.name, count: $0.size / 4) : [] }
        for index in fa.indices where abs(fa[index] - fb[index]) > worst {
            worst = abs(fa[index] - fb[index])
            attribute = names.isEmpty ? "" : names[index % (stride / 4)] + " of vertex \(index / (stride / 4))"
        }
        return (worst, attribute)
    }
}

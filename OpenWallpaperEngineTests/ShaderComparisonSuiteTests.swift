import XCTest
import Metal
import CryptoKit
@testable import OpenWallpaperEngine

/// The shader comparison suite: a record of what the translator makes of every shader it can
/// reach, and of a list of scenes drawn with it, to compare two builds of the translator
/// (`Scripts/shader-compare.sh` runs both tests and `Scripts/shader-compare-diff.py` diffs two runs).
///
/// Runs only when `OWE_SHADER_COMPARE_OUT` names the run's folder (`TEST_RUNNER_…` through
/// xcodebuild):
/// - `testTranslateCorpus` translates every vert/frag pair in `OWE_ASSETS` and in each wallpaper
///   folder of `OWE_SHADER_COMPARE_LIBRARY` (read only; the wallpaper's own files first, then the
///   assets, as a scene loads them), each with its default combos and with each declared combo
///   switched on alone (as `ShaderRevisionGuardTests` does), plus a pair's geometry stage folded
///   into its vertex stage as particle materials build it, compiles the MSL with Metal, and
///   writes `shaders.json`: per shader and combo set, ok or failed, the error class and a hash of
///   the output.
/// - `testRenderScenes` draws each scene folder listed in the file `OWE_SHADER_COMPARE_SCENES`
///   (one per line) at `OWE_SHADER_COMPARE_TIME` seconds (2), the local time of day
///   `OWE_SHADER_COMPARE_LOCAL_TIME` (12:00, for scenes that read the clock) and 960×540 through
///   `WEReferenceRenderer`, writes `renders/<name>.png`, and with `OWE_SHADER_COMPARE_BASELINE`
///   (an earlier run's folder) compares each frame with the baseline's by `WEReferenceMetrics`
///   (mean absolute difference and SSIM, never byte equality) into `renders.json`.
final class ShaderComparisonSuiteTests: XCTestCase {
    private static var environment: [String: String] { ProcessInfo.processInfo.environment }

    private static func outputFolder() throws -> URL {
        guard let path = environment["OWE_SHADER_COMPARE_OUT"], !path.isEmpty else {
            throw XCTSkip("set OWE_SHADER_COMPARE_OUT to run the shader comparison suite")
        }
        let url = URL(fileURLWithPath: path, isDirectory: true)
        try FileManager.default.createDirectory(at: url, withIntermediateDirectories: true)
        return url
    }

    // MARK: - Translation

    struct ShaderRecord: Codable {
        var ok: Bool
        /// The failing step and its first error line without paths or line numbers.
        var error: String?
        /// SHA-256 of both stages' MSL, the uniform layout, texture slots and attributes.
        var hash: String?
    }

    struct CorpusSummary: Codable {
        var revision: Int
        var pairs: Int
        var variants: Int
        var ok: Int
        var failed: Int
        var failedByClass: [String: Int]
        var seconds: Double
    }

    struct CorpusFile: Codable {
        var summary: CorpusSummary
        /// `<root>/<pair path>|<combos>` → record.
        var items: [String: ShaderRecord]
    }

    func testTranslateCorpus() throws {
        let output = try Self.outputFolder()
        let assets = try Fixtures.assets()
        let started = Date()
        let translator = ShaderVariantTranslator(compiler: InProcessShaderCompiler(), cacheDirectory: nil, failureDirectory: nil)
        let device = try XCTUnwrap(MTLCreateSystemDefaultDevice())
        var metalVerdicts: [String: String?] = [:]
        var items: [String: ShaderRecord] = [:]
        var pairs = 0

        var corpora: [(label: String, root: URL, roots: [URL])] = [("assets", assets, [assets])]
        if let library = Self.environment["OWE_SHADER_COMPARE_LIBRARY"], !library.isEmpty {
            let root = URL(fileURLWithPath: library, isDirectory: true)
            for id in try FileManager.default.contentsOfDirectory(atPath: root.path).sorted() where !id.hasPrefix(".") {
                let folder = root.appending(path: id, directoryHint: .isDirectory)
                corpora.append(("library/\(id)", folder, [folder, assets]))
            }
        }
        func record(_ key: String, _ translate: () throws -> TranslatedShaderVariant) {
            let variant: TranslatedShaderVariant
            do {
                variant = try translate()
            } catch {
                items[key] = ShaderRecord(ok: false, error: Self.translationErrorClass(error))
                return
            }
            let hash = Self.hash(variant)
            if metalVerdicts[hash] == nil {
                metalVerdicts[hash] = Self.metalError(variant, device: device)
            }
            if let failure = metalVerdicts[hash] ?? nil {
                items[key] = ShaderRecord(ok: false, error: "metal: " + failure, hash: hash)
            } else {
                items[key] = ShaderRecord(ok: true, hash: hash)
            }
        }
        for corpus in corpora {
            let roots = corpus.roots
            let readFile: (String) -> Data? = { path in
                for root in roots {
                    // Optional: a root without the file falls through to the next.
                    if let data = try? AssetPathResolver.data(path, in: root) { return data }
                }
                return nil
            }
            let loader = ShaderSourceLoader(readFile: readFile)
            for path in Self.shaderPaths(under: corpus.root) {
                pairs += 1
                let key = "\(corpus.label)/\(path)"
                let vertex: ShaderSource, fragment: ShaderSource
                do {
                    vertex = try loader.load(path, stage: .vertex)
                    fragment = try loader.load(path, stage: .fragment)
                } catch {
                    items[key + "|load"] = ShaderRecord(ok: false, error: "load: " + Self.errorClass("\(error)"))
                    continue
                }
                for combos in Self.comboSets(vertex: vertex, fragment: fragment) {
                    record(key + "|" + Self.label(combos)) {
                        try translator.variant(vertex: vertex, fragment: fragment, combos: combos)
                    }
                }
                // A geometry stage is folded into the vertex stage, as particle materials build it
                // (`ParticleMaterialPlanBuilder`, `GS_ENABLED` 1).
                let geometry: GeometryShaderEmulation.Sources?
                do {
                    geometry = try GeometryShaderEmulation.sources(path, readFile: readFile)
                } catch {
                    items[key + "|geom|load"] = ShaderRecord(ok: false, error: "load: " + Self.errorClass("\(error)"))
                    continue
                }
                guard let geometry else { continue }
                func synthetic(_ name: String, _ text: String) throws -> ShaderSource {
                    let data = Data(text.utf8)
                    return try ShaderSourceLoader(readFile: { $0 == name ? data : readFile($0) }).load(name, stage: .vertex)
                }
                let declarations: ShaderSource
                do {
                    declarations = try synthetic("shaders/\(path)+declarations.vert", geometry.declarations)
                } catch {
                    items[key + "|geom|load"] = ShaderRecord(ok: false, error: "load: " + Self.errorClass("\(error)"))
                    continue
                }
                for combos in Self.comboSets(vertex: declarations, fragment: fragment, base: ["GS_ENABLED": 1]) {
                    record(key + "|geom|" + Self.label(combos)) {
                        let emulation = try GeometryShaderEmulation.make(geometry, combos: combos, compiler: translator.compiler)
                        let folded = try synthetic("shaders/\(path)+geom.vert", emulation.vertexText)
                        return try translator.variant(vertex: folded, fragment: fragment, combos: combos)
                    }
                }
            }
        }
        var byClass: [String: Int] = [:]
        for record in items.values where !record.ok { byClass[record.error ?? "?", default: 0] += 1 }
        let ok = items.values.filter(\.ok).count
        let summary = CorpusSummary(revision: ShaderVariantTranslator.revision, pairs: pairs, variants: items.count,
                                    ok: ok, failed: items.count - ok, failedByClass: byClass,
                                    seconds: Date().timeIntervalSince(started))
        try Self.write(CorpusFile(summary: summary, items: items), to: output.appending(path: "shaders.json"))
        print("Shader corpus: \(pairs) pairs, \(items.count) variants, \(ok) ok, \(items.count - ok) failed "
              + "in \(Int(summary.seconds)) s → \(output.path)/shaders.json")
    }

    /// Pair paths (no extension) under `root`: every `.vert` or `.frag` file's, sorted. The other
    /// stage may come from a later root (a wallpaper's fragment over WE's vertex stage).
    static func shaderPaths(under root: URL) -> [String] {
        guard let files = FileManager.default.enumerator(at: root, includingPropertiesForKeys: nil,
                                                         options: [.skipsHiddenFiles]) else { return [] }
        let base = root.standardizedFileURL.path
        var paths = Set<String>()
        for case let url as URL in files where url.pathExtension == "vert" || url.pathExtension == "frag" {
            paths.insert(String(url.deletingPathExtension().standardizedFileURL.path.dropFirst(base.count + 1)))
        }
        return paths.sorted()
    }

    /// The default combos (texture slot 0 bound, as every layer's is) and each declared combo
    /// switched on alone.
    static func comboSets(vertex: ShaderSource, fragment: ShaderSource, base: [String: Int] = [:]) -> [[String: Int]] {
        let defaults = ShaderVariantTranslator.resolveCombos(vertex: vertex, fragment: fragment, overrides: [base],
                                                             boundTextureSlots: [0])
        var sets = [defaults]
        for combo in Set((vertex.combos + fragment.combos).map(\.name)).sorted() where defaults[combo] != 1 {
            var combos = defaults
            combos[combo] = 1
            sets.append(combos)
        }
        return sets
    }

    static func label(_ combos: [String: Int]) -> String {
        combos.sorted { $0.key < $1.key }.map { "\($0.key)=\($0.value)" }.joined(separator: ",")
    }

    static func hash(_ variant: TranslatedShaderVariant) -> String {
        var hasher = SHA256()
        hasher.update(data: Data(variant.vertexMSL.utf8))
        hasher.update(data: Data("\u{0}".utf8))
        hasher.update(data: Data(variant.fragmentMSL.utf8))
        for (name, member) in (variant.uniforms?.members ?? [:]).sorted(by: { $0.key < $1.key }) {
            hasher.update(data: Data("\u{0}\(name):\(member.type):\(member.offset):\(member.count)".utf8))
        }
        hasher.update(data: Data("\u{0}\(variant.textureSlots)\(variant.attributes.sorted { $0.key < $1.key })".utf8))
        return hasher.finalize().map { String(format: "%02x", $0) }.joined()
    }

    /// nil when both stages compile with Metal; else the first error's class.
    static func metalError(_ variant: TranslatedShaderVariant, device: MTLDevice) -> String? {
        for source in [variant.vertexMSL, variant.fragmentMSL] {
            do {
                _ = try device.makeLibrary(source: source, options: nil)
            } catch {
                return errorClass("\(error)")
            }
        }
        return nil
    }

    static func translationErrorClass(_ error: Error) -> String {
        if case ShaderVariantError.translation(_, let underlying) = error {
            if case ShaderCompilerError.failed(let step, let output) = underlying { return "\(step): " + errorClass(output) }
            return errorClass("\(underlying)")
        }
        return errorClass("\(error)")
    }

    /// `LibrarySweepTests.cause`, which groups identical problems: no paths or line numbers.
    static func errorClass(_ detail: String) -> String {
        LibrarySweepTests.cause(detail)
    }

    // MARK: - Renders

    struct RenderRecord: Codable {
        var ok: Bool
        var error: String?
        /// Against the baseline's frame: mean absolute RGB difference (0…255) and SSIM.
        var meanAbs: Double?
        var ssim: Double?
    }

    struct RenderFile: Codable {
        var time: Double
        var width: Int
        var height: Int
        var baseline: String?
        /// Scene folder name → record.
        var scenes: [String: RenderRecord]
    }

    static let renderSize = SIMD2(960, 540)

    func testRenderScenes() throws {
        let output = try Self.outputFolder()
        _ = try Fixtures.assets()
        guard let list = Self.environment["OWE_SHADER_COMPARE_SCENES"], !list.isEmpty else {
            throw XCTSkip("set OWE_SHADER_COMPARE_SCENES to a file listing scene folders")
        }
        let scenes = try String(contentsOfFile: list, encoding: .utf8).split(separator: "\n")
            .map { $0.trimmingCharacters(in: .whitespaces) }.filter { !$0.isEmpty && !$0.hasPrefix("#") }
        let time = Double(Self.environment["OWE_SHADER_COMPARE_TIME"] ?? "") ?? 2
        let localTime = Self.environment["OWE_SHADER_COMPARE_LOCAL_TIME"].flatMap { $0.isEmpty ? nil : $0 } ?? "12:00"
        let baseline = Self.environment["OWE_SHADER_COMPARE_BASELINE"].flatMap { $0.isEmpty ? nil : URL(fileURLWithPath: $0) }
        let renders = output.appending(path: "renders", directoryHint: .isDirectory)
        try FileManager.default.createDirectory(at: renders, withIntermediateDirectories: true)
        let scratch = FileManager.default.temporaryDirectory.appending(path: "owe-shader-compare-\(UUID().uuidString)")
        defer { try? FileManager.default.removeItem(at: scratch) } // scratch cleanup

        var records: [String: RenderRecord] = [:]
        for path in scenes {
            let directory = URL(fileURLWithPath: path, isDirectory: true)
            // Folder names repeat across roots (a default project and a Workshop copy): keep the parent.
            let name = directory.deletingLastPathComponent().lastPathComponent + "_" + directory.lastPathComponent
            do {
                let image = try Self.render(directory, time: time, localTime: localTime, storage: scratch.appending(path: name))
                let file = renders.appending(path: "\(name).png")
                try image.write(to: file)
                var record = RenderRecord(ok: true)
                if let baseline {
                    let previous = baseline.appending(path: "renders/\(name).png")
                    if FileManager.default.fileExists(atPath: previous.path) {
                        let before = try WEReferenceImage.load(previous)
                        let after = try WEReferenceImage.load(file)
                        let mask = WEReferenceMask(width: before.width, height: before.height, masks: [], taskbar: 0)
                        let metrics = WEReferenceMetrics.compare(we: before, ours: after, mask: mask,
                                                                 grid: WEReferenceConfig.Grid(columns: 4, rows: 4),
                                                                 taskbar: 0, edges: false)
                        record.meanAbs = metrics.meanAbs
                        record.ssim = metrics.ssim
                    }
                }
                records[name] = record
            } catch {
                records[name] = RenderRecord(ok: false, error: Self.errorClass("\(error)"))
            }
            Fixtures.removeStoredSettings(for: directory)
        }
        try Self.write(RenderFile(time: time, width: Self.renderSize.x, height: Self.renderSize.y,
                                  baseline: baseline?.path, scenes: records),
                       to: output.appending(path: "renders.json"))
        print("Shader compare renders: \(records.count) scenes, \(records.values.filter { !$0.ok }.count) failed → \(renders.path)")
    }

    /// The scene at `time` (at `localTime` of day) with the default properties, WE's gallery quality settings and seeded
    /// particles (`WEReferenceRenderer`), at `renderSize`.
    private static func render(_ directory: URL, time: Double, localTime: String, storage: URL) throws -> WEReferenceImage {
        let data = try Data(contentsOf: directory.appending(path: "project.json"))
        let project = try decodeTolerant(WEProject.self, from: data)
        var settings = SceneRenderSettings()
        settings.postProcessing = .enabled
        settings.particleBudget = .unlimited
        settings.textureReduction = 1
        settings.sceneDetail = .full
        settings.renderResolution = .yourDisplay
        var renderer = WEReferenceRenderer(directory: directory, project: project, settings: settings, storage: storage)
        renderer.outputSize = renderSize
        renderer.localTime = localTime
        let centre = SIMD2(Double(renderSize.x) / 2, Double(renderSize.y) / 2)
        let images = try renderer.render([WEReferenceRenderer.Shot(time: time, cursor: centre)])
        return try XCTUnwrap(images.first)
    }

    private static func write<T: Encodable>(_ value: T, to url: URL) throws {
        let encoder = JSONEncoder()
        encoder.outputFormatting = [.prettyPrinted, .sortedKeys]
        try encoder.encode(value).write(to: url, options: .atomic)
    }
}

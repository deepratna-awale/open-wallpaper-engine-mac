import XCTest
import Metal
import MetalKit
@testable import OpenWallpaperEngine

/// Pass fusion (`ShaderPassFusion`) and half-precision outputs (`ShaderHalfPrecision`): the proof
/// accepts what it should, fused pairs draw what the two passes draw (SSIM ≥ 0.999) on the effect
/// chains of the CI scenes and the test playlist, and half outputs change no frame beyond
/// ΔE99 ≤ 2.0.
final class ShaderFusionHalfTests: XCTestCase {
    private static let compiler = InProcessShaderCompiler()

    private static func translator(half: Bool = true) -> ShaderVariantTranslator {
        ShaderVariantTranslator(compiler: compiler, cacheDirectory: nil,
                                failureDirectory: ShaderVariantTranslator.defaultFailureDirectory, halfOutputs: half)
    }

    // MARK: - Half outputs

    private static let floatEntry = """
        struct main0_out
        {
            float4 out_FragColor [[color(0)]];
        };

        fragment main0_out main0(texture2d<float> t [[texture(0)]], sampler s [[sampler(0)]])
        {
            main0_out out = {};
            out.out_FragColor = t.sample(s, float2(0.5));
            if (out.out_FragColor.x > 0.5)
            {
                return out;
            }
            out.out_FragColor.y = 1.0;
            return out;
        }
        """

    func testHalfOutputsConvertAtEveryReturn() throws {
        let rewritten = ShaderHalfPrecision.rewriteFragmentOutputs(Self.floatEntry)
        XCTAssertTrue(rewritten.contains("half4 out_FragColor [[color(0)]];"))
        XCTAssertTrue(rewritten.contains("float4 out_FragColor_weFloat = {};"))
        XCTAssertEqual(rewritten.components(separatedBy: "out.out_FragColor = half4(out_FragColor_weFloat); return out;").count, 3)
        XCTAssertFalse(rewritten.contains("out.out_FragColor.y"))
        let device = try XCTUnwrap(MTLCreateSystemDefaultDevice())
        XCTAssertNoThrow(try device.makeLibrary(source: "#include <metal_stdlib>\nusing namespace metal;\n" + rewritten, options: nil))
    }

    func testHalfOutputsLeaveAFunctionThatPassesItsOutputsOnAlone() {
        let helper = Self.floatEntry.replacingOccurrences(
            of: "fragment main0_out", with: "static void helper(thread main0_out& o) {}\n\nfragment main0_out")
        XCTAssertEqual(ShaderHalfPrecision.rewriteFragmentOutputs(helper), helper)
    }

    /// Every effect, material and particle shader of the WE assets with its default combos: the
    /// half variant compiles in Metal. Prints how many fragment functions went half.
    func testEveryAssetShaderCompilesWithHalfOutputs() throws {
        let assets = try Fixtures.assets()
        let device = try XCTUnwrap(MTLCreateSystemDefaultDevice())
        let translator = Self.translator()
        var half = 0, total = 0, failed: [String] = []
        for (root, path) in Self.assetPairs(assets) {
            let loader = ShaderSourceLoader(roots: [root, assets])
            guard let vertex = try? loader.load(path, stage: .vertex), let fragment = try? loader.load(path, stage: .fragment) else { continue }
            let combos = ShaderVariantTranslator.resolveCombos(vertex: vertex, fragment: fragment, overrides: [], boundTextureSlots: [0])
            // Optional: shaders that don't translate today are the translator's own failures, not this rewrite's.
            guard let variant = try? translator.variant(vertex: vertex, fragment: fragment, combos: combos) else { continue }
            total += 1
            if variant.fragmentMSL.contains("half4 out_FragColor [[color(0)]]") { half += 1 }
            do {
                _ = try device.makeLibrary(source: variant.fragmentMSL, options: nil)
            } catch {
                failed.append("\(path): \(error)")
            }
        }
        print("wp3b: half outputs \(half) of \(total) asset fragment shaders")
        XCTAssertEqual(failed, [])
        XCTAssertGreaterThan(half, total * 9 / 10)
    }

    /// Relative (root, shader path) of every vert/frag pair under the assets' shader folders.
    private static func assetPairs(_ assets: URL) -> [(URL, String)] {
        var result: [(URL, String)] = []
        var roots: [URL] = [assets]
        let effects = assets.appending(path: "effects")
        for name in ((try? FileManager.default.contentsOfDirectory(atPath: effects.path)) ?? []).sorted() {
            roots.append(effects.appending(path: name))
        }
        for root in roots {
            let shaders = root.appending(path: "shaders")
            guard let files = FileManager.default.enumerator(at: shaders, includingPropertiesForKeys: nil) else { continue }
            for case let url as URL in files where url.pathExtension == "frag" {
                let base = url.deletingPathExtension()
                guard FileManager.default.fileExists(atPath: base.appendingPathExtension("vert").path) else { continue }
                result.append((root, String(base.standardizedFileURL.path.dropFirst(shaders.standardizedFileURL.path.count + 1))))
            }
        }
        return result
    }

    // MARK: - Fusion proof

    private func preprocessed(_ effect: String, _ shader: String, combos: [String: Int] = [:]) throws -> (vertex: String, fragment: String) {
        let assets = try Fixtures.assets()
        let loader = ShaderSourceLoader(roots: [assets.appending(path: "effects/\(effect)"), assets])
        let vertex = try loader.load("effects/\(shader)", stage: .vertex)
        let fragment = try loader.load("effects/\(shader)", stage: .fragment)
        var resolved = ShaderVariantTranslator.resolveCombos(vertex: vertex, fragment: fragment, overrides: [], boundTextureSlots: [0])
        resolved.merge(combos) { $1 }
        func run(_ source: ShaderSource) throws -> String {
            ShaderPrelude.fixupAfterPreprocess(try Self.compiler.preprocess(
                ShaderPrelude.text(for: source.stage, combos: resolved, analysis: source.preludeAnalysis) + source.text(combos: resolved),
                stage: source.stage))
        }
        return (try run(vertex), try run(fragment))
    }

    func testTheProofAcceptsPassesThatReadTheirOwnPixelOnly() throws {
        for (effect, shader) in [("tint", "tint"), ("opacity", "opacity")] {
            let pair = try preprocessed(effect, shader)
            XCTAssertNil(ShaderPassFusion.refusalForSecond(vertex: pair.vertex, fragment: pair.fragment), effect)
        }
        let masked = try preprocessed("tint", "tint", combos: ["MASK": 1])
        XCTAssertNil(ShaderPassFusion.refusalForSecond(vertex: masked.vertex, fragment: masked.fragment))
    }

    func testTheProofRefusesNeighboursAndMovedCoordinates() throws {
        let blur = try preprocessed("blur", "blur_gaussian")
        XCTAssertEqual(ShaderPassFusion.refusalForSecond(vertex: blur.vertex, fragment: blur.fragment), .readsInputElsewhere)
        let scroll = try preprocessed("scroll", "scroll")
        XCTAssertNotNil(ShaderPassFusion.refusalForSecond(vertex: scroll.vertex, fragment: scroll.fragment))
        let shake = try preprocessed("shake", "shake")
        XCTAssertNotNil(ShaderPassFusion.refusalForSecond(vertex: shake.vertex, fragment: shake.fragment))
    }

    func testPassThroughCoordinateForms() {
        XCTAssertTrue(ShaderPassFusion.texCoordIsPassedThrough("void main() { v_TexCoord = a_TexCoord.xyxy; v_TexCoord.zw = foo; }"))
        XCTAssertTrue(ShaderPassFusion.texCoordIsPassedThrough("void main() { v_TexCoord.xy = a_TexCoord; }"))
        XCTAssertFalse(ShaderPassFusion.texCoordIsPassedThrough("void main() { v_TexCoord.xy = a_TexCoord; v_TexCoord.x += 0.1; }"))
        XCTAssertFalse(ShaderPassFusion.texCoordIsPassedThrough("void main() { v_TexCoord = a_TexCoord * 2.0; }"))
        XCTAssertFalse(ShaderPassFusion.texCoordIsPassedThrough("void main() { v_TexCoord.zw = a_TexCoord; }"))
    }

    // MARK: - Fused vs unfused on real chains

    /// Every pair of consecutive passes in the effect chains of the CI scenes, the WE default
    /// projects and the test playlist that the translator fuses: the fused draw matches the two
    /// passes (SSIM ≥ 0.999) with the chain's own combos and constants. Prints the counts.
    func testFusedPairsMatchTheirTwoPassesOnSceneChains() throws {
        let assets = try Fixtures.assets()
        var directories = Self.sceneDirectories(Fixtures.url("Scenes"))
        directories += Self.sceneDirectories(assets.deletingLastPathComponent().appending(path: "projects/defaultprojects"))
        if let library = ProcessInfo.processInfo.environment["OWE_LIBRARY"] {
            directories += Self.sceneDirectories(URL(fileURLWithPath: library))
        }
        let harness = try PassHarness(size: SIMD2(256, 256))
        let translator = Self.translator()
        var pairs = 0, fused = 0, fusedInstances = 0, compared = 0, minSSIM = 1.0, maxStep = 0
        var outcome: [String: Bool] = [:]
        var refusals: [String: Int] = [:]
        var seen = Set<String>()
        for directory in directories {
            for chain in Self.effectChains(in: directory, assets: assets) {
                for index in chain.indices.dropLast() {
                    let first = chain[index], second = chain[index + 1]
                    guard first.fusableAsFirst, second.fusableAsSecond else { continue }
                    pairs += 1
                    let key = "\(first.key)|\(second.key)"
                    if let known = outcome[key] { fusedInstances += known ? 1 : 0; continue }
                    seen.insert(key)
                    outcome[key] = false
                    guard let a = first.pass(assets: assets), let b = second.pass(assets: assets) else { continue }
                    switch translator.fusedVariant(first: a, second: b) {
                    case .failure(let error):
                        refusals["\(error)".prefix(40).description, default: 0] += 1
                    case .success(let plan):
                        fused += 1
                        fusedInstances += 1
                        outcome[key] = true
                        let result = try harness.compare(first: (a, first), second: (b, second), plan: plan, translator: translator)
                        minSSIM = min(minSSIM, result.ssim)
                        maxStep = max(maxStep, result.maxDifference)
                        compared += 1
                        // One rounding step is the most a store can move: a constant on a rounding
                        // tie (every pixel's alpha one step apart) drops SSIM over black on the flat
                        // synthetic input without anything to see.
                        XCTAssertTrue(result.ssim >= 0.999 || result.maxDifference <= 1,
                                      "\(directory.lastPathComponent): \(key): SSIM \(result.ssim), max step \(result.maxDifference)")
                    }
                }
            }
        }
        print("wp3b: fusion \(pairs) adjacent pairs, \(seen.count) distinct, \(fused) fused (\(fusedInstances) of the adjacent pairs), \(compared) compared, min SSIM \(minSSIM), max step \(maxStep); refusals \(refusals)")
        XCTAssertGreaterThan(compared, 0)
    }

    /// GPU time of the unfused pair vs the fused draw at 3840×2160, interleaved, over the fused
    /// pairs of the CI scenes and playlist. `OWE_WP3B_FUSION_TIMING=1`.
    func testFusionGPUTime() throws {
        guard ProcessInfo.processInfo.environment["OWE_WP3B_FUSION_TIMING"] == "1" else { throw XCTSkip("timing off") }
        let assets = try Fixtures.assets()
        var directories = Self.sceneDirectories(Fixtures.url("Scenes"))
        if let library = ProcessInfo.processInfo.environment["OWE_LIBRARY"] {
            directories += Self.sceneDirectories(URL(fileURLWithPath: library))
        }
        let harness = try PassHarness(size: SIMD2(3840, 2160))
        let translator = Self.translator()
        var seen = Set<String>()
        var unfusedTotal = 0.0, fusedTotal = 0.0
        for directory in directories {
            for chain in Self.effectChains(in: directory, assets: assets) {
                for index in chain.indices.dropLast() {
                    let first = chain[index], second = chain[index + 1]
                    guard first.fusableAsFirst, second.fusableAsSecond, seen.insert("\(first.key)|\(second.key)").inserted,
                          let a = first.pass(assets: assets), let b = second.pass(assets: assets),
                          case .success(let plan) = translator.fusedVariant(first: a, second: b) else { continue }
                    let times = try harness.time(first: (a, first), second: (b, second), plan: plan, translator: translator, rounds: 30)
                    print(String(format: "wp3b: timing %@ unfused %.3f ms fused %.3f ms", "\(first.key)|\(second.key)", times.unfused, times.fused))
                    unfusedTotal += times.unfused
                    fusedTotal += times.fused
                }
            }
        }
        print(String(format: "wp3b: timing total unfused %.3f ms fused %.3f ms over %d pairs", unfusedTotal, fusedTotal, seen.count))
    }

    // MARK: - Half vs float frames

    /// Half vs float outputs on the CI scenes and the test playlist's scenes (`OWE_LIBRARY`),
    /// each scene drawn by three renderers in one process: float, float again as the control,
    /// and half. Frames where the two float renders differ (random particles, scripts) are skipped;
    /// the rest must stay within ΔE99 ≤ 2.0. `OWE_WP3B_HALF_SCENES=1`.
    func testHalfFramesMatchFloatFramesOnScenes() throws {
        guard ProcessInfo.processInfo.environment["OWE_WP3B_HALF_SCENES"] == "1" else { throw XCTSkip("set OWE_WP3B_HALF_SCENES=1") }
        var directories = Self.sceneDirectories(Fixtures.url("Scenes")).filter { $0.lastPathComponent != "scripted-hang" }
        if let library = ProcessInfo.processInfo.environment["OWE_LIBRARY"] {
            directories += Self.sceneDirectories(URL(fileURLWithPath: library))
        }
        let half = Self.translator(half: true), float = Self.translator(half: false)
        let size = SIMD2(480, 270)
        var compared = 0, skipped = 0, worst = 0.0
        for directory in directories where FileManager.default.fileExists(atPath: directory.appending(path: "project.json").path) {
            let runs = try [float, float, half].enumerated().map { index, translator in
                try TranslatorFrameHarness(directory: directory, size: size, translator: translator, screenID: "wp3b\(index)")
            }
            defer { runs.forEach { $0.close() } }
            var sceneWorst = 0.0
            for frame in 0..<40 {
                runs.forEach { $0.draw(step: 1.0 / 30) }
                guard frame >= 5, frame % 5 == 0 else { continue }
                let images = runs.map(\.image)
                guard PerceptualCompare.deltaE99(images[0], images[1]) <= 0.5 else { skipped += 1; continue }
                let deltaE = PerceptualCompare.deltaE99(images[1], images[2])
                sceneWorst = max(sceneWorst, deltaE)
                compared += 1
                XCTAssertLessThanOrEqual(deltaE, 2.0, "\(directory.lastPathComponent) frame \(frame)")
            }
            worst = max(worst, sceneWorst)
            print("wp3b: half vs float \(directory.lastPathComponent) worst ΔE99 \(sceneWorst)")
        }
        print("wp3b: half vs float \(compared) frames compared (\(skipped) nondeterministic skipped), worst ΔE99 \(worst)")
        XCTAssertGreaterThan(compared, 0)
    }

    // MARK: - Scene chains

    private static func sceneDirectories(_ root: URL) -> [URL] {
        ((try? FileManager.default.contentsOfDirectory(atPath: root.path)) ?? []).sorted()
            .map { root.appending(path: $0) }
            .filter { FileManager.default.fileExists(atPath: $0.appending(path: "scene.json").path) }
    }

    /// One effect pass of a layer's chain, as the scene and its effect and material files set it.
    struct ChainPass {
        let roots: [URL]
        let shader: String
        let combos: [String: Int]
        let constants: [String: Any]
        let boundSlots: Set<Int>
        let fusableAsFirst: Bool
        let fusableAsSecond: Bool

        var key: String {
            "\(roots.first?.lastPathComponent ?? "")/\(shader)\(combos.sorted { $0.key < $1.key })\((constants.keys.sorted()))"
        }

        func pass(assets: URL) -> ShaderPassFusion.Pass? {
            let loader = ShaderSourceLoader(roots: roots)
            guard let vertex = try? loader.load(shader, stage: .vertex), let fragment = try? loader.load(shader, stage: .fragment) else {
                return nil
            }
            let resolved = ShaderVariantTranslator.resolveCombos(vertex: vertex, fragment: fragment, overrides: [combos],
                                                                 boundTextureSlots: boundSlots)
            return ShaderPassFusion.Pass(vertex: vertex, fragment: fragment, combos: resolved)
        }
    }

    private static func json(_ url: URL) -> [String: Any]? {
        FileManager.default.contents(atPath: url.path).flatMap { try? JSONSerialization.jsonObject(with: $0) as? [String: Any] }
    }

    private static func intCombos(_ value: Any?) -> [String: Int] {
        var result: [String: Int] = [:]
        for (name, value) in value as? [String: Any] ?? [:] {
            if let number = value as? NSNumber { result[name.uppercased()] = number.intValue }
        }
        return result
    }

    /// Each visible layer's effect passes, in order.
    static func effectChains(in directory: URL, assets: URL) -> [[ChainPass]] {
        guard let scene = json(directory.appending(path: "scene.json")) else { return [] }
        func resolve(_ path: String, in roots: [URL]) -> (root: URL, json: [String: Any])? {
            for root in roots {
                if let found = json(root.appending(path: path)) { return (root, found) }
            }
            return nil
        }
        var chains: [[ChainPass]] = []
        for object in scene["objects"] as? [[String: Any]] ?? [] {
            var chain: [ChainPass] = []
            for effect in object["effects"] as? [[String: Any]] ?? [] {
                if let visible = effect["visible"] as? Bool, !visible { continue }
                guard let file = effect["file"] as? String, let definition = resolve(file, in: [directory, assets]) else { continue }
                let effectFolder = definition.root.appending(path: file).deletingLastPathComponent()
                let roots = [effectFolder, directory, assets]
                let instances = effect["passes"] as? [[String: Any]] ?? []
                for (index, pass) in (definition.json["passes"] as? [[String: Any]] ?? []).enumerated() {
                    let instance = index < instances.count ? instances[index] : [:]
                    guard let materialPath = pass["material"] as? String,
                          let material = resolve(materialPath, in: roots),
                          let materialPass = (material.json["passes"] as? [[String: Any]])?.first,
                          let shader = materialPass["shader"] as? String else {
                        chain.append(ChainPass(roots: roots, shader: "", combos: [:], constants: [:], boundSlots: [],
                                               fusableAsFirst: false, fusableAsSecond: false))
                        continue
                    }
                    var combos = intCombos(materialPass["combos"])
                    combos.merge(intCombos(instance["combos"])) { $1 }
                    var constants = materialPass["constantshadervalues"] as? [String: Any] ?? [:]
                    constants.merge(instance["constantshadervalues"] as? [String: Any] ?? [:]) { $1 }
                    var bound: Set<Int> = [0]
                    for source in [materialPass["textures"], instance["textures"]] {
                        for (slot, texture) in (source as? [Any] ?? []).enumerated() where !(texture is NSNull) { bound.insert(slot) }
                    }
                    let plain = pass["target"] == nil && pass["bind"] == nil && pass["command"] == nil
                    let blending = (materialPass["blending"] as? String ?? "normal").lowercased()
                    let slotZeroIsPrevious = ((instance["textures"] as? [Any])?.first).map { $0 is NSNull } ?? true
                    chain.append(ChainPass(roots: roots, shader: shader,
                                           combos: combos, constants: constants, boundSlots: bound,
                                           fusableAsFirst: plain && ["normal", "disabled"].contains(blending),
                                           fusableAsSecond: plain && slotZeroIsPrevious))
                }
            }
            if chain.count > 1 { chains.append(chain) }
        }
        return chains
    }
}

// MARK: - A minimal pass renderer

/// Draws translated effect passes on a full quad into RGBA8 targets, with the uniforms their
/// declarations and chain constants give, and synthetic textures in every bound slot.
private final class PassHarness {
    let device: MTLDevice
    let queue: MTLCommandQueue
    let size: SIMD2<Int>
    let input: MTLTexture
    let extra: MTLTexture
    let sampler: MTLSamplerState

    init(size: SIMD2<Int>) throws {
        let device = try XCTUnwrap(MTLCreateSystemDefaultDevice())
        self.device = device
        queue = try XCTUnwrap(device.makeCommandQueue())
        self.size = size
        func pattern(_ seed: UInt32) throws -> MTLTexture {
            let descriptor = MTLTextureDescriptor.texture2DDescriptor(pixelFormat: .rgba8Unorm, width: size.x, height: size.y, mipmapped: false)
            let texture = try XCTUnwrap(device.makeTexture(descriptor: descriptor))
            var bytes = [UInt8](repeating: 0, count: size.x * size.y * 4)
            var state = seed
            for y in 0..<size.y {
                for x in 0..<size.x {
                    state = state &* 1664525 &+ 1013904223
                    let i = (y * size.x + x) * 4
                    bytes[i] = UInt8(x * 255 / max(size.x - 1, 1))
                    bytes[i + 1] = UInt8(y * 255 / max(size.y - 1, 1))
                    bytes[i + 2] = UInt8((state >> 24) & 0xFF)
                    bytes[i + 3] = UInt8(128 + (x + y) % 128)
                }
            }
            texture.replace(region: MTLRegionMake2D(0, 0, size.x, size.y), mipmapLevel: 0, withBytes: bytes, bytesPerRow: size.x * 4)
            return texture
        }
        input = try pattern(7)
        extra = try pattern(99)
        let descriptor = MTLSamplerDescriptor()
        descriptor.minFilter = .linear
        descriptor.magFilter = .linear
        descriptor.sAddressMode = .clampToEdge
        descriptor.tAddressMode = .clampToEdge
        sampler = try XCTUnwrap(device.makeSamplerState(descriptor: descriptor))
    }

    func target() throws -> MTLTexture {
        let descriptor = MTLTextureDescriptor.texture2DDescriptor(pixelFormat: .rgba8Unorm, width: size.x, height: size.y, mipmapped: false)
        descriptor.usage = [.renderTarget, .shaderRead]
        descriptor.storageMode = .shared
        return try XCTUnwrap(device.makeTexture(descriptor: descriptor))
    }

    func pipeline(_ variant: TranslatedShaderVariant) throws -> MTLRenderPipelineState {
        let vertexFunction = try XCTUnwrap(device.makeLibrary(source: variant.vertexMSL, options: nil).makeFunction(name: "main0"))
        let fragmentFunction = try XCTUnwrap(device.makeLibrary(source: variant.fragmentMSL, options: nil).makeFunction(name: "main0"))
        let descriptor = MTLRenderPipelineDescriptor()
        descriptor.vertexFunction = vertexFunction
        descriptor.fragmentFunction = fragmentFunction
        descriptor.vertexDescriptor = EffectGraphRenderer.vertexDescriptor(for: vertexFunction)
        descriptor.colorAttachments[0].pixelFormat = .rgba8Unorm
        return try device.makeRenderPipelineState(descriptor: descriptor)
    }

    /// The pass's uniform values by member name: declaration defaults, chain constants, builtins.
    func values(_ pass: ShaderPassFusion.Pass, _ chain: ShaderFusionHalfTests.ChainPass) -> [String: [Float]] {
        var result: [String: [Float]] = [:]
        func floats(_ value: Any?) -> [Float]? {
            if let number = value as? NSNumber { return [number.floatValue] }
            if let text = value as? String { let parts = text.split(separator: " ").compactMap { Float($0) }; return parts.isEmpty ? nil : parts }
            if let dictionary = value as? [String: Any] { return floats(dictionary["value"]) }
            return nil
        }
        for declaration in pass.vertex.uniforms + pass.fragment.uniforms where !declaration.isSampler {
            var value = floats(declaration.annotation["default"])
            if let key = declaration.materialKey, let constant = floats(chain.constants[key]) { value = constant }
            if let value { result[declaration.name] = value }
        }
        let w = Float(size.x), h = Float(size.y)
        result["g_ModelViewProjectionMatrix"] = [1, 0, 0, 0, 0, 1, 0, 0, 0, 0, 1, 0, 0, 0, 0, 1]
        result["g_Time"] = [1.7]
        result["g_Daytime"] = [0.4]
        for slot in 0..<16 { result["g_Texture\(slot)Resolution"] = [w, h, w, h] }
        return result
    }

    func bytes(_ layout: UniformLayout?, _ values: [String: [Float]], into buffer: inout [UInt8]) {
        guard let layout else { return }
        if buffer.count < layout.size { buffer += [UInt8](repeating: 0, count: layout.size - buffer.count) }
        for (name, member) in layout.members {
            let own = name.hasSuffix(ShaderUniformDeclaration.fragmentSuffix) ? String(name.dropLast(ShaderUniformDeclaration.fragmentSuffix.count)) : name
            guard let value = values[own] ?? values[name] else { continue }
            UniformWriter.write(value, member: member, into: &buffer)
        }
    }

    func draw(_ pipeline: MTLRenderPipelineState, uniforms: [UInt8], textures: [Int: MTLTexture], into target: MTLTexture,
              commandBuffer: MTLCommandBuffer) {
        let pass = MTLRenderPassDescriptor()
        pass.colorAttachments[0].texture = target
        pass.colorAttachments[0].loadAction = .dontCare
        pass.colorAttachments[0].storeAction = .store
        guard let encoder = commandBuffer.makeRenderCommandEncoder(descriptor: pass) else { return }
        encoder.setRenderPipelineState(pipeline)
        var positions: [Float] = [-1, -1, 0, 1, -1, 0, -1, 1, 0, 1, 1, 0]
        var uvs: [Float] = [0, 0, 1, 0, 0, 1, 1, 1]
        var zeros = [Float](repeating: 0, count: 4)
        encoder.setVertexBytes(&positions, length: 48, index: EffectGraphRenderer.positionBuffer)
        encoder.setVertexBytes(&uvs, length: 32, index: EffectGraphRenderer.texCoordBuffer)
        encoder.setVertexBytes(&zeros, length: 16, index: EffectGraphRenderer.zeroBuffer)
        if !uniforms.isEmpty {
            encoder.setVertexBytes(uniforms, length: uniforms.count, index: 0)
            encoder.setFragmentBytes(uniforms, length: uniforms.count, index: 0)
        }
        for (slot, texture) in textures {
            encoder.setFragmentTexture(texture, index: slot)
            encoder.setFragmentSamplerState(sampler, index: slot)
            encoder.setVertexTexture(texture, index: slot)
            encoder.setVertexSamplerState(sampler, index: slot)
        }
        encoder.drawPrimitives(type: .triangleStrip, vertexStart: 0, vertexCount: 4)
        encoder.endEncoding()
    }

    struct Prepared {
        let unfused: [(MTLRenderPipelineState, [UInt8], [Int: MTLTexture])]
        let fused: (MTLRenderPipelineState, [UInt8], [Int: MTLTexture])
    }

    func prepare(first: (ShaderPassFusion.Pass, ShaderFusionHalfTests.ChainPass), second: (ShaderPassFusion.Pass, ShaderFusionHalfTests.ChainPass),
                 plan: ShaderPassFusion.Plan, translator: ShaderVariantTranslator, middle: MTLTexture) throws -> Prepared {
        let a = try translator.variant(vertex: first.0.vertex, fragment: first.0.fragment, combos: first.0.combos)
        let b = try translator.variant(vertex: second.0.vertex, fragment: second.0.fragment, combos: second.0.combos)
        let aValues = values(first.0, first.1), bValues = values(second.0, second.1)
        var aBytes: [UInt8] = [], bBytes: [UInt8] = [], fusedBytes: [UInt8] = []
        bytes(a.uniforms, aValues, into: &aBytes)
        bytes(b.uniforms, bValues, into: &bBytes)
        bytes(plan.firstUniforms, aValues, into: &fusedBytes)
        bytes(plan.secondUniforms, bValues, into: &fusedBytes)
        if let size = plan.variant.uniforms?.size, fusedBytes.count < size { fusedBytes += [UInt8](repeating: 0, count: size - fusedBytes.count) }
        var aTextures: [Int: MTLTexture] = [0: input], bTextures: [Int: MTLTexture] = [0: middle], fusedTextures: [Int: MTLTexture] = [0: input]
        for slot in a.textureSlots where slot != 0 { aTextures[slot] = extra; fusedTextures[slot] = extra }
        for slot in b.textureSlots where slot != 0 {
            bTextures[slot] = extra
            if let fusedSlot = plan.secondTextureSlots[slot] { fusedTextures[fusedSlot] = extra }
        }
        return Prepared(unfused: [(try pipeline(a), aBytes, aTextures), (try pipeline(b), bBytes, bTextures)],
                        fused: (try pipeline(plan.variant), fusedBytes, fusedTextures))
    }

    func read(_ texture: MTLTexture) -> PerceptualImage {
        var bytes = [UInt8](repeating: 0, count: size.x * size.y * 4)
        texture.getBytes(&bytes, bytesPerRow: size.x * 4, from: MTLRegionMake2D(0, 0, size.x, size.y), mipmapLevel: 0)
        // Over black, as a frame is seen.
        for pixel in stride(from: 0, to: bytes.count, by: 4) {
            let alpha = Int(bytes[pixel + 3])
            for channel in 0..<3 { bytes[pixel + channel] = UInt8(Int(bytes[pixel + channel]) * alpha / 255) }
            bytes[pixel + 3] = 255
        }
        return PerceptualImage(width: size.x, height: size.y, rgba: bytes)
    }

    func compare(first: (ShaderPassFusion.Pass, ShaderFusionHalfTests.ChainPass), second: (ShaderPassFusion.Pass, ShaderFusionHalfTests.ChainPass),
                 plan: ShaderPassFusion.Plan, translator: ShaderVariantTranslator) throws -> (ssim: Double, maxDifference: Int) {
        let middle = try target(), unfusedOut = try target(), fusedOut = try target()
        let prepared = try prepare(first: first, second: second, plan: plan, translator: translator, middle: middle)
        let commandBuffer = try XCTUnwrap(queue.makeCommandBuffer())
        draw(prepared.unfused[0].0, uniforms: prepared.unfused[0].1, textures: prepared.unfused[0].2, into: middle, commandBuffer: commandBuffer)
        draw(prepared.unfused[1].0, uniforms: prepared.unfused[1].1, textures: prepared.unfused[1].2, into: unfusedOut, commandBuffer: commandBuffer)
        draw(prepared.fused.0, uniforms: prepared.fused.1, textures: prepared.fused.2, into: fusedOut, commandBuffer: commandBuffer)
        commandBuffer.commit()
        commandBuffer.waitUntilCompleted()
        let ssim = PerceptualCompare.ssim(read(unfusedOut), read(fusedOut))
        var unfusedBytes = [UInt8](repeating: 0, count: size.x * size.y * 4), fusedBytes = unfusedBytes
        unfusedOut.getBytes(&unfusedBytes, bytesPerRow: size.x * 4, from: MTLRegionMake2D(0, 0, size.x, size.y), mipmapLevel: 0)
        fusedOut.getBytes(&fusedBytes, bytesPerRow: size.x * 4, from: MTLRegionMake2D(0, 0, size.x, size.y), mipmapLevel: 0)
        let maxDifference = zip(unfusedBytes, fusedBytes).map { abs(Int($0) - Int($1)) }.max() ?? 0
        return (ssim, maxDifference)
    }

    /// Median GPU ms of the two passes and of the fused draw, alternated `rounds` times.
    func time(first: (ShaderPassFusion.Pass, ShaderFusionHalfTests.ChainPass), second: (ShaderPassFusion.Pass, ShaderFusionHalfTests.ChainPass),
              plan: ShaderPassFusion.Plan, translator: ShaderVariantTranslator, rounds: Int) throws -> (unfused: Double, fused: Double) {
        let descriptor = MTLTextureDescriptor.texture2DDescriptor(pixelFormat: .rgba8Unorm, width: size.x, height: size.y, mipmapped: false)
        descriptor.usage = [.renderTarget, .shaderRead]
        descriptor.storageMode = .private
        let middle = try XCTUnwrap(device.makeTexture(descriptor: descriptor))
        let out = try XCTUnwrap(device.makeTexture(descriptor: descriptor))
        let prepared = try prepare(first: first, second: second, plan: plan, translator: translator, middle: middle)
        var unfused: [Double] = [], fused: [Double] = []
        for round in 0..<(rounds + 3) {
            for mode in 0..<2 {
                let commandBuffer = try XCTUnwrap(queue.makeCommandBuffer())
                if mode == 0 {
                    draw(prepared.unfused[0].0, uniforms: prepared.unfused[0].1, textures: prepared.unfused[0].2, into: middle, commandBuffer: commandBuffer)
                    draw(prepared.unfused[1].0, uniforms: prepared.unfused[1].1, textures: prepared.unfused[1].2, into: out, commandBuffer: commandBuffer)
                } else {
                    draw(prepared.fused.0, uniforms: prepared.fused.1, textures: prepared.fused.2, into: out, commandBuffer: commandBuffer)
                }
                commandBuffer.commit()
                commandBuffer.waitUntilCompleted()
                guard round >= 3 else { continue }
                let ms = (commandBuffer.gpuEndTime - commandBuffer.gpuStartTime) * 1000
                if mode == 0 { unfused.append(ms) } else { fused.append(ms) }
            }
        }
        return (unfused.sorted()[unfused.count / 2], fused.sorted()[fused.count / 2])
    }
}

/// `SceneFrameHarness` with a translator of its own.
private final class TranslatorFrameHarness {
    let renderer: SceneMetalRenderer
    let view: MTKView
    let directory: URL
    let size: SIMD2<Int>
    var now: CFTimeInterval = 1000

    init(directory: URL, size: SIMD2<Int>, translator: ShaderVariantTranslator, screenID: String) throws {
        self.directory = directory
        self.size = size
        let project = try JSONDecoder().decode(WEProject.self, from: Data(contentsOf: directory.appending(path: "project.json")))
        let model = SceneWallpaperViewModel(wallpaper: WEWallpaper(using: project, where: directory), effectTranslator: translator)
        let device = try XCTUnwrap(MTLCreateSystemDefaultDevice())
        view = MTKView(frame: CGRect(x: 0, y: 0, width: size.x, height: size.y), device: device)
        view.colorPixelFormat = .bgra8Unorm
        view.framebufferOnly = false
        view.autoResizeDrawable = false
        view.drawableSize = CGSize(width: size.x, height: size.y)
        renderer = try XCTUnwrap(SceneMetalRenderer(view: view, scriptServices: nil, screenID: screenID))
        view.isPaused = true
        renderer.setPlacement(.stretch)
        renderer.scripts.frameWait = 5
        renderer.wallTime = { [unowned self] in self.now }
        renderer.setContent(try XCTUnwrap(model.metalContent()))
        let deadline = Date().addingTimeInterval(60)
        while !renderer.hasContent, Date() < deadline { RunLoop.main.run(until: Date().addingTimeInterval(0.01)) }
    }

    func close() {
        renderer.releaseContent()
        Fixtures.removeStoredSettings(for: directory)
    }

    func draw(step: Double) {
        now += step
        renderer.draw(in: view)
        renderer.lastCommandBuffer?.waitUntilCompleted()
        renderer.scripts.wallpaper?.waitUntilIdle()
        RunLoop.main.run(until: Date().addingTimeInterval(0.001))
    }

    var image: PerceptualImage {
        var bytes = [UInt8](repeating: 0, count: size.x * size.y * 4)
        view.currentDrawable?.texture.getBytes(&bytes, bytesPerRow: size.x * 4, from: MTLRegionMake2D(0, 0, size.x, size.y), mipmapLevel: 0)
        for pixel in stride(from: 0, to: bytes.count, by: 4) {
            bytes.swapAt(pixel, pixel + 2)
            bytes[pixel + 3] = 255
        }
        return PerceptualImage(width: size.x, height: size.y, rgba: bytes)
    }
}

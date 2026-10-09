import XCTest
@testable import OpenWallpaperEngine

/// The Swift text passes around glslang (prelude analysis, implicit-conversion fixups, the pair
/// rewriter): their fast paths must give exactly what the plain patterns give.
final class ShaderTextPassTests: XCTestCase {
    /// Every `.vert`/`.frag` in the bundled WE assets, includes inlined.
    private static func bundledSources() throws -> [ShaderSource] {
        // Resolved, so an assets folder reached through a symlink is still enumerated.
        let assets = ShaderVariantTests.weAssets.resolvingSymlinksInPath()
        let loader = ShaderSourceLoader(roots: [assets])
        guard let files = FileManager.default.enumerator(at: assets, includingPropertiesForKeys: nil) else { return [] }
        var sources: [ShaderSource] = []
        for case let url as URL in files {
            guard let stage = ShaderStage(rawValue: url.pathExtension) else { continue }
            let relative = String(url.path.dropFirst(assets.path.count + 1))
            do {
                sources.append(try loader.load(relative, stage: stage))
            } catch ShaderSourceError.missingInclude {
                continue // a header-only fragment of a shader; not loadable on its own
            }
        }
        return sources
    }

    /// The identifier prefilter never hides a declaration the full pattern would find.
    func testReservedLocalsMatchTheUnfilteredPatterns() throws {
        _ = try Fixtures.assets()
        let sources = try Self.bundledSources()
        XCTAssertGreaterThan(sources.count, 100)
        for source in sources {
            let analysis = ShaderPrelude.SourceAnalysis(source: source.text)
            let unfiltered = ShaderPrelude.cppReservedWords.subtracting(analysis.macros).sorted()
                .filter { ShaderPrelude.declaresLocal($0, in: source.text) }
            XCTAssertEqual(analysis.reservedLocals, unfiltered, source.path)
        }
    }

    func testIdentifierTokensAreMaximalASCIIRuns() {
        let tokens = ShaderPrelude.identifierTokens(in: "vec2 or=a_b1;é new\nthis")
        XCTAssertEqual(tokens, ["vec2", "or", "a_b1", "new", "this"])
    }

    /// Every copy of a source shares one analysis, and it equals the one from the text.
    func testSourceAnalysisIsComputedFromTheText() {
        let source = ShaderSource(stage: .fragment, path: "x.frag", text: "#define A 1\nfloat log10(float x) { return x; }\nvoid main() { vec2 or = vec2(0.0); }",
                                  combos: [], uniforms: [])
        let copy = source
        XCTAssertEqual(copy.preludeAnalysis.macros, ["A"])
        XCTAssertEqual(source.preludeAnalysis.functions, ["log10", "main"])
        XCTAssertEqual(source.preludeAnalysis.reservedLocals, ["or"])
        XCTAssertEqual(ShaderPrelude.text(for: .fragment, combos: ["X": 1], analysis: source.preludeAnalysis),
                       ShaderPrelude.text(for: .fragment, combos: ["X": 1], source: source.text))
    }

    /// Declarations go after `#version`/`#extension` and blank lines, as their own line: a
    /// varying the fragment stage reads and the vertex stage never writes.
    func testRewriterInsertsDeclarationsAfterTheHeader() {
        let vertex = "#version 450\n#extension GL_X : enable\n\nvoid main() { gl_Position = vec4(0.0); }"
        let result = ShaderPairRewriter.rewrite(vertex: vertex, fragment: "#version 450\nin vec2 v_X;\nvoid main() {}")
        XCTAssertTrue(result.vertex.hasPrefix("#version 450\n#extension GL_X : enable\n\nlayout(location = 0) out vec2 v_X;\n"),
                      result.vertex)
        XCTAssertFalse(result.vertex.contains("WEUniforms"), "loose uniforms are left to glslang's relaxed rules")
    }

    /// WE's GLSL backend leaves `HLSL`/`HLSL_SM30` undefined, so `#ifdef HLSL` branches (D3D
    /// screen-space flips and half-texel offsets) are not taken.
    func testPreludeLeavesHLSLUndefined() throws {
        let prelude = ShaderPrelude.text(for: .fragment, combos: [:])
        XCTAssertFalse(prelude.contains("#define HLSL"), prelude)
        let source = "#ifdef HLSL\nFLIPPED\n#endif\n#if HLSL_SM30\nSM30\n#endif\n"
        let text = try InProcessShaderCompiler().preprocess(prelude + source, stage: .fragment)
        XCTAssertFalse(text.contains("FLIPPED"))
        XCTAssertFalse(text.contains("SM30"))
    }
}

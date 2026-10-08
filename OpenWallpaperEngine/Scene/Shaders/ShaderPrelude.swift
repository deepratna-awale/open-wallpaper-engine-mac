import Foundation

/// The dialect shim prepended to every WE shader before glslang preprocesses it: the intrinsic and
/// type mapping of the HLSL front end (`HLSLFrontEnd`, rule 3).
///
/// WE writes GLSL with HLSL-isms (`frac`, `saturate`, `CAST3`, `float3`, ...). Names are mapped
/// with preprocessor macros and helper functions, never text replacement, so identifiers such as
/// `fract` or `sample` are left alone. `mul` and HLSL's implicit conversions depend on types, so
/// the front end's typed pass applies them to the preprocessed text (`fixupAfterPreprocess`).
enum ShaderPrelude {
    /// What the prelude needs to know about the shader it goes in front of. Depends on the source
    /// text only, so `ShaderSource` computes it once for all its variants.
    struct SourceAnalysis {
        /// Names the shader `#define`s.
        let macros: Set<String>
        /// Names the shader defines as functions.
        let functions: Set<String>
        /// C++ keywords the shader declares itself, sorted.
        let reservedLocals: [String]
        /// The shader reads a render target texel by texel (`texLoad2D`, `texSample2DBackBuffer`).
        let loadsTexels: Bool
        /// The shader discards with HLSL's `clip`.
        let clips: Bool
        /// The shader samples a volume texture (`texSample3D`, `ccsimple`'s LUT).
        let samplesVolumes: Bool
        /// The shader compares against a depth texture (`sampler2DComparison`, `texSample2DCompare`:
        /// the shadow atlas).
        let comparesDepth: Bool
        /// GLSL reserved words the shader uses as names (`GLSLReservedWords`), sorted.
        let glslReservedNames: [String]
        /// Every identifier the source names (comments and `// [COMBO]` declarations included).
        let identifiers: Set<Substring>

        init(source: String) {
            (macros, functions) = definedNames(in: source)
            // A declaration needs the name as a whole identifier, so only names that occur as one
            // are checked with the (much slower) declaration patterns.
            let identifiers = identifierTokens(in: source)
            self.identifiers = identifiers
            loadsTexels = Self.loadNames.contains { identifiers.contains(Substring($0)) }
            clips = identifiers.contains("clip")
            samplesVolumes = identifiers.contains("texSample3D")
            comparesDepth = identifiers.contains("texSample2DCompare") || identifiers.contains("sampler2DComparison")
            reservedLocals = cppReservedWords.subtracting(macros).sorted().filter { name in
                identifiers.contains(Substring(name)) && declaresLocal(name, in: source)
            }
            let skipped = macros.union(reservedLocals)
            glslReservedNames = GLSLReservedWords.used(in: source).filter { !skipped.contains($0) }
        }

        static let loadNames = ["texLoad2D", "texSample2DBackBuffer", "sampler2DBackBuffer"]
    }

    /// `source` is the shader the prelude goes in front of: a macro the shader defines itself (as a
    /// macro or a function, e.g. its own `M_PI` or `log10`) is left out, as WE has no such macro.
    static func text(for stage: ShaderStage, combos: [String: Int], source: String = "") -> String {
        text(for: stage, combos: combos, analysis: SourceAnalysis(source: source))
    }

    static func text(for stage: ShaderStage, combos: [String: Int], analysis: SourceAnalysis) -> String {
        var lines = ["#version 450"]
        // Resolved combos first so the shader's own `#ifndef X / #define X default` keeps them.
        for (name, value) in combos.sorted(by: { $0.key < $1.key }) {
            lines.append("#define \(name) \(value)")
        }
        let defined = analysis.macros.union(analysis.functions)
        lines.append(contentsOf: common.filter { line in
            macroName(line).map { !defined.contains($0) } ?? true
        })
        // A function named like a Metal built-in GLSL lacks (e.g. `log10`) becomes ambiguous
        // in MSL; rename the shader's own definition and every call to it.
        for name in metalOnlyBuiltins where analysis.functions.contains(name) && !analysis.macros.contains(name) {
            lines.append("#define \(name) we_\(name)")
        }
        // C++ keywords are valid GLSL names but not MSL ones (`vec2 or;`). Only names the shader
        // declares itself are renamed, never an interface name, which binds by name.
        for name in analysis.reservedLocals {
            lines.append("#define \(name) we_\(name)")
        }
        // GLSL reserves names WE's HLSL compiler accepts (`float common;`). These are renamed
        // everywhere, interface names included: both stages rename a varying alike, and the
        // uniform block is reflected back to WE's names (`GLSLReservedWords.originalName`).
        for name in analysis.glslReservedNames {
            lines.append("#define \(name) \(GLSLReservedWords.prefix)\(name)")
        }
        switch stage {
        case .vertex:
            lines.append(contentsOf: ["#define attribute in", "#define varying out"])
        case .fragment:
            lines.append(contentsOf: ["#define varying in", "#define gl_FragColor out_FragColor",
                                      "out vec4 out_FragColor;"])
        }
        lines.append(helperFunctions)
        if !defined.contains("texSample2D") {
            lines.append(sampleFunctions)
            // A bias only exists where derivatives do.
            if stage == .fragment {
                lines.append("vec4 texSample2D(sampler2D s, vec2 uv, float bias) { return texture(s, uv, bias); }")
            }
        }
        if analysis.loadsTexels { lines.append(loadFunctions) }
        if analysis.clips && stage == .fragment && !defined.contains("clip") { lines.append(clipFunctions) }
        if analysis.samplesVolumes && !defined.contains("texSample3D") { lines.append(volumeFunctions) }
        if analysis.comparesDepth && !defined.contains("texSample2DCompare") {
            lines.append(stage == .fragment ? compareFunctions : compareFunctionsWithoutDerivatives)
        }
        lines.append(moduloFunctions)
        lines.append(endMarker)
        return lines.joined(separator: "\n") + "\n"
    }

    /// `HLSL` and `HLSL_SM30` are left undefined, as WE's GLSL backend leaves them: shaders test
    /// them with `#ifdef` (screen-space UV flips, half-texel offsets for D3D9), and in an `#if`
    /// an undefined name is 0.
    /// Every identifier the prelude's own lines name: a combo they test would change a variant.
    static let commonIdentifiers = identifierTokens(in: common.joined(separator: "\n"))

    private static let common = [
        "#define GLSL 1",
        "#define highp",
        "#define mediump",
        "#define lowp",
        "#define frac(x) fract(x)",
        "#define lerp(x, y, a) mix(x, y, a)",
        "#define saturate(x) clamp(x, 0.0, 1.0)",
        "#define atan2(y, x) atan(y, x)",
        "#define fmod(x, y) ((x) - (y) * trunc((x) / (y)))",
        "#define log10(x) (log2(x) * 0.301029995663981)",
        "#define ddx(x) dFdx(x)",
        "#define ddy(x) dFdy(-(x))",
        "#define CAST2(x) (vec2(x))",
        "#define CAST3(x) (vec3(x))",
        "#define CAST4(x) (vec4(x))",
        "#define CAST3X3(x) (mat3(x))",
        "#define CASTF(x) (float(x))",
        "#define CASTI(x) (int(x))",
        "#define CASTU(x) (uint(x))",
        "#define float1 float",
        "#define float2 vec2",
        "#define float3 vec3",
        "#define float4 vec4",
        "#define int2 ivec2",
        "#define int3 ivec3",
        "#define int4 ivec4",
        // `sample` is a reserved word in GLSL 4.50 that WE shaders use as a variable name.
        "#define sample weSample",
        // common.h's constants, token-for-token, for shaders that use them without including it
        // (an identical redefinition is legal, a different one is an error).
        "#define M_PI 3.14159265359",
        "#define M_PI_HALF 1.57079632679",
        "#define M_PI_2 6.28318530718",
        "#define SQRT_2 1.41421356237",
        "#define SQRT_3 1.73205080756",
    ]

    private static func macroName(_ line: String) -> String? {
        guard line.hasPrefix("#define ") else { return nil }
        return line.dropFirst("#define ".count).prefix { $0.isLetter || $0.isNumber || $0 == "_" }.description
    }

    private static let definitionPattern = try! NSRegularExpression(
        pattern: #"(?m)^[ \t]*#[ \t]*define[ \t]+(\w+)|\b\w+[ \t]+(\w+)[ \t]*\([^;{}()]*\)\s*\{"#)

    /// Built-in in the Metal standard library but not in GLSL, so a shader may define its own.
    static let metalOnlyBuiltins = ["log10", "fmod", "rsqrt", "saturate", "fract2", "powr", "select", "median3"]

    /// C++ keywords (MSL is C++) that GLSL doesn't reserve. `not` is left out: it's a GLSL built-in.
    static let cppReservedWords: Set<String> = [
        "and", "or", "xor", "bitand", "bitor", "compl", "and_eq", "or_eq", "xor_eq", "not_eq",
        "template", "namespace", "this", "new", "delete", "operator", "class", "typename", "private",
        "public", "protected", "friend", "virtual", "register", "auto", "explicit", "mutable", "using",
        "typedef", "union", "enum", "extern", "static", "goto", "try", "catch", "throw", "sizeof",
        "alignas", "alignof", "decltype", "constexpr", "nullptr", "static_assert", "thread_local",
        "noexcept", "char", "short", "long", "signed", "unsigned", "wchar_t", "typeid", "export",
        "concept", "requires", "device", "constant", "thread", "threadgroup", "kernel", "vertex", "fragment",
    ]

    private static let interfacePattern = try! NSRegularExpression(
        pattern: #"(?m)^[ \t]*(?:uniform|varying|attribute|in|out)\b[^;]*;"#)

    /// Whether the shader declares `name` itself (a variable or function after a type), and not
    /// as a uniform, varying or attribute.
    static func declaresLocal(_ name: String, in source: String) -> Bool {
        guard let patterns = localPatterns[name] ?? makeLocalPatterns(name) else { return false }
        let whole = NSRange(source.startIndex..., in: source)
        guard patterns.declaration.firstMatch(in: source, range: whole) != nil else { return false }
        let declarations = interfacePattern.matches(in: source, range: whole)
        return !declarations.contains { match in
            patterns.interface.firstMatch(in: source, range: match.range) != nil
        }
    }

    /// A declaration of `name` after a type, and `name` declared in an interface statement.
    private typealias LocalPatterns = (declaration: NSRegularExpression, interface: NSRegularExpression)

    /// Compiled once; the names are fixed identifiers.
    private static let localPatterns: [String: LocalPatterns] = Dictionary(
        uniqueKeysWithValues: cppReservedWords.compactMap { name in makeLocalPatterns(name).map { (name, $0) } })

    private static func makeLocalPatterns(_ name: String) -> LocalPatterns? {
        do {
            return (try NSRegularExpression(pattern: #"\b\w+\s+"# + NSRegularExpression.escapedPattern(for: name) + #"\s*[=;,()\[]"#),
                    try NSRegularExpression(pattern: #"\b"# + NSRegularExpression.escapedPattern(for: name) + #"\s*[;\[]"#))
        } catch {
            OWELog.error(.shader, "Invalid declaration pattern for \(name): \(error)")
            return nil
        }
    }

    /// Every maximal run of ASCII identifier characters: a superset of the names a declaration
    /// pattern can match, found in one pass over the UTF-8 bytes.
    static func identifierTokens(in source: String) -> Set<Substring> {
        var tokens = Set<Substring>()
        let utf8 = source.utf8
        var start: String.Index?
        var index = utf8.startIndex
        while index != utf8.endIndex {
            let byte = utf8[index]
            let isWord = (byte >= 48 && byte <= 57) || (byte >= 65 && byte <= 90) || (byte >= 97 && byte <= 122) || byte == 95
            if isWord {
                if start == nil { start = index }
            } else if let tokenStart = start {
                tokens.insert(source[tokenStart..<index])
                start = nil
            }
            index = utf8.index(after: index)
        }
        if let tokenStart = start { tokens.insert(source[tokenStart...]) }
        return tokens
    }

    /// Names the shader `#define`s, and names it defines as functions.
    static func definedNames(in source: String) -> (macros: Set<String>, functions: Set<String>) {
        var macros = Set<String>(), functions = Set<String>()
        for match in definitionPattern.matches(in: source, range: NSRange(source.startIndex..., in: source)) {
            if let range = Range(match.range(at: 1), in: source) { macros.insert(String(source[range])) }
            if let range = Range(match.range(at: 2), in: source) { functions.insert(String(source[range])) }
        }
        return (macros, functions)
    }

    /// Helpers WE shaders call that neither dialect has. Scalar/vector mixes in built-in calls
    /// (`pow(v, 2)`, `max(0, v)`) are converted by the typed pass, not by overloads.
    private static let helperFunctions = """
    vec2 rotateVec2(vec4 v, float angle) { float s = sin(angle); float c = cos(angle); return vec2(v.x * c - v.y * s, v.x * s + v.y * c); }
    """

    /// WE's sampling functions. A wider coordinate truncates to the sampler's two by the typed
    /// pass's argument conversion, as HLSL's `Sample` truncates it.
    private static let sampleFunctions = """
    vec4 texSample2D(sampler2D s, vec2 uv) { return texture(s, uv); }
    vec4 texSample2DLod(sampler2D s, vec2 uv, float lod) { return textureLod(s, uv, lod); }
    vec4 texSample2DGrad(sampler2D s, vec2 uv, vec2 dx, vec2 dy) { return textureGrad(s, uv, dx, dy); }
    """

    /// WE's texel reads of a render target (`volumetricsfront` reads its depth targets so): the
    /// texel under `uv` of a `res`-sized target, unfiltered, as HLSL's `Load`. A back buffer is a
    /// plain texture here: the scene target isn't multisampled.
    private static let loadFunctions = """
    #define sampler2DBackBuffer sampler2D
    vec4 weLoad2D(sampler2D s, vec2 uv, vec2 res) { return texelFetch(s, clamp(ivec2(uv * res), ivec2(0), textureSize(s, 0) - 1), 0); }
    vec4 texLoad2D(sampler2D s, vec2 uv, vec2 res) { return weLoad2D(s, uv, res); }
    vec4 texSample2DBackBuffer(sampler2D s, vec2 uv, vec2 res) { return weLoad2D(s, uv, res); }
    """

    /// WE's volume sampling (`ccsimple` reads its colour LUT so). Only shaders that name
    /// `texSample3D` get it, so no other shader's translation changes.
    private static let volumeFunctions = """
    vec4 texSample3D(sampler3D s, vec3 uvw) { return texture(s, uvw); }
    vec4 texSample3DLod(sampler3D s, vec3 uvw, float lod) { return textureLod(s, uvw, lod); }
    """

    /// WE's depth comparison (`common_pbr_2.h`'s shadow lookups, `volumetricsfront`): a
    /// `sampler2DComparison` is D3D's comparison sampler over a depth texture, and
    /// `texSample2DCompare(s, uv, z)` its `SampleCmp`, 1 where `z` passes the sampler's test against
    /// the texel and 0 where it fails, filtered. As GLSL that is a shadow sampler, which SPIRV-Cross
    /// makes a Metal `depth2d` read with `sample_compare`; the test (WE's GREATER, reversed depth)
    /// is the bound sampler's (`SceneShadowAtlas.sampler`). Only shaders that name them get them.
    private static let compareFunctions = """
    #define sampler2DComparison sampler2DShadow
    vec4 texSample2DCompare(sampler2DShadow s, vec2 uv, float z) { return vec4(texture(s, vec3(uv, z))); }
    """

    /// The same where there are no derivatives: the base level.
    private static let compareFunctionsWithoutDerivatives = """
    #define sampler2DComparison sampler2DShadow
    vec4 texSample2DCompare(sampler2DShadow s, vec2 uv, float z) { return vec4(textureLod(s, vec3(uv, z), 0.0)); }
    """

    /// HLSL's `clip`: discards the fragment when any component is below zero.
    private static let clipFunctions = """
    void clip(float x) { if (x < 0.0) discard; }
    void clip(vec2 x) { if (any(lessThan(x, vec2(0.0)))) discard; }
    void clip(vec3 x) { if (any(lessThan(x, vec3(0.0)))) discard; }
    void clip(vec4 x) { if (any(lessThan(x, vec4(0.0)))) discard; }
    """

    /// The front end's rules for preprocessed text (`HLSLFrontEnd.afterPreprocess`): system
    /// values, scoping, HLSL's implicit conversions and `mul`.
    static func fixupAfterPreprocess(_ text: String) -> String {
        HLSLFrontEnd.afterPreprocess(text)
    }

    /// WE's shaders declare the system values they read and write like other interface
    /// variables: `shadowcaster.vert`'s `in uint gl_InstanceID;` and `varying uint
    /// gl_ViewportIndex;` (D3D's `SV_InstanceID` and `SV_ViewportArrayIndex`: each instance of a
    /// caster draws into one view of the shadow atlas). GLSL has them built in and forbids the
    /// declarations, so they are dropped, and writing the viewport index from the vertex stage
    /// takes `GL_ARB_shader_viewport_layer_array` (Metal's `[[viewport_array_index]]`).
    static func builtInDeclarations(_ text: String) -> String {
        let range = NSRange(text.startIndex..., in: text)
        guard builtInDeclarationPattern.firstMatch(in: text, range: range) != nil else { return text }
        var result = builtInDeclarationPattern.stringByReplacingMatches(in: text, range: range, withTemplate: "")
        if result.contains("gl_ViewportIndex"), let version = versionPattern.firstRange(in: result) {
            result.insert(contentsOf: "\n#extension GL_ARB_shader_viewport_layer_array : require", at: version.upperBound)
        }
        return result
    }

    private static let builtInDeclarationPattern = NSRegularExpression.shader(
        #"(?m)^[ \t]*(?:in|out)[ \t]+u?int[ \t]+gl_(?:InstanceID|VertexID|ViewportIndex)[ \t]*;"#)
    private static let versionPattern = NSRegularExpression.shader(#"(?m)^[ \t]*#[ \t]*version[^\n]*"#)
}

// MARK: - Helpers of the typed pass

extension ShaderPrelude {
    /// `weMod(x, y)`: HLSL's `%` on floats (`fmod`, truncating), which `HLSLConversionPass` writes
    /// for a float `%`. Integer `%` stays GLSL's.
    static let moduloFunctions: String = {
        var lines = ["float weMod(float x, float y) { return x - y * trunc(x / y); }"]
        for vector in ["vec2", "vec3", "vec4"] {
            lines.append("\(vector) weMod(\(vector) x, \(vector) y) { return x - y * trunc(x / y); }")
        }
        return lines.joined(separator: "\n")
    }()

    /// Ends the prelude in preprocessed text; the front end's rules apply only to the shader after it.
    static let endMarker = "void weEndOfPrelude() {}"
}

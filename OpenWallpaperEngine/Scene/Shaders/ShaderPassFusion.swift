import Foundation
import CryptoKit

/// Fuses two consecutive effect passes into one draw, when the translator can prove the second
/// reads the first's output only at its own pixel.
///
/// The proof, on the preprocessed GLSL (combos resolved):
/// - the second fragment stage reads `g_Texture0` only as `texSample2D(g_Texture0, v_TexCoord)` or
///   `….xy`, never assigns `v_TexCoord`, and names nothing else of slot 0 (no resolution, no LOD,
///   no gather, no neighbour);
/// - the second vertex stage sets `v_TexCoord.xy` to `a_TexCoord.xy` and nothing else, and places
///   the quad with the same statement as the first;
/// - the first fragment stage never discards (a discarded pixel would keep the target's old value).
///
/// The renderer adds what only it knows: both passes draw the full quad into targets of the same
/// size, the first pass's target is RGBA8 (the fused pair clamps and rounds its colour as that
/// target stores it), the first overwrites (no blending), and nothing else reads its target: no
/// later pass, FBO binding or static-chain cache.
///
/// The fused pair runs the first pass's `main` as a function, renamed with `firstPrefix` together
/// with everything the first pass declares at file scope (uniforms, varyings, functions, globals),
/// and the second pass's `main` reads its colour instead of sampling slot 0. The first pass keeps
/// its texture slots; the second's other slots follow them (`secondTextureSlots`).
enum ShaderPassFusion {
    /// Prefix of every name the first pass contributes (uniform members too).
    static let firstPrefix = "weFusedA_"

    struct Pass {
        let vertex: ShaderSource
        let fragment: ShaderSource
        let combos: [String: Int]
    }

    /// One fused draw for two passes.
    struct Plan: Codable {
        /// The fused shaders. Uniform members of the first pass carry `firstPrefix`.
        let variant: TranslatedShaderVariant
        /// The first pass's uniforms in the fused block, by the first pass's own names.
        let firstUniforms: UniformLayout?
        /// The second pass's uniforms in the fused block, by its own names.
        let secondUniforms: UniformLayout?
        /// The second pass's texture slot → the fused slot it is bound at. Slot 0 (the first
        /// pass's output) has none; the first pass's slots are unchanged.
        let secondTextureSlots: [Int: Int]
    }

    /// Why a pair isn't fused; for logs and tests.
    enum Refusal: Error, Equatable {
        case readsInputElsewhere
        case movesTexCoord
        case differentPlacement
        case firstDiscards
        case tooManyTextures
        case conflictingAttribute(String)
    }

    // MARK: - Proof

    private static let pointwiseRead = NSRegularExpression.shader(
        #"\btexSample2D\s*\(\s*g_Texture0\s*,\s*v_TexCoord(?:\s*\.\s*xy)?\s*\)"#)
    private static let slotZeroDeclaration = NSRegularExpression.shader(
        #"(?m)^[ \t]*uniform\s+(?:(?:lowp|mediump|highp)\s+)?sampler2D\s+g_Texture0\s*;[ \t]*\n?"#)
    private static let positionStatement = NSRegularExpression.shader(#"\bgl_Position\s*=[^;]*;"#)

    /// Whether the second pass's stages read slot 0 only at the pixel they draw (`fragment` and
    /// `vertex` preprocessed). nil when they do; the refusal otherwise.
    static func refusalForSecond(vertex: String, fragment: String) -> Refusal? {
        let tokens = GLSLTokens(fragment)
        let reads = pointwiseRead.matches(in: fragment, range: NSRange(fragment.startIndex..., in: fragment)).count
        let declarations = slotZeroDeclaration.matches(in: fragment, range: NSRange(fragment.startIndex..., in: fragment)).count
        let uses = tokens.identifiers.filter { $0 == "g_Texture0" }.count
        guard reads > 0, declarations == 1, uses == reads + declarations else { return .readsInputElsewhere }
        guard !tokens.identifiers.contains(where: { $0.hasPrefix("g_Texture0") && $0 != "g_Texture0" }),
              !GLSLTokens(vertex).identifiers.contains(where: { $0.hasPrefix("g_Texture0") }) else {
            return .readsInputElsewhere
        }
        // Only `main` reads it: the first pass's colour is in scope there.
        guard let main = fragment.range(of: #"(?m)^[ \t]*void\s+main\s*\("#, options: .regularExpression),
              let firstRead = pointwiseRead.firstMatch(in: fragment, range: NSRange(fragment.startIndex..., in: fragment))
                .flatMap({ Range($0.range, in: fragment) }), firstRead.lowerBound > main.lowerBound else {
            return .readsInputElsewhere
        }
        guard !ShaderPairRewriter.isAssigned("v_TexCoord", in: fragment),
              !ShaderPairRewriter.isAssigned("a_TexCoord", in: vertex),
              texCoordIsPassedThrough(vertex) else { return .movesTexCoord }
        return nil
    }

    /// Every write to `v_TexCoord`'s x or y in `vertex` copies `a_TexCoord`'s, and one does.
    static func texCoordIsPassedThrough(_ vertex: String) -> Bool {
        let tokens = GLSLTokens(vertex).tokens
        var copiesXY = false
        var index = 0
        while index < tokens.count {
            defer { index += 1 }
            guard tokens[index] == "v_TexCoord", index == 0 || tokens[index - 1] != "." else { continue }
            var cursor = index + 1
            var swizzle = "xyzw"
            if cursor + 1 < tokens.count, tokens[cursor] == "." {
                swizzle = tokens[cursor + 1]
                cursor += 2
            }
            guard cursor < tokens.count else { return false }
            let op = tokens[cursor]
            if ["=", "+=", "-=", "*=", "/=", "++", "--"].contains(op) {
                let touchesXY = swizzle.contains("x") || swizzle.contains("y") || swizzle.contains("r") || swizzle.contains("g")
                guard touchesXY else { continue }
                guard op == "=", let end = tokens[(cursor + 1)...].firstIndex(of: ";") else { return false }
                let value = tokens[(cursor + 1)..<end].joined()
                let accepted: Set<String>
                switch swizzle {
                case "xyzw": accepted = ["a_TexCoord", "a_TexCoord.xy", "a_TexCoord.xyxy"]
                case "xy": accepted = ["a_TexCoord", "a_TexCoord.xy"]
                default: return false
                }
                guard accepted.contains(value) else { return false }
                copiesXY = true
                continue
            }
            // Handed to a function, whose parameter could be `out`.
            if index > 0, ["(", ","].contains(tokens[index - 1]), swizzle == "xyzw", [")", ","].contains(op) { return false }
        }
        return copiesXY
    }

    // MARK: - Fusion

    /// The fused stages of `first` then `second` (both preprocessed and fixed up), or the refusal.
    static func fuseSources(first: (vertex: String, fragment: String), second: (vertex: String, fragment: String))
        -> Result<(vertex: String, fragment: String, textureMap: [Int: Int]), Refusal> {
        if let refusal = refusalForSecond(vertex: second.vertex, fragment: second.fragment) { return .failure(refusal) }
        guard !GLSLTokens(first.fragment).identifiers.contains("discard") else { return .failure(.firstDiscards) }
        func placement(_ text: String) -> [String] {
            positionStatement.matches(in: text, range: NSRange(text.startIndex..., in: text))
                .map { (text as NSString).substring(with: $0.range).filter { !$0.isWhitespace } }
        }
        let firstPlacement = placement(first.vertex)
        guard firstPlacement.count == 1, firstPlacement == placement(second.vertex) else { return .failure(.differentPlacement) }

        // Texture slots: the first pass's stay; the second's others follow the highest of them.
        let firstSlots = samplerSlots(first.fragment).union(samplerSlots(first.vertex))
        let secondSlots = samplerSlots(second.fragment).union(samplerSlots(second.vertex)).subtracting([0])
        var map: [Int: Int] = [:]
        var next = (firstSlots.max() ?? 0) + 1
        for slot in secondSlots.sorted() {
            map[slot] = next
            next += 1
        }
        guard next <= 16 else { return .failure(.tooManyTextures) }

        // First pass: vertex attributes stay shared; everything else it declares is renamed.
        let secondAttributes = attributes(second.vertex)
        for name in attributes(first.vertex).keys where ShaderPairRewriter.isAssigned(name, in: first.vertex) {
            return .failure(.conflictingAttribute(name))
        }
        for (name, type) in attributes(first.vertex) where secondAttributes[name].map({ $0 != type }) == true {
            return .failure(.conflictingAttribute(name))
        }
        let firstVertex = renamedFirst(first.vertex, stage: .vertex, dropAttributes: Set(secondAttributes.keys),
                                       second: second.vertex)
        let firstFragment = renamedFirst(first.fragment, stage: .fragment, dropAttributes: [], second: second.fragment)
        let output = firstPrefix + "out_FragColor"
        let fragmentBody = firstFragment.body.replacingOccurrences(
            of: NSRegularExpression.shader(#"\bout\s+vec4\s+"# + output + #"\s*;"#), with: "vec4 \(output);")

        // Second pass: slot 0 reads become the first pass's colour; other slots move.
        var secondFragment = slotZeroDeclaration.stringByReplacingMatches(
            in: second.fragment, range: NSRange(second.fragment.startIndex..., in: second.fragment), withTemplate: "")
        secondFragment = pointwiseRead.stringByReplacingMatches(
            in: secondFragment, range: NSRange(secondFragment.startIndex..., in: secondFragment), withTemplate: output)
        secondFragment = GLSLTokens.rename(secondFragment) { map[slotOf($0) ?? -1].map { "g_Texture\($0)" } }
        let secondVertex = GLSLTokens.rename(second.vertex) { map[slotOf($0) ?? -1].map { "g_Texture\($0)" } }

        guard let vertex = combine(header: firstVertex.header, firstBody: firstVertex.body, second: secondVertex,
                                   call: firstPrefix + "main();"),
              let fragment = combine(header: firstFragment.header, firstBody: fragmentBody, second: secondFragment,
                                     call: firstPrefix + "main(); " + storeAsUnorm8(output)) else { return .failure(.readsInputElsewhere) }
        return .success((vertex, fragment, map))
    }

    /// What storing `name` in the RGBA8 intermediate and reading it back does: clamp to 0…1 and
    /// round to 8 bits. Without it the fused pair would be more precise than the two passes, and
    /// would keep values outside 0…1 the target clamps.
    private static func storeAsUnorm8(_ name: String) -> String {
        "\(name) = floor(clamp(\(name), 0.0, 1.0) * 255.0 + 0.5) / 255.0;"
    }

    private static func slotOf(_ identifier: String) -> Int? {
        guard identifier.hasPrefix("g_Texture") else { return nil }
        return Int(identifier.dropFirst("g_Texture".count))
    }

    private static let samplerDeclaration = NSRegularExpression.shader(
        #"(?m)^[ \t]*uniform\s+(?:(?:lowp|mediump|highp)\s+)?sampler\w*\s+g_Texture(\d+)\s*;"#)

    private static func samplerSlots(_ text: String) -> Set<Int> {
        Set(samplerDeclaration.matches(in: text, range: NSRange(text.startIndex..., in: text)).compactMap {
            Range($0.range(at: 1), in: text).flatMap { Int(text[$0]) }
        })
    }

    private static let attributeDeclaration = NSRegularExpression.shader(
        #"(?m)^[ \t]*in\s+(?:(?:lowp|mediump|highp)\s+)?(\w+)\s+(\w+)\s*;[ \t]*\n?"#)

    /// The vertex stage's inputs, name → type.
    private static func attributes(_ vertex: String) -> [String: String] {
        var result: [String: String] = [:]
        for match in attributeDeclaration.matches(in: vertex, range: NSRange(vertex.startIndex..., in: vertex)) {
            let ns = vertex as NSString
            result[ns.substring(with: match.range(at: 2))] = ns.substring(with: match.range(at: 1))
        }
        return result
    }

    /// Header lines (`#version`, `#extension`) and the rest, with every file-scope name the pass
    /// declares prefixed, except vertex inputs and `g_TextureN` samplers. Inputs the second pass
    /// also declares are dropped (`dropAttributes`).
    private static func renamedFirst(_ text: String, stage: ShaderStage, dropAttributes: Set<String>, second: String)
        -> (header: [String], body: String) {
        var header: [String] = []
        var body = ""
        for line in text.split(separator: "\n", omittingEmptySubsequences: false) {
            let trimmed = line.trimmingCharacters(in: .whitespaces)
            if trimmed.hasPrefix("#version") { continue }
            if trimmed.hasPrefix("#extension") { header.append(trimmed); continue }
            body += line + "\n"
        }
        var inputs = Set<String>()
        if stage == .vertex {
            inputs = Set(attributes(body).keys)
            body = attributeDeclaration.stringByReplacingMatches(in: body, range: NSRange(body.startIndex..., in: body),
                                                                 withTemplate: "") // re-added below when needed
            let kept = attributes(text).filter { !dropAttributes.contains($0.key) }
            body = kept.sorted { $0.key < $1.key }.map { "in \($0.value) \($0.key);\n" }.joined() + body
        }
        // Functions both stages define alike (the prelude's, shared headers') are kept once, from
        // the second pass, under their own names; so are the prelude's overloads of GLSL's own
        // functions, which can't be renamed.
        let secondFunctions = Set(topLevelFunctions(second).map(\.normalized))
        let functions = topLevelFunctions(body)
        var shared = Set<String>()
        var drop: [Range<String.Index>] = []
        for name in Set(functions.map(\.name)) where name != "main" {
            let definitions = functions.filter { $0.name == name }
            let duplicated = definitions.filter { secondFunctions.contains($0.normalized) }
            guard duplicated.count == definitions.count || builtinFunctions.contains(name) else { continue }
            shared.insert(name)
            drop += duplicated.map(\.range)
        }
        for range in drop.sorted(by: { $0.lowerBound > $1.lowerBound }) { body.removeSubrange(range) }
        let declared = GLSLTokens(body).fileScopeNames().subtracting(inputs).subtracting(shared)
            .filter { slotOf($0) == nil || !isSampler($0, in: body) }
        body = GLSLTokens.rename(body) { declared.contains($0) ? firstPrefix + $0 : nil }
        return (header, body)
    }

    /// GLSL's own functions, which the prelude overloads for HLSL's argument forms.
    private static let builtinFunctions: Set<String> = [
        "abs", "acos", "asin", "atan", "ceil", "clamp", "cos", "cross", "degrees", "distance", "dot", "exp", "exp2",
        "floor", "fract", "inversesqrt", "length", "log", "log2", "max", "min", "mix", "mod", "normalize", "pow",
        "radians", "reflect", "refract", "round", "sign", "sin", "smoothstep", "sqrt", "step", "tan", "texture",
        "textureLod", "transpose", "determinant", "inverse", "sinh", "cosh", "tanh", "trunc", "fma",
    ]

    /// File-scope function definitions: name, range (header to closing brace) and the text with
    /// whitespace removed, to compare definitions.
    static func topLevelFunctions(_ text: String) -> [(name: String, range: Range<String.Index>, normalized: String)] {
        var result: [(name: String, range: Range<String.Index>, normalized: String)] = []
        var index = text.startIndex
        var statementStart = text.startIndex
        var atLineStart = true
        while index < text.endIndex {
            let character = text[index]
            if atLineStart, character == "#" {
                let end = text[index...].firstIndex(of: "\n") ?? text.endIndex
                index = end
                statementStart = end
                continue
            }
            atLineStart = character == "\n" || (atLineStart && (character == " " || character == "\t"))
            if character == ";" || character == "}" {
                statementStart = text.index(after: index)
            } else if character == "{" {
                let header = text[statementStart..<index].trimmingCharacters(in: .whitespacesAndNewlines)
                // The matching brace.
                var depth = 0
                var close = index
                while close < text.endIndex {
                    if text[close] == "{" { depth += 1 }
                    if text[close] == "}" { depth -= 1; if depth == 0 { break } }
                    close = text.index(after: close)
                }
                guard close < text.endIndex else { break }
                let end = text.index(after: close)
                if header.hasSuffix(")"), let paren = header.firstIndex(of: "("),
                   let name = header[..<paren].split(whereSeparator: { $0 == " " || $0 == "\t" || $0 == "\n" }).last {
                    let range = statementStart..<end
                    result.append((String(name), range, text[range].filter { !$0.isWhitespace }))
                }
                index = end
                statementStart = end
                continue
            }
            index = text.index(after: index)
        }
        return result
    }

    private static func isSampler(_ name: String, in text: String) -> Bool {
        NSRegularExpression.shader(#"\bsampler\w*\s+"# + name + #"\b"#).matches(text)
    }

    /// `second` with the first pass's extensions after its header, `firstBody` just before its
    /// `main`, and `call` at the start of `main`.
    private static func combine(header: [String], firstBody: String, second: String, call: String) -> String? {
        guard let main = second.range(of: #"(?m)^[ \t]*void\s+main\s*\(\s*(?:void)?\s*\)\s*\{"#, options: .regularExpression) else {
            return nil
        }
        var result = second
        result.insert(contentsOf: "\n\(call)\n", at: main.upperBound)
        result.insert(contentsOf: firstBody + "\n", at: main.lowerBound)
        var lines = result.split(separator: "\n", omittingEmptySubsequences: false).map(String.init)
        var insertAt = 0
        while insertAt < lines.count {
            let trimmed = lines[insertAt].trimmingCharacters(in: .whitespaces)
            guard trimmed.hasPrefix("#version") || trimmed.hasPrefix("#extension") || trimmed.isEmpty else { break }
            insertAt += 1
        }
        let existing = Set(lines.prefix(insertAt).map { $0.trimmingCharacters(in: .whitespaces) })
        lines.insert(contentsOf: header.filter { !existing.contains($0) }, at: insertAt)
        return lines.joined(separator: "\n")
    }
}

// MARK: - Translation

extension ShaderVariantTranslator {
    /// The fused variant of `first` then `second`, or the reason the pair can't fuse. Cached like
    /// single variants.
    func fusedVariant(first: ShaderPassFusion.Pass, second: ShaderPassFusion.Pass)
        -> Result<ShaderPassFusion.Plan, Error> {
        let firstCombos = Self.effectiveCombos(vertex: first.vertex, fragment: first.fragment, combos: first.combos)
        let secondCombos = Self.effectiveCombos(vertex: second.vertex, fragment: second.fragment, combos: second.combos)
        let key = Self.fusedCacheKey(first: Self.cacheKey(vertex: first.vertex, fragment: first.fragment,
                                                          combos: firstCombos, toolchain: toolchainFingerprint),
                                     second: Self.cacheKey(vertex: second.vertex, fragment: second.fragment,
                                                           combos: secondCombos, toolchain: toolchainFingerprint))
        if let cached = cachedFusion(key) { return cached }
        let result: Result<ShaderPassFusion.Plan, Error>
        do {
            result = .success(try translateFused(first: first, firstCombos: firstCombos,
                                                 second: second, secondCombos: secondCombos))
        } catch {
            result = .failure(error)
        }
        storeFusion(key, result)
        return result
    }

    static func fusedCacheKey(first: String, second: String) -> String {
        SHA256.hash(data: Data("fused\u{0}\(first)\u{0}\(second)".utf8)).map { String(format: "%02x", $0) }.joined()
    }

    private func translateFused(first: ShaderPassFusion.Pass, firstCombos: [String: Int],
                                second: ShaderPassFusion.Pass, secondCombos: [String: Int]) throws -> ShaderPassFusion.Plan {
        func preprocessed(_ source: ShaderSource, _ combos: [String: Int]) throws -> String {
            let text = ShaderPrelude.text(for: source.stage, combos: combos, analysis: source.preludeAnalysis)
                + source.text(combos: combos)
            return ShaderPrelude.fixupAfterPreprocess(try compiler.preprocess(text, stage: source.stage))
        }
        let firstVertex = try preprocessed(first.vertex, firstCombos)
        let firstFragment = try preprocessed(first.fragment, firstCombos)
        let secondVertex = try preprocessed(second.vertex, secondCombos)
        let secondFragment = try preprocessed(second.fragment, secondCombos)
        let fused = try ShaderPassFusion.fuseSources(first: (firstVertex, firstFragment),
                                                     second: (secondVertex, secondFragment)).get()
        let prefix = ShaderPassFusion.firstPrefix
        let stageLocal = ShaderUniformDeclaration.stageLocalNames(vertex: second.vertex.uniforms, fragment: second.fragment.uniforms)
            .union(ShaderUniformDeclaration.stageLocalNames(vertex: first.vertex.uniforms, fragment: first.fragment.uniforms)
                .map { prefix + $0 })
        let pair = ShaderPairRewriter.rewrite(vertex: fused.vertex, fragment: fused.fragment, stageLocal: stageLocal)
        let label = "fused \(first.fragment.path) → \(second.fragment.path)"
        let vertexOut: (msl: String, reflection: Data)
        let fragmentOut: (msl: String, reflection: Data)
        do {
            vertexOut = try compiler.compileToMSL(pair.vertex, stage: .vertex)
        } catch {
            recordFusionFailure(label, stage: .vertex, text: pair.vertex, error: error)
            throw error
        }
        do {
            fragmentOut = try compiler.compileToMSL(pair.fragment, stage: .fragment)
        } catch {
            recordFusionFailure(label, stage: .fragment, text: pair.fragment, error: error)
            throw error
        }
        let layout = try Self.uniformLayout(from: fragmentOut.reflection) ?? Self.uniformLayout(from: vertexOut.reflection)
        var combos = secondCombos
        for (name, value) in firstCombos { combos[prefix + name] = value }
        let variant = TranslatedShaderVariant(vertexMSL: vertexOut.msl,
                                              fragmentMSL: halfOutputs ? ShaderHalfPrecision.rewriteFragmentOutputs(fragmentOut.msl) : fragmentOut.msl,
                                              uniforms: layout, textureSlots: pair.textureSlots,
                                              attributes: pair.attributes, combos: combos)
        func split(_ keep: (String) -> String?) -> UniformLayout? {
            guard let layout else { return nil }
            var members: [String: UniformMember] = [:]
            for (name, member) in layout.members {
                guard let own = keep(name) else { continue }
                members[own] = UniformMember(name: own, type: member.type, offset: member.offset, count: member.count,
                                             arrayStride: member.arrayStride, matrixStride: member.matrixStride)
            }
            return members.isEmpty ? nil : UniformLayout(size: layout.size, members: members)
        }
        return ShaderPassFusion.Plan(
            variant: variant,
            firstUniforms: split { $0.hasPrefix(prefix) ? String($0.dropFirst(prefix.count)) : nil },
            secondUniforms: split { $0.hasPrefix(prefix) ? nil : $0 },
            secondTextureSlots: fused.textureMap)
    }

    private func recordFusionFailure(_ label: String, stage: ShaderStage, text: String, error: Error) {
        guard let failureDirectory else { return }
        let name = label.replacingOccurrences(of: "/", with: "_").replacingOccurrences(of: " ", with: "") + "." + stage.rawValue
        let url = failureDirectory.appending(path: name)
        let trailer = "\(error)".split(separator: "\n").map { "// \($0)" }.joined(separator: "\n")
        do {
            try FileManager.default.createDirectory(at: failureDirectory, withIntermediateDirectories: true)
            try (text + "\n" + trailer + "\n").write(to: url, atomically: true, encoding: .utf8)
            OWELog.error(.shader, "Shader pair \(label) failed to fuse; its source is at \(url.path)")
        } catch {
            OWELog.error(.shader, "Could not write the failed shader \(url.path): \(error)")
        }
    }
}

// MARK: - Tokens

/// A preprocessed GLSL text as tokens: identifiers, numbers, operators and punctuation. Only what
/// fusion needs: renaming identifiers and finding the names a file declares at file scope.
struct GLSLTokens {
    let tokens: [String]

    init(_ text: String) {
        tokens = Self.scan(text).map { String(text.utf8[$0.range]) ?? "" }
    }

    var identifiers: [String] { tokens.filter { $0.first.map { $0 == "_" || $0.isLetter } == true } }

    private struct Token { let range: Range<String.UTF8View.Index>; let isIdentifier: Bool }

    private static func scan(_ text: String) -> [Token] {
        var result: [Token] = []
        let utf8 = text.utf8
        var index = utf8.startIndex
        func isWord(_ byte: UInt8) -> Bool {
            (byte >= 0x30 && byte <= 0x39) || (byte >= 0x41 && byte <= 0x5A) || (byte >= 0x61 && byte <= 0x7A) || byte == 0x5F
        }
        while index < utf8.endIndex {
            let byte = utf8[index]
            if byte == 0x20 || byte == 0x09 || byte == 0x0A || byte == 0x0D {
                index = utf8.index(after: index)
                continue
            }
            // A preprocessor line (`#version`, `#extension`, `#line`) is one token.
            if byte == UInt8(ascii: "#") {
                let end = utf8[index...].firstIndex(of: 0x0A) ?? utf8.endIndex
                result.append(Token(range: index..<end, isIdentifier: false))
                index = end
                continue
            }
            let start = index
            if isWord(byte) {
                let isNumber = byte >= 0x30 && byte <= 0x39
                while index < utf8.endIndex, isWord(utf8[index]) || (isNumber && utf8[index] == UInt8(ascii: ".")) {
                    index = utf8.index(after: index)
                }
                result.append(Token(range: start..<index, isIdentifier: !isNumber))
                continue
            }
            index = utf8.index(after: index)
            if index < utf8.endIndex {
                let pair = [byte, utf8[index]]
                let two: Set<[UInt8]> = ["+=", "-=", "*=", "/=", "==", "!=", "<=", ">=", "&&", "||", "++", "--", "<<", ">>"]
                    .reduce(into: []) { $0.insert(Array($1.utf8)) }
                if two.contains(pair) { index = utf8.index(after: index) }
            }
            result.append(Token(range: start..<index, isIdentifier: false))
        }
        return result
    }

    /// `text` with every identifier `rename` maps (not member accesses after `.`) replaced.
    static func rename(_ text: String, _ rename: (String) -> String?) -> String {
        var result = ""
        let utf8 = text.utf8
        var last = utf8.startIndex
        var previous = ""
        for token in scan(text) {
            let spelling = String(text.utf8[token.range]) ?? ""
            defer { previous = spelling }
            guard token.isIdentifier, previous != ".", let renamed = rename(spelling) else { continue }
            result += String(text.utf8[last..<token.range.lowerBound]) ?? ""
            result += renamed
            last = token.range.upperBound
        }
        result += String(text.utf8[last...]) ?? ""
        return result
    }

    private static let keywords: Set<String> = [
        "void", "bool", "int", "uint", "float", "double", "struct", "const", "uniform", "in", "out", "inout",
        "flat", "smooth", "noperspective", "centroid", "invariant", "precise", "highp", "mediump", "lowp",
        "precision", "layout", "return", "if", "else", "for", "while", "do", "switch", "case", "default",
        "break", "continue", "discard", "true", "false",
    ]

    /// Names declared at file scope: functions, globals, uniforms, varyings, structs.
    func fileScopeNames() -> Set<String> {
        var names = Set<String>()
        var depth = 0
        for (index, token) in tokens.enumerated() {
            switch token {
            case "{", "(", "[": depth += 1; continue
            case "}", ")", "]": depth -= 1; continue
            default: break
            }
            guard depth == 0, index > 0, Self.isIdentifier(token), !Self.isBuiltin(token) else { continue }
            let before = tokens[index - 1]
            let after = index + 1 < tokens.count ? tokens[index + 1] : ""
            if before == "struct" { names.insert(token); continue }
            guard Self.isIdentifier(before) || before == "]", ["(", ";", "=", "[", ","].contains(after) else { continue }
            names.insert(token)
        }
        // A declaration list's later names: `float a, b;` at file scope.
        return names
    }

    private static func isIdentifier(_ token: String) -> Bool {
        token.first.map { $0 == "_" || $0.isLetter } == true
    }

    private static let builtinType = NSRegularExpression.shader(
        #"^(?:[biud]?vec[234]|d?mat[234](?:x[234])?|[iu]?sampler\w*|[iu]?texture\w*|[iu]?image\w*|gl_\w*)$"#)

    private static func isBuiltin(_ token: String) -> Bool {
        keywords.contains(token) || builtinType.matches(token)
    }
}

private extension String {
    func replacingOccurrences(of pattern: NSRegularExpression, with template: String) -> String {
        pattern.stringByReplacingMatches(in: self, range: NSRange(startIndex..., in: self), withTemplate: template)
    }
}

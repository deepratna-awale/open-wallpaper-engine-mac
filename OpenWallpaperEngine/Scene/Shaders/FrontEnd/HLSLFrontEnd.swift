import Foundation

/// The front end that turns a WE shader stage into GLSL glslang accepts, by WE's own rules.
///
/// WE writes its shaders in GLSL syntax with HLSL's intrinsics and compiles them as HLSL:
/// `wallpaper64.exe` prepends `#define vec2 float2`, `#define mix lerp`,
/// `#define mod(x, y) ((x)-(y)*floor((x)/(y)))`, the `CAST*` C-style casts and the `texSample*`
/// mappings (0x486b10–0x487000), turns the interface into `VS_INPUT`/`VS_OUTPUT` structs and a
/// cbuffer, and calls `D3DCompile` (FXC, `d3dcompiler_47.dll`). So the semantics a shader relies
/// on are FXC's, and this front end applies them as rules, in order:
///
/// 1. **Includes and requires** (`ShaderSourceLoader.inlineIncludes`, `expandRequires`): headers
///    from the wallpaper's `shaders/` then WE's; `#require LightingV1` is WE's generated source.
/// 2. **Combos** (`ShaderVariantTranslator.resolveCombos`): `#define`s ahead of the source.
/// 3. **Intrinsic and type mapping** (`ShaderPrelude`): HLSL's names as GLSL macros and helpers
///    (`frac`, `lerp`, `saturate`, `float3`, `CAST3`, `texSample2D`, `clip`, …).
/// 4. **System values** (`builtInDeclarations`): declarations of `gl_InstanceID` and friends,
///    which HLSL declares as inputs, are dropped.
/// 5. **Scoping** (`loopBodyScopes`): HLSL lets a loop body redeclare the loop variable.
/// 6. **Implicit conversions and promotions** (`HLSLConversionPass`), typed: assignments,
///    initialisers, returns and arguments convert to their target (a scalar splats, a wider vector
///    truncates, kinds convert), operands of different vector sizes truncate to the narrower,
///    bools take part in arithmetic as 0 or 1, numbers are tested against zero, `%` on floats is
///    `fmod`, float subscripts truncate, intrinsics bring their arguments to one type, and HLSL's
///    component-wise vector comparisons become GLSL's functions.
/// 7. **`mul`** (`HLSLConversionPass.multiply`): operands swap for GLSL's column vectors, wider
///    vectors truncate, and a vector times a vector is a dot product. A `mul` the typed pass
///    couldn't reach still swaps (`expandRemainingMul`).
enum HLSLFrontEnd {
    /// Rules 4–7 on a preprocessed stage whose prelude ends with `ShaderPrelude.endMarker`.
    static func afterPreprocess(_ text: String) -> String {
        let declared = ShaderPrelude.builtInDeclarations(text)
        let preludeEnd = endOfPrelude(in: declared)
        let scoped = String(declared.prefix(preludeEnd)) + loopBodyScopes(String(declared.dropFirst(preludeEnd)))
        let converted = HLSLConversionPass.apply(to: scoped, editableFrom: endOfPrelude(utf16In: scoped))
        return expandRemainingMul(converted)
    }

    private static let endMarkerPattern = NSRegularExpression.shader(#"void\s+weEndOfPrelude\s*\(\s*\)\s*\{\s*\}"#)

    /// Characters before the end of the prelude (0 without one).
    static func endOfPrelude(in text: String) -> Int {
        guard let range = endMarkerPattern.firstRange(in: text) else { return 0 }
        return text.distance(from: text.startIndex, to: range.upperBound)
    }

    /// The same as a UTF-16 offset.
    static func endOfPrelude(utf16In text: String) -> Int {
        guard let range = endMarkerPattern.firstRange(in: text) else { return 0 }
        return text.utf16.distance(from: text.utf16.startIndex, to: range.upperBound)
    }

    // MARK: - Scoping

    private static let loopHeaderPattern = NSRegularExpression.shader(#"\bfor\s*\(\s*\w+\s+(\w+)\s*="#)

    /// `for (int s = …) { float s = …; … }`: HLSL scopes the loop variable outside the body, so the
    /// body may declare its own; the body's `s` becomes `s_weBody` from its declaration on.
    static func loopBodyScopes(_ text: String) -> String {
        var result = text
        for match in loopHeaderPattern.matches(in: text, range: NSRange(text.startIndex..., in: text)).reversed() {
            guard let nameRange = Range(match.range(at: 1), in: result),
                  let headerRange = Range(match.range, in: result),
                  let headerOpen = result[headerRange].firstIndex(of: "("),
                  let headerClose = matching(result, open: headerOpen),
                  let bodyOpen = result[result.index(after: headerClose)...].firstIndex(where: { !$0.isWhitespace }),
                  result[bodyOpen] == "{", let bodyClose = matching(result, open: bodyOpen) else { continue }
            let name = String(result[nameRange])
            let body = String(result[result.index(after: bodyOpen)..<bodyClose])
            let declaration = NSRegularExpression.shader(
                #"\b(?:float|int|uint|bool|[iub]?vec[234]|mat[234])\s+"# + NSRegularExpression.escapedPattern(for: name) + #"\b"#)
            guard let found = declaration.firstMatch(in: body, range: NSRange(body.startIndex..., in: body)),
                  let foundRange = Range(found.range, in: body) else { continue }
            let use = NSRegularExpression.shader(#"(?<![\w.])"# + NSRegularExpression.escapedPattern(for: name) + #"\b"#)
            let tail = String(body[foundRange.lowerBound...])
            let renamed = use.stringByReplacingMatches(in: tail, range: NSRange(tail.startIndex..., in: tail),
                                                       withTemplate: NSRegularExpression.escapedTemplate(for: name + "_weBody"))
            result.replaceSubrange(result.index(after: bodyOpen)..<bodyClose, with: body[..<foundRange.lowerBound] + renamed)
        }
        return result
    }

    /// The bracket closing the one at `open` (`(`/`{`).
    private static func matching(_ text: String, open: String.Index) -> String.Index? {
        let opening = text[open]
        let closing: Character = opening == "(" ? ")" : "}"
        var depth = 0
        var index = open
        while index < text.endIndex {
            if text[index] == opening { depth += 1 }
            if text[index] == closing {
                depth -= 1
                if depth == 0 { return index }
            }
            index = text.index(after: index)
        }
        return nil
    }

    // MARK: - mul

    /// `mul(a, b)` → `((b) * (a))` for every call the typed pass left (one in a statement it
    /// couldn't type), unless the shader defines its own `mul`.
    static func expandRemainingMul(_ text: String) -> String {
        guard text.contains("mul") else { return text }
        let code = Array(text.utf16)
        let tokens = GLSLTokenizer.tokens(code)
        var edits = HLSLEdits(editableFrom: endOfPrelude(utf16In: text))
        let definesMul = tokens.indices.contains { index in
            index > 0 && index + 1 < tokens.count && tokens[index].text == "mul" && tokens[index + 1].text == "("
                && tokens[index - 1].kind == .identifier && tokens[index - 1].text != "return"
        }
        guard !definesMul else { return text }
        var index = 0
        while index + 1 < tokens.count {
            defer { index += 1 }
            guard tokens[index].text == "mul", tokens[index + 1].text == "(",
                  index == 0 || tokens[index - 1].text != "." else { continue }
            // Arguments: the two top-level comma-separated ranges up to the matching `)`.
            var depth = 0
            var comma: Int?
            var close: Int?
            for inner in (index + 1)..<tokens.count {
                let token = tokens[inner].text
                if token == "(" || token == "[" || token == "{" { depth += 1 }
                if token == ")" || token == "]" || token == "}" {
                    depth -= 1
                    if depth == 0 { close = inner; break }
                }
                if token == ",", depth == 1 {
                    if comma != nil { comma = nil; break }
                    comma = inner
                }
            }
            guard let comma, let close, comma > index + 2, close > comma + 1 else { continue }
            let first = String(decoding: code[tokens[index + 2].start..<tokens[comma - 1].end], as: UTF16.self)
            let second = String(decoding: code[tokens[comma + 1].start..<tokens[close - 1].end], as: UTF16.self)
            edits.replace(tokens[index].start, tokens[close].end, "((\(second)) * (\(first)))")
            index = close
        }
        guard edits.count > 0 else { return text }
        // Nested calls inside an argument are expanded by another round.
        return expandRemainingMul(String(decoding: edits.apply(to: code), as: UTF16.self))
    }
}

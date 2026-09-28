import Foundation

/// Writes a translated fragment function's colour outputs as `half`.
///
/// Every colour attachment the scene renders into holds 16 bits or less a channel (8-bit unorm or
/// 16-bit float targets; the one 32-bit float texture, the volumetrics depth copy, is written by a
/// compute pass, not a fragment output). A `half` output is then exact for 16-bit float targets
/// and loses nothing for 8-bit ones (11 significant bits against 8), and the GPU writes half the
/// output registers. The shader's own math stays `float`: UVs, positions, time and anything that
/// feeds a texture coordinate keep full precision.
///
/// SPIRV-Cross declares each output in `main0_out` and writes it through `out.<name>` inside the
/// entry point. The rewrite keeps those writes on a `float` local and converts once, at every
/// `return out;`. A function it can't prove it understands (the output reached from another
/// function, or no `return out;`) is left as it is.
enum ShaderHalfPrecision {
    /// `OWE_SHADER_HALF=0` turns the rewrite off (benchmarks compare both). Part of the variant
    /// cache key (`ShaderVariantTranslator.halfOutputs`), so either setting reads only its own variants.
    static let isEnabled: Bool = ProcessInfo.processInfo.environment["OWE_SHADER_HALF"] != "0"

    private static let outputStruct = NSRegularExpression.shader(#"struct main0_out\s*\{([^}]*)\};"#)
    private static let colorMember = NSRegularExpression.shader(
        #"(?m)^(\s*)float([234]?) (\w+) \[\[color\((\d+)\)\]\];"#)
    private static let entryPoint = NSRegularExpression.shader(#"(?m)^fragment main0_out main0\("#)
    private static let outDeclaration = "    main0_out out = {};\n"

    /// `msl` with its colour outputs in `half`, or `msl` unchanged when it has none it can rewrite.
    static func rewriteFragmentOutputs(_ msl: String) -> String {
        let whole = NSRange(msl.startIndex..., in: msl)
        guard let structMatch = outputStruct.firstMatch(in: msl, range: whole),
              let bodyRange = Range(structMatch.range(at: 1), in: msl),
              let entry = entryPoint.firstMatch(in: msl, range: whole),
              let entryStart = Range(entry.range, in: msl)?.lowerBound else { return msl }
        let body = String(msl[bodyRange])
        let members: [(width: String, name: String)] = colorMember
            .matches(in: body, range: NSRange(body.startIndex..., in: body))
            .compactMap { match in
                guard let width = Range(match.range(at: 2), in: body), let name = Range(match.range(at: 3), in: body) else { return nil }
                return (String(body[width]), String(body[name]))
            }
        guard !members.isEmpty else { return msl }
        // The entry point is the last function SPIRV-Cross writes; the outputs must not be reached
        // anywhere before it (a helper taking `main0_out`).
        let prefix = msl[..<entryStart]
        let entryText = String(msl[entryStart...])
        guard prefix.components(separatedBy: "main0_out").count == 2, // the struct and nothing else
              entryText.contains(outDeclaration),
              entryText.contains("return out;") else { return msl }
        var rewrittenEntry = entryText
        var locals = ""
        var conversions = ""
        for member in members {
            let local = "\(member.name)_weFloat"
            guard !entryText.contains(local) else { return msl }
            rewrittenEntry = rewrittenEntry.replacingOccurrences(of: "out.\(member.name)", with: local)
            locals += "    float\(member.width) \(local) = {};\n"
            conversions += "out.\(member.name) = half\(member.width)(\(local)); "
        }
        rewrittenEntry = rewrittenEntry.replacingOccurrences(of: outDeclaration, with: outDeclaration + locals,
                                                             range: rewrittenEntry.range(of: outDeclaration))
        rewrittenEntry = rewrittenEntry.replacingOccurrences(of: "return out;", with: "{ \(conversions)return out; }")
        let halfBody = colorMember.stringByReplacingMatches(in: body, range: NSRange(body.startIndex..., in: body),
                                                            withTemplate: "$1half$2 $3 [[color($4)]];")
        var result = String(prefix) + rewrittenEntry
        let resultBody = result.range(of: body)!
        result.replaceSubrange(resultBody, with: halfBody)
        return result
    }
}

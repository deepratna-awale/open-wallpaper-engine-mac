import Foundation
import Metal
import simd

/// The instanced path of model materials (docs/models-plan.md §4.3 O, "instancing identical
/// meshes"). WE draws every model object with its own `g_ModelMatrix`; objects that draw the same
/// mesh through the same material differ only in the built-ins that follow their world matrix, so
/// one instanced draw can draw them all when each instance reads those built-ins from a vertex
/// stream instead of the uniform block.
///
/// The translator (`ShaderVariantTranslator.variant(…, instancing: true)`, model materials only)
/// rewrites a vertex stage's reads of the supported built-ins (`builtins`) and of `gl_InstanceID`
/// (the shadow caster's view) to `OWE_INSTANCED ? <instance stream> : <uniform>`, where
/// `OWE_INSTANCED` is a specialization constant (Metal function constant `constantIndex`) that
/// defaults to false: a pipeline made without it (`vertexFunction(_:instanced: false)`) reads the
/// uniforms exactly as before. The instance streams are per-instance vertex attributes from one
/// buffer (`instanceBuffer`, `record` floats per instance, written by `writeRecord`), so the
/// values are the CPU's own, bit for bit, as the uniform block would hold them.
///
/// A variant is instanceable (`TranslatedShaderVariant.instanceable`) when its vertex stage reads
/// no other built-in that follows the world (`worldDependent`) and its fragment stage none at all.
enum ShaderInstancing {
    /// The specialization constant's name and Metal function-constant index.
    static let constantName = "OWE_INSTANCED"
    static let constantIndex = 0
    /// The vertex buffer index of the instance records (free in the model pipelines: the mesh
    /// streams are 30 and 27, zeros 28, the uniforms 0).
    static let instanceBuffer = 26

    /// A built-in an instance carries: its uniform, GLSL type, attribute prefix, columns, first
    /// attribute location and offset (floats) in the record.
    struct Builtin {
        let uniform: String
        let type: String
        let attribute: String
        let columns: Int
        let rows: Int
        let location: Int
        let offset: Int
        let key: BuiltinUniforms.Key
    }

    static let builtins: [Builtin] = [
        Builtin(uniform: "g_ModelMatrix", type: "mat4", attribute: "a_OWEInstanceModel", columns: 4, rows: 4,
                location: 16, offset: 0, key: .modelMatrix),
        Builtin(uniform: "g_ModelMatrixInverse", type: "mat4", attribute: "a_OWEInstanceModelInverse", columns: 4, rows: 4,
                location: 20, offset: 16, key: .modelMatrixInverse),
        Builtin(uniform: "g_ModelViewProjectionMatrix", type: "mat4", attribute: "a_OWEInstanceMVP", columns: 4, rows: 4,
                location: 24, offset: 32, key: .modelViewProjection),
        Builtin(uniform: "g_NormalModelMatrix", type: "mat3", attribute: "a_OWEInstanceNormal", columns: 3, rows: 3,
                location: 28, offset: 48, key: .normalModelMatrix),
    ]
    /// The view index replacing `gl_InstanceID` (the shadow caster's), its location and offset.
    static let viewAttribute = "a_OWEInstanceView"
    static let viewLocation = 12
    static let viewOffset = 57
    /// Floats per instance record.
    static let record = 58

    /// Every built-in that follows the draw's world matrix (`BuiltinUniforms.Key`'s placement
    /// keys bar the camera's own): an instanced draw can't share any but `builtins`.
    static let worldDependent: Set<String> = [
        "g_ModelMatrix", "g_ModelMatrixInverse", "g_ModelViewProjectionMatrix", "g_NormalModelMatrix",
        "g_ModelViewProjectionMatrixInverse", "g_EffectModelViewProjectionMatrix", "g_EffectModelViewProjectionMatrixInverse",
        "g_EffectModelMatrix", "g_AltModelMatrix", "g_AltNormalModelMatrix", "g_ModelViewMatrix", "g_ModelViewMatrixInverse",
    ]

    /// The attribute locations the instanced path adds (`ShaderPairRewriter.attributeLocations`).
    static let attributeLocations: [String: Int] = {
        var locations = [viewAttribute: viewLocation]
        for builtin in builtins {
            for column in 0..<builtin.columns { locations["\(builtin.attribute)\(column)"] = builtin.location + column }
        }
        return locations
    }()

    /// An instance attribute's format and byte offset in the record; nil for any other name.
    static func instanceAttribute(_ name: String) -> (format: MTLVertexFormat, offset: Int)? {
        if name == viewAttribute { return (.float, viewOffset * 4) }
        for builtin in builtins where name.hasPrefix(builtin.attribute) {
            guard let column = Int(name.dropFirst(builtin.attribute.count)), column < builtin.columns else { continue }
            return (builtin.rows == 4 ? .float4 : .float3, (builtin.offset + column * builtin.rows) * 4)
        }
        return nil
    }

    // MARK: - Translation

    private static func word(_ name: String) -> NSRegularExpression {
        NSRegularExpression.shader(#"(?<![\w.])"# + NSRegularExpression.escapedPattern(for: name) + #"(?!\w)"#)
    }

    private static let uniformLine = NSRegularExpression.shader(#"(?m)^[ \t]*uniform\b[^\n]*$"#)
    private static let directiveLine = NSRegularExpression.shader(#"(?m)^[ \t]*#[ \t]*(?:version|extension)\b[^\n]*$"#)

    /// The text without its uniform declarations: what a stage reads, not what it declares.
    private static func body(_ text: String) -> String {
        uniformLine.stringByReplacingMatches(in: text, range: NSRange(text.startIndex..., in: text), withTemplate: "")
    }

    private static func reads(_ name: String, in body: String) -> Bool {
        word(name).firstMatch(in: body, range: NSRange(body.startIndex..., in: body)) != nil
    }

    /// The declared type of uniform `name` in `text`; nil when it isn't declared.
    private static func declaredType(_ name: String, in text: String) -> String? {
        let pattern = NSRegularExpression.shader(#"(?m)^[ \t]*uniform\s+(?:(?:lowp|mediump|highp)\s+)?(\w+)\s+"#
                                                 + NSRegularExpression.escapedPattern(for: name) + #"\s*;"#)
        let range = NSRange(text.startIndex..., in: text)
        guard let match = pattern.firstMatch(in: text, range: range), let type = Range(match.range(at: 1), in: text) else { return nil }
        return String(text[type])
    }

    /// The preprocessed vertex stage with its instanced path, and whether the pair is instanceable.
    /// A pair that isn't keeps its vertex stage as it was.
    static func rewrite(vertex: String, fragment: String) -> (vertex: String, instanceable: Bool) {
        let vertexBody = body(vertex), fragmentBody = body(fragment)
        // The fragment stage would need the instance passed along: such a pair draws one by one.
        guard !worldDependent.contains(where: { reads($0, in: fragmentBody) }) else { return (vertex, false) }
        let supported = Set(builtins.map(\.uniform))
        guard !worldDependent.subtracting(supported).contains(where: { reads($0, in: vertexBody) }) else { return (vertex, false) }
        let used = builtins.filter { reads($0.uniform, in: vertexBody) }
        // A declaration of another type than WE's would read the stream wrongly.
        guard used.allSatisfy({ declaredType($0.uniform, in: vertex) == $0.type }) else { return (vertex, false) }
        let readsInstance = reads("gl_InstanceID", in: vertexBody)
        guard !used.isEmpty || readsInstance else { return (vertex, true) }

        var header = ["layout(constant_id = \(constantIndex)) const bool \(constantName) = false;"]
        for builtin in used {
            let vector = builtin.rows == 4 ? "vec4" : "vec3"
            let columns = (0..<builtin.columns).map { "\(builtin.attribute)\($0)" }
            header += columns.map { "in \(vector) \($0);" }
            header.append("#define OWE_I_\(builtin.uniform) (\(constantName) ? \(builtin.type)(\(columns.joined(separator: ", "))) : \(builtin.uniform))")
        }
        if readsInstance {
            header.append("in float \(viewAttribute);")
            header.append("#define OWE_I_gl_InstanceID (\(constantName) ? int(\(viewAttribute)) : gl_InstanceID)")
        }
        // Reads only: the uniform declarations keep their names (the block is made from them).
        var lines = vertex.components(separatedBy: "\n")
        let declaration = NSRegularExpression.shader(#"^[ \t]*uniform\b"#)
        let names = used.map(\.uniform) + (readsInstance ? ["gl_InstanceID"] : [])
        let patterns = names.map { ($0, word($0)) }
        for index in lines.indices {
            let line = lines[index]
            if declaration.firstMatch(in: line, range: NSRange(line.startIndex..., in: line)) != nil { continue }
            var rewritten = line
            for (name, pattern) in patterns where rewritten.contains(name) {
                rewritten = pattern.stringByReplacingMatches(in: rewritten, range: NSRange(rewritten.startIndex..., in: rewritten),
                                                             withTemplate: "OWE_I_\(name)")
            }
            lines[index] = rewritten
        }
        var text = lines.joined(separator: "\n")
        // After `#version` and the extensions, which must come first.
        let matches = directiveLine.matches(in: text, range: NSRange(text.startIndex..., in: text))
        if let last = matches.last, let range = Range(last.range, in: text) {
            text.insert(contentsOf: "\n" + header.joined(separator: "\n"), at: range.upperBound)
        } else {
            text = header.joined(separator: "\n") + "\n" + text
        }
        return (text, true)
    }

    // MARK: - Drawing

    /// The vertex stage's `main0`, specialized for the instanced path or not. A stage without the
    /// constant is the plain function.
    static func vertexFunction(_ library: MTLLibrary, instanced: Bool) throws -> MTLFunction? {
        guard let plain = library.makeFunction(name: "main0") else { return nil }
        guard !plain.functionConstantsDictionary.isEmpty else { return plain }
        let values = MTLFunctionConstantValues()
        var flag = instanced
        values.setConstantValue(&flag, type: .bool, index: constantIndex)
        return try library.makeFunction(name: "main0", constantValues: values)
    }

    /// Writes one instance's record: the built-ins `pass` gives (the object's placement), and the
    /// view index.
    static func writeRecord(into records: inout [Float], frame: BuiltinFrameContext, pass: BuiltinPassContext, view: Int = 0) {
        let start = records.count
        records.append(contentsOf: repeatElement(0, count: record))
        for builtin in builtins {
            let value = BuiltinUniforms.value(builtin.key, frame: frame, pass: pass)
            for (index, component) in value.prefix(builtin.columns * builtin.rows).enumerated() {
                records[start + builtin.offset + index] = component
            }
        }
        records[start + viewOffset] = Float(view)
    }

    /// `bytes` with the world-dependent members of `layout` (and `ignoring`) zeroed: what two
    /// instances' uniform blocks share when they can draw together.
    static func sharedBytes(_ bytes: [UInt8], layout: UniformLayout?, ignoring: Set<String> = []) -> [UInt8] {
        guard let layout else { return bytes }
        var shared = bytes
        for name in worldDependent.union(ignoring) {
            guard let member = layout.members[name] else { continue }
            let columns = member.type.hasPrefix("mat") ? Int(String(member.type.dropFirst(3).prefix(1))) ?? 4 : 1
            let element = member.type.hasPrefix("mat") ? columns * max(member.matrixStride, 16) : 16
            let length = member.count > 1 ? member.count * max(member.arrayStride, element) : element
            let end = min(shared.count, member.offset + length)
            if member.offset < end { for index in member.offset..<end { shared[index] = 0 } }
        }
        return shared
    }
}

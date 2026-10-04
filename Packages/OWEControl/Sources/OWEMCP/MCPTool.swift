import Foundation
import OWEControlProtocol

/// One MCP tool: its schema for `tools/list`, and how its result reads. A call is the control
/// request of the same name with the tool's arguments as its parameters (`docs/mcp.md`).
public struct MCPTool: Sendable {
    public struct Annotations: Sendable {
        public var readOnly = false
        public var destructive = false
        public var idempotent = false
    }

    public let name: String
    public let title: String
    public let description: String
    public let inputSchema: JSONValue
    public let annotations: Annotations
    /// The result has a PNG (`png_base64`), returned as image content.
    let returnsImage: Bool
    /// A sentence saying what happened, from the app's result.
    let summary: @Sendable (JSONValue) -> String

    init(_ name: String, title: String, description: String, input: JSONValue = JSONSchema.object([:]),
         annotations: Annotations = Annotations(), returnsImage: Bool = false,
         summary: @escaping @Sendable (JSONValue) -> String) {
        self.name = name
        self.title = title
        self.description = description
        inputSchema = input
        self.annotations = annotations
        self.returnsImage = returnsImage
        self.summary = summary
    }

    /// The tool as `tools/list` lists it.
    var definition: JSONValue {
        [
            "name": .string(name),
            "title": .string(title),
            "description": .string(description),
            "inputSchema": inputSchema,
            "annotations": [
                "title": .string(title),
                "readOnlyHint": .bool(annotations.readOnly),
                "destructiveHint": .bool(annotations.destructive),
                "idempotentHint": .bool(annotations.idempotent),
                // Everything happens in the app on this Mac.
                "openWorldHint": false,
            ],
        ]
    }
}

extension MCPTool.Annotations {
    static let readOnly = MCPTool.Annotations(readOnly: true, destructive: false, idempotent: true)
    static let idempotent = MCPTool.Annotations(readOnly: false, destructive: false, idempotent: true)
    static let change = MCPTool.Annotations(readOnly: false, destructive: false, idempotent: false)
}

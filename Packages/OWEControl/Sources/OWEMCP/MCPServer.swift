import Foundation
import OWEControlProtocol

/// Where tool calls go: the running app's control channel (`SocketControlChannel`), or a fake in
/// tests. Throws `ControlError` for what the app refused, anything else when it couldn't be reached.
public protocol ControlChannel: AnyObject {
    func call(_ method: String, params: [String: JSONValue]) async throws -> JSONValue
}

/// The Model Context Protocol server: JSON-RPC 2.0 messages in, responses out, one line each
/// (MCP's stdio transport). It answers `initialize`, `ping`, `tools/list`, `tools/call`,
/// `resources/list`, `resources/templates/list` and `resources/read`; notifications get no answer.
///
/// - A tool call checks its arguments against the tool's schema, then becomes the control request
///   of the same name. Its result comes back as structured content, with a one-line summary and
///   the JSON as text for clients without structured content; a snapshot's PNG as image content.
/// - What the app refuses, and an app that can't be reached, are tool errors (`isError`) with a
///   message saying why and what to do. An unknown tool or method is a JSON-RPC error.
public final class MCPServer {
    public static let protocolVersion = "2025-06-18"
    /// The versions a client may ask for; any other gets `protocolVersion`.
    public static let supportedVersions = ["2025-06-18", "2025-03-26", "2024-11-05"]
    public static let libraryResource = "owe://library"
    public static let statusResource = "owe://status"

    enum ErrorCode {
        static let parse = -32700
        static let invalidRequest = -32600
        static let methodNotFound = -32601
        static let invalidParams = -32602
        static let internalError = -32603
        static let resourceNotFound = -32002
    }

    private let channel: ControlChannel
    private let version: String

    public init(channel: ControlChannel, version: String) {
        self.channel = channel
        self.version = version
    }

    /// The response line (without its newline) to one line read from the client; nil when the
    /// line needs no answer (a notification, a response, a blank line).
    public func handle(line: Data) async -> Data? {
        guard !line.allSatisfy({ $0 == 0x20 || $0 == 0x09 || $0 == 0x0D }) else { return nil }
        let message: JSONValue
        do {
            message = try JSONValue.decode(line)
        } catch {
            return Self.encode(Self.error(id: .null, code: ErrorCode.parse, message: "Parse error: the line isn't JSON."))
        }
        return await handle(message: message).map(Self.encode)
    }

    /// The response to one JSON-RPC message, or nil for a notification or a response.
    public func handle(message: JSONValue) async -> JSONValue? {
        guard case .object(let object) = message else {
            // Batches were removed from MCP in 2025-06-18.
            return Self.error(id: .null, code: ErrorCode.invalidRequest, message: "Invalid request: expected one JSON-RPC object.")
        }
        let id = object["id"]
        guard object["jsonrpc"]?.stringValue == "2.0", let method = object["method"]?.stringValue else {
            // A response to something we never sent, or not JSON-RPC at all.
            if object["result"] != nil || object["error"] != nil { return nil }
            return Self.error(id: id ?? .null, code: ErrorCode.invalidRequest,
                              message: "Invalid request: expected \"jsonrpc\": \"2.0\" and a method.")
        }
        guard let id, Self.isValidID(id) else {
            if object["id"] != nil {
                return Self.error(id: .null, code: ErrorCode.invalidRequest, message: "Invalid request: the id must be a string or a number.")
            }
            return nil // A notification (`notifications/initialized`, `notifications/cancelled`…).
        }
        let params = object["params"] ?? .object([:])
        guard case .object(let parameters) = params else {
            return Self.error(id: id, code: ErrorCode.invalidParams, message: "Invalid params: expected an object.")
        }
        switch method {
        case "initialize": return Self.result(id: id, initialize(parameters))
        case "ping": return Self.result(id: id, .object([:]))
        case "tools/list": return Self.result(id: id, ["tools": .array(MCPToolCatalog.tools.map(\.definition))])
        case "tools/call": return await callTool(id: id, parameters)
        case "resources/list": return Self.result(id: id, ["resources": .array(Self.resources)])
        case "resources/templates/list": return Self.result(id: id, ["resourceTemplates": []])
        case "resources/read": return await readResource(id: id, parameters)
        default:
            return Self.error(id: id, code: ErrorCode.methodNotFound, message: "Method not found: \(method)")
        }
    }

    // MARK: - Lifecycle

    private func initialize(_ params: [String: JSONValue]) -> JSONValue {
        let requested = params["protocolVersion"]?.stringValue
        let agreed = requested.flatMap { Self.supportedVersions.contains($0) ? $0 : nil } ?? Self.protocolVersion
        return [
            "protocolVersion": .string(agreed),
            "capabilities": [
                "tools": ["listChanged": false],
                "resources": ["listChanged": false, "subscribe": false],
            ],
            "serverInfo": [
                "name": "open-wallpaper-engine",
                "title": "Open Wallpaper Engine",
                "version": .string(version),
            ],
            "instructions": """
            Controls Open Wallpaper Engine, the wallpaper player on this Mac: its displays, library, \
            playback, user properties, playlists and editors. Ids come from list_wallpapers and \
            list_displays; get_wallpaper lists a wallpaper's user properties. The app's MCP Server plugin \
            must be installed (Settings › Plugins); owe-mcp starts the app when it isn't running.
            """,
        ]
    }

    // MARK: - Tools

    private func callTool(id: JSONValue, _ params: [String: JSONValue]) async -> JSONValue {
        guard let name = params["name"]?.stringValue else {
            return Self.error(id: id, code: ErrorCode.invalidParams, message: "Invalid params: tools/call needs the tool's name.")
        }
        guard let tool = MCPToolCatalog.tool(named: name) else {
            return Self.error(id: id, code: ErrorCode.invalidParams, message: "Unknown tool: \(name)")
        }
        let arguments = params["arguments"] ?? .object([:])
        let problems = JSONSchema.problems(arguments, against: tool.inputSchema)
        guard problems.isEmpty, case .object(let values) = arguments else {
            return Self.result(id: id, Self.toolError("Invalid arguments for \(name): " + problems.joined(separator: "; ") + "."))
        }
        do {
            let result = try await channel.call(name, params: values)
            return Self.result(id: id, Self.toolResult(tool, result))
        } catch let error as ControlError {
            return Self.result(id: id, Self.toolError(error.message))
        } catch {
            return Self.result(id: id, Self.toolError(Self.unreachableMessage(error)))
        }
    }

    static func toolResult(_ tool: MCPTool, _ result: JSONValue) -> JSONValue {
        var structured = result
        var content: [JSONValue] = []
        if tool.returnsImage, case .object(var object) = result, let png = object.removeValue(forKey: "png_base64") {
            structured = .object(object)
            content.append(["type": "image", "data": png, "mimeType": "image/png"])
        }
        content.insert(["type": "text", "text": .string(tool.summary(result))], at: 0)
        // Clients from before structured content read the result as text.
        if let json = try? structured.encodedLine(), let text = String(data: json, encoding: .utf8) { // Encoding a decoded value can't fail.
            content.append(["type": "text", "text": .string(text)])
        }
        return ["content": .array(content), "structuredContent": structured, "isError": false]
    }

    static func toolError(_ message: String) -> JSONValue {
        ["content": [["type": "text", "text": .string(message)]], "isError": true]
    }

    /// What to tell the client when the app couldn't be reached.
    static func unreachableMessage(_ error: Error) -> String {
        if let error = error as? AppConnectionError { return error.message }
        return "Open Wallpaper Engine couldn't be reached (\(error)). Make sure it is running with the MCP Server plugin installed (Settings › Plugins)."
    }

    // MARK: - Resources

    static let resources: [JSONValue] = [
        [
            "uri": .string(libraryResource), "name": "library", "title": "Wallpaper library",
            "description": "Every wallpaper in the library: id, title, type, tags, folder and Workshop id.",
            "mimeType": "application/json",
        ],
        [
            "uri": .string(statusResource), "name": "status", "title": "Playback status",
            "description": "What each display shows, playback, volume and the active playlist.",
            "mimeType": "application/json",
        ],
    ]

    private func readResource(id: JSONValue, _ params: [String: JSONValue]) async -> JSONValue {
        guard let uri = params["uri"]?.stringValue else {
            return Self.error(id: id, code: ErrorCode.invalidParams, message: "Invalid params: resources/read needs a uri.")
        }
        do {
            let value: JSONValue
            switch uri {
            case Self.libraryResource: value = try await wholeLibrary()
            case Self.statusResource: value = try await channel.call("get_status", params: [:])
            default:
                return Self.error(id: id, code: ErrorCode.resourceNotFound, message: "Resource not found: \(uri)")
            }
            let text = String(decoding: try value.encodedLine(), as: UTF8.self)
            return Self.result(id: id, ["contents": [["uri": .string(uri), "mimeType": "application/json", "text": .string(text)]]])
        } catch let error as ControlError {
            return Self.error(id: id, code: ErrorCode.internalError, message: error.message)
        } catch {
            return Self.error(id: id, code: ErrorCode.internalError, message: Self.unreachableMessage(error))
        }
    }

    /// Every page of `list_wallpapers`.
    private func wholeLibrary() async throws -> JSONValue {
        var wallpapers: [JSONValue] = []
        while true {
            let page = try await channel.call("list_wallpapers", params: ["limit": 500, "offset": .number(Double(wallpapers.count))])
            let items = page["wallpapers"]?.arrayValue ?? []
            wallpapers += items
            let total = page["total"]?.intValue ?? wallpapers.count
            if items.isEmpty || wallpapers.count >= total { break }
        }
        return ["total": .number(Double(wallpapers.count)), "wallpapers": .array(wallpapers)]
    }

    // MARK: - JSON-RPC

    private static func isValidID(_ id: JSONValue) -> Bool {
        switch id {
        case .string, .number: return true
        default: return false
        }
    }

    static func result(id: JSONValue, _ result: JSONValue) -> JSONValue {
        ["jsonrpc": "2.0", "id": id, "result": result]
    }

    static func error(id: JSONValue, code: Int, message: String) -> JSONValue {
        ["jsonrpc": "2.0", "id": id, "error": ["code": .number(Double(code)), "message": .string(message)]]
    }

    private static func encode(_ value: JSONValue) -> Data {
        // A value built from decoded JSON and strings always encodes.
        (try? value.encodedLine()) ?? Data(#"{"jsonrpc":"2.0","id":null,"error":{"code":-32603,"message":"Internal error"}}"#.utf8)
    }
}

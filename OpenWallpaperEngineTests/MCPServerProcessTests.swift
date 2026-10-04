import XCTest
import OWEControlProtocol
@testable import OpenWallpaperEngine

/// The owe-mcp the app ships (`Contents/Helpers/owe-mcp`), run as an MCP client runs it: JSON-RPC
/// over its stdin and stdout. It never starts the app here (`--no-launch`, and a socket nobody serves).
final class MCPServerProcessTests: XCTestCase {
    private var process: Process!
    private var input: FileHandle!
    private let lines = LineCollector()

    override func setUpWithError() throws {
        // The test host is the app, which embeds the server.
        let executable = AppBundleLayout.mcpServerURL(inApp: Bundle.main.bundleURL)
        guard FileManager.default.isExecutableFile(atPath: executable.path) else {
            return XCTFail("owe-mcp is missing from \(executable.path)")
        }
        let stdin = Pipe()
        let stdout = Pipe()
        process = Process()
        process.executableURL = executable
        process.arguments = ["--no-launch", "--socket", "/tmp/owe-mcp-test-\(UUID().uuidString.prefix(8)).sock"]
        process.standardInput = stdin
        process.standardOutput = stdout
        process.standardError = FileHandle.nullDevice
        try process.run()
        input = stdin.fileHandleForWriting
        stdout.fileHandleForReading.readabilityHandler = { [lines] handle in lines.append(handle.availableData) }
    }

    override func tearDown() {
        try? input?.close() // Closing stdin ends the server; it may have exited already.
        if let process, process.isRunning {
            let deadline = Date().addingTimeInterval(5)
            while process.isRunning, Date() < deadline { usleep(20_000) }
            if process.isRunning { process.terminate() }
        }
    }

    private func send(_ message: JSONValue) throws {
        try input.write(contentsOf: message.encodedLine() + Data([0x0A]))
    }

    /// The next line the server writes, as JSON.
    private func readMessage(timeout: TimeInterval = 10) throws -> JSONValue {
        let line = try XCTUnwrap(lines.next(timeout: timeout), "owe-mcp didn't answer within \(timeout) s")
        return try JSONValue.decode(line)
    }

    func testInitializeAndListToolsOverStdio() throws {
        try send(["jsonrpc": "2.0", "id": 1, "method": "initialize", "params": [
            "protocolVersion": "2025-06-18", "capabilities": [:], "clientInfo": ["name": "tests", "version": "1"],
        ]])
        let initialized = try readMessage()
        XCTAssertEqual(initialized["id"], 1)
        XCTAssertEqual(initialized["result"]?["protocolVersion"], "2025-06-18")
        XCTAssertEqual(initialized["result"]?["serverInfo"]?["name"], "open-wallpaper-engine")

        try send(["jsonrpc": "2.0", "method": "notifications/initialized"])
        try send(["jsonrpc": "2.0", "id": 2, "method": "tools/list"])
        let list = try readMessage()
        XCTAssertEqual(list["id"], 2, "the notification got no answer")
        let tools = list["result"]?["tools"]?.arrayValue ?? []
        XCTAssertGreaterThanOrEqual(tools.count, 18)
        XCTAssertTrue(tools.contains { $0["name"] == "set_wallpaper" })
        XCTAssertTrue(tools.allSatisfy { $0["inputSchema"]?["type"] == "object" })

        // With no app to talk to, a call is a tool error that says what to do.
        try send(["jsonrpc": "2.0", "id": 3, "method": "tools/call", "params": ["name": "pause", "arguments": [:]]])
        let call = try readMessage()
        XCTAssertEqual(call["result"]?["isError"], true)
        XCTAssertTrue(call["result"]?["content"]?.arrayValue?.first?["text"]?.stringValue?.contains("MCP Server plugin") ?? false)

        input.closeFile()
        process.waitUntilExit()
        XCTAssertEqual(process.terminationStatus, 0)
    }
}

/// Lines read from a pipe on its own queue, waited for with a timeout.
private final class LineCollector: @unchecked Sendable { // `buffer` is guarded by `lock`.
    private let lock = NSLock()
    private let arrived = DispatchSemaphore(value: 0)
    private var buffer = Data()

    func append(_ data: Data) {
        guard !data.isEmpty else { return }
        lock.withLock { buffer.append(data) }
        arrived.signal()
    }

    func next(timeout: TimeInterval) -> Data? {
        let deadline = DispatchTime.now() + timeout
        while true {
            let line: Data? = lock.withLock {
                guard let newline = buffer.firstIndex(of: 0x0A) else { return nil }
                let line = Data(buffer[buffer.startIndex..<newline])
                buffer.removeSubrange(buffer.startIndex...newline)
                return line
            }
            if let line { return line }
            guard arrived.wait(timeout: deadline) == .success else { return nil }
        }
    }
}

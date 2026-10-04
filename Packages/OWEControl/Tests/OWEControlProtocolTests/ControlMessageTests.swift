import XCTest
@testable import OWEControlProtocol

final class ControlMessageTests: XCTestCase {
    func testRequestIsOneLineWithVersion() throws {
        let line = try ControlRequest(id: 4, method: "set_volume", params: ["level": 0.5]).line()
        XCTAssertEqual(line.last, 0x0A)
        XCTAssertEqual(line.filter { $0 == 0x0A }.count, 1)
        let text = String(decoding: line, as: UTF8.self)
        XCTAssertEqual(text, #"{"id":4,"method":"set_volume","params":{"level":0.5},"version":1}"# + "\n")
    }

    func testRequestWithoutParamsDecodes() throws {
        let request = try JSONDecoder().decode(ControlRequest.self, from: Data(#"{"version":1,"id":2,"method":"pause"}"#.utf8))
        XCTAssertEqual(request, ControlRequest(id: 2, method: "pause"))
    }

    func testResponseRoundTrip() throws {
        let error = ControlResponse(id: 3, error: ControlError(.notFound, "No wallpaper \"x\"."))
        let decoded = try JSONDecoder().decode(ControlResponse.self, from: error.line().dropLast())
        XCTAssertEqual(decoded, error)
        XCTAssertTrue(String(decoding: try error.line(), as: UTF8.self).contains(#""code":"not_found""#))
    }

    func testWholeNumbersHaveNoFraction() throws {
        let value: JSONValue = ["limit": 50, "level": 0.25, "list": [1, true, nil, "a"]]
        XCTAssertEqual(String(decoding: try value.encodedLine(), as: UTF8.self),
                       #"{"level":0.25,"limit":50,"list":[1,true,null,"a"]}"#)
        XCTAssertEqual(try JSONValue.decode(value.encodedLine()), value)
    }

    func testAccessors() {
        let value: JSONValue = ["n": 3, "f": 1.5, "s": "x", "b": false]
        XCTAssertEqual(value["n"]?.intValue, 3)
        XCTAssertNil(value["f"]?.intValue)
        XCTAssertEqual(value["f"]?.doubleValue, 1.5)
        XCTAssertEqual(value["s"]?.stringValue, "x")
        XCTAssertEqual(value["b"]?.boolValue, false)
        XCTAssertEqual(value["n"]?.typeName, "integer")
        XCTAssertNil(value["missing"])
    }

    func testSocketLocationFollowsTheAppsFolders() {
        let support = URL(fileURLWithPath: "/Users/u/Library/Application Support", isDirectory: true)
        XCTAssertEqual(ControlSocketLocation.supportDirectory(isolationTag: nil, applicationSupport: support).path,
                       "/Users/u/Library/Application Support/Open Wallpaper Engine")
        XCTAssertEqual(ControlSocketLocation.supportDirectory(isolationTag: "shots", applicationSupport: support).path,
                       "/Users/u/Library/Application Support/Open Wallpaper Engine (isolated shots)")
        // Cleaned as the app cleans it; an empty tag is the real app.
        XCTAssertEqual(ControlSocketLocation.sanitizedTag("a b/c"), "a-b-c")
        XCTAssertEqual(ControlSocketLocation.supportDirectory(isolationTag: "--", applicationSupport: support).lastPathComponent,
                       "Open Wallpaper Engine")
        XCTAssertEqual(ControlSocketLocation.socketURL(supportDirectory: support.appending(path: "Open Wallpaper Engine")).path,
                       "/Users/u/Library/Application Support/Open Wallpaper Engine/Control/control.sock")
    }

    /// A support folder too deep for a socket address puts the socket in the user's temporary
    /// folder, at a place both processes work out from the support folder alone.
    func testLongSupportFoldersFallBackToTheUsersTemporaryFolder() {
        let deep = URL(fileURLWithPath: "/Users/" + String(repeating: "n", count: 40) + "/Library/Application Support/Open Wallpaper Engine (isolated a-long-tag)")
        let temporary = URL(fileURLWithPath: "/var/folders/ab/cd/T", isDirectory: true)
        let socket = ControlSocketLocation.socketURL(supportDirectory: deep, temporaryDirectory: temporary)
        XCTAssertTrue(socket.path.hasPrefix("/var/folders/ab/cd/T/owe-"), socket.path)
        XCTAssertEqual(socket.lastPathComponent, "control.sock")
        XCTAssertLessThanOrEqual(socket.path.utf8.count, ControlSocketLocation.maxPathBytes)
        XCTAssertEqual(socket, ControlSocketLocation.socketURL(supportDirectory: deep, temporaryDirectory: temporary), "stable")
        XCTAssertNotEqual(socket, ControlSocketLocation.socketURL(supportDirectory: deep.appending(path: "x"), temporaryDirectory: temporary))
        XCTAssertEqual(ControlSocketLocation.hash(""), "cbf29ce484222325")
        XCTAssertTrue(ControlSocketLocation.userTemporaryDirectory.path.hasPrefix("/"))
    }
}
